/**
 * #902 sub-gap 2 — Fase 1: VEP-expired re-application comms (DORMANT) contract guard.
 *
 * Locks in the council's hard requirements (legal-counsel + security-engineer + data-architect
 * + product-leader, all CONDITIONAL) so a future edit cannot silently violate them:
 *   - the invite ships DORMANT (RPC default p_dry_run=true; no cron scheduled in the migration);
 *   - bucket is Expired/OfferExpired ONLY (Withdrawn + OfferNotExtended excluded);
 *   - comms is comms-only (manage_member gate, NOT manage_platform — it must never touch lifecycle);
 *   - the copy NEVER promises automatic approval (LGPD Art. 9 expectativa legítima);
 *   - LGPD Art. 9 transparency + Art. 18 rights channel present in the trilingual template;
 *   - single-fire idempotency via vep_expired_reapply_email_sent_at.
 *
 * Static source-parse only (no DB / network) — flake-free, mirrors 902-vep-deadline-capture.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');

const MIG = (() => {
  const dir = join(REPO_ROOT, 'supabase/migrations');
  const file = readdirSync(dir).find((f) => f.includes('902_subgap2_phase1_vep_expired_reapply_comms'));
  assert.ok(file, 'the #902 sub-gap 2 Fase 1 migration file must exist');
  return readFileSync(join(dir, file), 'utf8');
})();

test('migration adds the single-fire idempotency stamp column', () => {
  assert.match(MIG, /ADD COLUMN IF NOT EXISTS vep_expired_reapply_email_sent_at\s+timestamptz/i);
  assert.match(MIG, /SET vep_expired_reapply_email_sent_at = now\(\)/,
    'the RPC must stamp the column AFTER a successful send (single-fire)');
});

test('RPC ships DORMANT: default dry-run + no cron scheduled', () => {
  assert.match(MIG, /p_dry_run\s+boolean\s+DEFAULT\s+true/i,
    'the dispatch RPC must default to dry-run (no accidental send)');
  assert.match(MIG, /IF p_reapply_url IS NULL[\s\S]*?v_dry\s*:=\s*true/,
    'a missing reapply_url must force dry-run (dormancy latch — no valid destination)');
  assert.doesNotMatch(MIG, /cron\.schedule/,
    'Fase 1 must NOT schedule a cron — dormant until cycle5 exists (PM decision 2026-06-26)');
});

test('bucket is Expired/OfferExpired ONLY — Withdrawn + OfferNotExtended excluded', () => {
  assert.match(MIG, /vep_status_raw IN \('Expired',\s*'OfferExpired'\)/,
    'the dispatch filter must target the Expired/OfferExpired bucket');
  // The eligibility filter must not let Withdrawn/OfferNotExtended through.
  // Check for the QUOTED SQL literal (not the bare word, which appears in explanatory comments).
  const filterBlock = MIG.match(/FOR v_app IN[\s\S]*?LOOP/)[0];
  assert.doesNotMatch(filterBlock, /'OfferNotExtended'/,
    'OfferNotExtended must NOT be a value in the dispatch filter (case-by-case GP review, not auto-invite)');
  assert.doesNotMatch(filterBlock, /'Withdrawn'/,
    'Withdrawn must NOT be a value in the dispatch filter (candidate opted out)');
  assert.match(filterBlock, /status = 'rejected'/,
    'filter must require status=rejected (excludes the withdrawn row)');
});

test('comms is comms-only: manage_member gate, never manage_platform (no lifecycle)', () => {
  assert.match(MIG, /can_by_member\([\s\S]*?'manage_member'/,
    'gate must be manage_member (comms) + cron bypass — mirrors D7');
  assert.doesNotMatch(MIG, /'manage_platform'/,
    'this RPC must NEVER gate on the manage_platform action literal — it sends email, it does not approve/grant membership');
  // it must not write any lifecycle/score columns
  assert.doesNotMatch(MIG, /SET status\s*=\s*'approved'/, 'must not approve anything');
  assert.doesNotMatch(MIG, /INTO public\.members/, 'must not create members');
});

test('copy NEVER promises automatic approval + carries LGPD Art. 9 / Art. 18', () => {
  assert.match(MIG, /não garante aprovação automática/, 'pt copy must disclaim automatic approval');
  assert.match(MIG, /does not guarantee automatic approval/, 'en copy must disclaim automatic approval');
  assert.match(MIG, /no garantiza aprobación automática/, 'es copy must disclaim automatic approval');
  // it must frame the expiry as administrative, not a merit rejection
  assert.match(MIG, /não foi uma rejeição por mérito/, 'pt copy must say it was not a merit rejection');
  // LGPD transparency (Art. 9 — prior data reuse) + rights channel (Art. 18)
  assert.match(MIG, /LGPD Art\. 9/, 'template must carry the Art. 9 transparency note (prior-data reuse)');
  assert.match(MIG, /LGPD Art\. 18/, 'template must carry the Art. 18 data-subject rights channel');
});

test('template + RPC are wired by the same slug', () => {
  assert.match(MIG, /'selection_vep_expired_reapply_invite'/);
  const count = (MIG.match(/selection_vep_expired_reapply_invite/g) || []).length;
  assert.ok(count >= 2, 'the slug must appear in both the template INSERT and the RPC dispatch');
});
