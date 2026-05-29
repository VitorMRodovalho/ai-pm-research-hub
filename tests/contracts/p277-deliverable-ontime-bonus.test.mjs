/**
 * Contract: p277 — deliverable/artifact/action on-time BONUS + trigger wiring
 * (gamification rule-wiring probe; PM-chosen policy = on-time bonus).
 *
 * The auto_trigger XP rules existed but had NO on-time semantics and were dormant (1 award row
 * ever; triggers fired only AFTER UPDATE OF <col>, missing insert-already-final + pre-effective_from
 * rows). This migration adds the PM's on-time BONUS (base always; +bonus when on time; NO late
 * penalty), gives the triggers INSERT coverage + an assignee fallback, and backfills the orphans.
 *
 * Live smoke verified (transactional, rolled back): deliverable completed on-time = 40 (30+10),
 * late = 30 (base, no penalty), INSERT-already-completed with no due_date = 30 (base).
 *
 * Migration: supabase/migrations/20260805000058_p277_deliverable_ontime_bonus_and_wiring.sql
 * Cross-ref: docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (rule-wiring probe F1/F2/F3) · ADR-0009 (config-driven).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000058_p277_deliverable_ontime_bonus_and_wiring.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

// ── static ────────────────────────────────────────────────────────────────
test('p277 F1: migration exists + config/audit columns + NOTIFY', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /ALTER TABLE public\.gamification_rules ADD COLUMN IF NOT EXISTS on_time_bonus_points integer/i);
  assert.match(body, /ALTER TABLE public\.tribe_deliverables\s+ADD COLUMN IF NOT EXISTS completed_at timestamptz/i);
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('p277 F1: on-time bonus is config-driven (deliverable +10, action +2)', () => {
  assert.match(body, /UPDATE public\.gamification_rules SET on_time_bonus_points = 10 WHERE slug = 'deliverable_completed'/i);
  assert.match(body, /UPDATE public\.gamification_rules SET on_time_bonus_points = 2\s+WHERE slug = 'action_resolved'/i);
});

test('p277 F1: _grant_auto_xp gains p_on_time + awards base + bonus only when on-time', () => {
  assert.match(body, /DROP FUNCTION IF EXISTS public\._grant_auto_xp\(text, uuid, uuid, text\)/i, 'old 4-arg dropped so 4-arg calls fall through to the new default-param version');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._grant_auto_xp\([^)]*p_on_time boolean DEFAULT NULL\)/is, 'new signature with p_on_time DEFAULT NULL');
  assert.match(body, /IF p_on_time IS TRUE AND COALESCE\(v_rule\.on_time_bonus_points, 0\) > 0 THEN[\s\S]*?v_points := v_points \+ v_rule\.on_time_bonus_points/i, 'bonus added only when on-time + configured');
  assert.match(body, /WHERE ref_id = p_ref_id AND category = p_slug AND member_id = p_recipient_id/i, 'idempotency preserved');
});

test('p277 F1 forward-defense: NO late penalty (bonus is additive only)', () => {
  // there must be no points-subtraction / late-reduction anywhere
  assert.ok(!/v_points\s*:=\s*v_points\s*-/.test(body), 'must not subtract points');
  assert.ok(!/late|penalt|atras/i.test(body.replace(/--[^\n]*/g, '')) || /no penalty|sem penalidade|NO late penalty/i.test(body), 'on-time policy is bonus-only, never a late penalty');
});

test('p277 F1: triggers cover INSERT OR UPDATE (not just UPDATE)', () => {
  assert.match(body, /AFTER INSERT OR UPDATE OF status ON public\.tribe_deliverables/i);
  assert.match(body, /AFTER INSERT OR UPDATE OF is_published ON public\.meeting_artifacts/i);
  assert.match(body, /AFTER INSERT OR UPDATE OF resolved_at ON public\.meeting_action_items/i);
  // function bodies handle the INSERT case (OLD is NULL on INSERT)
  assert.ok((body.match(/TG_OP = 'INSERT'/g) || []).length >= 3, 'each trigger fn handles TG_OP=INSERT');
});

test('p277 F1: deliverable on-time = due_date vs completion; action falls back assignee→resolved_by→created_by', () => {
  assert.match(body, /CASE WHEN NEW\.due_date IS NULL THEN NULL ELSE \(CURRENT_DATE <= NEW\.due_date\) END/i, 'deliverable on-time = CURRENT_DATE <= due_date');
  assert.match(body, /NEW\.resolved_at::date <= NEW\.due_date/i, 'action on-time = resolved_at <= due_date');
  assert.match(body, /COALESCE\(NEW\.assignee_id, NEW\.resolved_by, NEW\.created_by\)/i, 'action recipient fallback');
});

test('p277 F1: artifact award is base-only (no due_date → no bonus)', () => {
  // the artifact PERFORM passes only 4 args (no p_on_time) → base only
  assert.match(body, /'artifact_published',\s*NEW\.created_by,\s*NEW\.id,\s*\n?\s*'Ata rica publicada[^\n]*'\s*\n?\s*\)/i, 'artifact award omits the on-time arg');
});

test('p277 F1: idempotent backfill block present (base-only)', () => {
  assert.match(body, /DO \$backfill\$/i);
  assert.match(body, /backfill p277/i);
  assert.match(body, /is_published = true AND created_by IS NOT NULL/i, 'backfills published artifacts');
  assert.match(body, /status = 'completed' AND assigned_member_id IS NOT NULL/i, 'backfills completed deliverables');
});

// ── DB-gated ────────────────────────────────────────────────────────────────
test('p277 F1 DB: bonus config live (deliverable=10, action=2, artifact=NULL)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('gamification_rules')
    .select('slug,on_time_bonus_points')
    .in('slug', ['deliverable_completed', 'action_resolved', 'artifact_published']);
  assert.ok(!error, error?.message);
  const m = Object.fromEntries((data || []).map((r) => [r.slug, r.on_time_bonus_points]));
  assert.equal(m.deliverable_completed, 10);
  assert.equal(m.action_resolved, 2);
  assert.equal(m.artifact_published, null, 'artifacts have no deadline → no bonus');
});

test('p277 F1 DB: dormant award lit up — backfill paid the orphans', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { count: artifacts } = await sb.from('gamification_points').select('id', { count: 'exact', head: true }).eq('category', 'artifact_published');
  assert.ok((artifacts || 0) >= 12, `artifact_published awards should be backfilled (>=12), got ${artifacts}`);
});
