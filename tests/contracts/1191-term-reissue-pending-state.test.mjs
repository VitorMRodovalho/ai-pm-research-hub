/**
 * #1191 — Termos panel distinguishes "reissued — awaiting re-signature" from "never signed".
 *
 * Context (decision PM 2026-07-08, option 1+3 — gate stays, UX explains; index case João):
 * reissue_agreement supersedes the year's cert, which detaches agreement_certificate_id →
 * auth_engagements.is_authoritative=false → operational_role cache stays guest until the
 * volunteer re-signs (then the new cert snapshots role+period from the engagement, F5/#1175,
 * and the cache promotes alone). That is BY DESIGN; the panel just could not tell the story:
 * a reissued member looked identical to someone who never signed.
 *
 * Locks (migration 20260805000373 + VolunteerAgreementPanel):
 *   1. the RPC emits, per member, reissue_pending (superseded cert of the year present AND no
 *      issued cert of the year) + reissued_at (supersede moment, for the tooltip);
 *   2. the panel renders a distinct badge for reissue_pending (never the red "Não assinado")
 *      and a cursor-help note on the guest role explaining the pending promotion;
 *   3. mig 359/362/370 lineage invariants stay: positive eligibility rule (active volunteer
 *      engagement), authority gate, template version read-through.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

const MIG = read('../../supabase/migrations/20260805000373_1191_term_reissue_pending_state.sql');
const MIG_CODE = MIG.replace(/--.*$/gm, '');
const PANEL = read('../../src/components/admin/VolunteerAgreementPanel.tsx');

// ── RPC source contract ─────────────────────────────────────────────────────

test('1191: RPC emits reissue_pending + reissued_at per member', () => {
  assert.match(MIG, /'reissue_pending'/, 'reissue_pending key');
  assert.match(MIG, /'reissued_at'/, 'reissued_at key');
});

test('1191: reissue_pending = superseded cert of the year AND no issued cert of the year', () => {
  const arm = MIG_CODE.slice(MIG_CODE.indexOf("'reissue_pending'"), MIG_CODE.indexOf("'reissued_at'"));
  assert.match(arm, /status\s*=\s*'superseded'/, 'positive arm anchored on superseded');
  assert.match(arm, /NOT EXISTS[\s\S]*status\s*=\s*'issued'/, 'negated arm excludes members who already re-signed');
  assert.match(arm, /EXTRACT\(YEAR FROM c\.issued_at\) = EXTRACT\(YEAR FROM now\(\)\)/, 'year-scoped like the rest of the panel');
});

test('1191: mig 359/362/370 lineage invariants preserved (not weakened)', () => {
  assert.match(MIG_CODE, /ae\.kind = 'volunteer' AND ae\.status = 'active'/, 'positive eligibility rule (#1173)');
  assert.match(MIG_CODE, /can_by_member\(v_caller_id, 'manage_member'\)/, 'authority gate');
  assert.match(MIG_CODE, /voluntariado_director/, 'program-wide director read');
  assert.match(MIG_CODE, /COALESCE\(dv\.version_label, gd\.version\)/, 'template version read-through (#1187)');
});

// ── Panel source contract ───────────────────────────────────────────────────

test('1191: panel renders the distinct reissue-pending badge, and the red badge excludes it', () => {
  assert.match(PANEL, /reissue_pending: boolean/, 'MemberRow carries the flag');
  assert.match(PANEL, /stateReissuePending/, 'distinct badge label');
  assert.match(PANEL, /!m\.signed && m\.reissue_pending/, 'badge branch');
  assert.match(PANEL, /!m\.signed && !m\.reissue_pending/, 'the "never signed" badge no longer swallows reissued members');
  assert.match(PANEL, /reissuePendingTitle\.replace\('\{date\}', fmtDate\(m\.reissued_at\)\)/, 'tooltip carries the supersede date');
});

test('1191: guest role gets the explanatory tooltip when re-signature is pending', () => {
  assert.match(PANEL, /m\.reissue_pending && m\.role === 'guest'/, 'guest note gated on the pending state');
  assert.match(PANEL, /guestReissueTitle/, 'explanation string wired');
});

test('1191: the three inline dictionaries all carry the new strings', () => {
  const langs = PANEL.match(/stateReissuePending:/g) || [];
  assert.equal(langs.length, 3, `stateReissuePending in pt/en/es (got ${langs.length})`);
  assert.equal((PANEL.match(/reissuePendingTitle:/g) || []).length, 3, 'reissuePendingTitle in pt/en/es');
  assert.equal((PANEL.match(/guestReissueTitle:/g) || []).length, 3, 'guestReissueTitle in pt/en/es');
});
