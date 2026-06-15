/**
 * #693 defeito 2 — dual-track auto-link must NOT drop the second VEP application.
 *
 * ROOT CAUSE (aterrado via cron_run_log 2026-06-14): `_trg_auto_link_dual_track`
 * rodava em BEFORE INSERT e fazia o back-link recíproco
 * `UPDATE sibling SET linked_application_id = NEW.id` — mas em BEFORE INSERT a row
 * NEW ainda não existe, e a FK `selection_applications_linked_application_id_fkey`
 * é NÃO-deferrable → FK violation → o INSERT da 2ª candidatura dual-track aborta →
 * a app é dropada em toda sync (live: Ana Sofia, researcher 296896 ↔ leader 296862).
 *
 * FIX (migration 20260805000172): trigger convertido para AFTER INSERT (NEW.id já
 * é uma row materializada → ambos os UPDATEs recíprocos resolvem a FK).
 *
 * STATIC: o trigger deve ser AFTER INSERT (não BEFORE) — trava a regressão.
 * DB-AWARE: insere um par dual-track sintético, confirma o link recíproco mútuo +
 * promotion_path=dual_track, e LIMPA as rows de teste (FK-safe).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000172_693_dual_track_autolink_after_insert_fkfix.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const TEST_EMAIL = 'test-693-autolink@example.invalid';

// ── STATIC ──────────────────────────────────────────────────────────────────
test('#693 static: migration 20260805000172 exists and makes the trigger AFTER INSERT', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000172 present');
  const src = readFileSync(MIG, 'utf8');
  // strip line comments so a comment mentioning the old BEFORE pattern doesn't trip us
  const code = src.replace(/^\s*--.*$/gm, '');
  assert.match(code, /CREATE TRIGGER trg_auto_link_dual_track\s+AFTER INSERT ON public\.selection_applications/i,
    'trigger must be AFTER INSERT');
  assert.doesNotMatch(code, /CREATE TRIGGER trg_auto_link_dual_track\s+BEFORE INSERT/i,
    'REGRESSION: trigger reverted to BEFORE INSERT (#693 defeito 2 FK violation)');
});

// ── DB-AWARE BEHAVIOURAL ──────────────────────────────────────────────────────
test('#693 behavioural: a dual-track 2nd application inserts + links reciprocally (no FK drop)',
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // a real open cycle to satisfy the cycle_id FK + the trigger's same-cycle match
  const { data: cycle, error: cycErr } = await sb
    .from('selection_cycles').select('id').eq('status', 'open')
    .order('open_date', { ascending: false }).limit(1).maybeSingle();
  assert.ok(!cycErr && cycle?.id, `need an open selection_cycle: ${cycErr?.message}`);

  // defensive pre-clean (in case a prior aborted run left rows)
  await sb.from('selection_applications').delete().eq('email', TEST_EMAIL);

  try {
    // 1) leader first — no sibling yet, trigger no-op
    const { error: e1 } = await sb.from('selection_applications').insert({
      cycle_id: cycle.id, applicant_name: 'TEST693 AutoLink', email: TEST_EMAIL,
      role_applied: 'leader', vep_application_id: 'TEST693AL', vep_opportunity_id: '64966', status: 'submitted',
    });
    assert.ok(!e1, `leader insert failed: ${e1?.message}`);

    // 2) researcher second — the case that FK-violated under the BEFORE trigger.
    //    Must succeed now (AFTER INSERT) — this is the core regression assertion.
    const { error: e2 } = await sb.from('selection_applications').insert({
      cycle_id: cycle.id, applicant_name: 'TEST693 AutoLink', email: TEST_EMAIL,
      role_applied: 'researcher', vep_application_id: 'TEST693AR', vep_opportunity_id: '64967', status: 'submitted',
    });
    assert.ok(!e2, `researcher (2nd dual-track) insert MUST succeed post-fix, got FK drop: ${e2?.message}`);

    // 3) both rows linked reciprocally + promotion_path=dual_track
    const { data: rows, error: e3 } = await sb.from('selection_applications')
      .select('id, role_applied, promotion_path, linked_application_id')
      .eq('email', TEST_EMAIL);
    assert.ok(!e3, `read-back failed: ${e3?.message}`);
    assert.equal(rows.length, 2, 'both dual-track rows present');
    const leader = rows.find(r => r.role_applied === 'leader');
    const researcher = rows.find(r => r.role_applied === 'researcher');
    assert.ok(leader && researcher, 'leader + researcher rows present');
    assert.equal(leader.promotion_path, 'dual_track', 'leader promotion_path');
    assert.equal(researcher.promotion_path, 'dual_track', 'researcher promotion_path');
    assert.equal(leader.linked_application_id, researcher.id, 'leader links → researcher');
    assert.equal(researcher.linked_application_id, leader.id, 'researcher links → leader (reciprocal)');
  } finally {
    // FK-safe cleanup: NULL the reciprocal links first, then delete.
    await sb.from('selection_applications').update({ linked_application_id: null }).eq('email', TEST_EMAIL);
    await sb.from('selection_applications').delete().eq('email', TEST_EMAIL);
  }
});
