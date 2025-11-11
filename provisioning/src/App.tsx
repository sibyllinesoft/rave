import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import * as Icons from 'lucide-react';
import { availableServices } from './data/services';
import { CompanyDetails, Service, ServiceConfig } from './types';
import { ServiceCard } from './components/ServiceCard';
import { CompanyDetailsPanel } from './components/CompanyDetailsPanel';
import { ProvisioningSummary } from './components/ProvisioningSummary';
import { ReviewTable } from './components/ReviewTable';
import { useDebouncedValue } from './hooks/useDebouncedValue';
import { buildProvisioningSnapshot, createDefaultServiceConfigs } from './utils/provisioning';
import { calculateServiceRequirements } from './utils/estimation';

const CALC_DEBOUNCE = 150;

const steps: { id: 'services' | 'company' | 'review'; title: string; desc: string }[] = [
  { id: 'services', title: 'Select services', desc: 'Choose the stack you want to provision' },
  { id: 'company', title: 'Company profile', desc: 'Team size + workload signals' },
  { id: 'review', title: 'Review & export', desc: 'Totals, cost drivers, JSON plan' },
];

const categories = [
  { id: 'core', title: 'Core infrastructure', icon: Icons.Server, description: 'Datastores, ingress, cache layers' },
  { id: 'development', title: 'Dev acceleration', icon: Icons.Code2, description: 'Message buses, workflow, automation' },
  { id: 'monitoring', title: 'Observability', icon: Icons.BarChart3, description: 'Dashboards, tracing, alerting' },
  { id: 'security', title: 'Zero trust & security', icon: Icons.ShieldCheck, description: 'Access control, identity, policy enforcement' },
  { id: 'design', title: 'Design & prototyping', icon: Icons.Palette, description: 'Product design + research tools' },
  { id: 'collaboration', title: 'Collaboration', icon: Icons.Users, description: 'Knowledge base, chat, async work' },
];

const initialCompanyDetails: CompanyDetails = {
  name: '',
  teamSize: 12,
  developmentIntensity: 'moderate',
  cicdUsage: 'moderate',
  concurrentUsers: 25,
  estimatedMonthlyTraffic: 150,
};

const emptyFootprint = { cpu: 0, memory: 0, storage: 0 } as const;

