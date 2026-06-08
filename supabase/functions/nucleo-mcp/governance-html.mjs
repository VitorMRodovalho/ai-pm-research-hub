// governance-html.mjs — pure, dependency-free helpers for the #459
// `get_governance_document_body` MCP tool.
//
// Shared single source of truth between:
//   - the Deno Edge Function (supabase/functions/nucleo-mcp/index.ts), and
//   - the Node contract test (tests/contracts/459-governance-document-body.test.mjs).
//
// Regex/string based on purpose: DOMParser is unavailable in the Deno EF runtime,
// and the critical MCP EF stays dependency-free (no turndown / deno-dom). The input
// is well-structured TipTap StarterKit HTML (h1-h6, p, ul/ol/li, strong/em, blockquote,
// pre/code, a, img, hr, br), so a targeted converter is robust and testable.
//
// Anchor extraction mirrors src/components/governance/ClauseCommentDrawer.tsx
// (CLAUSE_REGEX) for clause-anchor parity with the curation UI.

// Legal guard-rail #2 (#459 legal-counsel review, 2026-06-07): the MCP/LLM channel
// serves the body ONLY for these visibility classes — a tighter ceiling than the
// canonical reader's web authority. admin_only / audit_restricted / legal_scoped are
// NEVER served via MCP even when the caller would pass the RPC gate. Forward-defense
// (today 16/16 governance_documents are active_members).
export const MCP_GOVERNANCE_VISIBLE_CLASSES = ['public', 'active_members'];

// Mirrors ClauseCommentDrawer.tsx CLAUSE_REGEX: "§ 3", "§ 4.5.1", "1.", "2.3",
// "2.3.4", "Art. 5", "Cláusula 2".
const CLAUSE_REGEX = /^\s*(§\s*[\d]+(?:\.\d+)*[a-z]?|\d+(?:\.\d+)+|\d+\.(?!\d)|Art\.?\s*\d+|Cláusula\s*[\d.]+)/i;

// Legal guard-rail #1: mandatory caveat when the document is not yet `active`.
const RATIFICATION_CAVEAT =
  'Documento em processo de ratificação — texto sujeito a alteração antes de entrada em vigor. ' +
  'Não utilize como texto definitivo sem confirmação do status de ratificação.';

export function ratificationCaveat(status) {
  return status === 'active' ? null : RATIFICATION_CAVEAT;
}

const NAMED_ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
  mdash: '—', ndash: '–', hellip: '…', laquo: '«', raquo: '»',
  ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’',
  deg: '°', sect: '§', copy: '©', reg: '®', trade: '™', middot: '·',
};

