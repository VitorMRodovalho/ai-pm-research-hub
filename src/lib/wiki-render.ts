/**
 * wiki-render — markdown de página do wiki para HTML seguro (#2495, tela /wiki).
 *
 * O conteúdo vem de duas fontes: o espelho do repositório `nucleo-ia-gp/wiki` (Obsidian) e as
 * versões escritas na plataforma por qualquer membro de tribo. Nas duas é texto de pessoa, e o
 * `marked` não sanitiza: HTML cru no markdown passa inteiro. Por isso a saída SEMPRE atravessa
 * `sanitizeUserHtml`, o SSOT de #1629, e nenhum caminho da tela injeta `marked.parse` direto.
 *
 * Links internos: o vault usa link relativo para outro `.md` (`tribo-1-radar-tecnologico.md`) e
 * wikilink (`[[Nome]]`). Os dois viram rota da tela, senão todo link interno dá 404.
 */

import { Marked } from 'marked';
import { sanitizeUserHtml } from './sanitize-html.ts';

export interface WikiLinkTargets {
  /** URL da tela para ler a página no caminho dado. */
  page: (path: string) => string;
  /** URL da tela para buscar um termo (destino de wikilink, que nomeia e não aponta). */
  search: (query: string) => string;
}

/**
 * Resolve um link relativo do vault para o caminho da página. Devolve `null` quando o link não é
 * relativo a outro `.md` (externo, absoluto, âncora, e-mail): esses ficam como estão.
 */
export function resolveWikiPath(href: string, currentPath: string): { path: string; hash: string } | null {
  if (!href || /^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith('/') || href.startsWith('#')) return null;
  const hashAt = href.indexOf('#');
  const target = hashAt === -1 ? href : href.slice(0, hashAt);
  const hash = hashAt === -1 ? '' : href.slice(hashAt);
  if (!/\.md$/i.test(target)) return null;

  const parts = currentPath.split('/').slice(0, -1);
  for (const seg of decodeURIComponent(target).split('/')) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') { if (parts.length === 0) return null; parts.pop(); continue; }
    parts.push(seg);
  }
  return { path: parts.join('/'), hash };
}

/** `[[Alvo]]` e `[[Alvo|Rótulo]]` viram link de busca. Fora de bloco de código. */
function expandWikilinks(md: string, links: WikiLinkTargets): string {
  return md
    .split(/(```[\s\S]*?```|`[^`\n]*`)/g)
    .map((chunk, i) => (i % 2 === 1 ? chunk : chunk.replace(/\[\[([^\]|\n]+)(?:\|([^\]\n]+))?\]\]/g,
      (_m, target: string, label?: string) => `[${(label || target).trim()}](${links.search(target.trim())})`)))
    .join('');
}

/** Markdown da página → HTML sanitizado, com os links internos apontando para a tela. */
export function renderWikiMarkdown(md: string | null | undefined, currentPath: string, links: WikiLinkTargets): string {
  if (!md) return '';
  const marked = new Marked({
    gfm: true,
    async: false,
    walkTokens(token) {
      if (token.type !== 'link') return;
      const resolved = resolveWikiPath(token.href, currentPath);
      if (resolved) token.href = links.page(resolved.path) + resolved.hash;
    },
  });
  const html = marked.parse(expandWikilinks(md, links)) as string;
  return sanitizeUserHtml(html);
}
