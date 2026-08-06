/**
 * sanitize-html — SSOT para renderizar HTML autorado por pessoas (#1629).
 *
 * Por que existe: `blog_posts.body_html` e `governance_documents.content_html` são escritos
 * por membros e renderizados com `set:html` em páginas que servem visitante ANÔNIMO. Sem
 * sanitização, quem tem `rls_can('write')` faz JS arbitrário executar na origem pública —
 * onde vivem sessão e tokens. Medido em 2026-08-06: 14 de 89 membros ativos têm essa
 * capacidade, e o `body_html` é montado no CLIENTE, então sanitizar no editor não seria
 * barreira. O gate tem de estar na leitura.
 *
 * ⚠️ Por que NÃO usamos `ultrahtml/transformers/sanitize` direto: ele **não nega atributo por
 * padrão** — só remove o que estiver explicitamente em `dropAttributes`. Sondado no #1629:
 * com uma config que só define `allowElements`, atravessam `onclick=`, `href="javascript:"` e
 * `style=`. Ele bloqueia `<script>`/`<iframe>`/`<svg>`/`<form>`, o que dá a impressão de estar
 * funcionando. Usamos o PARSER do ultrahtml (a parte difícil e vetada) e implementamos a
 * política de allowlist aqui, com negação por padrão nos dois eixos.
 *
 * Política:
 *   - tag na allowlist        → mantém, filtrando atributos
 *   - tag perigosa            → DROPA com os filhos (o conteúdo de um <script> não é texto)
 *   - qualquer outra tag      → DESEMBRULHA (mantém os filhos, descarta a tag)
 *   - atributo fora da allowlist do tag → removido, sem exceção
 *   - href/src                → esquema validado; `javascript:`/`data:` (não-imagem) caem
 *
 * Testes adversariais por payload em `tests/contracts/1629-sanitize-html.test.mjs`.
 * Um teste de grep de fonte NÃO serve aqui: provaria que o código existe, nunca que ele
 * bloqueia — a mesma classe que motivou o tripwire do #1620.
 */

import { parse, renderSync, walkSync, ELEMENT_NODE } from 'ultrahtml';

/** Tags mantidas. Tudo que não está aqui é desembrulhado ou dropado. */
const ALLOWED_TAGS = new Set([
  'p', 'br', 'hr', 'span', 'div',
  'strong', 'b', 'em', 'i', 'u', 's', 'sub', 'sup', 'mark', 'small',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'li',
  'blockquote', 'code', 'pre', 'kbd', 'samp',
  'a', 'img', 'figure', 'figcaption',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'caption', 'colgroup', 'col',
]);

/**
 * Tags dropadas COM os filhos. Desembrulhar aqui seria pior que remover: o corpo de um
 * `<script>` vira texto visível, e o de um `<style>` idem.
 */
const DROP_WITH_CHILDREN = new Set([
  'script', 'style', 'iframe', 'object', 'embed', 'applet', 'frame', 'frameset',
  'form', 'input', 'button', 'select', 'option', 'textarea', 'label', 'fieldset',
  'link', 'meta', 'base', 'title', 'head', 'noscript', 'template', 'slot',
  'svg', 'math', 'audio', 'video', 'source', 'track', 'canvas', 'portal', 'dialog',
]);

/** Atributos permitidos POR TAG. `*` vale para qualquer tag da allowlist. */
const ALLOWED_ATTRS: Record<string, Set<string>> = {
  '*': new Set(['title', 'lang', 'dir']),
  a: new Set(['href', 'target', 'rel']),
  img: new Set(['src', 'alt', 'width', 'height', 'loading']),
  th: new Set(['colspan', 'rowspan', 'scope']),
  td: new Set(['colspan', 'rowspan']),
  col: new Set(['span']),
  colgroup: new Set(['span']),
  ol: new Set(['start', 'reversed']),
};

/** Esquemas aceitos em `href`. Relativo e âncora também passam (não têm esquema). */
const SAFE_HREF_SCHEMES = new Set(['http:', 'https:', 'mailto:', 'tel:']);

/**
 * `data:` é aceito em `src` de imagem apenas para estes tipos. `data:text/html` é execução
 * de script na prática, e `data:image/svg+xml` carrega `<script>` dentro do SVG.
 */
