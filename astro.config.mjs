import { defineConfig } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://nucleoia.vitormr.dev',
  output: 'server',
  security: { checkOrigin: false },  // CSRF handled in middleware (MCP/OAuth need cross-origin POST)
  adapter: cloudflare({
    platformProxy: {
      enabled: true,
    },
  }),
  integrations: [
    react(),
    sitemap({
      filter: (page) =>
        !page.includes('/admin/')
        && !page.includes('/api/')
        && !page.includes('/auth/')
        && !page.includes('/oauth/')
        && !page.includes('/mcp')
        && !page.includes('/.well-known')
        && !page.includes('/workspace')
        && !page.includes('/profile')
        && !page.includes('/private')
        && !page.includes('/preview')
        && !page.includes('/report'),
      i18n: {
        defaultLocale: 'pt',
        locales: { pt: 'pt-BR', en: 'en-US', es: 'es-LATAM' },
      },
    }),
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
