import {
  CompanyDetails,
  ProvisioningSnapshot,
  Service,
  ServiceBreakdownItem,
  ServiceConfig,
} from '../types';
import { calculateServiceRequirements, calculateVMEstimate, estimateServiceCost } from './estimation';

const defaultSelected = ['postgresql', 'redis', 'nginx', 'gitlab', 'mattermost'];

export const createDefaultServiceConfigs = (services: Service[]) => {
  const record: Record<string, ServiceConfig> = {};
  services.forEach(service => {
    record[service.id] = {
      include: defaultSelected.includes(service.id),
    } satisfies ServiceConfig;
  });
  return record;
};

export const buildProvisioningSnapshot = (
  selectedServices: Service[],
  companyDetails: CompanyDetails,
  serviceConfigs: Record<string, ServiceConfig>
): ProvisioningSnapshot => {
  const breakdown: ServiceBreakdownItem[] = selectedServices.map(service => {
    const requirements = calculateServiceRequirements(service, companyDetails, serviceConfigs[service.id]);
    const deltaFromBaseline = {
      cpu: Number((requirements.cpu - service.resourceUsage.cpu).toFixed(2)),
      memory: Number((requirements.memory - service.resourceUsage.memory).toFixed(2)),
      storage: Number((requirements.storage - service.resourceUsage.storage).toFixed(2)),
    };

    return {
      service,
      requirements,
      deltaFromBaseline,
      cost: estimateServiceCost(requirements),
      warnings: [],
    } satisfies ServiceBreakdownItem;
  });

  const totals = breakdown.reduce(
    (acc, item) => {
      acc.cpu += item.requirements.cpu;
      acc.memory += item.requirements.memory;
      acc.storage += item.requirements.storage;
      acc.cost += item.cost;
      return acc;
    },
    { cpu: 0, memory: 0, storage: 0, cost: 0 }
  );

  const estimate = calculateVMEstimate(selectedServices, companyDetails, serviceConfigs);
  const vmCost = estimate.estimatedCost;

  let distributedTotal = 0;
  const heuristicsTotal = totals.cost || 1;
  const scale = heuristicsTotal ? vmCost / heuristicsTotal : 1;

  breakdown.forEach(item => {
    const serviceCost = Number((item.cost * scale).toFixed(2));
    distributedTotal += serviceCost;
    item.cost = serviceCost;
  });

  const roundingDiff = Number((vmCost - distributedTotal).toFixed(2));
  if (Math.abs(roundingDiff) >= 0.01 && breakdown.length > 0) {
    breakdown[0].cost = Number((breakdown[0].cost + roundingDiff).toFixed(2));
  }

  const costDrivers = [...breakdown]
    .sort((a, b) => b.cost - a.cost)
    .slice(0, 2);

  const bottlenecks: string[] = [];
  if (companyDetails.concurrentUsers > companyDetails.teamSize * 6) {
    bottlenecks.push('Concurrent user target is high relative to team size—double check load assumptions.');
  }

  if (totals.memory > 64 && companyDetails.developmentIntensity === 'light') {
    bottlenecks.push('Light workloads rarely need more than 64 GB RAM.');
  }

  const savingsTips: string[] = [];
  if (totals.cpu > 16 && companyDetails.developmentIntensity !== 'heavy') {
    savingsTips.push('Trim optional services to target <16 vCPU for moderate workloads.');
  }

  if (companyDetails.cicdUsage === 'minimal' && selectedServices.some(service => service.id === 'gitlab')) {
    savingsTips.push('CI/CD usage is minimal—consider lighter Git hosting or disable runners.');
  }

  const warnings = Array.from(new Set([...estimate.warnings, ...breakdown.flatMap(item => item.warnings)]));

  return {
    breakdown,
    totals: {
      cpu: Number(totals.cpu.toFixed(1)),
      memory: Number(totals.memory.toFixed(1)),
      storage: Number(totals.storage.toFixed(1)),
      cost: Number(vmCost.toFixed(2)),
    },
    costDrivers,
    bottlenecks,
    savingsTips,
    warnings,
    estimate,
  };
};
