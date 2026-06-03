/**
 * Contract: #246 — /attendance grid must refresh live during meetings.
 *
 * Root cause (grounded 2026-06-03): `public.attendance` was never added to the
 * `supabase_realtime` publication, so Postgres emitted no change events for it and any
 * `postgres_changes` subscription was silent. The grid (AttendanceGridTab) also had no
 * subscription, and its optimistic patch keyed on `m.member_id` (the RPC emits `id`, so
 * that field was undefined → the patch was a silent no-op).
 *
 * Fix:
 *  - migration 20260805000099: ADD TABLE public.attendance to supabase_realtime + REPLICA IDENTITY FULL.
 *  - AttendanceGridTab: subscribe to postgres_changes on attendance (with cleanup), patch keyed on m.id.
 *
 * Static-only contract: the DB membership/replica-identity were verified live at ship time
 * (attendance_in_publication=true, replica_identity=full); pg_publication_tables is a system
 * catalog not reachable via the PostgREST client, so the migration file + grid wiring are the
 * testable contract here.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000099_246_attendance_realtime_publication.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const GRID = resolve(ROOT, 'src/components/attendance/AttendanceGridTab.tsx');
const gridRaw = existsSync(GRID) ? readFileSync(GRID, 'utf8') : '';

test('#246 static: migration 099 publishes attendance + sets REPLICA IDENTITY FULL', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000099 exists');
  assert.match(migRaw, /ALTER PUBLICATION supabase_realtime ADD TABLE public\.attendance/i,
    'adds attendance to the supabase_realtime publication');
  assert.match(migRaw, /ALTER TABLE public\.attendance REPLICA IDENTITY FULL/i,
    'sets REPLICA IDENTITY FULL so UPDATE/DELETE payloads carry event_id + member_id');
});

test('#246 static: grid subscribes to postgres_changes on attendance and cleans up', () => {
  assert.match(gridRaw, /'postgres_changes'/, 'grid uses a postgres_changes subscription');
  assert.match(gridRaw, /table:\s*'attendance'/, 'subscription targets the attendance table');
  assert.match(gridRaw, /\.subscribe\(\)/, 'channel is subscribed');
  assert.match(gridRaw, /removeChannel\(/, 'channel is removed on unmount (no leak)');
});

test('#246 static: optimistic patch keys on m.id, never the undefined m.member_id', () => {
  // get_attendance_grid emits members as {id, ...} — m.member_id was a silent no-op.
  assert.doesNotMatch(gridRaw, /m\.member_id\s*===\s*memberId/,
    'the optimistic/realtime patch must key on m.id (RPC emits id), not the undefined m.member_id');
  assert.match(gridRaw, /m\.id === memberId/, 'patch keys on m.id');
});
