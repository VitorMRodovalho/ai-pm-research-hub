/**
 * Contract: #1148 (Fio 2 da umbrella #1150) — historical curation XP backfill + no-silent-backlog guard.
 *
 * The four curation triggers (curation_doc_locked / _doc_published / _comment_resolved / _ratification)
 * fire correctly forward but were attached after the data existed, so a historical backlog earned no XP
 * (audit 2026-07-06: 113 unpaid eligible events / 5 members / 2010 XP). The migration replays each
 * pre-effective_from source row through the shared _grant_auto_xp core (idempotent). The one documented
 * exception is the 2026-05-25 02:11:33.748952 batch seed (1 doc-lock + 7 member_ratification, single
 * signer, single instant = replica-mode bulk) — excluded by decision (2026-07-06); allowlisted below.
 *
 * Migration: supabase/migrations/20260805000377_1148_curation_xp_backfill.sql
 * Cross-ref: handoff_2026_07_06_gamif_attribution_audit · #1150 umbrella · #1087 · #1032.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000377_1148_curation_xp_backfill.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

// The four curation rules and the source column each trigger reads (must match the live trigger bodies).
const SOURCES = [
  { cat: 'curation_doc_locked',       table: 'document_versions', recipient: 'locked_by',    event: 'locked_at' },
  { cat: 'curation_doc_published',    table: 'document_versions', recipient: 'published_by', event: 'published_at' },
  { cat: 'curation_comment_resolved', table: 'document_comments', recipient: 'resolved_by',  event: 'resolved_at' },
  { cat: 'curation_ratification',     table: 'approval_signoffs', recipient: 'signer_id',    event: 'created_at' },
];

// Documented technical batch seed (session_replication_role=replica bulk): excluded from backfill by
// decision. A miss at this exact instant is expected; a miss anywhere else is NEW backlog → fail.
const SEED_INSTANT_MS = new Date('2026-05-25T02:11:33.748952+00:00').getTime();

// ── static ────────────────────────────────────────────────────────────────
test('1148: migration exists + backfill-only (no new/dropped trigger) + NOTIFY', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(body, /NOTIFY\s+pgrst/i);
  assert.ok(!/CREATE\s+TRIGGER/i.test(body), 'backfill-only: creates no trigger');
  assert.ok(!/DROP\s+TRIGGER/i.test(body), 'backfill-only: retires no trigger');
});

test('1148: backfills all four curation categories via the shared _grant_auto_xp core', () => {
  for (const s of SOURCES) {
    const re = new RegExp(`_grant_auto_xp\\(\\s*\\n?\\s*'${s.cat}'`, 'i');
    assert.match(body, re, `awards ${s.cat} via _grant_auto_xp`);
  }
});

test('1148: scope = pre-effective_from (SSOT cutoff, no hardcoded date) → excludes the seed', () => {
  assert.match(body, /<\s*gr\.effective_from/i, 'cutoff reads effective_from from gamification_rules');
  assert.match(body, /JOIN\s+public\.gamification_rules/i, 'joins the SSOT rules table for the cutoff');
  // the cutoff must be a derived comparison against effective_from, never a hardcoded date in a WHERE/JOIN
  assert.ok(!/(WHERE|AND)[^\n]*<\s*'20\d\d-\d\d-\d\d/i.test(body), 'cutoff is derived, not a hardcoded date literal');
});

test('1148: curation is base-only (no on-time bonus, no point subtraction)', () => {
  // every _grant_auto_xp call passes NULL for p_on_time (curation rules have no on_time bonus)
  assert.ok(!/v_points\s*:=\s*v_points\s*-/.test(body), 'must never subtract points');
  assert.match(body, /on-time N\/A|on-time.*N\/A|base-only/i, 'documents base-only intent');
});

test('1148: backfill grants are traceable (reason marker) + idempotent by construction', () => {
  assert.match(body, /backfill #1148/i, 'reason marks the backfill for the extrato');
  assert.match(body, /DO \$backfill\$/i, 'single idempotent DO-block pass');
});

// The migration ships after the C3→C4 boundary (C4 is_current since 2026-07-09) and cycle
// leaderboards bucket gamification_points by created_at — the historical backlog must land in C3
// (same pinned instant as the #1147 backfill), never in the freshly-zeroed C4 board.
const C3_PIN = '2026-07-08 12:00:00+00';

test('1148: backfilled rows are pinned inside the C3 window (no C4 leaderboard leak)', () => {
  assert.match(body, /UPDATE public\.gamification_points/i, 'has the created_at pin pass');
  assert.ok(body.includes(C3_PIN), `pins created_at to ${C3_PIN} (C3 ended 2026-07-08, C4 starts 2026-07-09)`);
  assert.match(body, /reason LIKE '%\(backfill #1148\)%'/, "pin targets only this backfill's rows");
});

// ── DB-gated: reconciliation guard-rail ─────────────────────────────────────
test('1148 DB: every eligible curation event is paid, except the documented seed', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // valid members (recipient must resolve to a member — _grant_auto_xp skips otherwise; not a backlog)
  const { data: members, error: em } = await sb.from('members').select('id');
  assert.ok(!em, em?.message);
  const memberIds = new Set((members || []).map((m) => m.id));

  const offenders = [];
  for (const s of SOURCES) {
    // eligible source rows: recipient present + event present
    const { data: rows, error: e1 } = await sb
      .from(s.table)
      .select(`id, ${s.recipient}, ${s.event}`)
      .not(s.recipient, 'is', null)
      .not(s.event, 'is', null);
    assert.ok(!e1, `${s.cat}: ${e1?.message}`);

    const refIds = (rows || []).map((r) => r.id);
    // grants already recorded for this category over those refs
    const { data: grants, error: e2 } = await sb
      .from('gamification_points')
      .select('ref_id, member_id')
      .eq('category', s.cat)
      .in('ref_id', refIds.length ? refIds : ['00000000-0000-0000-0000-000000000000']);
    assert.ok(!e2, `${s.cat}: ${e2?.message}`);
    const paid = new Set((grants || []).map((g) => `${g.ref_id}:${g.member_id}`));

    for (const r of rows || []) {
      const recipient = r[s.recipient];
      if (!memberIds.has(recipient)) continue;            // legit _grant_auto_xp skip (non-member)
      if (paid.has(`${r.id}:${recipient}`)) continue;     // already paid
      const evMs = new Date(r[s.event]).getTime();
      if (evMs === SEED_INSTANT_MS) continue;             // documented seed exclusion (allowlisted)
      offenders.push(`${s.cat}:${r.id} (recipient ${recipient}, at ${r[s.event]})`);
    }
  }

  assert.equal(offenders.length, 0, `unpaid curation events (new silent backlog): ${offenders.slice(0, 8).join(' | ')}`);
});

test('1148 DB: every backfilled row sits at the C3 pin instant (0 in the C4 window)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: rows, error } = await sb
    .from('gamification_points')
    .select('id, created_at, category')
    .like('reason', '%(backfill #1148)%');
  assert.ok(!error, error?.message);
  // C3_PIN mirrors the SQL literal ('+00' offset); normalize to ISO 'Z' so Node parses it
  const pinMs = new Date(C3_PIN.replace(' ', 'T').replace('+00', 'Z')).getTime();
  const strays = (rows || []).filter((r) => new Date(r.created_at).getTime() !== pinMs);
  assert.equal(strays.length, 0, `backfill rows off the C3 pin: ${strays.slice(0, 5).map((r) => `${r.category}:${r.id} @ ${r.created_at}`).join(' | ')}`);
});
