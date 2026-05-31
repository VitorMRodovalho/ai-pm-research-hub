/**
 * Contract: p277 / #420 — Board Kanban + drag overlay display the multi-role "Participantes"
 * (board_item_assignments) instead of only the legacy single assignee_name (= card author).
 *
 * Root cause (see #440): the platform has TWO un-synced assignee models — board_items.assignee_id
 * (single "Responsável", defaults to the creator in create_board_item) vs board_item_assignments
 * (multi-role junction "Participantes", where the chosen people actually live). TableView +
 * GroupedListView already prefer assignments[]; the Kanban card (BoardKanban.tsx) and the drag
 * overlay (islands/BoardEngine.tsx) rendered only assignee_name (= author), so the board showed the
 * author instead of the chosen members. This is the SAFE display slice — it does NOT decide the
 * canonical model (that remains #440); it just makes the Kanban surface consistent with the others.
 *
 * Forward-defense: lock the assignments-preference so a future "simplification" can't regress the
 * Kanban/overlay back to bare assignee_name.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const kanban = read('src/components/board/BoardKanban.tsx');
const overlay = read('src/components/islands/BoardEngine.tsx');
const table = read('src/components/board/TableView.tsx');
const grouped = read('src/components/board/GroupedListView.tsx');

test('#420: Kanban card prefers assignments[] (Participantes) over legacy assignee_name', () => {
  assert.ok(kanban, 'BoardKanban.tsx exists');
  // the assignments-preference expression must be present
  assert.match(kanban, /item\.assignments\?\.length\s*\?\s*item\.assignments\.map\(\(?a\)?\s*=>\s*a\.name\)\.join/);
  // and it must NOT render a bare 👤 {item.assignee_name} with no assignments check
  assert.ok(!/👤 \{item\.assignee_name\}/.test(kanban),
    'Kanban must not render bare assignee_name without the assignments preference');
});

test('#420: drag overlay (BoardEngine island) prefers assignments[] over legacy assignee_name', () => {
  assert.ok(overlay, 'islands/BoardEngine.tsx exists');
  assert.match(overlay, /activeItem\.assignments\?\.length\s*\?\s*activeItem\.assignments\.map\(\(?a\)?\s*=>\s*a\.name\)\.join/);
  assert.ok(!/👤 \{activeItem\.assignee_name\}/.test(overlay),
    'drag overlay must not render bare activeItem.assignee_name without the assignments preference');
});

test('#420: TableView + GroupedListView already use the same canonical assignments-preference (consistency)', () => {
  // documents that the Kanban fix aligns with the views that were already correct
  assert.match(table, /item\.assignments\?\.length/, 'TableView prefers assignments');
  assert.match(grouped, /assignments\?\.length/, 'GroupedListView prefers assignments');
});
