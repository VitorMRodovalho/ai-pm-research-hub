/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        navy:   '#003B5C',
        orange: '#FF610F',
        purple: '#4F17A8',
        teal:   '#00799E',
        crimson:'#BE2027',
        pink:   '#EC4899',
        emerald:'#10B981',
        amber:  '#D97706',
        violet: '#7C3AED',
      },
      fontFamily: {
        sans: ['Plus Jakarta Sans', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
