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
  // Each removal runs to a fixpoint in its OWN do-while: stripping one construct can
  // concatenate the surrounding chars into a fresh one — "<scr<script></script>ipt>" →
  // "<script>", "<!<!-- -->-- -->" → "<!-- -->", or a revealed "on…=" handler. A single
  // pass is incomplete sanitization (CodeQL js/incomplete-multi-character-sanitization;
  // the per-replace loop is the form the query recognises as complete). Every pass only
  // removes or neutralizes, so each loop converges. All [\s\S]*? are non-greedy → no ReDoS.
  let s = String(html);
  let prev;
  // HTML comments — admin-authored "<!-- hidden -->" is a prompt-injection channel reaching
  // the MCP/LLM consumer via content_html (#579). (?:-->|$) also drops an UNTERMINATED opener
  // (HTML spec: an unclosed comment runs to EOF; TipTap escapes a literal "<!--" as &lt;!--
  // so a raw opener is always a real comment).
  do { prev = s; s = s.replace(/<!--[\s\S]*?(?:-->|$)/g, ''); } while (s !== prev);
  // script/style/embed blocks, then their void/unclosed forms
  do { prev = s; s = s.replace(/<(script|style|iframe|object|embed|noscript)\b[^>]*>[\s\S]*?<\/\1>/gi, ''); } while (s !== prev);
  do { prev = s; s = s.replace(/<(script|style|iframe|object|embed|noscript)\b[^>]*\/?>/gi, ''); } while (s !== prev);
  // inline event handlers (double-quoted, single-quoted, or unquoted value)
  do { prev = s; s = s.replace(/\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, ''); } while (s !== prev);
  // Neutralize script-y URL schemes in href/src. external http(s) links + TipTap-authored
  // <img src> (incl. data: images) are trusted-author content and intentionally preserved;
  // broader data:/SSRF hardening for downstream HTML renderers is tracked as a #459 follow-up.
  do { prev = s; s = s.replace(/(href|src)\s*=\s*("|')\s*(javascript|vbscript):[^"']*\2/gi, '$1=$2#$2'); } while (s !== prev);
  return s;
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
    (_m, href, text) => `[${inlineTextOnly(text)}](${href})`);
  // images: <img src ... alt ...>
  out = out.replace(/<img\b[^>]*>/gi, (m) => {
    const src = (m.match(/src\s*=\s*["']([^"']*)["']/i) || [])[1] || '';
    const alt = (m.match(/alt\s*=\s*["']([^"']*)["']/i) || [])[1] || '';
    return src ? `![${alt}](${src})` : '';
  });
  // bold then italic then inline code
  out = out.replace(/<(strong|b)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_m, _t, c) => {
    const inner = inlineTextOnly(c);
    return inner ? `**${inner}**` : '';
  });
  out = out.replace(/<(em|i)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_m, _t, c) => {
    const inner = inlineTextOnly(c);
    return inner ? `*${inner}*` : '';
  });
  out = out.replace(/<code\b[^>]*>([\s\S]*?)<\/code>/gi, (_m, c) => `\`${inlineTextOnly(c)}\``);
  // line breaks → soft newline (a "  \n" hard break would be stripped by the trailing-space
  // cleanup below; a soft \n keeps the parts on separate source lines, which is what an LLM reads)
  out = out.replace(/<br\s*\/?>/gi, '\n');
  // strip any remaining inline tags (entities still ENCODED — decoded once at the end)
  out = out.replace(/<[^>]+>/g, '');
  return out.replace(/[ \t]+/g, ' ').replace(/[ \t]+\n/g, '\n').trim();
}

// --- Lists: balanced + recursive (handles nested <ul>/<ol>) ---
// A non-greedy regex cannot balance nested lists — the inner </ul>/</li> closes the
// match early, garbling parent+child text (~half of production governance bodies nest
// lists). So extraction tracks open/close depth. Nested lists indent by the parent
// marker width (CommonMark-correct: "- " → 2 spaces, "1. " → 3 spaces), and the rendered
// block is stashed into a NUL token so the trailing whitespace-collapsing inlineToMd pass
// can't flatten the leading indentation (same protection pattern as code blocks).

