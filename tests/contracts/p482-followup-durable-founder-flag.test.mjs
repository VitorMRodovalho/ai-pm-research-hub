/**
 * Contract: #482 follow-up — durable members.is_founder for the public "Fundadores" wall.
 *
 * #482 keyed the wall off the 'founder' DESIGNATION, but invariant C clears designations on
 * terminal status — so an alumni founder/pilot participant dropped out entirely and the muting
 * never fired. Migration 20260805000095 adds a durable is_founder boolean (survives offboarding),
 * seeds it from the 2024-pilot cohort (cycles @> {pilot-2024}) + any 'founder'-designated member,
 * and exposes it on public_members. TeamSection re-sources off is_founder and mutes by member_status.
 *
 * Behavioural checks assert the seeding RELATIONSHIPS (pilot-tagged ⇒ is_founder; founder-designated ⇒
 * is_founder) rather than hardcoding the 8 names, so the contract survives roster growth.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000095_p482_followup_durable_founder_flag.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#482-followup static: migration exists + adds durable is_founder', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000095 exists');
  assert.match(migRaw, /ADD COLUMN IF NOT EXISTS is_founder boolean NOT NULL DEFAULT false/, 'adds is_founder');
  assert.match(migRaw, /cycles && ARRAY\['pilot-2024'\]::text\[\]/, 'seeds from the durable pilot-2024 cycles tag');
  assert.match(migRaw, /CREATE OR REPLACE VIEW public\.public_members[\s\S]*is_founder[\s\S]*FROM public\.members/, 'public_members exposes is_founder');
});

// ── BEHAVIOURAL (DB-gated) ────────────────────────────────────────────────────────
test('#482-followup behavioural: public_members exposes is_founder', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const { data, error } = await sb.from('public_members').select('name, is_founder, member_status').eq('is_founder', true).limit(50);
  assert.ifError(error);
  assert.ok(Array.isArray(data), 'returns rows');
  assert.ok(data.length >= 8, `expected >= 8 founders flagged, got ${data.length}`);
});

test('#482-followup behavioural: every pilot-2024 member is is_founder', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const { data, error } = await sb.from('public_members').select('name, cycles, is_founder');
  assert.ifError(error);
  const pilot = (data || []).filter(m => Array.isArray(m.cycles) && m.cycles.includes('pilot-2024'));
  assert.ok(pilot.length >= 8, `expected >= 8 pilot-2024 members, got ${pilot.length}`);
  for (const m of pilot) assert.equal(m.is_founder, true, `pilot-2024 member ${m.name} must be is_founder`);
});

test('#482-followup behavioural: every founder-designated member is is_founder', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const { data, error } = await sb.from('public_members').select('name, designations, is_founder');
  assert.ifError(error);
  const designated = (data || []).filter(m => Array.isArray(m.designations) && m.designations.includes('founder'));
  for (const m of designated) assert.equal(m.is_founder, true, `founder-designated ${m.name} must be is_founder`);
});
