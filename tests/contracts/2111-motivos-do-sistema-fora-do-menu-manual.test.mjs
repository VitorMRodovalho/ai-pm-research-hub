// tests/contracts/2111-motivos-do-sistema-fora-do-menu-manual.test.mjs
// Hermetic: reads the migrations, the members island and the latest capture of admin_offboard_member; comments are
// masked before matching.
/**
 * O8 (Refs #2111). The offboard reason menu of /admin/members reads offboard_reason_categories (#2966) and offered
 * every active code, including reacceptance_refusal and reacceptance_lapse, which only the Term re-acceptance flow
 * records (#976). Decision of the GP (03/11/2026): mark them in the catalog with a "system only" column, and have the
 * menu filter by it, with no fixed list in the screen. The menu filter itself is arm A of
 * 2111-motivo-do-desligamento-lido-do-catalogo (the whole read chain, anchored).
 *
 *   A  exactly one migration adds is_system_only to offboard_reason_categories, boolean NOT NULL DEFAULT false;
 *   B  that migration marks exactly the two re-acceptance codes, in one UPDATE whose row count is checked to be 2
 *      inside the same block, and nothing else sets the column;
 *   C  the island has no literal of the two codes: the menu leaves them out by the catalog, not by a fixed list;
 *   D  admin_offboard_member does not read the column: the VEP reconciliation screen calls it with
 *      reacceptance_refusal on purpose (#1445), so the column must not turn into a refusal in the RPC.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments, maskLineComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const ISLAND = maskJsComments(read('src/components/admin/members/MemberListIsland.tsx'));
const CODES = ['reacceptance_refusal', 'reacceptance_lapse'];

const migrations = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => [f, maskLineComments(readFileSync(resolve(MIG_DIR, f), 'utf8'))]);
const adders = migrations.filter(([, sql]) => /\bADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?is_system_only\b/i.test(sql));

function theMigration() {
  assert.equal(adders.length, 1,
    `expected exactly one migration adding is_system_only, found: ${JSON.stringify(adders.map(([f]) => f))}`);
  return adders[0][1];
}

test('A: one migration adds is_system_only to the catalog, boolean NOT NULL DEFAULT false', () => {
  const sql = theMigration();
  assert.match(sql,
    /ALTER TABLE public\.offboard_reason_categories\s+ADD COLUMN is_system_only boolean NOT NULL DEFAULT false;/,
    'the column is not added to offboard_reason_categories as boolean NOT NULL DEFAULT false');
});

test('B: the migration marks exactly the two re-acceptance codes, and checks it marked 2', () => {
  const sql = theMigration();
  const block = sql.match(/DO \$\$[\s\S]*?END \$\$;/g)?.find((b) => /is_system_only/.test(b));
  assert.ok(block, 'no DO block sets is_system_only');
  assert.match(block,
    /UPDATE public\.offboard_reason_categories\s+SET is_system_only = true\s+WHERE code IN \('reacceptance_refusal', 'reacceptance_lapse'\);\s*GET DIAGNOSTICS v_n = ROW_COUNT;\s*IF v_n <> 2 THEN\s*RAISE EXCEPTION/,
    'the UPDATE does not mark exactly the two re-acceptance codes with a row count check of 2');
  const setters = migrations.flatMap(([f, s]) =>
    [...s.matchAll(/SET\s+is_system_only\s*=/gi)].map(() => f));
  assert.equal(setters.length, 1, `is_system_only is set in more than one place: ${JSON.stringify(setters)}`);
});

test('C: the island leaves the system codes out by the catalog, with no literal of them', () => {
  const found = CODES.filter((c) => ISLAND.includes(c));
  assert.deepEqual(found, [], `the island names system-only codes: ${JSON.stringify(found)}`);
});

test('D: admin_offboard_member does not read is_system_only (the VEP reconciliation path sends a system code)', () => {
  const { body } = latestFunctionCapture(ROOT, 'admin_offboard_member');
  assert.doesNotMatch(maskLineComments(body), /is_system_only/,
    'admin_offboard_member reads is_system_only; the VEP reconciliation screen calls it with reacceptance_refusal');
  // Control: the capture read is the right function (it validates the category against the catalog).
  assert.match(body, /SELECT code INTO v_reason_code FROM public\.offboard_reason_categories WHERE code = p_reason_category/,
    'control: the capture read is not the admin_offboard_member that validates the category');
});