const SAFE_DATA_IMAGE = /^data:image\/(png|jpe?g|gif|webp|avif);base64,[a-z0-9+/=\s]+$/i;

/**
 * Um valor de URL é seguro?
 *
 * Não dá para confiar em `startsWith('javascript:')`: `java\tscript:`, `JaVaScRiPt:`,
 * ` javascript:` e entidades HTML já decodificadas pelo parser passariam. Normalizamos
 * removendo espaços/controles e comparando o esquema inteiro contra a allowlist.
 */
function isSafeUrl(raw: string, tag: string): boolean {
  // Caracteres de controle e espaco sao ignorados por navegadores DENTRO do esquema:
  // `java\tscript:` e ` javascript:` executam. Removemos NUL..espaco e DEL antes de comparar.
  const value = raw.replace(/[\u0000-\u0020\u007F]/g, '');
  if (value === '') return false;

  if (/^data:/i.test(value)) return tag === 'img' && SAFE_DATA_IMAGE.test(value);

  // Sem esquema (relativo, âncora, protocol-relative) — não há esquema perigoso a executar.
  // `//host` é protocol-relative e herda http(s), então é aceitável.
  const schemeMatch = value.match(/^([a-z][a-z0-9+.-]*):/i);
  if (!schemeMatch) return true;

  return SAFE_HREF_SCHEMES.has(schemeMatch[1].toLowerCase() + ':');
}

function isAttrAllowed(tag: string, attr: string): boolean {
  const name = attr.toLowerCase();
  // Negação explícita e antecipada: nenhum `on*` sobrevive, mesmo que uma allowlist futura
  // liste um por engano. Idem `style` (permite `url(javascript:)` e exfiltração via CSS).
  if (name.startsWith('on') || name === 'style') return false;
  if (ALLOWED_ATTRS['*'].has(name)) return true;
  return ALLOWED_ATTRS[tag]?.has(name) ?? false;
}

export interface SanitizeOptions {
  /** Tags extras a permitir, além da allowlist padrão. */
  allowTags?: string[];
}

/**
 * Sanitiza HTML autorado por pessoas para renderização segura.
 *
 * Devolve `''` para entrada vazia/nula, então o chamador pode passar direto o valor do banco.
 */
export function sanitizeUserHtml(input: string | null | undefined, options: SanitizeOptions = {}): string {
  if (!input) return '';

  const allowed = options.allowTags
    ? new Set([...ALLOWED_TAGS, ...options.allowTags.map((t) => t.toLowerCase())])
    : ALLOWED_TAGS;

  const doc = parse(input);
  // As mutações são coletadas e aplicadas de trás para frente: mexer em `parent.children`
  // durante a caminhada reindexa os irmãos ainda não visitados.
  const mutations: Array<() => void> = [];

  walkSync(doc, (node, parent) => {
    if (node.type !== ELEMENT_NODE) return;
    const tag = String(node.name || '').toLowerCase();

    if (DROP_WITH_CHILDREN.has(tag)) {
      if (parent) mutations.push(() => {
        parent.children = parent.children.filter((c: unknown) => c !== node);
      });
      return;
    }

    if (!allowed.has(tag)) {
      // Desembrulha: o texto do usuário sobrevive, a tag desconhecida não.
      if (parent) mutations.push(() => {
        const at = parent.children.indexOf(node);
        if (at !== -1) parent.children.splice(at, 1, ...node.children);
      });
      return;
    }

    const clean: Record<string, string> = {};
    for (const [rawName, rawValue] of Object.entries(node.attributes ?? {})) {
      const name = rawName.toLowerCase();
      if (!isAttrAllowed(tag, name)) continue;
      const value = String(rawValue ?? '');
      if ((name === 'href' || name === 'src') && !isSafeUrl(value, tag)) continue;
      clean[name] = value;
    }

    // Link que abre em nova aba sem `noopener` entrega `window.opener` ao destino (tabnabbing).
    // Forçamos o par inteiro em qualquer <a href>, não só nos com target — é barato e não
    // depende de o autor ter escrito o target.
    if (tag === 'a' && clean.href) clean.rel = 'noopener noreferrer';

    node.attributes = clean;
  });

  for (let i = mutations.length - 1; i >= 0; i--) mutations[i]();

  return renderSync(doc);
}
