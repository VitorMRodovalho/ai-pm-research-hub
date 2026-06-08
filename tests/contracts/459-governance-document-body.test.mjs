/**
 * #459 contract test — get_governance_document_body MCP tool + governance-html.mjs
 *
 * Feature #459: expose the normative body (clauses) of governance_documents via the MCP
 * server, as sanitized HTML + server-rendered Markdown + section anchors. Decision:
 * docs/council/decisions/2026-06-07-459-governance-document-body-build.md (Option A, full
 * AC, current body). Legal gate cleared GO-com-condições (legal-counsel 2026-06-07) with 5
 * guard-rails — all asserted below.
 *
 * Architecture: the tool WRAPS the already-legally-reviewed canonical reader RPC
 * get_governance_document_reader (same visibility authority as the member-facing
 * /governance/document/[id] route) and enriches in the EF layer (Markdown / section anchors
 * / ratification caveat / channel visibility ceiling) via the pure module
 * supabase/functions/nucleo-mcp/governance-html.mjs. No migration (the RPC is untouched).
 *
 * Two test layers:
 *   1. UNIT — exercise the pure converter/anchor/sanitizer/caveat helpers directly (the
 *      riskiest, edge-case-prone logic). DOMParser is unavailable in the Deno EF, so these
 *      are regex/string based; the unit tests are the adversarial verification of that.
 *   2. STATIC CONTRACT — regex assertions over index.ts that the tool is wired correctly
 *      and honors every legal guard-rail. Fast, no DB env required (offline-CI safe).
 *
 * Live behavioural proof captured during the build session (impersonated member JWT):
 * get_governance_document_reader returned full bodies for the 3 CR-050 docs
 * (Acordo 30993 / Termo 22517 / Adendo 14720 chars). Not re-run here (no DB env in offline CI).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  htmlToMarkdown,
  extractSectionAnchors,
  sanitizeGovernanceHtml,
  ratificationCaveat,
  decodeEntities,
  stripTags,
  MCP_GOVERNANCE_VISIBLE_CLASSES,
} from '../../supabase/functions/nucleo-mcp/governance-html.mjs';

const ROOT = process.cwd();
const EF = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// Isolate just this tool's registration block for scoped assertions.
function toolBlock() {
  const start = EF.indexOf('mcp.tool("get_governance_document_body"');
  assert.ok(start > -1, 'get_governance_document_body must be registered in index.ts');
  const end = EF.indexOf('mcp.tool("propose_new_version"', start);
  assert.ok(end > start, 'could not bound the get_governance_document_body tool block');
  return EF.slice(start, end);
}

// ─────────────────────────── 1. UNIT — htmlToMarkdown ───────────────────────────

test('#459 md: headings → # levels', () => {
  assert.match(htmlToMarkdown('<h2>Título</h2>'), /^## Título$/);
  assert.match(htmlToMarkdown('<h3>Art. 1 — Obras</h3>'), /^### Art\. 1 — Obras$/);
});

test('#459 md: heading wrapping <strong> keeps the text', () => {
  const md = htmlToMarkdown('<h2><strong>Adendo de PI</strong></h2>');
  assert.match(md, /^## /);
  assert.match(md, /Adendo de PI/);
});

test('#459 md: paragraph + bold + italic', () => {
  assert.equal(htmlToMarkdown('<p>a <strong>b</strong> <em>c</em></p>'), 'a **b** *c*');
});

test('#459 md: unordered + ordered lists', () => {
  assert.equal(htmlToMarkdown('<ul><li>one</li><li>two</li></ul>'), '- one\n- two');
  assert.equal(htmlToMarkdown('<ol><li>one</li><li>two</li></ol>'), '1. one\n2. two');
});

test('#459 md: TipTap nests <li><p>…</p></li>', () => {
  assert.equal(htmlToMarkdown('<ul><li><p>x</p></li><li><p>y</p></li></ul>'), '- x\n- y');
});

test('#459 md: links become [text](href)', () => {
  assert.equal(htmlToMarkdown('<p>see <a href="https://nucleoia.vitormr.dev">site</a></p>'),
    'see [site](https://nucleoia.vitormr.dev)');
});

test('#459 md: blockquote + hr', () => {
  assert.equal(htmlToMarkdown('<blockquote><p>quoted</p></blockquote>'), '> quoted');
  assert.equal(htmlToMarkdown('<p>a</p><hr><p>b</p>'), 'a\n\n---\n\nb');
});

test('#459 md: HTML entities decode (incl. nbsp → space)', () => {
  assert.match(htmlToMarkdown('<p>a &amp; b &lt;c&gt;</p>'), /a & b <c>/);
  assert.equal(decodeEntities('PMI&reg; &mdash; &#167; &#x2014;'), 'PMI® — § —');
});

test('#459 md: script/style are stripped (defense-in-depth)', () => {
  const md = htmlToMarkdown('<p>safe</p><script>alert(1)</script><style>.x{}</style>');
  assert.match(md, /safe/);
  assert.doesNotMatch(md, /alert|<script|\.x\{/i);
});

test('#459 md: real clause structure (Art. + §)', () => {
  const html = '<h3>Art. 1 — Obras Coletivas</h3><p><strong>§ 1º — Notificação prévia.</strong> corpo</p>';
  const md = htmlToMarkdown(html);
  assert.match(md, /### Art\. 1 — Obras Coletivas/);
  assert.match(md, /\*\*§ 1º — Notificação prévia\.\*\* corpo/);
});

test('#459 md: empty/nullish input → empty string', () => {
  assert.equal(htmlToMarkdown(''), '');
  assert.equal(htmlToMarkdown(null), '');
  assert.equal(htmlToMarkdown(undefined), '');
});

test('#459 md: code blocks round-trip (NUL-token stash/restore, none leaked)', () => {
  const one = htmlToMarkdown('<pre><code>const x = 1;</code></pre>');
  assert.match(one, /```[\s\S]*const x = 1;[\s\S]*```/, 'single code block must be fenced + restored');
  assert.doesNotMatch(one, /\u0000|CODE0/, 'no leftover stash token');
  const two = htmlToMarkdown('<p>a</p><pre><code>one</code></pre><p>b</p><pre><code>two</code></pre>');
  assert.match(two, /one/);
  assert.match(two, /two/);
  assert.doesNotMatch(two, /\u0000|CODE\d/, 'both code tokens restored, none leaked');
});

test('#459 md: <br> becomes a soft newline (documented)', () => {
  assert.equal(htmlToMarkdown('<p>a<br>b</p>'), 'a\nb');
});

test('#459 md: nested lists flatten (documented known limitation)', () => {
  // Governance bodies are flat-list dominated; nested lists flatten rather than indent.
  // Asserting the CURRENT behavior makes any future change a conscious one.
  const md = htmlToMarkdown('<ul><li>outer<ul><li>nested</li></ul></li></ul>');
  assert.match(md, /outer/);
  assert.match(md, /nested/);
});

// ─────────────────────────── 2. UNIT — extractSectionAnchors ───────────────────────────

test('#459 anchors: Art./Cláusula headings → clause value', () => {
  const a = extractSectionAnchors('<h3>Art. 1 — Obras</h3><h2>Cláusula 12. Vigência</h2>');
  const values = a.map((x) => x.value);
  assert.ok(values.includes('Art. 1'), `expected "Art. 1" in ${JSON.stringify(values)}`);
  assert.ok(values.includes('Cláusula 12'), `expected "Cláusula 12" (trailing dot stripped) in ${JSON.stringify(values)}`);
});

test('#459 anchors: non-clause heading falls back to full title', () => {
  const a = extractSectionAnchors('<h2>Preâmbulo</h2>');
  assert.equal(a.length, 1);
  assert.equal(a[0].value, 'Preâmbulo');
});

test('#459 anchors: <strong> only contributes when clause-numbered', () => {
  const a = extractSectionAnchors('<p><strong>§ 1º — n.</strong></p><p><strong>PMI®</strong></p>');
  const values = a.map((x) => x.value);
  assert.ok(values.some((v) => /§\s*1/.test(v)), `expected a § 1 anchor in ${JSON.stringify(values)}`);
  assert.ok(!values.includes('PMI®'), 'non-clause <strong> must not become an anchor');
});

test('#459 anchors: duplicate clause numbers dedup', () => {
  const a = extractSectionAnchors('<h3>Art. 1 — A</h3><h3>Art. 1 — B</h3>');
  assert.equal(a.filter((x) => x.value === 'Art. 1').length, 1);
});

test('#459 anchors: empty input → []', () => {
  assert.deepEqual(extractSectionAnchors(''), []);
  assert.deepEqual(extractSectionAnchors(null), []);
});

// ─────────────────────────── 3. UNIT — sanitize / caveat / constants ───────────────────────────

test('#459 sanitize: strips script + event handlers + javascript: URLs, keeps markup', () => {
  const dirty = '<h2>T</h2><p onclick="evil()">x</p><script>steal()</script><a href="javascript:bad()">l</a>';
  const clean = sanitizeGovernanceHtml(dirty);
  assert.doesNotMatch(clean, /<script|onclick=|javascript:/i);
  assert.match(clean, /<h2>T<\/h2>/);
  assert.match(clean, /<p[^>]*>x<\/p>/);
});

test('#459 caveat: active → null, non-active → ratification warning', () => {
  assert.equal(ratificationCaveat('active'), null);
  assert.match(ratificationCaveat('under_review'), /ratifica/i);
  assert.match(ratificationCaveat('draft'), /sujeito a altera/i);
});

test('#459 ceiling: MCP serves only public + active_members (legal guard-rail #2)', () => {
  assert.deepEqual(MCP_GOVERNANCE_VISIBLE_CLASSES, ['public', 'active_members']);
  for (const restricted of ['admin_only', 'audit_restricted', 'legal_scoped']) {
    assert.ok(!MCP_GOVERNANCE_VISIBLE_CLASSES.includes(restricted),
      `${restricted} must NOT be served via MCP`);
  }
});

test('#459 stripTags: tags out, entities decoded, whitespace collapsed', () => {
  assert.equal(stripTags('<h2><strong>A &amp;  B</strong></h2>'), 'A & B');
});

// ─────────────────────────── 4. STATIC CONTRACT — index.ts wiring ───────────────────────────

test('#459 wiring: tool wraps the canonical reader RPC (not get_version_diff)', () => {
  const block = toolBlock();
  assert.match(block, /sb\.rpc\(\s*"get_governance_document_reader"/,
    'must call the canonical body-reader RPC');
  assert.doesNotMatch(block, /get_version_diff/,
    'must NOT route through get_version_diff (its active-member-only gate is weaker than the canon)');
});

test('#459 wiring: auth + UUID validation gates present', () => {
  const block = toolBlock();
  assert.match(block, /getMember\(sb\)/, 'must resolve the authenticated member');
  assert.match(block, /Not authenticated/, 'must fail closed when unauthenticated');
  assert.match(block, /isUUID\(params\.document_id\)/, 'must validate document_id is a UUID');
});

test('#459 guard-rail #2: MCP visibility ceiling applied in the tool', () => {
  const block = toolBlock();
  assert.match(block, /MCP_GOVERNANCE_VISIBLE_CLASSES/, 'must apply the channel visibility ceiling');
  assert.match(block, /restricted_for_mcp_channel/, 'must short-circuit restricted classes without the body');
  // council M1: the restricted branch returns document:null (do not fingerprint a restricted doc)
  assert.match(block, /reason:\s*"restricted_for_mcp_channel"[\s\S]{0,200}?document:\s*null/,
    'restricted_for_mcp_channel must return document:null (no metadata fingerprint)');
});

test('#459 guard-rail #2b (council M3): forward-defense draft_not_locked gate', () => {
  const block = toolBlock();
  assert.match(block, /!ver\.locked_at/, 'EF must independently gate on locked_at (forward-defense)');
  assert.match(block, /draft_not_locked/, 'unlocked-draft body must not be served via MCP');
});

test('#459 guard-rail #3: tool never reads document_comments (curation notes)', () => {
  const block = toolBlock();
  assert.doesNotMatch(block, /document_comments/,
    'the body-read tool must not surface curation comments');
});

test('#459 guard-rail #4: reinforced logging includes document_id + version_id', () => {
  const block = toolBlock();
  // success path logs a response_summary object carrying the audited doc/version ids.
  assert.match(block, /document_id:\s*doc\.id/, 'success log must record document_id');
  assert.match(block, /version_id:\s*ver\.version_id/, 'success log must record version_id');
  assert.match(block, /ratification_status:\s*status/, 'success log must record ratification_status');
});

test('#459 guard-rail #5: no-legal-advice + under_review disclaimer in description', () => {
  const block = toolBlock();
  assert.match(block, /does NOT constitute legal advice/i, 'description must disclaim legal advice');
  assert.match(block, /under_review/, 'description must warn about under_review documents');
});

test('#459 guard-rail #1: payload carries ratification_status + caveat', () => {
  const block = toolBlock();
  assert.match(block, /ratification_status:\s*status/);
  assert.match(block, /caveat:\s*ratificationCaveat\(status\)/);
});

test('#459 enrichment: payload returns html + markdown + anchors + length (md/anchors from sanitized html)', () => {
  const block = toolBlock();
  assert.match(block, /content_html:\s*cleanHtml/);
  // council L1: markdown + anchors derive from the SANITIZED html, not raw
  assert.match(block, /content_markdown:\s*htmlToMarkdown\(cleanHtml\)/);
  assert.match(block, /section_anchors:\s*extractSectionAnchors\(cleanHtml\)/);
  assert.match(block, /content_html_length:\s*cleanHtml\.length/);
});

test('#459 wiring: index.ts imports the shared pure module', () => {
  assert.match(EF, /from\s+"\.\/governance-html\.mjs"/, 'must import the shared enrichment module');
});

test('#459 logUsage extended with optional responseSummary → p_response_summary', () => {
  assert.match(EF, /async function logUsage\([^)]*responseSummary\?: unknown\)/,
    'logUsage must accept an optional responseSummary');
  assert.match(EF, /p_response_summary:\s*responseSummary\s*\?\?\s*null/,
    'logUsage must forward response_summary to log_mcp_usage');
});

test('#459 /health declares /mcp tools = 308', () => {
  assert.match(EF, /"\/mcp":\s*\{\s*server:\s*"nucleo-ia-hub"\s*,\s*version:\s*"2\.79\.0"\s*,\s*tools:\s*308\s*\}/);
});
