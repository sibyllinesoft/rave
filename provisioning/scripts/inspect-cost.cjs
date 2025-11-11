const { buildProvisioningSnapshot, createDefaultServiceConfigs } = require('../../tmp-run/utils/provisioning.js');
const { availableServices } = require('../../tmp-run/data/services.js');

const companyDetails = {
  name: '',
  teamSize: 12,
  developmentIntensity: 'moderate',
  cicdUsage: 'moderate',
  concurrentUsers: 25,
  estimatedMonthlyTraffic: 150,
};

const serviceConfigs = createDefaultServiceConfigs(availableServices);

const logSnapshot = (label, snapshot) => {
  const { estimate, totals } = snapshot;
  console.log(label, {
    services: snapshot.breakdown.map(item => item.service.id),
    vm: estimate.recommendedInstanceType,
    totalCpu: estimate.totalCpu,
    totalMem: estimate.totalMemory,
    totalStorage: estimate.totalStorage,
    cost: totals.cost,
  });
};

const setInclude = (serviceId, include) => {
  serviceConfigs[serviceId] = { ...(serviceConfigs[serviceId] || { include: false }), include };
};

function snapshot() {
  const selected = availableServices.filter(service => serviceConfigs[service.id]?.include);
  return buildProvisioningSnapshot(selected, companyDetails, serviceConfigs);
}

let snap = snapshot();
logSnapshot('initial', snap);

setInclude('grafana', true);
snap = snapshot();
logSnapshot('after grafana', snap);

setInclude('prometheus', true);
snap = snapshot();
logSnapshot('after prometheus', snap);

setInclude('grafana', false);
snap = snapshot();
logSnapshot('after removing grafana', snap);

Object.keys(serviceConfigs).forEach(id => setInclude(id, false));
snap = snapshot();
logSnapshot('after removing all', snap);

setInclude('grafana', true);
snap = snapshot();
logSnapshot('grafana only', snap);
