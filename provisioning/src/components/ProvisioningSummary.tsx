import { ComponentType, SVGProps } from 'react';
import { ProvisioningSnapshot } from '../types';
import * as Icons from 'lucide-react';
import { useDeltaPulse } from '../hooks/useDeltaPulse';

interface ProvisioningSummaryProps {
  snapshot: ProvisioningSnapshot;
  isCalculating: boolean;
  onReview: () => void;
  onExport: () => void;
  layout?: 'panel' | 'drawer';
}

const metricConfig = [
  { key: 'cpu', label: 'Total vCPU', unit: 'vCPU', icon: Icons.Cpu },
  { key: 'memory', label: 'Memory', unit: 'GB', icon: Icons.HardDrive },
  { key: 'storage', label: 'Storage', unit: 'GB', icon: Icons.Database },
  { key: 'cost', label: 'Est. cost', unit: '$/mo', icon: Icons.BadgeDollarSign },
] as const;

export const ProvisioningSummary = ({
  snapshot,
  isCalculating,
  onReview,
  onExport,
  layout = 'panel',
}: ProvisioningSummaryProps) => {
  const totals = {
    cpu: snapshot.estimate.totalCpu,
    memory: snapshot.estimate.totalMemory,
    storage: snapshot.estimate.totalStorage,
    cost: snapshot.totals.cost,
  } as const;

  const deltas = {
    cpu: useDeltaPulse(totals.cpu),
    memory: useDeltaPulse(totals.memory),
    storage: useDeltaPulse(totals.storage),
    cost: useDeltaPulse(totals.cost),
  };

  const activeBuckets = snapshot.bucketPlans.filter(plan => plan.serviceIds.length > 0 && plan.estimate.estimatedCost > 0);
  const vmLabel = activeBuckets.length ? `${activeBuckets.length} VM${activeBuckets.length > 1 ? 's' : ''}` : 'No VMs';
  const vmSubtitle = activeBuckets.length
    ? activeBuckets.map(plan => plan.label).join(' · ')
    : 'Add services to generate dedicated plans.';

  const containerClasses =
    layout === 'panel'
      ? 'rounded-[var(--radius-card)] border border-[color:var(--color-stroke)]/40 bg-[color:var(--color-bg-1)] shadow-elevated'
      : 'rounded-t-[var(--radius-card)] border border-[color:var(--color-stroke)]/40 bg-[color:var(--color-bg-1)] shadow-elevated';

  return (
    <section className={`${containerClasses} ${layout === 'drawer' ? 'px-4 py-4' : 'p-6 space-y-6'}`} aria-live="polite">
      <header className="flex items-center justify-between gap-2">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-[color:var(--color-muted)]">
            Provisioning summary
          </p>
          <h3 className="text-[20px] font-semibold text-[color:var(--color-text-1)]">Always-on totals</h3>
          <p className="text-xs text-[color:var(--color-muted)] mt-1">
            Hetzner quote: ${snapshot.estimate.estimatedCost.toFixed(0)}/mo · {vmLabel}
            <span className="block text-[color:var(--color-text-2)]/80">{vmSubtitle}</span>
          </p>
        </div>
        <span className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-semibold ${
          isCalculating
            ? 'bg-[color:var(--color-warn)]/10 text-[color:var(--color-warn)]'
            : 'bg-[color:var(--color-accent)]/10 text-[color:var(--color-accent)]'
        }`}>
          {isCalculating ? (
            <>
              <Icons.Loader2 className="h-3.5 w-3.5 animate-spin" /> Calculating
            </>
          ) : (
            <>
              <Icons.CheckCircle2 className="h-3.5 w-3.5" /> Up to date
            </>
          )}
        </span>
      </header>

      <div className="grid gap-3 md:grid-cols-2">
        {metricConfig.map(metric => (
          <MetricCard
            key={metric.key}
            icon={metric.icon}
            label={metric.label}
            unit={metric.unit}
            value={totals[metric.key]}
            delta={deltas[metric.key]}
          />
        ))}
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between text-xs text-[color:var(--color-muted)]">
          <span>Dedicated VMs by tier</span>
          <span>Total: ${snapshot.estimate.estimatedCost.toFixed(0)}/mo</span>
        </div>
        <div className="space-y-2">
          {snapshot.bucketPlans.map(plan => (
            <div
              key={plan.id}
              className="rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/30 bg-[color:var(--color-bg-2)]/60 p-4"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-[color:var(--color-muted)]">{plan.label}</p>
                  <p className="text-sm text-[color:var(--color-text-1)]">{plan.estimate.recommendedInstanceType}</p>
                  <p className="text-xs text-[color:var(--color-muted)]">
                    {plan.serviceIds.length ? `${plan.serviceIds.length} service${plan.serviceIds.length > 1 ? 's' : ''}` : 'No services assigned'}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-lg font-semibold text-[color:var(--color-text-1)]">${plan.estimate.estimatedCost.toFixed(0)}/mo</p>
                  <p className="text-xs text-[color:var(--color-muted)]">{plan.estimate.totalCpu} vCPU · {plan.estimate.totalMemory} GB</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between text-xs text-[color:var(--color-muted)]">
          <span>Top cost drivers</span>
          <span title="Proportional share of VM cost">Share of VM cost (USD)</span>
        </div>
        <div className="rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/30 bg-[color:var(--color-bg-2)]/60 p-4 text-sm text-[color:var(--color-text-1)]">
          {snapshot.costDrivers.length ? (
            <ul className="space-y-2">
              {snapshot.costDrivers.map(item => (
                <li key={item.service.id} className="flex items-center justify-between">
                  <span className="flex items-center gap-2 text-[color:var(--color-text-2)]">
                    <Icons.Activity className="h-3.5 w-3.5 text-[color:var(--color-muted)]" />
                    {item.service.name}
                  </span>
                  <span className="font-semibold text-[color:var(--color-accent)]">+${item.cost.toFixed(0)}/mo</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-[color:var(--color-muted)]">Select services to see drivers.</p>
          )}
        </div>
        {snapshot.bottlenecks.length > 0 && (
          <div className="rounded-[var(--radius-control)] border border-[color:var(--color-warn)]/40 bg-[color:var(--color-warn)]/10 p-3 text-xs text-[color:var(--color-warn)]">
            <p className="font-semibold uppercase tracking-wide">Bottlenecks</p>
            <ul className="mt-1 list-disc pl-4">
              {snapshot.bottlenecks.map(item => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </div>
        )}
      </div>

      <div className={`flex flex-col gap-3 ${layout === 'drawer' ? 'md:flex-row md:items-center md:justify-between' : 'md:flex-row md:items-center md:justify-between'}`}>
        <div className="text-xs text-[color:var(--color-muted)]">
          CTA updates under 100 ms · Export JSON plan for audits.
        </div>
        <div className="flex flex-col gap-2 md:flex-row">
          <button
            type="button"
            onClick={onExport}
            className="rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/40 px-4 py-2 text-sm font-semibold text-[color:var(--color-text-1)] hover:border-[color:var(--color-accent)]/40"
          >
            Export plan
          </button>
          <button
            type="button"
            onClick={onReview}
            className="rounded-[var(--radius-control)] bg-[color:var(--color-accent)] px-4 py-2 text-sm font-semibold text-black transition-colors duration-150 hover:bg-[color:var(--color-accent-weak)]/90"
          >
            Review & Provision
          </button>
        </div>
      </div>
    </section>
  );
};

interface MetricProps {
  icon: ComponentType<SVGProps<SVGSVGElement>>;
  label: string;
  unit: string;
  value: number;
  delta: number;
}

const MetricCard = ({ icon: Icon, label, unit, value, delta }: MetricProps) => {
  const formattedValue = unit === '$/mo' ? `$${value.toFixed(0)}` : value.toFixed(1);
  const deltaLabel = delta !== 0 ? `${delta > 0 ? '+' : ''}${unit === '$/mo' ? `$${delta.toFixed(0)}` : delta.toFixed(1)}` : null;

  return (
    <div className="rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/30 bg-[color:var(--color-bg-2)]/60 p-4">
      <div className="flex items-center justify-between text-xs text-[color:var(--color-muted)]">
        <span className="inline-flex items-center gap-2">
          <Icon className="h-4 w-4" />
          {label}
        </span>
        {deltaLabel && (
          <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide ${
            delta > 0 ? 'bg-[color:var(--color-accent)]/15 text-[color:var(--color-accent)]' : 'bg-[color:var(--color-muted)]/15 text-[color:var(--color-muted)]'
          }`}>
            {deltaLabel}
          </span>
        )}
      </div>
      <div className="mt-2 text-[32px] font-semibold text-[color:var(--color-text-1)]">
        {formattedValue}
        <span className="ml-1 text-sm text-[color:var(--color-text-2)]">{unit}</span>
      </div>
    </div>
  );
};
