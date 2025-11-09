export const tokens = {
  colors: {
    bg0: '#0E1113',
    bg1: '#121619',
    bg2: '#181D21',
    stroke: 'rgba(39, 50, 58, 0.3)',
    strokeStrong: '#27323A',
    muted: '#6B7785',
    textPrimary: '#E6ECF1',
    textSecondary: '#BAC4CE',
    accent: '#24AE7C',
    accentWeak: '#1B8D64',
    warn: '#E9B949',
    danger: '#EF6A6A',
    focus: '#3AA0FF',
  },
  spacing: {
    xs: 8,
    sm: 12,
    md: 16,
    lg: 24,
    xl: 32,
  },
  radii: {
    card: 12,
    control: 8,
    pill: 999,
  },
  shadow: {
    elevated: '0 1px 0 rgba(0,0,0,0.4), 0 8px 24px rgba(0,0,0,0.2)',
    soft: '0 1px 0 rgba(0,0,0,0.4), 0 4px 16px rgba(0,0,0,0.18)',
  },
  typography: {
    family: "'Inter', 'Söhne', system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
    sizes: {
      xs: 12,
      sm: 14,
      base: 16,
      lg: 20,
      xl: 24,
      xxl: 32,
    },
    weight: {
      body: 400,
      label: 500,
      heading: 600,
    },
  },
} as const;

export const costModel = {
  perCpu: 14,
  perMemoryGb: 4.5,
  perStorageGb: 0.2,
};
