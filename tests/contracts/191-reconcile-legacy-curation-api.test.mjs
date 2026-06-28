/**
 * Contract: #191 — reconcile the legacy curation API with the p197 structured flow.
 *
 * The consumer-facing legacy divergence was the MCP tool `advance_card_curation` — it advertised
 * assign/approve/reject/request_changes but wrapped advance_board_item_curation, which only accepts
 * request_review/approve_peer/approve_leader. 0 lifetime uses. REMOVED (tool count 304 → 303).
 *
 * The canonical curation API is the p197 flow (complete_peer_review / complete_leader_review /
 * submit_for_curation / submit_curation_review), covered by 194-p197-review-flow-contracts.
 *
 * DEFERRED follow-up: the orphan `TribeKanbanIsland.tsx` (imported by tribe/[id].astro but never
 * JSX-mounted — the live board is BoardEngine) is dead code, but 3 ui-stabilization tests still
 * read it as a kanban-island proxy + comp.kanban.* i18n keys reference it. Deleting it cleanly
 * needs those tests re-pointed to BoardEngine first — tracked as a separate cleanup.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const EF = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');
const MATRIX_JSON = readFileSync(resolve(ROOT, 'docs/reference/mcp-tool-matrix.json'), 'utf8');

test('#191: the broken advance_card_curation MCP tool is removed', () => {
  assert.doesNotMatch(EF, /mcp\.tool\(\s*"advance_card_curation"/,
    'advance_card_curation tool must be removed from the MCP catalog');
  assert.match(EF, /advance_card_curation MCP tool REMOVED/,
    'a removal-trace comment documents why');
});

test('#191 + #188 + #415 + #459 + #209: /health declares the corrected /mcp tool count (311)', () => {
  assert.match(EF, /"\/mcp":\s*\{\s*server:\s*"nucleo-ia-hub"\s*,\s*version:\s*"2\.79\.0"\s*,\s*tools:\s*311\s*\}/,
    '/health must report 311 (308 after #459, +3 via #209 drive revocation tools)');
});

test('#191: the matrix no longer lists advance_card_curation', () => {
  assert.doesNotMatch(MATRIX_JSON, /advance_card_curation/,
    'mcp-tool-matrix.json must not contain advance_card_curation');
});

test('#191: the canonical p197 RPCs remain wired (reconciliation target intact)', () => {
  // The legacy RPC body is intentionally left in place (0 callers, harmless); the canonical
  // path is the p197 flow which CardDetail drives. Assert the p197 RPCs still exist as MCP/RPC.
  assert.match(EF, /submit_curation_review/, 'submit_curation_review still referenced (p197 canonical)');
});
