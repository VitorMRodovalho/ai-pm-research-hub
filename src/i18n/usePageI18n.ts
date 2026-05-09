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
    // p124 fix — read BOTH global-i18n (BaseLayout) and page-i18n (per-page bundle)
    // and merge client-side. Previously the merge happened in an inline script in
    // BaseLayout, but that ran before <slot> was parsed, so the page-i18n script
    // tag inside the slot didn't exist yet — the inline script then created a
    // phantom page-i18n in <head> with ONLY global keys. The real page-i18n
    // arrived later, and getElementById returned the FIRST (phantom) tag.
    // Result: every page that mounted a usePageI18n island silently lost its
    // page-specific keys (only the global ones survived).
    let parsed: Record<string, string> = {};
    try {
      const globalEl = document.getElementById('global-i18n');
      if (globalEl) parsed = JSON.parse(globalEl.textContent || '{}');
    } catch {}
    // page-i18n: there may be two (the phantom in <head> from BaseLayout's
    // legacy merge script and the real one in <slot>). Merge them all so
    // either ordering is safe.
    const pageEls = document.querySelectorAll('script[id="page-i18n"]');
    pageEls.forEach((el) => {
      try {
        const obj = JSON.parse(el.textContent || '{}');
        parsed = { ...parsed, ...obj };
      } catch {}
    });
    setDict(parsed);
  }, []);

  return (key: string, fallback?: string) => dict[key] || fallback || key;
}
