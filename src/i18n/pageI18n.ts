// ─── Page i18n bundle builder ───
// Usage in Astro frontmatter:
//   import { buildPageI18n } from '../i18n/pageI18n';
//   const bundle = buildPageI18n(['gamification', 'common', 'role'], lang);
// In template:
//   <script id="page-i18n" type="application/json" set:html={bundle}></script>
// In client JS:
//   const i18n = JSON.parse(document.getElementById('page-i18n')?.textContent || '{}');
//   const text = i18n['gamification.title'] || 'fallback';

import { t, type Lang } from './utils';
import ptBR from './pt-BR';

export function buildPageI18n(prefixes: string[], lang: Lang): string {
  const bundle: Record<string, string> = {};
  for (const key of Object.keys(ptBR)) {
    if (prefixes.some(p => key.startsWith(p + '.'))) {
      bundle[key] = t(key, lang);
    }
  }
  return JSON.stringify(bundle);
}
