/**
 * Contract: #191 — reconcile the legacy curation API with the p197 structured flow.
 *
 * Two legacy surfaces shadowed the canonical p197 flow:
 *   1. MCP tool `advance_card_curation` — advertised assign/approve/reject/request_changes
 *      but wrapped advance_board_item_curation, which only accepts request_review/approve_peer/
 *      approve_leader. 0 lifetime uses. REMOVED (tool count 304 → 303).
 *   2. `TribeKanbanIsland.tsx` — imported by tribe/[id].astro but NEVER JSX-mounted (the live
 *      board island is BoardEngine). DELETED.
 *
 * The canonical curation API is the p197 flow (complete_peer_review / complete_leader_review /
 * submit_for_curation / submit_curation_review), covered by 194-p197-review-flow-contracts.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const EF = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');
const TRIBE_PAGE = readFileSync(resolve(ROOT, 'src/pages/tribe/[id].astro'), 'utf8');
const MATRIX_JSON = readFileSync(resolve(ROOT, 'docs/reference/mcp-tool-matrix.json'), 'utf8');

test('#191: the broken advance_card_curation MCP tool is removed', () => {
  assert.doesNotMatch(EF, /mcp\.tool\(\s*"advance_card_curation"/,
    'advance_card_curation tool must be removed from the MCP catalog');
  assert.match(EF, /advance_card_curation MCP tool REMOVED/,
    'a removal-trace comment documents why');
});

test('#191: /health declares the corrected /mcp tool count (303)', () => {
  assert.match(EF, /"\/mcp":\s*\{\s*server:\s*"nucleo-ia-hub"\s*,\s*version:\s*"2\.79\.0"\s*,\s*tools:\s*303\s*\}/,
    '/health must report 303 (was 304 before the advance_card_curation removal)');
});

test('#191: the matrix no longer lists advance_card_curation', () => {
  assert.doesNotMatch(MATRIX_JSON, /advance_card_curation/,
    'mcp-tool-matrix.json must not contain advance_card_curation');
});

test('#191: orphan TribeKanbanIsland is deleted + un-imported', () => {
  assert.ok(!existsSync(resolve(ROOT, 'src/components/boards/TribeKanbanIsland.tsx')),
    'TribeKanbanIsland.tsx must be deleted (was never JSX-mounted)');
  assert.doesNotMatch(TRIBE_PAGE, /import\s+TribeKanbanIsland/,
    'tribe/[id].astro must not import TribeKanbanIsland');
  assert.doesNotMatch(TRIBE_PAGE, /<TribeKanbanIsland/,
    'tribe/[id].astro must not mount TribeKanbanIsland');
});

test('#191: the canonical p197 RPCs remain wired (reconciliation target intact)', () => {
  // The legacy RPC body is intentionally left in place (0 callers, harmless); the canonical
  // path is the p197 flow which CardDetail drives. Assert the p197 RPCs still exist as MCP/RPC.
  assert.match(EF, /submit_curation_review/, 'submit_curation_review still referenced (p197 canonical)');
});
