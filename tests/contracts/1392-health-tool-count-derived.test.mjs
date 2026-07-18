/**
 * #1392 — /health must DERIVE per-surface tool counts, never hardcode them.
 *
 * Root cause (guardian, Wave 3 of #1383): the /health handler in nucleo-mcp declared
 * `tools: 323` (/mcp) and `tools: 27` (/semantic) as bare number literals. /mcp had
 * actually grown to 342 tools since e32e7fd (2026-05-22) — 19 tools of silent drift — and
 * /semantic was correct only by manual discipline. /health exists to be the fast source of
 * truth for the surfaces (first command of every MCP re-grounding), so it was lying about
 * itself in the one place a "never pin a count, always re-derive" rule (.claude/rules/mcp.md)
 * is supposed to protect.
 *
 * Fix (#1392): count the tools off the SAME registrars the live endpoints use
 * (`countRegisteredTools(registerKnowledge, registerTools)` for /mcp;
 * `countRegisteredTools(registerSemanticTools)` for /semantic), mirroring how /actions already
 * derives from `ACTIONS_ALLOWLIST.size`.
 *
 * This is the anti-drift guard: it fails if a bare numeric literal reappears as a `tools:` value
 * in /health, or if the derived constants stop being wired to the correct registrars. Pure static
 * check (no network / no DB) so it runs in every offline baseline.
 *
 * Cross-ref: #1392, #1383, .claude/rules/mcp.md.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// Isolate the /health handler body (from `app.get("/health"` to its closing `}));`).
function healthBlock() {
  const m = SRC.match(/app\.get\("\/health"[\s\S]*?\}\)\);/);
  assert.ok(m, 'could not locate the /health handler in nucleo-mcp/index.ts');
  return m[0];
}

test('#1392 — /health does not hardcode any surface tool count as a numeric literal', () => {
  const block = healthBlock();
  const literals = [...block.matchAll(/tools:\s*(\d+)\b/g)].map((x) => x[1]);
  assert.equal(
    literals.length,
    0,
    `/health must DERIVE tool counts, not hardcode them. Found literal(s): ${literals.join(', ')}. ` +
      `Wire the surface to a derived count (MCP_TOOL_COUNT / SEMANTIC_TOOL_COUNT / ACTIONS_ALLOWLIST.size).`,
  );
});

test('#1392 — each /health surface is wired to its derived count', () => {
  const block = healthBlock();
  assert.match(block, /"\/mcp":\s*\{[^}]*tools:\s*MCP_TOOL_COUNT\b/, '/mcp must use MCP_TOOL_COUNT');
  assert.match(block, /"\/semantic":\s*\{[^}]*tools:\s*SEMANTIC_TOOL_COUNT\b/, '/semantic must use SEMANTIC_TOOL_COUNT');
  assert.match(block, /"\/actions":\s*\{[^}]*tools:\s*ACTIONS_ALLOWLIST\.size\b/, '/actions must use ACTIONS_ALLOWLIST.size');
});

test('#1392 — the derived constants are computed off the correct registrars', () => {
  // /mcp = registerKnowledge + registerTools (full catalog); /semantic = registerSemanticTools.
  assert.match(
    SRC,
    /const\s+MCP_TOOL_COUNT\s*=\s*countRegisteredTools\(\s*registerKnowledge\s*,\s*registerTools\s*\)/,
    'MCP_TOOL_COUNT must be countRegisteredTools(registerKnowledge, registerTools)',
  );
  assert.match(
    SRC,
    /const\s+SEMANTIC_TOOL_COUNT\s*=\s*countRegisteredTools\(\s*registerSemanticTools\s*\)/,
    'SEMANTIC_TOOL_COUNT must be countRegisteredTools(registerSemanticTools)',
  );
});
