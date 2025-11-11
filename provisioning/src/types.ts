export interface Service {
  id: string;
  name: string;
  description: string;
  icon: string;
  category: 'core' | 'development' | 'design' | 'monitoring' | 'collaboration' | 'security';
  resourceUsage: {
    cpu: number; // CPU cores baseline
    memory: number; // GB baseline
    storage: number; // GB baseline
  };
  scaling?: {
    // Scaling factors based on usage patterns
    concurrentUsers?: { cpu?: number; memory?: number; storage?: number };
    cicdIntensity?: { cpu?: number; memory?: number; storage?: number };
    teamSize?: { cpu?: number; memory?: number; storage?: number };
  };
  requirements?: string[];
}

export interface ServiceConfig {
  include: boolean;
}

export interface CompanyDetails {
  name: string;
  teamSize: number;
  developmentIntensity: 'light' | 'moderate' | 'heavy';
  cicdUsage: 'minimal' | 'moderate' | 'extensive';
  concurrentUsers: number;
  estimatedMonthlyTraffic: number; // GB
}

export interface VMEstimate {
  totalCpu: number;
  totalMemory: number;
  totalStorage: number;
  estimatedCost: number;
  recommendedInstanceType: string;
  vmCostUsd: number;
  storageSurchargeUsd: number;
  warnings: string[];
  optimizations: string[];
}

export interface ResourceFootprint {
  cpu: number;
  memory: number;
  storage: number;
}

export interface ServiceBreakdownItem {
  service: Service;
  requirements: ResourceFootprint;
  deltaFromBaseline: ResourceFootprint;
  cost: number;
  warnings: string[];
}

export type ServiceBucket = 'application' | 'data';

export interface VmBucketPlan {
  id: ServiceBucket;
  label: string;
  serviceIds: string[];
  estimate: VMEstimate;
}

export interface ProvisioningSnapshot {
  breakdown: ServiceBreakdownItem[];
  totals: ResourceFootprint & { cost: number };
  costDrivers: ServiceBreakdownItem[];
  bottlenecks: string[];
  savingsTips: string[];
  warnings: string[];
  estimate: VMEstimate;
  bucketPlans: VmBucketPlan[];
}