// Find the matching close of a list opened at `openStart` (index of '<' of <ul|<ol>),
// counting nested ul/ol depth. Returns {tag, innerStart, innerEnd, end} or null if unbalanced.
function findListClose(s, openStart) {
  const open = /^<(ul|ol)\b[^>]*>/i.exec(s.slice(openStart));
  if (!open) return null;
  const tag = open[1].toLowerCase();
  const innerStart = openStart + open[0].length;
  const re = /<(\/?)(?:ul|ol)\b[^>]*>/gi;
  re.lastIndex = innerStart;
  let depth = 1;
  let m;
  while ((m = re.exec(s)) !== null) {
    if (m[1] === '/') {
      depth -= 1;
      if (depth === 0) return { tag, innerStart, innerEnd: m.index, end: re.lastIndex };
    } else {
      depth += 1;
    }
  }
  return null;
}

// Split a list's inner HTML into its TOP-LEVEL <li> inner-HTML strings (nested <li>
// skipped), counting <li> depth so a nested item's </li> can't close the parent early.
function splitTopLevelLi(inner) {
  const items = [];
  const openRe = /<li\b[^>]*>/gi;
  let m;
  while ((m = openRe.exec(inner)) !== null) {
    const liStart = m.index + m[0].length;
    const re = /<(\/?)li\b[^>]*>/gi;
    re.lastIndex = liStart;
    let depth = 1;
    let liEnd = inner.length;
    let after = inner.length;
    let mm;
    while ((mm = re.exec(inner)) !== null) {
      if (mm[1] === '/') {
        depth -= 1;
        if (depth === 0) { liEnd = mm.index; after = re.lastIndex; break; }
      } else {
        depth += 1;
      }
    }
    items.push(inner.slice(liStart, liEnd));
    openRe.lastIndex = after;
  }
  return items;
}

// Separate an <li>'s own inline content from the nested child lists directly inside it.
function splitItemContent(liInner) {
  const selfParts = [];
  const children = [];
  let cursor = 0;
  const openRe = /<(?:ul|ol)\b[^>]*>/gi;
  let m;
  while ((m = openRe.exec(liInner)) !== null) {
    const close = findListClose(liInner, m.index);
    if (!close) break;
    selfParts.push(liInner.slice(cursor, m.index));
    children.push({ inner: liInner.slice(close.innerStart, close.innerEnd), ordered: close.tag === 'ol' });
    cursor = close.end;
    openRe.lastIndex = close.end;
  }
  selfParts.push(liInner.slice(cursor));
  // Join with a space so bare text on either side of a nested child list keeps its word
  // spacing (e.g. "<li>intro<ul>…</ul>trailing</li>" → "intro trailing", not "introtrailing").
  return { selfHtml: selfParts.join(' '), children };
}

// Recursively render a list's inner HTML to indented Markdown.
function renderList(inner, ordered, indentPrefix) {
  const lines = [];
  let i = 1;
  for (const liInner of splitTopLevelLi(inner)) {
    const { selfHtml, children } = splitItemContent(liInner);
    // Split the item's own content (nested child lists already removed) on <p> boundaries:
    // TipTap wraps li text in <p>, and a hard-Enter inside an item yields multiple <p>.
    // Rendering each segment separately keeps paragraphs from silently merging into one
    // run-on line (the first segment sits on the marker line; extras become indented
    // continuation lines). Entities stay ENCODED here (decoded once at the end).
    const segments = selfHtml
      .split(/<\/p>\s*<p\b[^>]*>/i)
      .map((seg) => inlineToMd(seg.replace(/<\/?p\b[^>]*>/gi, '')))
      .filter((seg) => seg !== '');
    if (segments.length === 0 && children.length === 0) continue;
    const marker = ordered ? `${i}.` : '-';
    const childIndent = indentPrefix + ' '.repeat(marker.length + 1);
    // NOTE: an empty-text item that has only a nested child (impossible in TipTap
    // StarterKit — the schema forbids a bare list as a li's sole content) renders a bare
    // marker; the trailing space can't survive the final whitespace cleanup.
    lines.push(`${indentPrefix}${marker} ${segments[0] || ''}`.replace(/\s+$/, ''));
    for (const seg of segments.slice(1)) lines.push(`${childIndent}${seg}`);
    i += 1;
    for (const child of children) {
      const childMd = renderList(child.inner, child.ordered, childIndent);
      if (childMd) lines.push(childMd);
    }
  }
  return lines.join('\n');
}

