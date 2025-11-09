import { useEffect, useRef, useState } from 'react';
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
  const [draftDetails, setDraftDetails] = useState(details);
  const lastCommittedRef = useRef(details);

  useEffect(() => {
    setDraftDetails(details);
    lastCommittedRef.current = details;
  }, [details]);

  const updateField = <K extends keyof CompanyDetails>(field: K, value: CompanyDetails[K]) => {
    setDraftDetails(prev => ({ ...prev, [field]: value }));
  };

  const commitDraft = (override?: CompanyDetails) => {
    const payload = override ?? draftDetails;
    if (lastCommittedRef.current === payload) {
      return;
    }
    lastCommittedRef.current = payload;
    onUpdate(payload);
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
            value={draftDetails.teamSize}
            min={1}
            max={500}
            onChange={value => updateField('teamSize', value)}
            onCommit={commitDraft}
          />
          <NumberField
            label="Total users"
            value={draftDetails.concurrentUsers}
            min={1}
            max={1000}
            onChange={value => updateField('concurrentUsers', value)}
            onCommit={commitDraft}
          />
        </div>

        <SegmentGroup
          label="Development activity"
          value={draftDetails.developmentIntensity}
          options={devIntensityOptions}
          onChange={value => {
            const nextValue = value as CompanyDetails['developmentIntensity'];
            const nextDetails = { ...draftDetails, developmentIntensity: nextValue };
            setDraftDetails(nextDetails);
            commitDraft(nextDetails);
          }}
        />

        <SegmentGroup
          label="CI/CD usage"
          value={draftDetails.cicdUsage}
          options={cicdOptions}
          onChange={value => {
            const nextValue = value as CompanyDetails['cicdUsage'];
            const nextDetails = { ...draftDetails, cicdUsage: nextValue };
            setDraftDetails(nextDetails);
            commitDraft(nextDetails);
          }}
        />
      </div>
    </section>
  );
};

interface NumberFieldProps {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
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
      onChange={event => onChange(Math.min(max, Math.max(min, Number(event.target.value) || min)))}
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
