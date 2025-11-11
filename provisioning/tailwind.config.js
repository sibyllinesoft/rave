/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        surface: {
          0: '#0E1113',
          1: '#121619',
          2: '#181D21',
        },
        stroke: '#27323A',
        muted: '#6B7785',
        text: {
          primary: '#E6ECF1',
          secondary: '#BAC4CE',
        },
        accent: {
          DEFAULT: '#24AE7C',
          weak: '#1B8D64',
        },
        warn: '#E9B949',
        danger: '#EF6A6A',
        focus: '#3AA0FF',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Consolas', 'monospace'],
      },
      fontSize: {
        // Major Third Scale (1.25) for clear hierarchy
        'xs': ['0.75rem', { lineHeight: '1.5' }],     // 12px
        'sm': ['0.875rem', { lineHeight: '1.5' }],    // 14px
        'base': ['1rem', { lineHeight: '1.6' }],      // 16px
        'lg': ['1.25rem', { lineHeight: '1.5' }],     // 20px
        'xl': ['1.563rem', { lineHeight: '1.4' }],    // 25px
        '2xl': ['1.953rem', { lineHeight: '1.3' }],   // 31px
        '3xl': ['2.441rem', { lineHeight: '1.2' }],   // 39px
        '4xl': ['3.052rem', { lineHeight: '1.1' }],   // 49px
      },
      spacing: {
        // 8pt grid system additions
        '18': '4.5rem',   // 72px
        '22': '5.5rem',   // 88px
        '26': '6.5rem',   // 104px
        '30': '7.5rem',   // 120px
      },
      borderRadius: {
        card: '12px',
        control: '8px',
      },
      boxShadow: {
        elevated: '0 1px 0 rgba(0, 0, 0, 0.4), 0 8px 24px rgba(0, 0, 0, 0.2)',
        soft: '0 1px 0 rgba(0, 0, 0, 0.4), 0 4px 16px rgba(0, 0, 0, 0.18)',
      },
      backdropBlur: {
        'xs': '2px',
        'glass': '16px',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
  ],
}
