/**
 * #1377 — /actions overflow surface: coverage guard.
 *
 * Root cause (confirmed live 2026-07-14): the Claude chat connector caps a SINGLE
 * connector at 256 tools and ingests them ALPHABETICALLY by display name. /mcp exposes
 * ~339 tools in one tools/list, so the connector silently drops everything past the
 * ~"manage_*" boundary — which is almost the entire write/action surface
 * (schedule_interview, submit_interview_scores, move_card, offboard_member, …). The
 * operator saw "não consigo acessar rotas de seleção de candidato": the READ tools
 * (get_selection_*) survive in the a→m half; the write tools do not.
 *
 * Fix (#1377): a second EF surface /actions (proxy src/pages/mcp/actions.ts) re-exposes
 * the dropped tail as a separate connector, reusing the SAME registerTools definitions via
 * an allowlist filter (ACTIONS_ALLOWLIST in supabase/functions/nucleo-mcp/index.ts).
 *
 * This test is the anti-drift guard: if a future tool addition shifts the /mcp 256-cut and
 * pushes a tool off the cliff, CI fails until that tool is added to ACTIONS_ALLOWLIST. It is
 * a pure static check (no network / no DB) so it runs in every offline baseline.
 *
 * Cross-ref: #1377, .claude/rules/mcp.md, /health surfaces.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The Claude connector's per-connector tool cap (empirically 256 = 2^8, observed in the
// connector UI "Other tools 256" label). Tools alphabetically past this are dropped from /mcp.
const CONNECTOR_CAP = 256;

// The semantic-gateway tools live on /semantic ONLY (registerSemanticTools) — they are NOT part
// of the /mcp registerTools surface and must be excluded from the 256-cap overflow computation.
// 4 bridge tools (SPEC-280) + 8 Wave-1 boards/cards tools (#1383).
const SEMANTIC_ONLY = new Set([
  'get_my_context',
  'search_nucleo_knowledge',
  'get_board_or_initiative_context',
  'get_operational_status',
  // Wave 1 (#1383) — /semantic only
  'card_checklist',
  'card_write',
  'card_comment',
  'card_search',
  'card_get',
  'board_overview',
  'platform_context',
  'portfolio_report',
]);

/** All single-line `mcp.tool("name", ...)` names = the /mcp surface (registerKnowledge + registerTools). */
function extractMcpToolNames(src) {
  const names = new Set();
  for (const m of src.matchAll(/mcp\.tool\(\s*"([a-zA-Z0-9_]+)"/g)) {
    if (!SEMANTIC_ONLY.has(m[1])) names.add(m[1]);
  }
  return [...names];
}

/** Parse the ACTIONS_ALLOWLIST Set literal. */
function extractAllowlist(src) {
  const block = src.match(/const ACTIONS_ALLOWLIST:\s*Set<string>\s*=\s*new Set\(\[([\s\S]*?)\]\);/);
  assert.ok(block, 'ACTIONS_ALLOWLIST Set literal not found in index.ts');
  const names = new Set();
  for (const m of block[1].matchAll(/"([a-zA-Z0-9_]+)"/g)) names.add(m[1]);
  return names;
}

const ALL_MCP_TOOLS = extractMcpToolNames(SRC);
const ALLOWLIST = extractAllowlist(SRC);

test('#1377: every tool /mcp drops past the 256 cap is covered by ACTIONS_ALLOWLIST', () => {
  const sorted = [...ALL_MCP_TOOLS].sort();
  const dropped = sorted.slice(CONNECTOR_CAP); // positions 257..end
  const missing = dropped.filter((n) => !ALLOWLIST.has(n));
  assert.deepEqual(
    missing,
    [],
    `These tools fall off the /mcp 256-cut but are NOT on /actions (add them to ACTIONS_ALLOWLIST):\n  ${missing.join('\n  ')}`
  );
});

test('#1377: every ACTIONS_ALLOWLIST entry is a real registered tool (no typos / stale names)', () => {
  const known = new Set(ALL_MCP_TOOLS);
  const orphans = [...ALLOWLIST].filter((n) => !known.has(n));
  assert.deepEqual(orphans, [], `ACTIONS_ALLOWLIST names with no matching mcp.tool(): ${orphans.join(', ')}`);
});

test('#1377: /actions surface itself fits under the connector cap', () => {
  assert.ok(
    ALLOWLIST.size < CONNECTOR_CAP,
    `/actions exposes ${ALLOWLIST.size} tools, which is >= the ${CONNECTOR_CAP} connector cap`
  );
});

test('#1377: the selection write tools that motivated this are on /actions', () => {
  // Regression sentinels — the exact tools the operator could not reach.
  for (const t of [
    'schedule_interview',
    'submit_interview_scores',
    'mark_interview_status',
    'promote_lead_to_application',
    'manage_selection_committee',
    'update_application_contact',
  ]) {
    assert.ok(ALLOWLIST.has(t), `${t} must be on /actions (it is a dropped selection write tool)`);
  }
});
