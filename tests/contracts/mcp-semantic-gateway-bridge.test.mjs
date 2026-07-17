/**
 * Contract: MCP Semantic Gateway bridge (p222 #280 alpha).
 *
 * Forward-defense for the bridge-first migration described in
 * docs/specs/SPEC_280A_CONNECTOR_STORE_READINESS.md (parent gate) and
 * docs/specs/SPEC_280B_SEMANTIC_MCP_GATEWAY_IMPLEMENTATION.md (impl brief).
 *
 * Origin: p222 session (2026-05-22). Issue #280 motivated by recurring Perplexity
 * tools/list failures (#277, #279) and the broader observation that a 299-tool
 * monolithic catalog is a poor public discovery contract for strict MCP clients.
 *
 * Bridge-first migration (per #280 PM decision):
 *   - `/mcp` stays as the existing full-catalog endpoint (regression-safe)
 *   - `/mcp/semantic` is the new public semantic gateway (4 read-only tools: 3 wave-1 + get_operational_status wave-2)
 *   - the 299-tool catalog stays internal/dev; future migration moves the full
 *     surface behind `/mcp/full` or `?profile=full` once metrics + docs catch up.
 *
 * Wave-1 semantic tools (this PR):
 *   - get_my_context
 *   - search_nucleo_knowledge
 *   - get_board_or_initiative_context
 *
 * Static-only (no DB, no live HTTP). Verifies source-code invariants that survive
 * across refactors: function existence, route presence, tool names, envelope shape,
 * worker proxy wiring, and the /mcp regression-safety guarantee.
 *
 * Cross-ref:
 *   - SPEC_280A_CONNECTOR_STORE_READINESS.md
 *   - SPEC_280B_SEMANTIC_MCP_GATEWAY_IMPLEMENTATION.md
 *   - .claude/rules/mcp.md (header updated to declare semantic surface)
 *   - GH #280 (parent SPEC) + #283 (child store-readiness)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const EF_PATH = resolve(process.cwd(), 'supabase/functions/nucleo-mcp/index.ts');
const PROXY_PATH = resolve(process.cwd(), 'src/pages/mcp/semantic.ts');
const LEGACY_PROXY_PATH = resolve(process.cwd(), 'src/pages/mcp.ts');

const EF = readFileSync(EF_PATH, 'utf8');

// ─── 1. Header changelog ──────────────────────────────────────────────────────

test('ef header declares v2.79.x–v2.81.x (semantic gateway bridge era + #1383 Wave 1)', () => {
  // p232: loosened to v2.79.\d+ so additive patches (description bumps, no-new-tools)
  //   don't break this assertion. The contract is "semantic gateway bridge shipped in 2.79.x".
  // p239b: extended to also accept v2.80.x — +2 LGPD retroactive operator tools (#332 close).
  // #1383 Wave 1: extended to v2.81.x — the semantic surface graduated from bridge (4 tools) to
  //   the first migration wave (+8 boards/cards tools, /semantic 4→12, nucleo-ia-semantic@0.3.0).
  assert.match(EF, /MCP server v2\.(79|80|81)\.\d+/, 'expected v2.79.x–v2.81.x marker in header');
  assert.match(EF, /p222 #280 alpha/i, 'expected p222 #280 alpha provenance');
  assert.match(EF, /Semantic MCP Gateway bridge/i, 'expected semantic gateway naming in header');
});

// ─── 2. registerSemanticTools function ────────────────────────────────────────

test('ef declares function registerSemanticTools(mcp, sb)', () => {
  assert.match(EF, /function\s+registerSemanticTools\s*\(\s*mcp\s*:\s*McpServer\s*,\s*sb/);
});

test('ef declares buildSemanticError helper for structured error envelopes', () => {
  assert.match(EF, /function\s+buildSemanticError\s*\(/);
  assert.match(EF, /code:\s*args\.code/, 'expected error envelope to carry code');
  assert.match(EF, /message:\s*args\.message/, 'expected error envelope to carry message');
  assert.match(EF, /action:\s*args\.action/, 'expected error envelope to carry action');
});

// ─── 3. Three wave-1 semantic tools registered (exact names) ──────────────────

function semanticBlock() {
  const start = EF.indexOf('function registerSemanticTools');
  assert.notEqual(start, -1, 'registerSemanticTools function not found');
  // Find the next `function ` declaration OR `// MCP endpoint` boundary OR
  // /mcp route OR /semantic route boundary to bound the block.
  const boundaryCandidates = [
    EF.indexOf('\nfunction ', start + 1),
    EF.indexOf('// MCP endpoint', start + 1),
    EF.indexOf('app.all("/mcp"', start + 1),
    EF.indexOf('app.all("/semantic"', start + 1),
  ].filter((i) => i > 0);
  const end = Math.min(...boundaryCandidates);
  assert.ok(end > start, 'could not locate semantic-block end boundary');
  const block = EF.slice(start, end);
  // Council MED defensive — boundary detection truncation guard. registerSemanticTools
  // body is ~280 lines (~12000 chars). If boundary detection accidentally truncates,
  // tests would silently pass on an incomplete view of the function. Anchor a minimum.
  assert.ok(block.length > 8000, `semantic block suspiciously short (${block.length} chars) — boundary detection may have truncated`);
  return block;
}

test('semantic block registers exactly 52 mcp.tool() calls (4 bridge + 8 W1 + 9 W2 + 6 W3 + 6 W4 + 7 W5 + 7 W6a + 5 W6b #1383)', () => {
  const block = semanticBlock();
  const matches = block.match(/mcp\.tool\(\s*"[^"]+"/g) || [];
  assert.equal(matches.length, 52, `expected 52 mcp.tool() in registerSemanticTools, got ${matches.length}: ${matches.join(', ')}`);
});

test('semantic block names the bridge + Wave-1 tools exactly', () => {
  const block = semanticBlock();
  const BRIDGE = ['get_my_context', 'search_nucleo_knowledge', 'get_board_or_initiative_context', 'get_operational_status'];
  const WAVE1 = ['card_checklist', 'card_write', 'card_comment', 'card_search', 'card_get', 'board_overview', 'platform_context', 'portfolio_report'];
  for (const name of [...BRIDGE, ...WAVE1]) {
    assert.match(block, new RegExp(`mcp\\.tool\\(\\s*"${name}"`), `expected mcp.tool("${name}") in semantic block`);
  }
});

test('semantic tools have Zod input schemas (object literal as 3rd arg)', () => {
  const block = semanticBlock();
  // Each tool definition should include at least one z. usage in its inputSchema block.
  // (get_my_context and search_nucleo_knowledge use z.enum/z.string/z.boolean/z.number;
  // get_board_or_initiative_context uses z.string/z.number/z.enum.)
  for (const name of ['get_my_context', 'search_nucleo_knowledge', 'get_board_or_initiative_context', 'get_operational_status']) {
    // Capture from the tool declaration up to the async handler keyword to scope to the schema area.
    const m = block.match(new RegExp(`mcp\\.tool\\(\\s*"${name}"[\\s\\S]*?async\\s*\\(`, 'm'));
    assert.ok(m, `did not find ${name} tool declaration`);
    assert.match(m[0], /z\.[a-zA-Z]+\(/, `expected at least one Zod schema in ${name} input schema`);
  }
});

// ─── 4. Stable envelope shape ─────────────────────────────────────────────────

test('semantic block returns envelope keys (ok, data, summary, warnings, next_actions, audit)', () => {
  const block = semanticBlock();
  // Each envelope key may appear in object literals as either:
  //   - explicit:  `key: value`
  //   - shorthand: `key,` (variable of same name passed through)
  // Count both forms; require >=3 per tool (one return per tool minimum).
  for (const key of ['ok', 'data', 'summary', 'warnings', 'next_actions', 'audit']) {
    const count = (block.match(new RegExp(`\\b${key}[,:]`, 'g')) || []).length;
    assert.ok(count >= 3, `expected envelope key '${key}' >=3 occurrences (one per tool) in semantic block; got ${count}`);
  }
});

test('semantic audit carries semantic_domain + permission + pii_level + source_tools + generated_at', () => {
  const block = semanticBlock();
  for (const key of ['semantic_domain:', 'permission:', 'pii_level:', 'source_tools:', 'generated_at:']) {
    assert.match(block, new RegExp(key.replace(':', ':\\s*')), `expected audit field '${key}' in semantic block`);
  }
});

// ─── 5. /semantic HTTP route ──────────────────────────────────────────────────

// Slice the actual route handler block (between this app.all and the next app. directive
// OR the file's Deno.serve). Anchored on `app.all("/semantic", async` to avoid matching
// header comment mentions like `app.all("/semantic")`.
function routeBlock(routeKey) {
  const start = EF.search(new RegExp(`app\\.all\\(\\s*"${routeKey}"\\s*,\\s*async`));
  assert.notEqual(start, -1, `${routeKey} route start not found`);
  // Walk to the next top-level app.* directive after this one, or to Deno.serve.
  const tailSearchFrom = start + 1;
  const candidates = [
    EF.indexOf('\napp.all(', tailSearchFrom),
    EF.indexOf('\napp.get(', tailSearchFrom),
    EF.indexOf('\napp.post(', tailSearchFrom),
    EF.indexOf('\nDeno.serve(', tailSearchFrom),
  ].filter((i) => i > 0);
  const end = candidates.length > 0 ? Math.min(...candidates) : EF.length;
  return EF.slice(start, end);
}

test('ef declares app.all("/semantic") route', () => {
  assert.match(EF, /app\.all\(\s*"\/semantic"\s*,\s*async/, 'expected app.all("/semantic", ...) route');
});

test('/semantic handler constructs McpServer "nucleo-ia-semantic" v0.9.0 (#1383 Wave 6b)', () => {
  const block = routeBlock('/semantic');
  assert.match(block, /new McpServer\(\s*\{\s*name:\s*"nucleo-ia-semantic"\s*,\s*version:\s*"0\.9\.0"\s*\}\s*\)/);
});

test('/semantic handler registers ONLY registerSemanticTools (not registerTools/registerKnowledge)', () => {
  const block = routeBlock('/semantic');
  assert.match(block, /registerSemanticTools\s*\(\s*mcp\s*,\s*sb\s*\)/);
  assert.doesNotMatch(block, /registerTools\s*\(\s*mcp/, '/semantic should NOT call registerTools (would leak full 299 catalog)');
  assert.doesNotMatch(block, /registerKnowledge\s*\(\s*mcp/, '/semantic should NOT call registerKnowledge (not part of public wave-1 surface)');
});

test('/semantic handler uses stateless transport (sessionIdGenerator: undefined)', () => {
  const block = routeBlock('/semantic');
  assert.match(block, /sessionIdGenerator:\s*undefined/, 'expected stateless transport mode');
  assert.match(block, /WebStandardStreamableHTTPServerTransport/, 'expected native Streamable HTTP transport');
});

// ─── 6. /health endpoint surfaces both endpoints ──────────────────────────────

test('/health endpoint reports both /mcp and /semantic surfaces', () => {
  const m = EF.match(/app\.get\(\s*"\/health"[\s\S]*?\}\s*\)\s*\)/);
  assert.ok(m, 'could not capture /health handler');
  assert.match(m[0], /"\/mcp":/, '/health should report /mcp surface');
  assert.match(m[0], /"\/semantic":/, '/health should report /semantic surface');
  assert.match(m[0], /"nucleo-ia-hub"/, '/health should report /mcp server name');
  assert.match(m[0], /"nucleo-ia-semantic"/, '/health should report /semantic server name');
  assert.match(m[0], /tools:\s*52/, '/health should report 52 tools on /semantic (4 bridge + 8 W1 + 9 W2 + 6 W3 + 6 W4 + 7 W5 + 7 W6a + 5 W6b #1383)');
  // p239b: /mcp grew 299 → 301 via +2 LGPD retroactive operator tools (#332 close);
  // then 301 → 304 via the #411 selection-cutoff MCP exposure (+3); then 304 → 303 via #191
  // (removed the broken advance_card_curation tool); then 303 → 306 via #188 (+3 curator-native tools);
  // then 306 → 307 via #415 (+1 get_recurrence_stockout); then 307 → 308 via #459 (+1 get_governance_document_body);
  // then 308 → 311 via #209 (+3 drive revocation tools); then 311 → 314 via #301 (+3 curation drive grant tools);
  // then 314 → 317 via #1099 (+3 comms scheduling on-ramp tools), then 317 → 323 via #1138 (+6 tribe journey parity).
  assert.match(m[0], /tools:\s*323/, '/health should report 323 tools on /mcp (317 → 323 via #1138 tribe hybrid-journey MCP parity)');
});

// ─── 7. /mcp regression-safety guarantee ──────────────────────────────────────

test('regression: /mcp route still exists and still registers full catalog', () => {
  const block = routeBlock('/mcp');
  assert.match(block, /registerKnowledge\s*\(\s*mcp\s*,\s*sb\s*\)/, '/mcp must still call registerKnowledge');
  assert.match(block, /registerTools\s*\(\s*mcp\s*,\s*sb\s*\)/, '/mcp must still call registerTools');
  assert.match(block, /new McpServer\(\s*\{\s*name:\s*"nucleo-ia-hub"/, '/mcp must still construct nucleo-ia-hub server');
});

// ─── 8. Worker proxy ──────────────────────────────────────────────────────────

test('worker proxy file src/pages/mcp/semantic.ts exists', () => {
  assert.ok(existsSync(PROXY_PATH), `expected ${PROXY_PATH} to exist`);
});

test('worker proxy UPSTREAM points to /nucleo-mcp/semantic (NOT /mcp)', () => {
  const PROXY = readFileSync(PROXY_PATH, 'utf8');
  assert.match(PROXY, /const\s+UPSTREAM\s*=\s*'https:\/\/[^']*\/functions\/v1\/nucleo-mcp\/semantic'/, 'expected UPSTREAM ending in /nucleo-mcp/semantic');
  // Sanity: shouldn't accidentally proxy to the full /mcp endpoint.
  assert.doesNotMatch(PROXY, /UPSTREAM\s*=\s*'[^']*\/functions\/v1\/nucleo-mcp\/mcp'/, 'semantic proxy must not point to /nucleo-mcp/mcp UPSTREAM');
});

test('worker proxy preserves OAuth 401 + WWW-Authenticate gate', () => {
  const PROXY = readFileSync(PROXY_PATH, 'utf8');
  assert.match(PROXY, /WWW-Authenticate/, 'expected WWW-Authenticate header (RFC 9728)');
  assert.match(PROXY, /resource_metadata="\$\{BASE\}\/\.well-known\/oauth-protected-resource"/, 'expected resource_metadata pointer to OAuth metadata endpoint');
});

test('worker proxy does NOT refresh server-side (single-refresher model, #1053)', () => {
  const PROXY = readFileSync(PROXY_PATH, 'utf8');
  // #1053: the proxy-side refresh was removed — it raced Claude's own refresh over the
  // same rotating Supabase refresh token → ~1h re-login. Claude is the sole refresher
  // (via /oauth/token). The proxy only decodes the JWT `sub` for rate limiting.
  assert.doesNotMatch(PROXY, /tryAutoRefresh\(/, 'proxy must NOT call tryAutoRefresh (#1053)');
  assert.match(PROXY, /decodeJwtPayload\(/, 'still decodes the JWT for rate-limit keying');
  // The shared refresh helpers + KV key prefix stay in the module (used by /oauth/token,
  // and unit-tested), just not wired into the proxy anymore.
  const REFRESH_LIB = readFileSync(resolve(process.cwd(), 'src/lib/mcp-refresh.ts'), 'utf8');
  assert.match(REFRESH_LIB, /mcp_refresh:/, 'expected mcp_refresh KV key prefix in shared lib/mcp-refresh');
});

test('worker proxy preserves rate limiting (ADR-0018 W2)', () => {
  const PROXY = readFileSync(PROXY_PATH, 'utf8');
  assert.match(PROXY, /from\s+['"]\.\.\/\.\.\/lib\/mcp-rate-limit['"]/, 'expected ../../lib/mcp-rate-limit import (semantic.ts is one level deeper than mcp.ts)');
  assert.match(PROXY, /checkRateLimit\(/);
  assert.match(PROXY, /extractToolName\(/);
});

test('worker proxy preserves tools/list execution-strip (p220 fix)', () => {
  const PROXY = readFileSync(PROXY_PATH, 'utf8');
  assert.match(PROXY, /isToolsList/, 'expected tools/list detection variable');
  assert.match(PROXY, /"execution"\\s\*:\\s\*\\\{\\s\*"taskSupport"\\s\*:\\s\*"forbidden"\\s\*\\\}/, 'expected execution.taskSupport regex strip');
  assert.match(PROXY, /respHeadersOut\.delete\(\s*'content-length'\s*\)/, 'expected content-length removal after strip');
});

test('worker proxy preserves CORS preflight + universal CORS headers', () => {
  const PROXY = readFileSync(PROXY_PATH, 'utf8');
  assert.match(PROXY, /'Access-Control-Allow-Origin':\s*'\*'/);
  assert.match(PROXY, /'Access-Control-Expose-Headers':\s*'Mcp-Session-Id'/);
  assert.match(PROXY, /if\s*\(\s*request\.method\s*===\s*'OPTIONS'\s*\)/);
});

// ─── 9. Legacy /mcp proxy untouched (regression-safety) ───────────────────────

test('regression: legacy src/pages/mcp.ts still exists and still targets /nucleo-mcp/mcp', () => {
  assert.ok(existsSync(LEGACY_PROXY_PATH), 'legacy mcp.ts proxy must remain');
  const LEGACY = readFileSync(LEGACY_PROXY_PATH, 'utf8');
  assert.match(LEGACY, /const\s+UPSTREAM\s*=\s*'https:\/\/[^']*\/functions\/v1\/nucleo-mcp\/mcp'/, 'legacy proxy must keep pointing to /nucleo-mcp/mcp');
});

// ─── 10. PII discipline ───────────────────────────────────────────────────────

test('semantic block declares pii_level audit field (none|low|self|high) on each tool', () => {
  const block = semanticBlock();
  // At least 3 occurrences expected (one per tool); tools with summary+standard branches
  // may declare 2x (one per code path). Cap at 6 to catch runaway leakage.
  const matches = block.match(/pii_level:\s*"(none|low|self|high)"/g) || [];
  // 21 tools; several declare pii_level in >1 code path (card_write preview+exec, board_overview
  // list+board+initiative, member_lifecycle/engagement_write preview+exec, initiative_report
  // comparison+pilots+per-init). A couple (member_search/member_get) use a DYNAMIC ternary
  // (pii_level reflects the actual view_pii disclosure) so they contribute 0 literal matches.
  // One per tool minimum, capped generously to still catch runaway leakage.
  assert.ok(matches.length >= 19, `expected >=19 literal pii_level declarations; got ${matches.length}`);
  assert.ok(matches.length <= 72, `expected <=72 pii_level declarations (multi-branch cap; W6b adds 5 literal — champion_award 'low', lgpd_admin 'high' x2, knowledge page/latest 'none' x2 — while gamification_report/admin_dashboard/audit_log use dynamic ternaries = 0 literal matches; live count 65); got ${matches.length}`);
  // Each of the three values must appear at least once across the 3 tools.
  for (const expected of ['"none"', '"low"', '"self"']) {
    assert.ok(block.includes(`pii_level: ${expected}`), `expected at least one pii_level: ${expected} in semantic block`);
  }
});

test('semantic tools do not include raw email/phone/address selection from members table', () => {
  const block = semanticBlock();
  // The members.select inside get_my_context must NOT include email/phone/address columns.
  const m = block.match(/sb\.from\(\s*"members"\s*\)\s*\.select\(\s*"([^"]+)"\s*\)/);
  assert.ok(m, 'expected members.select(...) call inside get_my_context');
  const cols = m[1];
  for (const piiCol of ['email', 'phone', 'address']) {
    assert.doesNotMatch(cols, new RegExp(`\\b${piiCol}\\b`), `get_my_context must NOT select members.${piiCol} (LGPD wave-1)`);
  }
});

// ─── 11. Council HIGH-1 forward-defense — notifications schema correctness ────

test('get_my_context notifications.select uses real columns (no `payload`)', () => {
  const block = semanticBlock();
  // The notifications.select(...) inside get_my_context (the withNotifs branch) must
  // use columns that exist on the table: id/recipient_id/type/title/body/link/created_at/
  // is_read/read_at/actor_id/email_sent_at/delivery_mode/digest_*. The first attempted
  // shape "id, type, payload, created_at" referenced a non-existent `payload` column,
  // surfaced by Council Tier 1 HIGH-1 (platform-guardian + code-reviewer) and verified
  // via information_schema.columns live query.
  const m = block.match(/sb\.from\(\s*"notifications"\s*\)\s*\.select\(\s*"([^"]+)"\s*\)\s*\.eq\(\s*"recipient_id"/);
  assert.ok(m, 'expected withNotifs branch notifications.select(...) call');
  const cols = m[1];
  assert.doesNotMatch(cols, /\bpayload\b/, 'notifications has no `payload` column — use title/body/link');
  for (const expectedCol of ['title', 'body', 'link']) {
    assert.match(cols, new RegExp(`\\b${expectedCol}\\b`), `notifications.select must include ${expectedCol} (live notif content)`);
  }
});
