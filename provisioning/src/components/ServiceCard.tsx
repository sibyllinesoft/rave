import { useEffect, useRef, useState } from 'react';
import { Service, ServiceConfig, ResourceFootprint } from '../types';
import * as Icons from 'lucide-react';

const specMap = [
  { key: 'cpu', label: 'vCPU', icon: Icons.Cpu, unit: 'vCPU' },
  { key: 'memory', label: 'RAM', icon: Icons.HardDrive, unit: 'GB' },
  { key: 'storage', label: 'Storage', icon: Icons.Database, unit: 'GB' },
] as const;

interface ServiceCardProps {
  service: Service;
  config: ServiceConfig;
  requirements: ResourceFootprint;
  onConfigChange: (serviceId: string, updates: Partial<ServiceConfig>) => void;
  isDisabled?: boolean;
  disabledReason?: string;
  isCalculating: boolean;
}

export const ServiceCard = ({
  service,
  config,
  requirements,
  onConfigChange,
  isDisabled = false,
  disabledReason,
  isCalculating,
}: ServiceCardProps) => {
  const IconComponent = (Icons as any)[service.icon] || Icons.Package;
  const [deltaLabel, setDeltaLabel] = useState<string | null>(null);
  const previousRequirements = useRef<ResourceFootprint>(requirements);

  useEffect(() => {
    const prev = previousRequirements.current;
    const diffs: string[] = [];

    specMap.forEach(spec => {
      const change = Number((requirements[spec.key] - prev[spec.key]).toFixed(2));
      if (change !== 0) {
        const sign = change > 0 ? '+' : '';
        const suffix = spec.unit === 'vCPU' ? ' vCPU' : ` ${spec.unit}`;
        diffs.push(`${sign}${change}${suffix}`);
      }
    });

    previousRequirements.current = requirements;

    if (diffs.length) {
      setDeltaLabel(diffs.join(' · '));
      const timer = setTimeout(() => setDeltaLabel(null), 800);
      return () => clearTimeout(timer);
    }

    return undefined;
  }, [requirements]);

  const docsHref = `https://docs.rave.run/services/${service.id}`;

  const toggleInclude = () => {
    onConfigChange(service.id, { include: !config.include });
  };

  return (
    <article
      className={`relative rounded-[var(--radius-card)] border border-[color:var(--color-stroke)]/30 bg-[color:var(--color-bg-1)] shadow-soft transition-colors duration-200 hover:bg-[color:var(--color-bg-2)]/80 ${
        isDisabled ? 'opacity-60 pointer-events-none' : ''
      }`}
      aria-disabled={isDisabled}
    >
      <div className="p-6 space-y-5">
        <header className="flex items-start justify-between gap-4">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/40 bg-[color:var(--color-bg-2)]">
              <IconComponent className="h-5 w-5 text-[color:var(--color-accent)]" />
            </div>
            <div>
              <div className="flex items-center gap-3">
                <h3 className="text-[22px] font-semibold text-[color:var(--color-text-1)]">{service.name}</h3>
                <span className="inline-flex items-center rounded-full border border-[color:var(--color-stroke)]/40 px-3 py-1 text-xs font-medium uppercase tracking-wide text-[color:var(--color-muted)]">
                  {service.category}
                </span>
              </div>
              <p className="mt-1 text-sm text-[color:var(--color-text-2)] max-w-xl">{service.description}</p>
              {isCalculating && (
                <div className="mt-2 inline-flex items-center gap-2 text-xs text-[color:var(--color-muted)]">
                  <Icons.Loader2 className="h-3.5 w-3.5 animate-spin" /> live update
                </div>
              )}
            </div>
          </div>
          <button
            type="button"
            onClick={toggleInclude}
            className={`rounded-[var(--radius-control)] border px-3 py-1.5 text-sm font-semibold transition-colors duration-150 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[color:var(--color-focus)] ${
              config.include
                ? 'border-[color:var(--color-accent)] bg-[color:var(--color-accent)]/15 text-[color:var(--color-accent)]'
                : 'border-[color:var(--color-stroke)]/40 text-[color:var(--color-text-2)] hover:text-[color:var(--color-text-1)]'
            }`}
            aria-pressed={config.include}
          >
            {config.include ? 'Included' : 'Add service'}
          </button>
        </header>

        <section className="space-y-4">
          <div className="grid gap-3 md:grid-cols-3">
            {specMap.map(spec => {
              const Icon = spec.icon;
              const baselineValue = service.resourceUsage[spec.key];
              const currentValue = requirements[spec.key];
              const delta = Number((currentValue - baselineValue).toFixed(1));

              return (
                <div
                  key={spec.key}
                  className="rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/30 bg-[color:var(--color-bg-2)]/60 p-4"
                >
                  <div className="flex items-center justify-between text-xs text-[color:var(--color-muted)]">
                    <span className="inline-flex items-center gap-2 font-medium">
                      <Icon className="h-4 w-4" />
                      {spec.label}
                    </span>
                  </div>
                  <div className="mt-2 text-[24px] font-semibold text-[color:var(--color-text-1)]">
                    {currentValue.toFixed(1)} <span className="text-base text-[color:var(--color-muted)]">{spec.unit}</span>
                  </div>
                  <div className="text-xs text-[color:var(--color-text-2)]">
                    Baseline {baselineValue}{spec.unit === 'vCPU' ? '' : ` ${spec.unit}`}
                  </div>
                  <div className={`mt-1 text-xs font-semibold ${delta > 0 ? 'text-[color:var(--color-accent)]' : 'text-[color:var(--color-muted)]'}`}>
                    {delta === 0 ? 'No change' : `${delta > 0 ? '+' : ''}${delta} ${spec.unit}`}
                  </div>
                </div>
              );
            })}
          </div>

          {deltaLabel && (
            <div className="rounded-[var(--radius-control)] bg-[color:var(--color-accent)]/10 border border-[color:var(--color-accent)]/40 px-4 py-2 text-sm font-medium text-[color:var(--color-accent)] transition-opacity duration-200">
              {deltaLabel}
            </div>
          )}
        </section>

        <footer className="flex flex-wrap items-center gap-2 text-xs text-[color:var(--color-muted)]">
          {service.requirements?.map(req => (
            <span key={req} className="rounded-full border border-[color:var(--color-stroke)]/40 px-2 py-0.5">
              Depends on {req}
            </span>
          ))}
          <a
            href={docsHref}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 text-[color:var(--color-text-2)] hover:text-[color:var(--color-accent)]"
          >
            <Icons.ExternalLink className="h-3.5 w-3.5" /> Docs
          </a>
        </footer>
      </div>

      {isDisabled && disabledReason && (
        <div className="absolute inset-0 rounded-[var(--radius-card)] bg-[color:var(--color-bg-0)]/90 p-4 text-center text-sm text-[color:var(--color-text-2)]">
          {disabledReason}
        </div>
      )}
    </article>
  );
};
