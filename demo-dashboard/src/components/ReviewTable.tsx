import { useState } from 'react';
import { ProvisioningSnapshot } from '../types';

interface ReviewTableProps {
  snapshot: ProvisioningSnapshot;
}

export const ReviewTable = ({ snapshot }: ReviewTableProps) => {
  const [billingMode, setBillingMode] = useState<'monthly' | 'hourly'>('monthly');
  const divisor = billingMode === 'monthly' ? 1 : 730;
  const costLabel = billingMode === 'monthly' ? '$/mo' : '$/hr';
  const vmCost = snapshot.totals.cost;

  return (
    <section className="rounded-[var(--radius-card)] border border-[color:var(--color-stroke)]/40 bg-[color:var(--color-bg-1)] shadow-soft">
      <header className="flex flex-wrap items-center justify-between gap-4 border-b border-[color:var(--color-stroke)]/30 px-6 py-4">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-[color:var(--color-muted)]">Review</p>
          <h2 className="text-[24px] font-semibold text-[color:var(--color-text-1)]">Service × resource table</h2>
        </div>
        <div className="flex items-center gap-2 text-sm">
          <span className="text-[color:var(--color-text-2)]">Billing mode</span>
          <div className="flex overflow-hidden rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/40">
            {(['monthly', 'hourly'] as const).map(mode => (
              <button
                key={mode}
                type="button"
                onClick={() => setBillingMode(mode)}
                className={`px-3 py-1.5 text-xs font-semibold uppercase tracking-wide ${
                  billingMode === mode
                    ? 'bg-[color:var(--color-accent)]/20 text-[color:var(--color-accent)]'
                    : 'text-[color:var(--color-text-2)]'
                }`}
                aria-pressed={billingMode === mode}
              >
                {mode}
              </button>
            ))}
          </div>
        </div>
      </header>

      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-left text-sm text-[color:var(--color-text-2)]">
          <thead>
            <tr className="text-xs uppercase tracking-wide text-[color:var(--color-muted)]">
              <th className="px-6 py-3 font-semibold">Service</th>
              <th className="px-3 py-3 font-semibold">vCPU</th>
              <th className="px-3 py-3 font-semibold">RAM (GB)</th>
              <th className="px-3 py-3 font-semibold">Storage (GB)</th>
              <th className="px-4 py-3 font-semibold text-right">{costLabel}</th>
            </tr>
          </thead>
          <tbody>
            {snapshot.breakdown.map(item => (
              <tr key={item.service.id} className="border-t border-[color:var(--color-stroke)]/20">
                <td className="px-6 py-3 text-[color:var(--color-text-1)]">
                  <div className="flex flex-col">
                    <span className="font-semibold">{item.service.name}</span>
                    <span className="text-xs text-[color:var(--color-muted)]">{item.service.category}</span>
                  </div>
                </td>
                <td className="px-3 py-3">
                  <MetricCell value={item.requirements.cpu} delta={item.deltaFromBaseline.cpu} unit="vCPU" />
                </td>
                <td className="px-3 py-3">
                  <MetricCell value={item.requirements.memory} delta={item.deltaFromBaseline.memory} unit="GB" />
                </td>
                <td className="px-3 py-3">
                  <MetricCell value={item.requirements.storage} delta={item.deltaFromBaseline.storage} unit="GB" />
                </td>
                <td className="px-4 py-3 text-right text-[color:var(--color-text-1)] font-semibold">
                  ${(item.cost / divisor).toFixed(2)}
                </td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t border-[color:var(--color-stroke)]/40 text-[color:var(--color-text-1)]">
              <td className="px-6 py-4 font-semibold">Grand total</td>
              <td className="px-3 py-4 font-mono">{snapshot.estimate.totalCpu.toFixed(1)}</td>
              <td className="px-3 py-4 font-mono">{snapshot.estimate.totalMemory.toFixed(1)} GB</td>
              <td className="px-3 py-4 font-mono">{snapshot.estimate.totalStorage.toFixed(1)} GB</td>
              <td className="px-4 py-4 text-right text-[24px] font-bold">
                ${(vmCost / divisor).toFixed(2)}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </section>
  );
};

interface MetricCellProps {
  value: number;
  delta: number;
  unit: string;
}

const MetricCell = ({ value, delta, unit }: MetricCellProps) => (
  <div>
    <div className="text-[color:var(--color-text-1)] font-semibold">{value.toFixed(1)}</div>
    <div className="text-xs text-[color:var(--color-muted)]">
      {delta === 0 ? 'Baseline' : `${delta > 0 ? '+' : ''}${delta.toFixed(1)} ${unit}`}
    </div>
  </div>
);
