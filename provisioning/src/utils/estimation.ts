import { Service, CompanyDetails, VMEstimate, ServiceConfig, ResourceFootprint } from '../types';
import { findBestHetznerInstance, hetznerStoragePricing } from '../data/pricing';
import { costModel } from '../theme/tokens';

const EUR_TO_USD = 1.08;
const MANAGEMENT_FEE = 1.2; // 20% uplift

const devMultiplier = {
  light: 0.9,
  moderate: 1,
  heavy: 1.12,
} as const;

const cicdMultiplier = {
  minimal: 0.92,
  moderate: 1,
  extensive: 1.12,
} as const;

const loadFactor = (value: number, base: number, step: number) => Math.max(0, (value - base) / step);

// Calculate per-service resource requirements with individual scaling
export const calculateServiceRequirements = (
  service: Service,
  companyDetails: CompanyDetails,
  _config?: ServiceConfig
): ResourceFootprint => {
  const { resourceUsage, scaling } = service;
  const concurrencyLoad = loadFactor(companyDetails.concurrentUsers, 10, 20);
  const teamLoad = loadFactor(companyDetails.teamSize, 6, 10);
  const trafficLoad = loadFactor(companyDetails.estimatedMonthlyTraffic, 50, 200);

  let cpu = resourceUsage.cpu;
  let memory = resourceUsage.memory;
  let storage = resourceUsage.storage;

  if (scaling) {
    if (scaling.concurrentUsers) {
      cpu += (scaling.concurrentUsers.cpu || 0) * concurrencyLoad;
      memory += (scaling.concurrentUsers.memory || 0) * concurrencyLoad;
      storage += (scaling.concurrentUsers.storage || 0) * concurrencyLoad * 0.8;
    }

    if (scaling.teamSize) {
      cpu += (scaling.teamSize.cpu || 0) * teamLoad;
      memory += (scaling.teamSize.memory || 0) * teamLoad;
      storage += (scaling.teamSize.storage || 0) * teamLoad;
    }

    if (scaling.cicdIntensity) {
      const cicdLoad = cicdMultiplier[companyDetails.cicdUsage] - 1;
      cpu += (scaling.cicdIntensity.cpu || 0) * Math.max(0, cicdLoad);
      memory += (scaling.cicdIntensity.memory || 0) * Math.max(0, cicdLoad);
      storage += (scaling.cicdIntensity.storage || 0) * Math.max(0, cicdLoad);
    }
  }

  cpu *= devMultiplier[companyDetails.developmentIntensity] * cicdMultiplier[companyDetails.cicdUsage];
  memory *= devMultiplier[companyDetails.developmentIntensity] * (0.96 + 0.04 * cicdMultiplier[companyDetails.cicdUsage]);
  storage *= 1 + trafficLoad * 0.9;

  const minCpu = Math.max(cpu, 0.1);
  const minMemory = Math.max(memory, 0.1);
  const minStorage = Math.max(storage, 0.5);

  return {
    cpu: Number(minCpu.toFixed(2)),
    memory: Number(minMemory.toFixed(2)),
    storage: Number(minStorage.toFixed(2)),
  };
};

export const estimateServiceCost = (footprint: ResourceFootprint) => {
  const eurTotal =
    footprint.cpu * costModel.perCpu +
    footprint.memory * costModel.perMemoryGb +
    footprint.storage * costModel.perStorageGb;
  const usdWithFee = eurTotal * EUR_TO_USD * MANAGEMENT_FEE;
  return Number(usdWithFee.toFixed(2));
};

export const calculateVMEstimate = (
  selectedServices: Service[],
  companyDetails: CompanyDetails,
  serviceConfigs?: Record<string, ServiceConfig>
): VMEstimate => {
  const serviceRequirements = selectedServices.map(service => ({
    service,
    requirements: calculateServiceRequirements(service, companyDetails, serviceConfigs?.[service.id]),
  }));

  let totalCpu = serviceRequirements.reduce((sum, { requirements }) => sum + requirements.cpu, 0);
  let totalMemory = serviceRequirements.reduce((sum, { requirements }) => sum + requirements.memory, 0);
  let totalStorage = serviceRequirements.reduce((sum, { requirements }) => sum + requirements.storage, 0);

  // Round up to practical values
  totalCpu = Math.ceil(totalCpu * 10) / 10;
  totalMemory = Math.ceil(totalMemory);
  totalStorage = Math.ceil(totalStorage);

  totalCpu = Math.max(totalCpu, 1);
  totalMemory = Math.max(totalMemory, 2);
  totalStorage = Math.max(totalStorage, 20);

  const preferDedicated = companyDetails.cicdUsage === 'extensive' ||
    companyDetails.developmentIntensity === 'heavy' ||
    companyDetails.teamSize > 20;

  const hetznerRecommendation = findBestHetznerInstance(
    totalCpu,
    totalMemory,
    totalStorage,
    preferDedicated,
    true
  );

  const recommendedInstance = hetznerRecommendation.recommended;
  let recommendedInstanceType = `${recommendedInstance.name} (${recommendedInstance.vcpu} vCPU, ${recommendedInstance.memory}GB RAM, ${recommendedInstance.storage}GB)`;

  const baseVmCostUsd = Number((recommendedInstance.monthlyPrice * EUR_TO_USD * MANAGEMENT_FEE).toFixed(2));
  let storageSurchargeUsd = 0;

  const additionalStorage = Math.max(0, totalStorage - recommendedInstance.storage);
  if (additionalStorage > 0) {
    const additionalStorageEuro = additionalStorage * hetznerStoragePricing.volumeStoragePerGB;
    storageSurchargeUsd = Number((additionalStorageEuro * EUR_TO_USD * MANAGEMENT_FEE).toFixed(2));
  }

  const estimatedCost = Number((baseVmCostUsd + storageSurchargeUsd).toFixed(2));

  const warnings: string[] = [];
  const optimizations: string[] = [];

  if (totalCpu > 24 && companyDetails.teamSize <= 10) {
    warnings.push('CPU estimate is high for ≤10 engineers. Revisit concurrent user input.');
  }

  if (estimatedCost > 140) {
    warnings.push('Cost exceeds $140/month—consider splitting workloads across staged environments.');
  }

  if (companyDetails.cicdUsage === 'minimal' && selectedServices.some(s => s.id === 'gitlab')) {
    optimizations.push('Minimal CI/CD: consider GitHub + lightweight runners instead of full GitLab.');
  }

  return {
    totalCpu,
    totalMemory,
    totalStorage,
    estimatedCost,
    recommendedInstanceType,
    vmCostUsd: baseVmCostUsd,
    storageSurchargeUsd,
    warnings,
    optimizations,
  };
};
