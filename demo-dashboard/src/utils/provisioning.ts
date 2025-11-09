import {
  CompanyDetails,
  ProvisioningSnapshot,
  Service,
  ServiceBreakdownItem,
  ServiceConfig,
  ServiceBucket,
  VmBucketPlan,
  VMEstimate,
} from '../types';
import { calculateServiceRequirements, calculateVMEstimate, estimateServiceCost } from './estimation';

const defaultSelected = ['postgresql', 'redis', 'nginx', 'gitlab', 'mattermost'];
const DATA_SERVICE_IDS = new Set(['postgresql', 'redis']);

const bucketDescriptors: { id: ServiceBucket; label: string; predicate: (service: Service) => boolean }[] = [
  {
    id: 'data',
    label: 'Postgres + Redis tier',
    predicate: service => DATA_SERVICE_IDS.has(service.id),
  },
  {
    id: 'application',
    label: 'Application & supporting services',
    predicate: service => !DATA_SERVICE_IDS.has(service.id),
  },
];

const createZeroEstimate = (label: string): VMEstimate => ({
  totalCpu: 0,
  totalMemory: 0,
  totalStorage: 0,
  estimatedCost: 0,
  recommendedInstanceType: `${label}: no dedicated VM`,
  vmCostUsd: 0,
  storageSurchargeUsd: 0,
  warnings: [],
  optimizations: [],
});

const scaleServiceCostsToVm = (items: ServiceBreakdownItem[], targetCost: number) => {
  if (!items.length) {
    return;
  }

  const heuristicsTotal = items.reduce((sum, item) => sum + item.cost, 0);
  if (heuristicsTotal === 0 || targetCost === 0) {
    items.forEach(item => {
      item.cost = 0;
    });
    return;
  }

  const scale = targetCost / heuristicsTotal;
  let distributedTotal = 0;

  items.forEach(item => {
    const serviceCost = Number((item.cost * scale).toFixed(2));
    distributedTotal += serviceCost;
    item.cost = serviceCost;
  });

  const roundingDiff = Number((targetCost - distributedTotal).toFixed(2));
  if (Math.abs(roundingDiff) >= 0.01) {
    items[0].cost = Number((items[0].cost + roundingDiff).toFixed(2));
  }
};

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

  const bucketPlans: VmBucketPlan[] = bucketDescriptors.map(descriptor => {
    const bucketServices = selectedServices.filter(descriptor.predicate);
    const bucketItems = breakdown.filter(item => descriptor.predicate(item.service));

    const estimate = bucketServices.length
      ? calculateVMEstimate(bucketServices, companyDetails, serviceConfigs)
      : createZeroEstimate(descriptor.label);

    scaleServiceCostsToVm(bucketItems, estimate.estimatedCost);

    return {
      id: descriptor.id,
      label: descriptor.label,
      serviceIds: bucketServices.map(service => service.id),
      estimate,
    } satisfies VmBucketPlan;
  });

  const totalCost = bucketPlans.reduce((sum, bucket) => sum + bucket.estimate.estimatedCost, 0);
  const totalCpu = Number(bucketPlans.reduce((sum, bucket) => sum + bucket.estimate.totalCpu, 0).toFixed(1));
  const totalMemory = bucketPlans.reduce((sum, bucket) => sum + bucket.estimate.totalMemory, 0);
  const totalStorage = bucketPlans.reduce((sum, bucket) => sum + bucket.estimate.totalStorage, 0);
  const totalVmCostUsd = bucketPlans.reduce((sum, bucket) => sum + bucket.estimate.vmCostUsd, 0);
  const totalStorageSurcharge = bucketPlans.reduce((sum, bucket) => sum + bucket.estimate.storageSurchargeUsd, 0);

  const recommendedParts = bucketPlans
    .filter(bucket => bucket.serviceIds.length > 0)
    .map(bucket => `${bucket.label}: ${bucket.estimate.recommendedInstanceType}`);

  const combinedEstimate: VMEstimate = {
    totalCpu,
    totalMemory,
    totalStorage,
    estimatedCost: Number(totalCost.toFixed(2)),
    recommendedInstanceType: recommendedParts.length ? recommendedParts.join(' | ') : 'No services selected',
    vmCostUsd: Number(totalVmCostUsd.toFixed(2)),
    storageSurchargeUsd: Number(totalStorageSurcharge.toFixed(2)),
    warnings: bucketPlans.flatMap(bucket => bucket.estimate.warnings),
    optimizations: bucketPlans.flatMap(bucket => bucket.estimate.optimizations),
  } satisfies VMEstimate;

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

  const warnings = Array.from(new Set([...combinedEstimate.warnings, ...breakdown.flatMap(item => item.warnings)]));

  return {
    breakdown,
    totals: {
      cpu: Number(totals.cpu.toFixed(1)),
      memory: Number(totals.memory.toFixed(1)),
      storage: Number(totals.storage.toFixed(1)),
      cost: combinedEstimate.estimatedCost,
    },
    costDrivers,
    bottlenecks,
    savingsTips,
    warnings,
    estimate: combinedEstimate,
    bucketPlans,
  };
};
