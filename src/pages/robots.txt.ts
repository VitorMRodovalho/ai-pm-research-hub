// src/pages/robots.txt.ts
// #2471: robots.txt served by the app so it can point crawlers at the sitemap on
// the SEO canonical host. Cloudflare's managed robots.txt (content signals) is
// prepended to this at the edge, so this file only carries what is ours.
// Built from SEO_CANONICAL_ORIGIN so the host literal stays in src/lib/canonical.ts.
import type { APIRoute } from 'astro';
import { SEO_CANONICAL_ORIGIN } from '../lib/canonical';

export const prerender = true;

export const GET: APIRoute = () =>
  new Response(
    ['User-agent: *', 'Allow: /', '', `Sitemap: ${SEO_CANONICAL_ORIGIN}/sitemap-index.xml`, ''].join('\n'),
    { headers: { 'Content-Type': 'text/plain; charset=utf-8' } },
  );