function App() {
  const [currentStep, setCurrentStep] = useState<'services' | 'company' | 'review'>('services');
  const [companyDetails, setCompanyDetails] = useState<CompanyDetails>(initialCompanyDetails);
  const [serviceConfigs, setServiceConfigs] = useState<Record<string, ServiceConfig>>(createDefaultServiceConfigs(availableServices));
  const [isPendingRecalc, setIsPendingRecalc] = useState(false);
  const [showSkeleton, setShowSkeleton] = useState(true);
  const bootstrapped = useRef(false);

  const debouncedDetails = useDebouncedValue(companyDetails, CALC_DEBOUNCE);
  const debouncedConfigs = useDebouncedValue(serviceConfigs, CALC_DEBOUNCE);

  useEffect(() => {
    const timer = setTimeout(() => setShowSkeleton(false), 360);
    return () => clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!bootstrapped.current) {
      bootstrapped.current = true;
      return;
    }
    setIsPendingRecalc(true);
  }, [companyDetails, serviceConfigs]);

  useEffect(() => {
    if (isPendingRecalc) {
      setIsPendingRecalc(false);
    }
  }, [debouncedDetails, debouncedConfigs, isPendingRecalc]);

  const selectedServices = useMemo(
    () => availableServices.filter(service => serviceConfigs[service.id]?.include),
    [serviceConfigs]
  );

  const debouncedSelectedServices = useMemo(
    () => availableServices.filter(service => debouncedConfigs[service.id]?.include),
    [debouncedConfigs]
  );

  const liveRequirements = useMemo(() => {
    const map = new Map<string, { cpu: number; memory: number; storage: number }>();
    availableServices.forEach(service => {
      const config = serviceConfigs[service.id];
      map.set(service.id, calculateServiceRequirements(service, companyDetails, config));
    });
    return map;
  }, [companyDetails, serviceConfigs]);

  const liveSnapshot = useMemo(
    () => buildProvisioningSnapshot(selectedServices, companyDetails, serviceConfigs),
    [selectedServices, companyDetails, serviceConfigs]
  );

  const stableSnapshot = useMemo(
    () => buildProvisioningSnapshot(debouncedSelectedServices, debouncedDetails, debouncedConfigs),
    [debouncedSelectedServices, debouncedDetails, debouncedConfigs]
  );

  const dependencyState = useMemo(() => deriveDependencyState(availableServices, serviceConfigs), [serviceConfigs]);

  const handleConfigChange = useCallback(
    (serviceId: string, updates: Partial<ServiceConfig>) => {
      setServiceConfigs(prev => ({
        ...prev,
        [serviceId]: { ...prev[serviceId], ...updates },
      }));
    },
    []
  );

  const handleExportPlan = useCallback(() => {
    const blob = new Blob([JSON.stringify(stableSnapshot, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = 'rave-provisioning-plan.json';
    anchor.click();
    URL.revokeObjectURL(url);
  }, [stableSnapshot]);

  const handleStepChange = (step: 'services' | 'company' | 'review') => {
    setCurrentStep(step);
  };

  const liveCatalogue = (
    <div className="space-y-8">
      {categories.map(category => {
        const entries = availableServices.filter(service => service.category === category.id);
        if (!entries.length) return null;
        return (
          <section key={category.id} className="space-y-4">
            <header className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-[color:var(--color-muted)]">
                  {category.title}
                </p>
                <h3 className="text-[20px] font-semibold text-[color:var(--color-text-1)]">
                  {category.description}
                </h3>
              </div>
              <category.icon className="h-5 w-5 text-[color:var(--color-muted)]" />
            </header>
            <div className="space-y-4">
              {entries.map(service => {
                const config = serviceConfigs[service.id];
                const requirements = liveRequirements.get(service.id) ?? emptyFootprint;
                return (
                  <ServiceCard
                    key={service.id}
                    service={service}
                    config={config}
                    requirements={requirements}
                    onConfigChange={handleConfigChange}
                    isDisabled={dependencyState[service.id]?.disabled}
                    disabledReason={dependencyState[service.id]?.reason}
                    isCalculating={isPendingRecalc}
                  />
                );
              })}
            </div>
          </section>
        );
      })}

      {!selectedServices.length && (
        <div className="rounded-[var(--radius-card)] border border-dashed border-[color:var(--color-stroke)]/60 bg-[color:var(--color-bg-2)]/60 p-6 text-center text-sm text-[color:var(--color-text-2)]">
          <p className="font-semibold text-[color:var(--color-text-1)]">No services selected</p>
          <p className="mt-2">Pick services to start; we’ll compute totals here.</p>
        </div>
      )}
    </div>
  );

  const skeletonCatalogue = (
    <div className="space-y-4">
      {Array.from({ length: 3 }).map((_, idx) => (
        <div
          key={idx}
          className="h-40 animate-pulse rounded-[var(--radius-card)] border border-[color:var(--color-stroke)]/20 bg-[color:var(--color-bg-2)]/40"
        />
      ))}
    </div>
  );

  const leftColumn =
    currentStep === 'review' ? <ReviewTable snapshot={stableSnapshot} /> : showSkeleton ? skeletonCatalogue : liveCatalogue;

  return (
    <div className="min-h-screen bg-[color:var(--color-bg-0)] pb-32 text-[color:var(--color-text-1)]">
      <header className="border-b border-[color:var(--color-stroke)]/30 bg-[color:var(--color-bg-1)]/95">
        <div className="mx-auto max-w-7xl px-6 py-8">
          <h1 className="text-[34px] font-semibold text-[color:var(--color-text-1)]">Rave Provisioning Manager</h1>

          <nav className="mt-6 grid gap-3 md:grid-cols-3">
            {steps.map(step => (
              <button
                key={step.id}
                type="button"
                onClick={() => handleStepChange(step.id)}
                className={`rounded-[var(--radius-card)] border px-4 py-3 text-left transition-all duration-150 ${
                  currentStep === step.id
                    ? 'border-[color:var(--color-accent)] bg-[color:var(--color-accent)]/15 text-[color:var(--color-text-1)]'
                    : 'border-[color:var(--color-stroke)]/30 text-[color:var(--color-text-2)]'
                }`}
              >
                <div className="text-xs font-medium uppercase tracking-wide">{step.title}</div>
                <p className="text-sm text-[color:var(--color-muted)]">{step.desc}</p>
              </button>
            ))}
          </nav>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-6 py-10 2xl:px-8">
        <div className="grid gap-6 xl:grid-cols-12">
          <div className="space-y-6 xl:col-span-8 xl:pr-4" aria-live="polite">
            {leftColumn}
          </div>
          <div className="xl:col-span-4">
            <div className="space-y-6 xl:sticky xl:top-6">
              <CompanyDetailsPanel details={companyDetails} onUpdate={setCompanyDetails} />
              <div className="hidden xl:block">
                <ProvisioningSummary
                  snapshot={liveSnapshot}
                  isCalculating={isPendingRecalc}
                  onReview={() => setCurrentStep('review')}
                  onExport={handleExportPlan}
                />
              </div>
            </div>
          </div>
        </div>
      </main>

      <div className="xl:hidden fixed inset-x-0 bottom-0 z-30">
        <ProvisioningSummary
          snapshot={liveSnapshot}
          isCalculating={isPendingRecalc}
          onReview={() => setCurrentStep('review')}
          onExport={handleExportPlan}
          layout="drawer"
        />
      </div>
    </div>
  );
}

function deriveDependencyState(services: Service[], configs: Record<string, ServiceConfig>) {
  const state: Record<string, { disabled: boolean; reason?: string }> = {};
  services.forEach(service => {
    const missing = service.requirements?.filter(req => {
      const dependencyId = normaliseRequirement(req);
      return !configs[dependencyId]?.include;
    });
    if (missing && missing.length) {
      state[service.id] = {
        disabled: true,
        reason: `Requires: ${missing.join(', ')}`,
      };
    } else {
      state[service.id] = { disabled: false };
    }
  });
  return state;
}

function normaliseRequirement(req: string) {
  const normalized = req.toLowerCase();
  const byId = availableServices.find(service => service.id === normalized);
  if (byId) return byId.id;
  const byName = availableServices.find(service => service.name.toLowerCase() === normalized);
  return byName?.id ?? normalized;
}

export default App;
