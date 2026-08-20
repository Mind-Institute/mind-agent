import type { Config } from 'tailwindcss';
import animate from 'tailwindcss-animate';

/**
 * Identidade visual do Mind Agent, versão clara.
 *
 * O chat da raiz é escuro (`--bg: #13131a`). O painel é a mesma marca em
 * fundo claro: o verde Mind (#68ee95) e o coral (#ff7057) continuam sendo
 * as cores da casa, mas em superfície branca eles precisam de versões mais
 * fechadas para passar em contraste — daí `verde.600` e `coral.600`.
 */
const config: Config = {
  darkMode: ['class'],
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        /* Marca — valores idênticos aos tokens do chat */
        verde: {
          50: '#eefdf3',
          100: '#d6fae3',
          200: '#aff4c8',
          300: '#68ee95',
          400: '#38d873',
          500: '#1bbb5a',
          600: '#0f9549',
          700: '#0f763d',
          800: '#115d34',
          900: '#0f4d2d',
        },
        coral: {
          50: '#fff3f1',
          100: '#ffe4df',
          200: '#ffcdc4',
          300: '#ffa896',
          400: '#ff7057',
          500: '#f8502f',
          600: '#e53616',
          700: '#c02a0f',
          800: '#9e2712',
          900: '#832616',
        },
        roxo: { 400: '#b47dff', 500: '#9843ff', 600: '#8321eb' },

        /* Papéis semânticos (dirigidos por CSS vars em index.css) */
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      fontFamily: {
        sans: ['Satoshi', 'system-ui', 'Segoe UI', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      keyframes: {
        'accordion-down': {
          from: { height: '0' },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: '0' },
        },
      },
      animation: {
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
      },
    },
  },
  plugins: [animate],
};

export default config;
