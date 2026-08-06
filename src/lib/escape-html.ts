/**
 * escape-html — SSOT para interpolar TEXTO e URL de terceiros dentro do DOM (#1631).
 *
 * Irmão de `sanitize-html.ts`, com o problema oposto. Lá a entrada É HTML e a política
 * decide o que sobrevive; aqui a entrada NÃO é HTML e nada dela pode virar marcação.
 *
 * Por que existe: o repo tem 54 cópias locais de escape sob 7 nomes diferentes
 * (`esc`, `escapeHtml`, `escHtml`, `escH`, `escapeAttr`, `escOc`, `escapeHtmlSafe`), das
 * quais 13 cobrem `& < >` e esquecem a aspa. Uma cópia cega para aspa parece funcionar em
 * conteúdo de texto e falha exatamente onde dói: dentro de valor de atributo, onde a aspa
 * fecha o atributo e o resto do payload vira marcação (`" onmouseover=...`). Foi o caso
 * medido em `notifications.astro` em 2026-08-06.
 *
 * Regra de uso:
 *   - `escapeHtml` é seguro em nó de texto E em valor de atributo ENTRE ASPAS.
 *   - Atributo sem aspas não tem escape que salve (espaço, `=` e crase já quebram o valor):
 *     sempre citar. Não existe `escapeAttr` separado aqui de propósito — duas funções
 *     idênticas com nomes diferentes só recriam a confusão que este módulo resolve.
 *   - Se o destino é só texto, prefira `textContent` a `innerHTML`: isso REMOVE a classe
 *     de bug em vez de escapá-la.
 *
 * Testes por payload em `tests/contracts/1631-notification-escape-and-caller-gate.test.mjs`.
 * Teste de grep de fonte não serve: provaria que o escape está escrito, nunca que ele
 * bloqueia — a mesma classe que motivou o tripwire do #1620 e a bateria do #1629.
 */

const HTML_ENTITIES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

/**
 * Escapa texto para interpolação em HTML. Cobre os CINCO caracteres — as duas aspas
 * inclusive, que é o que separa esta função das 13 cópias cegas do repo.
 *
 * `null`/`undefined` viram string vazia (e não as palavras "null"/"undefined").
 */
export function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (c) => HTML_ENTITIES[c]);
}

/** Esquemas que podem virar destino de navegação. Tudo fora daqui é recusado. */
const SAFE_NAV_SCHEMES = new Set(['http:', 'https:']);

/**
 * Uma URL de terceiro é navegável com segurança?
 *
 * Escapar não basta quando o valor vira DESTINO: `window.location.href = 'javascript:…'`
 * executa, e nenhuma quantidade de `&quot;` impede isso. O gate tem de ser sobre o
 * esquema, antes da navegação.
 *
 * Aceita:
 *   - caminho da própria aplicação (`/algo`) — 5752 dos 5757 links vivos em 06/08/2026;
 *   - absoluto `http:`/`https:` — os outros 5.
 *
 * Recusa (devolve `null`):
 *   - `javascript:`, `data:`, `vbscript:` e qualquer outro esquema;
 *   - `//host`, que parece caminho e é troca de origem (protocol-relative);
 *   - relativo sem barra inicial, que não ocorre nos dados e seria ambíguo.
 *
 * Normaliza antes de comparar porque o navegador ignora controle e espaço DENTRO do
 * esquema: `java\tscript:`, ` javascript:` e `JaVaScRiPt:` executam. Mesma normalização
 * de `isSafeUrl` em `sanitize-html.ts`. A normalização vale só para DECIDIR; o valor
 * devolvido é o original, para não alterar link legítimo.
 */
export function safeNavigationUrl(raw: unknown): string | null {
  if (raw === null || raw === undefined) return null;
  const original = String(raw);
  // Descarta controle (0x00-0x20) e DEL (0x7F) por codigo de caractere, sem literal de
  // escape no fonte: um `\t` cru dentro de classe de regex e invisivel na revisao.
  const probe = Array.from(original)
    .filter((ch) => {
      const code = ch.charCodeAt(0);
      return code > 0x20 && code !== 0x7f;
    })
    .join('');
  if (probe === '') return null;

  // Protocol-relative: `//evil.com` navega para fora vestido de caminho.
  if (probe.startsWith('//')) return null;
  if (probe.startsWith('/')) return original;

  const scheme = probe.match(/^([a-z][a-z0-9+.-]*):/i);
  if (!scheme) return null;

  return SAFE_NAV_SCHEMES.has(scheme[1].toLowerCase() + ':') ? original : null;
}
