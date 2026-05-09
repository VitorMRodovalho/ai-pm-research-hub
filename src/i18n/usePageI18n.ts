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
// p124 i18n hook — version 3 (force-bust cached chunk under same Vite hash;
// see commit 0fee842 + 1efcb7b for the merge bug history).
export function usePageI18n() {
  const [dict, setDict] = useState<Record<string, string>>({});

  useEffect(() => {
    // Read global-i18n (always emitted by BaseLayout) plus every page-i18n
    // tag (per-page bundle, may appear inside <slot/>). Merge in DOM order so
    // page-specific keys override globals. Defensively handles parse errors
    // and missing elements without throwing.
    let parsed: Record<string, string> = {};
    try {
      const globalEl = document.getElementById('global-i18n');
      if (globalEl) parsed = JSON.parse(globalEl.textContent || '{}');
    } catch {}
    const pageEls = document.querySelectorAll('script[id="page-i18n"]');
    pageEls.forEach((el) => {
      try {
        const obj = JSON.parse(el.textContent || '{}');
        parsed = { ...parsed, ...obj };
      } catch {}
    });
    if (typeof window !== 'undefined') {
      (window as any).__USE_PAGE_I18N_VERSION__ = 3;
    }
    setDict(parsed);
  }, []);

  return (key: string, fallback?: string) => dict[key] || fallback || key;
}
