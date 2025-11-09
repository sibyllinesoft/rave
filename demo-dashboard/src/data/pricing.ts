export interface HetznerInstance {
  name: string;
  type: string;
  vcpu: number;
  memory: number; // GB
  storage: number; // GB
  monthlyPrice: number; // EUR
  hourlyPrice: number; // EUR
  network: string;
  description: string;
}

// Hetzner Cloud pricing for Europe (Frankfurt) - Updated November 2024
export const hetznerInstances: HetznerInstance[] = [
  // Shared CPU instances
  {
    name: "CX11",
    type: "shared",
    vcpu: 1,
    memory: 4,
    storage: 20,
    monthlyPrice: 3.29,
    hourlyPrice: 0.005,
    network: "10 Gbps",
    description: "Entry-level shared CPU"
  },
  {
    name: "CX21",
    type: "shared",
    vcpu: 2,
    memory: 8,
    storage: 40,
    monthlyPrice: 5.83,
    hourlyPrice: 0.009,
    network: "10 Gbps",
    description: "Shared CPU for small applications"
  },
  {
    name: "CX31",
    type: "shared",
    vcpu: 2,
    memory: 16,
    storage: 80,
    monthlyPrice: 11.05,
    hourlyPrice: 0.017,
    network: "10 Gbps",
    description: "Shared CPU for medium workloads"
  },
  {
    name: "CX41",
    type: "shared",
    vcpu: 4,
    memory: 32,
    storage: 160,
    monthlyPrice: 20.67,
    hourlyPrice: 0.031,
    network: "10 Gbps",
    description: "Shared CPU for larger applications"
  },
  {
    name: "CX51",
    type: "shared",
    vcpu: 8,
    memory: 64,
    storage: 240,
    monthlyPrice: 39.65,
    hourlyPrice: 0.060,
    network: "10 Gbps",
    description: "Shared CPU for demanding workloads"
  },

  // High-clock shared CPU instance to bridge the 8→16 vCPU jump
  {
    name: "CPX51",
    type: "shared",
    vcpu: 16,
    memory: 32,
    storage: 360,
    monthlyPrice: 64.9,
    hourlyPrice: 0.098,
    network: "10 Gbps",
    description: "16 vCPU high-clock shared CPU before moving to dedicated"
  },

  // Dedicated CPU instances
  {
    name: "CCX12",
    type: "dedicated",
    vcpu: 2,
    memory: 8,
    storage: 80,
    monthlyPrice: 15.84,
    hourlyPrice: 0.024,
    network: "10 Gbps",
    description: "Dedicated CPU for consistent performance"
  },
  {
    name: "CCX22",
    type: "dedicated",
    vcpu: 4,
    memory: 16,
    storage: 160,
    monthlyPrice: 29.75,
    hourlyPrice: 0.045,
    network: "10 Gbps",
    description: "Dedicated CPU for reliable workloads"
  },
  {
    name: "CCX32",
    type: "dedicated",
    vcpu: 8,
    memory: 32,
    storage: 240,
    monthlyPrice: 57.42,
    hourlyPrice: 0.087,
    network: "10 Gbps",
    description: "Dedicated CPU for high-performance apps"
  },
  {
    name: "CCX42",
    type: "dedicated",
    vcpu: 16,
    memory: 64,
    storage: 360,
    monthlyPrice: 112.67,
    hourlyPrice: 0.171,
    network: "10 Gbps",
    description: "Dedicated CPU for enterprise workloads"
  },
  {
    name: "CCX52",
    type: "dedicated",
    vcpu: 32,
    memory: 128,
    storage: 600,
    monthlyPrice: 223.17,
    hourlyPrice: 0.338,
    network: "10 Gbps",
    description: "Dedicated CPU for high-scale applications"
  },

  // ARM instances (more cost-effective)
  {
    name: "CAX11",
    type: "arm",
    vcpu: 2,
    memory: 4,
    storage: 40,
    monthlyPrice: 3.40,
    hourlyPrice: 0.005,
    network: "10 Gbps",
    description: "ARM-based cost-effective option"
  },
  {
    name: "CAX21",
    type: "arm",
    vcpu: 4,
    memory: 8,
    storage: 80,
    monthlyPrice: 6.80,
    hourlyPrice: 0.010,
    network: "10 Gbps",
    description: "ARM-based for moderate workloads"
  },
  {
    name: "CAX31",
    type: "arm",
    vcpu: 8,
    memory: 16,
    storage: 160,
    monthlyPrice: 13.60,
    hourlyPrice: 0.021,
    network: "10 Gbps",
    description: "ARM-based for performance workloads"
  }
];

// Additional storage pricing (if needed beyond base storage)
export const hetznerStoragePricing = {
  volumeStoragePerGB: 0.0476, // EUR per GB per month
  snapshotPerGB: 0.0119, // EUR per GB per month
  backupPercentage: 20, // 20% of server price for backup service
};

// Network pricing
export const hetznerNetworkPricing = {
  trafficIncluded: 1000, // GB per month included
  additionalTrafficPerTB: 1.19, // EUR per TB
};

export function findBestHetznerInstance(
  requiredCpu: number,
  requiredMemory: number,
  requiredStorage: number,
  preferDedicated: boolean = false,
  allowARM: boolean = true
): { 
  recommended: HetznerInstance;
  alternatives: HetznerInstance[];
  isOverprovisioned: boolean;
} {
  // Filter instances based on requirements
  let suitableInstances = hetznerInstances.filter(instance => 
    instance.vcpu >= requiredCpu &&
    instance.memory >= requiredMemory &&
    instance.storage >= requiredStorage
  );

  // Apply preferences
  if (!allowARM) {
    suitableInstances = suitableInstances.filter(instance => instance.type !== 'arm');
  }

  if (preferDedicated) {
    const dedicatedInstances = suitableInstances.filter(instance => instance.type === 'dedicated');
    if (dedicatedInstances.length > 0) {
      suitableInstances = dedicatedInstances;
    }
  }

  // Sort by price (ascending)
  suitableInstances.sort((a, b) => a.monthlyPrice - b.monthlyPrice);

  if (suitableInstances.length === 0) {
    // Return the largest instance if nothing fits
    const largest = hetznerInstances[hetznerInstances.length - 1];
    return {
      recommended: largest,
      alternatives: [],
      isOverprovisioned: false
    };
  }

  const recommended = suitableInstances[0];
  const alternatives = suitableInstances.slice(1, 4); // Show up to 3 alternatives

  // Check if we're significantly overprovisioning
  const cpuOverprovision = recommended.vcpu > requiredCpu * 2;
  const memoryOverprovision = recommended.memory > requiredMemory * 2;
  const isOverprovisioned = cpuOverprovision || memoryOverprovision;

  return {
    recommended,
    alternatives,
    isOverprovisioned
  };
}
