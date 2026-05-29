/**
 * Contract: p277 — "champions da noite" capture (Feature 2).
 *
 * Backend: set_event_champions (focused writer of events.suggested_champion_ids — does NOT close
 * the meeting like meeting_close) + get_event_champion_suggestions gains p_force_derive so the
 * picker always shows the present-member pool. Frontend: a champion picker in the MeetingsPage
 * detail modal, gated to manage_event / champion.award, feeding set_event_champions → the award
 * modal (F3 override) → award_champion. Live smoke: set 2 champions, force-derive still returns 8.
 *
 * Migration: supabase/migrations/20260805000060_p277_set_event_champions_and_force_derive.sql
 * Frontend: src/components/meetings/MeetingsPage.tsx
 * Cross-ref: docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (probe F2) · #424 · meeting_close.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000060_p277_set_event_champions_and_force_derive.sql');
const PAGE = resolve(ROOT, 'src/components/meetings/MeetingsPage.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const page = existsSync(PAGE) ? readFileSync(PAGE, 'utf8') : '';

// ── backend ────────────────────────────────────────────────────────────────
test('p277 F2: set_event_champions — SECDEF, gated, same-org, ≤10, clear-on-empty, anon revoked', () => {
  assert.ok(existsSync(MIG));
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.set_event_champions\(p_event_id uuid, p_champion_ids uuid\[\]\)[\s\S]*?SECURITY DEFINER/i);
  assert.match(mig, /can_by_member\(v_caller_id, 'manage_event'\)[\s\S]*?can_by_member\(v_caller_id, 'award_champion'\)/i, 'gate = manage_event OR award_champion');
  assert.match(mig, /v_event_org != v_caller_org/i, 'same-org guard');
  assert.match(mig, /cardinality\(p_champion_ids\) > 10/i, 'max 10');
  assert.match(mig, /p_champion_ids IS NULL OR cardinality\(p_champion_ids\) = 0[\s\S]*?suggested_champion_ids = NULL/i, 'empty clears the tags');
  assert.match(mig, /REVOKE EXECUTE ON FUNCTION public\.set_event_champions\(uuid, uuid\[\]\) FROM PUBLIC, anon/i);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.set_event_champions\(uuid, uuid\[\]\) TO authenticated, service_role/i);
});

test('p277 F2 forward-defense: set_event_champions does NOT close the meeting (no minutes stamp)', () => {
  const fn = mig.slice(mig.indexOf('FUNCTION public.set_event_champions'));
  assert.ok(!/minutes_posted_at/i.test(fn), 'setting champions must not stamp minutes_posted_at (that is meeting_close)');
});

test('p277 F2: get_event_champion_suggestions gains p_force_derive (skips override when true)', () => {
  assert.match(mig, /DROP FUNCTION IF EXISTS public\.get_event_champion_suggestions\(uuid\)/i);
  assert.match(mig, /get_event_champion_suggestions\(p_event_id uuid, p_force_derive boolean DEFAULT false\)/i);
  assert.match(mig, /IF NOT p_force_derive AND v_suggestions IS NOT NULL/i, 'force-derive skips the override branch');
});

// ── frontend ─────────────────────────────────────────────────────────────────
test('p277 F2 FE: MeetingsPage gates the picker on manage_event / champion.award', () => {
  assert.match(page, /import \{ hasPermission \} from '\.\.\/\.\.\/lib\/permissions'/);
  assert.match(page, /canCurateChampions =[\s\S]*?hasPermission\(member, 'manage_event'\)[\s\S]*?hasPermission\(member, 'champion\.award'\)/i);
  assert.match(page, /\{canCurateChampions && selectedEventId && \(\s*<ChampionPicker/i, 'picker only rendered when permitted + an event is open');
});

test('p277 F2 FE: ChampionPicker calls force-derived suggestions + set_event_champions', () => {
  const cp = page.slice(page.indexOf('function ChampionPicker'), page.indexOf('export default function MeetingsPage'));
  assert.ok(cp, 'ChampionPicker component must exist before the page');
  assert.match(cp, /get_event_champion_suggestions[\s\S]*?p_force_derive: true/i, 'loads the full present-member pool');
  assert.match(cp, /set_event_champions[\s\S]*?p_champion_ids: Array\.from\(selected\)/i, 'persists the selected champions');
});

test('p277 F2 FE: champions labels present in all 3 languages', () => {
  const occ = (page.match(/championsTitle:/g) || []).length;
  assert.ok(occ >= 3, `championsTitle must exist in pt-BR + en-US + es-LATAM; found ${occ}`);
});

// ── DB-gated ─────────────────────────────────────────────────────────────────
test('p277 F2 DB: set_event_champions denies without auth', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('set_event_champions', { p_event_id: '00000000-0000-0000-0000-000000000000', p_champion_ids: [] });
  assert.ok(error, 'no-auth caller must be rejected');
});
