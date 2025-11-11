import { useEffect, useState } from 'react';
import { CompanyDetails } from '../types';
import * as Icons from 'lucide-react';

interface CompanyDetailsPanelProps {
  details: CompanyDetails;
  onUpdate: (details: CompanyDetails) => void;
}

const devIntensityOptions = [
  { value: 'light', label: 'Light' },
  { value: 'moderate', label: 'Moderate' },
  { value: 'heavy', label: 'Heavy' },
] as const;

const cicdOptions = [
  { value: 'minimal', label: 'Minimal' },
  { value: 'moderate', label: 'Moderate' },
  { value: 'extensive', label: 'Extensive' },
] as const;

export const CompanyDetailsPanel = ({ details, onUpdate }: CompanyDetailsPanelProps) => {
  const [draftQuantities, setDraftQuantities] = useState({
    teamSize: details.teamSize.toString(),
    concurrentUsers: details.concurrentUsers.toString(),
  });

  useEffect(() => {
    setDraftQuantities({
      teamSize: details.teamSize.toString(),
      concurrentUsers: details.concurrentUsers.toString(),
    });
  }, [details.teamSize, details.concurrentUsers]);

  const clampNumericInput = (value: string, min: number, max: number) => {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return Math.min(max, Math.max(min, parsed));
    }
    return min;
  };

  const normalisedNumbers = () => ({
    teamSize: clampNumericInput(draftQuantities.teamSize, 1, 500),
    concurrentUsers: clampNumericInput(draftQuantities.concurrentUsers, 1, 1000),
  });

  const buildNextDetails = (overrides: Partial<CompanyDetails> = {}) => ({
    ...details,
    ...normalisedNumbers(),
    ...overrides,
  });

  const commitNumbers = () => {
    const next = buildNextDetails();
    setDraftQuantities({ teamSize: next.teamSize.toString(), concurrentUsers: next.concurrentUsers.toString() });
    if (next.teamSize !== details.teamSize || next.concurrentUsers !== details.concurrentUsers) {
      onUpdate(next);
    }
  };

  return (
    <section className="rounded-[var(--radius-card)] border border-[color:var(--color-stroke)]/40 bg-[color:var(--color-bg-1)] shadow-soft">
      <header className="flex items-center justify-between border-b border-[color:var(--color-stroke)]/30 px-6 py-4">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-[color:var(--color-muted)]">Company profile</p>
          <h2 className="text-[20px] font-semibold text-[color:var(--color-text-1)]">Provisioning inputs</h2>
        </div>
        <Icons.SlidersHorizontal className="h-5 w-5 text-[color:var(--color-muted)]" />
      </header>

      <div className="space-y-6 px-6 py-6">
        <div className="grid gap-4 md:grid-cols-2">
          <NumberField
            label="Developers"
            value={draftQuantities.teamSize}
            min={1}
            max={500}
            onChange={value => setDraftQuantities(prev => ({ ...prev, teamSize: value }))}
            onCommit={commitNumbers}
          />
          <NumberField
            label="Total users"
            value={draftQuantities.concurrentUsers}
            min={1}
            max={1000}
            onChange={value => setDraftQuantities(prev => ({ ...prev, concurrentUsers: value }))}
            onCommit={commitNumbers}
          />
        </div>

        <SegmentGroup
          label="Development activity"
          value={details.developmentIntensity}
          options={devIntensityOptions}
          onChange={value => {
            const nextValue = value as CompanyDetails['developmentIntensity'];
            if (nextValue === details.developmentIntensity) return;
            const nextDetails = buildNextDetails({ developmentIntensity: nextValue });
            setDraftQuantities({ teamSize: nextDetails.teamSize.toString(), concurrentUsers: nextDetails.concurrentUsers.toString() });
            onUpdate(nextDetails);
          }}
        />

        <SegmentGroup
          label="CI/CD usage"
          value={details.cicdUsage}
          options={cicdOptions}
          onChange={value => {
            const nextValue = value as CompanyDetails['cicdUsage'];
            if (nextValue === details.cicdUsage) return;
            const nextDetails = buildNextDetails({ cicdUsage: nextValue });
            setDraftQuantities({ teamSize: nextDetails.teamSize.toString(), concurrentUsers: nextDetails.concurrentUsers.toString() });
            onUpdate(nextDetails);
          }}
        />
      </div>
    </section>
  );
};

interface NumberFieldProps {
  label: string;
  value: string;
  min: number;
  max: number;
  onChange: (value: string) => void;
  onCommit: () => void;
}

const NumberField = ({ label, value, min, max, onChange, onCommit }: NumberFieldProps) => (
  <div>
    <label className="text-sm font-medium text-[color:var(--color-text-2)]">{label}</label>
    <input
      type="number"
      min={min}
      max={max}
      value={value}
      onChange={event => onChange(event.target.value)}
      onBlur={onCommit}
      onKeyDown={event => {
        if (event.key === 'Enter') {
          onCommit();
          event.currentTarget.blur();
        }
      }}
      className="mt-1 w-full rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/40 bg-[color:var(--color-bg-2)] px-3 py-2 text-[color:var(--color-text-1)] focus:border-[color:var(--color-accent)]"
    />
  </div>
);

interface SegmentGroupProps {
  label: string;
  value: string;
  options: ReadonlyArray<{ value: string; label: string }>;
  onChange: (value: string) => void;
}

const SegmentGroup = ({ label, value, options, onChange }: SegmentGroupProps) => (
  <div>
    <label className="text-sm font-medium text-[color:var(--color-text-2)]">{label}</label>
    <div className="mt-2 grid gap-2 md:grid-cols-3">
      {options.map(option => (
        <button
          key={option.value}
          type="button"
          onClick={() => onChange(option.value)}
          className={`rounded-[var(--radius-control)] border px-3 py-2 text-left text-sm transition-colors duration-150 ${
            value === option.value
              ? 'border-[color:var(--color-accent)] bg-[color:var(--color-accent)]/15 text-[color:var(--color-accent)]'
              : 'border-[color:var(--color-stroke)]/40 text-[color:var(--color-text-2)] hover:text-[color:var(--color-text-1)]'
          }`}
          aria-pressed={value === option.value}
        >
          <div className="font-semibold">{option.label}</div>
        </button>
      ))}
    </div>
  </div>
);
