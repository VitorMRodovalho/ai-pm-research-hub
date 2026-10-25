// #2783: os endereços de cada língua de uma página, para <link rel="alternate" hreflang>.
//
// Cada endereço é o que SERVE o conteúdo naquela língua, sem redirecionamento no meio:
//   'prefix': a página tem cópia real em /en e /es (a home: src/pages/en/index.astro);
//   'query':  /en/x e /es/x são só um meta refresh para /x?lang=..., e o servidor lê o ?lang.
// O origin é o mesmo do <link rel="canonical"> (SEO_CANONICAL_ORIGIN); o canonical não muda aqui.

export type AlternatesMode = 'prefix' | 'query';
export interface LanguageAlternate { hreflang: 'pt-BR' | 'en' | 'es' | 'x-default'; href: string }

const LANGS = [
  { hreflang: 'en', code: 'en-US', prefix: 'en' },
  { hreflang: 'es', code: 'es-LATAM', prefix: 'es' },
] as const;

/** O caminho em português: tira o prefixo /en ou /es, se houver. */
export function basePath(pathname: string): string {
  const stripped = pathname.replace(/^\/(en|es)(?=\/|$)/, '');
  return stripped === '' ? '/' : stripped;
}

export function languageAlternates(pathname: string, mode: AlternatesMode, origin: string): LanguageAlternate[] {
  const base = basePath(pathname);
  const pt = new URL(base, origin).href;
  const others = LANGS.map(({ hreflang, code, prefix }) => {
    if (mode === 'prefix') {
      return { hreflang, href: new URL(`/${prefix}${base === '/' ? '/' : base}`, origin).href };
    }
    const u = new URL(base, origin);
    u.searchParams.set('lang', code);
    return { hreflang, href: u.href };
  });
  return [{ hreflang: 'pt-BR', href: pt }, ...others, { hreflang: 'x-default', href: pt }];
}
