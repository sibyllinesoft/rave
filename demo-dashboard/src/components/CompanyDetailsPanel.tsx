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
  const updateField = <K extends keyof CompanyDetails>(field: K, value: CompanyDetails[K]) => {
    onUpdate({ ...details, [field]: value });
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
        <TextField
          label="Company name"
          placeholder="Acme DevLab"
          value={details.name}
          onChange={value => updateField('name', value)}
        />

        <div className="grid gap-4 md:grid-cols-2">
          <NumberField
            label="Team size"
            subtitle="People committing code"
            value={details.teamSize}
            min={1}
            max={500}
            onChange={value => updateField('teamSize', value)}
          />
          <NumberField
            label="Concurrent users"
            subtitle="Seats signed in at once"
            value={details.concurrentUsers}
            min={1}
            max={1000}
            onChange={value => updateField('concurrentUsers', value)}
          />
        </div>

        <SegmentGroup
          label="Development activity"
          value={details.developmentIntensity}
          options={devIntensityOptions}
          onChange={value => updateField('developmentIntensity', value as CompanyDetails['developmentIntensity'])}
        />

        <SegmentGroup
          label="CI/CD usage"
          value={details.cicdUsage}
          options={cicdOptions}
          onChange={value => updateField('cicdUsage', value as CompanyDetails['cicdUsage'])}
        />
      </div>
    </section>
  );
};

interface TextFieldProps {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  type?: string;
}

const TextField = ({ label, value, onChange, placeholder, type = 'text' }: TextFieldProps) => (
  <div>
    <label className="text-sm font-medium text-[color:var(--color-text-2)]">{label}</label>
    <input
      type={type}
      value={value}
      onChange={event => onChange(event.target.value)}
      placeholder={placeholder}
      className="mt-1 w-full rounded-[var(--radius-control)] border border-[color:var(--color-stroke)]/40 bg-[color:var(--color-bg-2)] px-3 py-2 text-[color:var(--color-text-1)] placeholder:text-[color:var(--color-muted)] focus:border-[color:var(--color-accent)]"
    />
  </div>
);

interface NumberFieldProps {
  label: string;
  subtitle?: string;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
}

const NumberField = ({ label, subtitle, value, min, max, onChange }: NumberFieldProps) => (
  <div>
    <label className="flex items-center justify-between text-sm font-medium text-[color:var(--color-text-2)]">
      {label}
      {subtitle && <span className="text-xs text-[color:var(--color-muted)]">{subtitle}</span>}
    </label>
    <input
      type="number"
      min={min}
      max={max}
      value={value}
      onChange={event => onChange(Math.min(max, Math.max(min, Number(event.target.value) || min)))}
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
