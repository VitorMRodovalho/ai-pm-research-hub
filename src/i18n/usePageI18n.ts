import { useState, useEffect } from 'react';

/**
 * React hook to read i18n strings injected by parent Astro page.
 *
 * Usage in Astro page (frontmatter):
 *   import { buildPageI18n } from '../i18n/pageI18n';
 *   const i18nBundle = buildPageI18n(['comp.tribe', 'comp.common'], lang);
 *
 * Usage in Astro page (template):
 *   <script id="page-i18n" type="application/json" set:html={i18nBundle}></script>
 *
 * Usage in React island:
 *   const t = usePageI18n();
 *   <span>{t('comp.tribe.members', 'Membros')}</span>
 */
export function usePageI18n() {
  const [dict, setDict] = useState<Record<string, string>>({});

  useEffect(() => {
    const el = document.getElementById('page-i18n');
    if (el) {
      try { setDict(JSON.parse(el.textContent || '{}')); } catch {}
    }
  }, []);

  return (key: string, fallback?: string) => dict[key] || fallback || key;
}