// Replace every TOP-LEVEL <ul>/<ol> in `s` with a stashed, rendered Markdown block
// (nested lists handled recursively inside renderList). Jumping past each balanced block
// means nested lists are never matched at the top level. Each block is pushed to
// `listBlocks` and replaced with a NUL token, restored after the inlineToMd pass.
function replaceTopLevelLists(s, listBlocks) {
  let out = '';
  let cursor = 0;
  const re = /<(?:ul|ol)\b[^>]*>/gi;
  let m;
  while ((m = re.exec(s)) !== null) {
    const close = findListClose(s, m.index);
    if (!close) continue;
    out += s.slice(cursor, m.index);
    const md = renderList(s.slice(close.innerStart, close.innerEnd), close.tag === 'ol', '');
    const token = `\u0000LIST${listBlocks.length}\u0000`;
    listBlocks.push(md);
    out += `\n\n${token}\n\n`;
    cursor = close.end;
    re.lastIndex = close.end;
  }
  out += s.slice(cursor);
  return out;
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
  s = s.replace(/<pre\b[^>]*>\s*<code\b[^>]*>([\s\S]*?)<\/code>\s*<\/pre>/gi, (_m, c) => stashCode(c));
  s = s.replace(/<pre\b[^>]*>([\s\S]*?)<\/pre>/gi, (_m, c) => stashCode(c));

  // Lists — balanced + recursive so nested <ul>/<ol> indent instead of flattening
  // (before paragraphs; TipTap wraps li content in <p>). Each rendered block is stashed
  // into a NUL token (like code blocks) so the straggler inlineToMd pass below can't
  // collapse its leading indentation.
  const listBlocks = [];
  s = replaceTopLevelLists(s, listBlocks);

  // Headings.
  s = s.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_m, lvl, c) => {
    const text = inlineToMd(c);
    return text ? `\n\n${'#'.repeat(Number(lvl))} ${text}\n\n` : '';
  });

  // Blockquote.
  s = s.replace(/<blockquote\b[^>]*>([\s\S]*?)<\/blockquote>/gi, (_m, c) => {
    const text = inlineToMd(c.replace(/<\/?p\b[^>]*>/gi, '\n')).trim();
    const quoted = text.split('\n').map((l) => `> ${l.trim()}`.replace(/\s+$/, '')).join('\n');
    return `\n\n${quoted}\n\n`;
  });

  // Horizontal rule.
  s = s.replace(/<hr\s*\/?>/gi, '\n\n---\n\n');

  // Paragraphs.
  s = s.replace(/<p\b[^>]*>([\s\S]*?)<\/p>/gi, (_m, c) => {
    const text = inlineToMd(c);
    return text ? `\n\n${text}\n\n` : '';
  });

  // Generic block closers → newline; then a final inline pass for any stragglers.
  s = s.replace(/<\/(div|section|article|header|footer|tr|td|th)>/gi, '\n');
  s = inlineToMd(s);

  // Restore list blocks BEFORE decoding entities (list-item text was rendered by
  // inlineToMd with entities still ENCODED) and AFTER the straggler inlineToMd pass
  // (so the whitespace collapse can't flatten the nested-list indentation).
  listBlocks.forEach((lb, idx) => { s = s.replaceAll(`\u0000LIST${idx}\u0000`, lb); });

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
