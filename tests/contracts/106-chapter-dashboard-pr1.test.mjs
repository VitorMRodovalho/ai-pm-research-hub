/**
 * Contract: #106 PR1 — chapter dashboard: cycle bug fix + by_tribe + movements 30d + CSV.
 *
 * The chapter dashboard (get_chapter_dashboard, /admin/chapter, ChapterDashboard.tsx) already
 * existed with own-chapter access. PR1 adds, per SPEC_106_CHAPTER_DASHBOARD.md (council + legal):
 *  - bug fix: cycle derived from cycles.is_current (was hardcoded 'cycle', 3 in BOTH RPC and FE dict)
 *  - Bloco 1: people.by_tribe with '__none__' bucket (sum == active)
 *  - Bloco 2: movements 30d — LGPD-minimized (category only, neutralized, no free text, no anonymized)
 *  - Bloco 5: CSV export (FE-only) + PostHog instrumentation
 *  - 2 composite indexes
 *
 * Offline source assertions; no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG = read('supabase/migrations/20260805000213_106_pr1_chapter_dashboard_movements.sql');
const FE = read('src/components/chapter/ChapterDashboard.tsx');

// ── Migration exists & is registered ────────────────────────────────────────────
test('migration 20260805000213 exists', () => {
  assert.ok(MIG, 'PR1 migration file exists');
});

// ── Bug fix: cycle derived, not hardcoded ───────────────────────────────────────
test('RPC: cycle derived from cycles.is_current (no hardcoded "cycle", 3)', () => {
  // code form is `'cycle', 3,` (trailing comma); the comment mention `'cycle', 3).` must not trip this
  assert.ok(!/'cycle',\s*3,/.test(MIG), 'no hardcoded cycle 3 in the RPC body');
  assert.match(MIG, /SELECT cycle_code, cycle_label INTO v_current_cycle/);
  assert.match(MIG, /'cycle_label', v_current_cycle\.cycle_label/);
});

test('FE: header uses data.cycle_label, dict no longer hardcodes "Ciclo 3"/"Cycle 3"', () => {
  assert.match(FE, /data\.cycle_label \|\| t\.cycle/);
  assert.ok(!/cycle: 'Ciclo 3'/.test(FE), 'pt dict no hardcoded Ciclo 3');
  assert.ok(!/cycle: 'Cycle 3'/.test(FE), 'en dict no hardcoded Cycle 3');
});

// ── Bloco 1: by_tribe with sem-tribo bucket ─────────────────────────────────────
test('RPC: people.by_tribe with __none__ bucket', () => {
  assert.match(MIG, /'by_tribe'/);
  assert.match(MIG, /COALESCE\(tname, '__none__'\)/);
  assert.match(MIG, /LEFT JOIN public\.tribes tr ON tr\.id = m2\.tribe_id/);
});

test('FE: renders by_tribe with Sem-tribo mapping', () => {
  assert.match(FE, /by_tribe/);
  assert.match(FE, /__none__'\s*\?\s*t\.noTribe/);
});

// ── Bloco 2: movements 30d — LGPD minimization (the legal blocker) ───────────────
test('RPC: movements projects ONLY name/date/neutralized-category/return_interest', () => {
  assert.match(MIG, /'movements'/);
  assert.match(MIG, /'joined_30d'/);
  assert.match(MIG, /'left_30d'/);
  // neutralization of sensitive categories (legal C2)
  assert.match(MIG, /CASE WHEN r\.reason_category_code IN \('health','policy_violation'\) THEN 'other'/);
  // exclude anonymized members (legal / Art. 18 IV)
  assert.match(MIG, /m\.anonymized_at IS NULL/);
});

test('RPC: movements does NOT project free-text exit-interview columns (LGPD)', () => {
  // the free-text offboarding columns must never be PROJECTED (r.<col>) into the chapter block.
  // (bare mentions appear in the LGPD comment listing what is excluded — that is expected.)
  assert.ok(!/r\.reason_detail/.test(MIG), 'no r.reason_detail projection');
  assert.ok(!/r\.exit_interview_full_text/.test(MIG), 'no r.exit_interview_full_text projection');
  assert.ok(!/r\.lessons_learned/.test(MIG), 'no r.lessons_learned projection');
  assert.ok(!/r\.recommendation_for_future/.test(MIG), 'no r.recommendation_for_future projection');
  assert.ok(!/r\.attachment_urls/.test(MIG), 'no r.attachment_urls projection');
});

test('RPC: LGPD base-legal comment present (legal C1)', () => {
  assert.match(MIG, /Art\. 7, IX/);
  assert.match(MIG, /Minimiza/i);
});

test('FE: movements block renders entries + exits as card-list with reason badge', () => {
  assert.match(FE, /mvEntries/);
  assert.match(FE, /mvExits/);
  assert.match(FE, /reasonLabel\(e\.reason_code\)/);
  // neutralized codes only — FE must not contain health/policy_violation labels
  assert.ok(!/policy_violation:/.test(FE), 'FE reason map omits policy_violation');
  assert.ok(!/\bhealth:/.test(FE), 'FE reason map omits health');
});

// ── Bloco 5: CSV export + instrumentation ───────────────────────────────────────
test('FE: CSV export (FE-only, no new rpc) + tracking events', () => {
  assert.match(FE, /exportCsv/);
  assert.match(FE, /text\/csv/);
  assert.match(FE, /__nucleoTrack\?\.\('chapter_csv_exported'/);
  assert.match(FE, /__nucleoTrack\?\.\('chapter_dashboard_viewed'/);
  // CSV is FE-only — no new RPC call introduced for it
  assert.ok(!/rpc\(['"]export_chapter/.test(FE), 'no export RPC');
});

// ── Indexes (data-architect) ────────────────────────────────────────────────────
test('migration adds the two composite indexes', () => {
  assert.match(MIG, /idx_offboarding_chapter_at[\s\S]*chapter_at_offboard, offboarded_at DESC/);
  assert.match(MIG, /idx_members_chapter_created_at[\s\S]*chapter, created_at DESC/);
});

// ── Migration registered in CLI history (Q-C orphan-capture) ────────────────────
test('migration file is the canonical capture (one timestamped file)', () => {
  const files = readdirSync(resolve(ROOT, 'supabase/migrations'))
    .filter((f) => f.includes('106_pr1_chapter_dashboard'));
  assert.equal(files.length, 1, 'exactly one PR1 migration file');
});
