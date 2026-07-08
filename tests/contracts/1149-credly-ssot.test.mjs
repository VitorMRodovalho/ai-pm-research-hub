/**
 * Contract: #1149 (Fio 3 da umbrella #1150) — Credly scoring governed by the SSOT.
 *
 * Grounded finding (2026-07-06, re-grounded 2026-07-08): gamification_points (the real XP surface)
 * already matched gamification_rules on points; the real defects were (P1) the CPMAI credential
 * family (v7 / +E / PLUS / PMI-CPMAI = ONE certification; PMI rebranded v7 → PMI-CPMAI 2025-09-30)
 * paying one 45-XP row per badge NAME, and (P2) members.credly_badges (display-only jsonb cache)
 * holding stale classifications (legacy 'master_cert', knowledge_ai_pm@15) for members not re-synced
 * since the classifier changed. (P3) is the structural guard: classify-badge.ts prices from ONE
 * table (CATEGORY_POINTS) that must equal gamification_rules.base_points — no silent drift on the
 * next reprice.
 *
 * Policy (Vitor 2026-07-06): ONE cert_cpmai credit per member; canonical = the PMI-CPMAI-branded
 * badge, else the most recently issued.
 *
 * Migration: supabase/migrations/20260805000378_1149_credly_ssot_dedup.sql
 * Forward fix: supabase/functions/_shared/classify-badge.ts + sync-credly-all + verify-credly.
 * Cross-ref: #1150 umbrella · #1087 · #1032.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import {
  CATEGORY_POINTS,
  classifyBadge,
  selectCanonicalCpmai,
} from '../../supabase/functions/_shared/classify-badge.ts';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── static: P3 — one pricing table, wired into both EFs ────────────────────
test('1149: classifyBadge prices every category from CATEGORY_POINTS (single table)', () => {
  for (const [category, points] of Object.entries(CATEGORY_POINTS)) {
    assert.equal(typeof points, 'number', `${category} priced`);
  }
  // spot-check the classifier flows through the table (not scattered literals)
  const src = readFileSync(resolve(ROOT, 'supabase/functions/_shared/classify-badge.ts'), 'utf8');
  assert.ok(!/return \{ category: '[a-z_]+', points: \d+ \}/.test(src),
    'no inline {category, points} literals — classification must price via CATEGORY_POINTS');
  const cpmai = classifyBadge('PMI Certified Professional in Managing AI (PMI-CPMAI)™', 'pmi-cpmai');
  assert.deepEqual(cpmai, { category: 'cert_cpmai', points: CATEGORY_POINTS.cert_cpmai });
});

test('1149: both credly EFs collapse the CPMAI family via the shared selectCanonicalCpmai', () => {
  for (const ef of ['sync-credly-all', 'verify-credly']) {
    const src = readFileSync(resolve(ROOT, `supabase/functions/${ef}/index.ts`), 'utf8');
    assert.match(src, /selectCanonicalCpmai/, `${ef} imports the shared canonical selection`);
    assert.match(src, /badge\.category === 'cert_cpmai' && badge !== cpmaiCanonical/,
      `${ef} skips superseded family siblings when paying XP`);
    assert.match(src, /\.neq\('reason', `Credly: \$\{cpmaiCanonical\.name\}`\)/,
      `${ef} self-heals previously-paid superseded rows`);
  }
});

test('1149: canonical selection — PMI-CPMAI brand wins, else most recent issue', () => {
  const family = [
    { name: 'Cognitive Project Management in AI (CPMAI)™ v7 Certification', issued_at: '2025-03-19T19:03:00Z' },
    { name: 'Cognitive Project Management in AI (CPMAI)™ +E Certified Professional', issued_at: '2025-03-19T19:03:00Z' },
    { name: 'PMI Certified Professional in Managing AI (PMI-CPMAI)™', issued_at: '2025-09-30T00:00:00Z' },
  ];
  assert.equal(selectCanonicalCpmai(family)?.name, 'PMI Certified Professional in Managing AI (PMI-CPMAI)™');
  // no branded badge → most recent
  const legacyOnly = family.slice(0, 2).concat([
    { name: 'Cognitive Project Management in AI (CPMAI)™ PLUS Certified Professional', issued_at: '2025-06-01T00:00:00Z' },
  ]);
  assert.equal(selectCanonicalCpmai(legacyOnly)?.name,
    'Cognitive Project Management in AI (CPMAI)™ PLUS Certified Professional');
  assert.equal(selectCanonicalCpmai([]), null);
});

// ── DB-gated ────────────────────────────────────────────────────────────────
test('1149 DB: CATEGORY_POINTS matches gamification_rules.base_points for every slug (P3 drift lock)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: rules, error } = await sb
    .from('gamification_rules')
    .select('slug, base_points, active')
    .in('slug', Object.keys(CATEGORY_POINTS));
  assert.ok(!error, error?.message);
  const bySlug = new Map((rules || []).filter((r) => r.active).map((r) => [r.slug, r.base_points]));
  const drift = [];
  for (const [category, points] of Object.entries(CATEGORY_POINTS)) {
    if (!bySlug.has(category)) drift.push(`${category}: no active rule slug`);
    else if (bySlug.get(category) !== points) drift.push(`${category}: code=${points} rule=${bySlug.get(category)}`);
  }
  assert.equal(drift.length, 0, `classify-badge ⟂ gamification_rules drift: ${drift.join(' | ')}`);
});

test('1149 DB: at most ONE Credly cert_cpmai XP row per member (P1 no double-count)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: rows, error } = await sb
    .from('gamification_points')
    .select('member_id, reason')
    .eq('category', 'cert_cpmai')
    .like('reason', 'Credly: %');
  assert.ok(!error, error?.message);
  const perMember = new Map();
  for (const r of rows || []) perMember.set(r.member_id, (perMember.get(r.member_id) || 0) + 1);
  const dups = [...perMember.entries()].filter(([, n]) => n > 1);
  assert.equal(dups.length, 0,
    `members with duplicated CPMAI family credits: ${dups.map(([m, n]) => `${m}(${n})`).join(' | ')}`);
});

test('1149 DB: every credly_badges element maps to an active rule slug at rule points (P2 no stale cache)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: rules, error: er } = await sb.from('gamification_rules').select('slug, base_points, active');
  assert.ok(!er, er?.message);
  const bySlug = new Map((rules || []).filter((r) => r.active).map((r) => [r.slug, r.base_points]));

  const { data: members, error: em } = await sb
    .from('members')
    .select('id, credly_badges')
    .not('credly_badges', 'is', null);
  assert.ok(!em, em?.message);

  const offenders = [];
  for (const m of members || []) {
    for (const b of Array.isArray(m.credly_badges) ? m.credly_badges : []) {
      const cat = b?.category;
      if (!bySlug.has(cat)) offenders.push(`${m.id}: orphan category '${cat}' (${b?.name})`);
      else if (Number(b?.points) !== bySlug.get(cat)) {
        offenders.push(`${m.id}: ${cat} cached@${b?.points} rule@${bySlug.get(cat)} (${b?.name})`);
      }
    }
  }
  assert.equal(offenders.length, 0, `stale display cache: ${offenders.slice(0, 8).join(' | ')}`);
});