export function decodeEntities(s) {
  if (!s) return '';
  return s.replace(/&(#x?[0-9a-f]+|[a-z][a-z0-9]*);/gi, (m, body) => {
    if (body[0] === '#') {
      const code = (body[1] === 'x' || body[1] === 'X')
        ? parseInt(body.slice(2), 16)
        : parseInt(body.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    const key = body.toLowerCase();
    return Object.prototype.hasOwnProperty.call(NAMED_ENTITIES, key) ? NAMED_ENTITIES[key] : m;
  });
}

// Strip all tags + decode entities + collapse whitespace → plain text.
export function stripTags(html) {
  if (!html) return '';
  return decodeEntities(String(html).replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();
}

// Remove dangerous constructs while keeping the value as HTML (for the content_html field).
// Defense-in-depth: governance bodies are authored via TipTap (no script), but content_html
// is stored unsanitized (no repo-wide sanitizer) — strip script/style/handlers/javascript: URLs.
export function sanitizeGovernanceHtml(html) {
  if (!html) return '';
  return String(html)
    .replace(/<(script|style|iframe|object|embed|noscript)\b[^>]*>[\s\S]*?<\/\1>/gi, '')
    .replace(/<(script|style|iframe|object|embed|noscript)\b[^>]*\/?>/gi, '')
    .replace(/\son[a-z]+\s*=\s*"[^"]*"/gi, '')
    .replace(/\son[a-z]+\s*=\s*'[^']*'/gi, '')
    .replace(/\son[a-z]+\s*=\s*[^\s>]+/gi, '')
    // Neutralize script-y URL schemes in href/src. external http(s) links + TipTap-authored
    // <img src> (incl. data: images) are trusted-author content and intentionally preserved;
    // broader data:/SSRF hardening for downstream HTML renderers is tracked as a #459 follow-up.
    .replace(/(href|src)\s*=\s*("|')\s*(javascript|vbscript):[^"']*\2/gi, '$1=$2#$2');
}

// --- HTML → Markdown (targeted for TipTap StarterKit output) ---

// NOTE: entity decoding is deliberately deferred to the very end of htmlToMarkdown
// (after all tag-stripping) — otherwise a decoded "&lt;c&gt;" → "<c>" gets eaten by a
// later tag-strip pass. So inline helpers keep entities ENCODED.
function inlineTextOnly(s) {
  return (s || '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
}

function inlineToMd(s) {
  if (!s) return '';
  let out = String(s);
  // links: <a href="url">text</a>
  out = out.replace(/<a\b[^>]*?href\s*=\s*["']([^"']*)["'][^>]*>([\s\S]*?)<\/a>/gi,
    (m, href, text) => `[${inlineTextOnly(text)}](${href})`);
  // images: <img src ... alt ...>
  out = out.replace(/<img\b[^>]*>/gi, (m) => {
    const src = (m.match(/src\s*=\s*["']([^"']*)["']/i) || [])[1] || '';
    const alt = (m.match(/alt\s*=\s*["']([^"']*)["']/i) || [])[1] || '';
    return src ? `![${alt}](${src})` : '';
  });
  // bold then italic then inline code
  out = out.replace(/<(strong|b)\b[^>]*>([\s\S]*?)<\/\1>/gi, (m, t, c) => {
    const inner = inlineTextOnly(c);
    return inner ? `**${inner}**` : '';
  });
  out = out.replace(/<(em|i)\b[^>]*>([\s\S]*?)<\/\1>/gi, (m, t, c) => {
    const inner = inlineTextOnly(c);
    return inner ? `*${inner}*` : '';
  });
  out = out.replace(/<code\b[^>]*>([\s\S]*?)<\/code>/gi, (m, c) => `\`${inlineTextOnly(c)}\``);
  // line breaks → soft newline (a "  \n" hard break would be stripped by the trailing-space
  // cleanup below; a soft \n keeps the parts on separate source lines, which is what an LLM reads)
  out = out.replace(/<br\s*\/?>/gi, '\n');
  // strip any remaining inline tags (entities still ENCODED — decoded once at the end)
  out = out.replace(/<[^>]+>/g, '');
  return out.replace(/[ \t]+/g, ' ').replace(/[ \t]+\n/g, '\n').trim();
}

function listItemsToMd(listHtml, ordered) {
  const items = [];
  const re = /<li\b[^>]*>([\s\S]*?)<\/li>/gi;
  let m;
  let i = 1;
  while ((m = re.exec(listHtml)) !== null) {
    // unwrap a single wrapping <p> inside <li> (TipTap nests <li><p>text</p></li>)
    const inner = m[1].replace(/^\s*<p\b[^>]*>([\s\S]*?)<\/p>\s*$/i, '$1');
    const text = inlineToMd(inner);
    if (text) { items.push(`${ordered ? `${i}.` : '-'} ${text}`); i++; }
  }
  return items.join('\n');
}

export function htmlToMarkdown(html) {
  if (!html) return '';
  let s = sanitizeGovernanceHtml(html);

  // Protect code blocks from inline processing.
  const codeBlocks = [];
  const stashCode = (c) => {
    const token = `\u0000CODE${codeBlocks.length}\u0000`;
    codeBlocks.push('```\n' + decodeEntities(c.replace(/<[^>]+>/g, '')).replace(/\s+$/, '') + '\n```');
    return `\n\n${token}\n\n`;
  };
  s = s.replace(/<pre\b[^>]*>\s*<code\b[^>]*>([\s\S]*?)<\/code>\s*<\/pre>/gi, (m, c) => stashCode(c));
  s = s.replace(/<pre\b[^>]*>([\s\S]*?)<\/pre>/gi, (m, c) => stashCode(c));

  // Lists (before paragraphs; TipTap wraps li content in <p>).
  s = s.replace(/<ol\b[^>]*>([\s\S]*?)<\/ol>/gi, (m, c) => `\n\n${listItemsToMd(c, true)}\n\n`);
  s = s.replace(/<ul\b[^>]*>([\s\S]*?)<\/ul>/gi, (m, c) => `\n\n${listItemsToMd(c, false)}\n\n`);

  // Headings.
  s = s.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (m, lvl, c) => {
    const text = inlineToMd(c);
    return text ? `\n\n${'#'.repeat(Number(lvl))} ${text}\n\n` : '';
  });

  // Blockquote.
  s = s.replace(/<blockquote\b[^>]*>([\s\S]*?)<\/blockquote>/gi, (m, c) => {
    const text = inlineToMd(c.replace(/<\/?p\b[^>]*>/gi, '\n')).trim();
    const quoted = text.split('\n').map((l) => `> ${l.trim()}`.replace(/\s+$/, '')).join('\n');
    return `\n\n${quoted}\n\n`;
  });

  // Horizontal rule.
  s = s.replace(/<hr\s*\/?>/gi, '\n\n---\n\n');

  // Paragraphs.
  s = s.replace(/<p\b[^>]*>([\s\S]*?)<\/p>/gi, (m, c) => {
    const text = inlineToMd(c);
    return text ? `\n\n${text}\n\n` : '';
  });

  // Generic block closers → newline; then a final inline pass for any stragglers.
  s = s.replace(/<\/(div|section|article|header|footer|tr|td|th)>/gi, '\n');
  s = inlineToMd(s);

  // Decode entities ONCE, now that all tag-stripping is done (so a decoded "<c>" is
  // never re-eaten as a tag). Code-block tokens carry no entities and are unaffected.
  s = decodeEntities(s);

  // Restore code blocks (content already decoded at stash time).
  codeBlocks.forEach((cb, idx) => { s = s.replaceAll(`\u0000CODE${idx}\u0000`, cb); });

  // Whitespace cleanup.
  return s.replace(/\n{3,}/g, '\n\n').replace(/[ \t]+\n/g, '\n').trim();
}

// Section anchors for clause citation (e.g. "Cláusula 12", "Art. 1", "§ 1º").
// Mirrors ClauseCommentDrawer.extractAnchors but regex-based (no DOMParser) and
// includes h4. Headings h2-h4 always contribute; <strong> only when clause-numbered.
export function extractSectionAnchors(html) {
  if (!html) return [];
  const anchors = new Map();
  let m;

  const hre = /<h([2-4])\b[^>]*>([\s\S]*?)<\/h\1>/gi;
  while ((m = hre.exec(html)) !== null) {
    const text = stripTags(m[2]);
    if (!text) continue;
    const cm = text.match(CLAUSE_REGEX);
    const value = (cm ? cm[1].replace(/\s+/g, ' ') : text).replace(/\.$/, '').trim();
    if (value && !anchors.has(value)) anchors.set(value, text);
  }

  const sre = /<strong\b[^>]*>([\s\S]*?)<\/strong>/gi;
  while ((m = sre.exec(html)) !== null) {
    const text = stripTags(m[1]);
    const cm = text.match(CLAUSE_REGEX);
    if (!cm) continue;
    const value = cm[1].replace(/\s+/g, ' ').replace(/\.$/, '').trim();
    if (value && !anchors.has(value)) anchors.set(value, text);
  }

  return Array.from(anchors.entries()).map(([value, label]) => ({ value, label }));
}
