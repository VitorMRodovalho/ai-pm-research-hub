/**
 * Contract: #187 — curation reviewer picker uses V4 curate_content, not the V3
 * `designations.includes('curator')` filter.
 *
 * PREMISE CORRECTION (live-verified): the picker was NOT empty — CardDetail fetches
 * members via get_board_members(), whose RETURNS TABLE already includes designations.
 * The real issue was the V3 filter. Fix: get_board_members now also returns a
 * canonical V4 `can_curate boolean` (can_by_member(_,'curate_content')) and
 * MemberPickerMulti filters curation_reviewer candidates by m.can_curate.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000116_187_get_board_members_can_curate.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const PICKER = readFileSync(resolve(ROOT, 'src/components/board/MemberPickerMulti.tsx'), 'utf8');
const TYPES = readFileSync(resolve(ROOT, 'src/types/board.ts'), 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#187 static: migration 116 DROP+CREATEs get_board_members with a can_curate column', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000116 exists');
  assert.match(migRaw, /DROP FUNCTION IF EXISTS public\.get_board_members\(uuid\)/, 'DROP (return-shape change)');
  assert.match(migRaw, /RETURNS TABLE\([\s\S]*?can_curate boolean\)/, 'RETURNS TABLE gains can_curate');
  assert.match(migRaw, /public\.can_by_member\(q\.id, 'curate_content'\) AS can_curate/, 'computed via can_by_member');
  assert.match(migRaw, /GRANT EXECUTE ON FUNCTION public\.get_board_members\(uuid\) TO authenticated/, 're-grants execute');
});

test('#187 static: migration adds no PII (rpc-acl invariant preserved)', () => {
  // the only member-derived columns are name + photo_url + designations + can_curate
  assert.doesNotMatch(migRaw, /m\.email|m\.phone|\.pmi_id/, 'no email/phone/pmi_id selected');
});

test('#187 static: MemberPickerMulti filters curation_reviewer by V4 can_curate', () => {
  assert.match(PICKER, /m\.can_curate === true/, 'picker uses can_curate');
  assert.doesNotMatch(PICKER, /selectedRole === 'curation_reviewer'\)?\s*\{?\s*return m\.designations\?\.includes\('curator'\)/,
    'picker no longer uses the V3 designation filter for the reviewer role');
  // the legacy designation include must be gone from BOTH filter sites
  assert.doesNotMatch(PICKER, /m\.designations\?\.includes\('curator'\)/, 'no residual designation-includes-curator filter');
});

test('#187 static: BoardMember type carries can_curate', () => {
  assert.match(TYPES, /can_curate\?: boolean/, 'BoardMember.can_curate declared');
});

// ── DB-GATED ──────────────────────────────────────────────────────────────────────
test('#187 db: get_board_members returns a can_curate boolean that matches can_by_member(curate_content)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data: board } = await sb.from('project_boards').select('id').eq('is_active', true).limit(1).single();
    assert.ok(board?.id, 'have an active board');
    const { data: rows, error } = await sb.rpc('get_board_members', { p_board_id: board.id });
    assert.ifError(error);
    assert.ok(Array.isArray(rows) && rows.length > 0, 'board has members');
    assert.ok('can_curate' in rows[0], 'rows expose can_curate');
    // can_curate must equal the canonical V4 authority for every row
    for (const r of rows.slice(0, 12)) {
      const { data: canV4, error: e2 } = await sb.rpc('can_by_member', { p_member_id: r.id, p_action: 'curate_content' });
      assert.ifError(e2);
      assert.equal(r.can_curate, canV4 === true,
        `can_curate must equal can_by_member(curate_content) for ${r.name}`);
    }
  });
