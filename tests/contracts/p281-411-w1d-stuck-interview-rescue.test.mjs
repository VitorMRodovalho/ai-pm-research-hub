import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

// p281 #411 Wave 1d — selection_rescue_stuck_interview RPC + modal F4 button
//
// Atomic 3-step rescue for a candidate whose scheduled interview lapsed:
//   1. cancel the stuck interview, 2. reset app -> interview_pending + clear
//   cutoff_approved_email_sent_at, 3. re-dispatch via notify_selection_cutoff_approved.
// The whole body is one transaction; notify is NOT wrapped in an exception handler, so a
// re-dispatch failure rolls the cancel back (atomic). Authority: committee lead OR
// manage_member, with the ADR-0028 cron/service bypass so the Wave 2b cron can reuse it.
//
// SEDIMENT-239b.A: the SECDEF function writes admin_audit_log.actor_id from the resolved
// caller (v_caller.id), NOT auth.uid() — preserving the FK to members(id) (NULL in cron).

const MIG_PATH = 'supabase/migrations/20260805000104_p281_411_w1d_selection_rescue_stuck_interview.sql';
const SELECTION_PAGE_PATH = 'src/pages/admin/selection.astro';
const I18N_KEYS = [
  "'admin.selection.modal.rescueStuckTitle'",
  "'admin.selection.modal.rescueStuckHint'",
  "'admin.selection.modal.rescueStuckBtn'",
  "'admin.selection.modal.rescueStuckConfirm'",
  "'admin.selection.modal.rescueStuckToast'",
  "'admin.selection.modal.rescueStuckError'",
];

const MIG_EXISTS = existsSync(MIG_PATH);
const MIG = MIG_EXISTS ? readFileSync(MIG_PATH, 'utf8') : '';
const PAGE = readFileSync(SELECTION_PAGE_PATH, 'utf8');
const I18N_PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const I18N_EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const I18N_ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

describe('p281 #411 Wave 1d — stuck-interview rescue', () => {
  describe('migration (selection_rescue_stuck_interview SECDEF RPC)', () => {
    it('migration file exists at canonical timestamp 20260805000104', () => {
      assert.ok(MIG_EXISTS, `migration must exist at ${MIG_PATH}`);
    });

    it('declares the RPC signature (p_application_id uuid) RETURNS jsonb', () => {
      assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.selection_rescue_stuck_interview\(p_application_id uuid\)/);
      assert.match(MIG, /RETURNS jsonb/);
    });

    it('is SECURITY DEFINER with search_path = \'\' (security-correct, fully-qualified)', () => {
      assert.match(MIG, /SECURITY DEFINER/);
      assert.match(MIG, /SET search_path = ''/);
    });

    it('STEP 1 — cancels the stuck interview (UPDATE selection_interviews SET status=cancelled)', () => {
      assert.match(MIG, /UPDATE public\.selection_interviews\s+SET status = 'cancelled'/);
    });

    it('finds the stuck interview by the canonical predicate (scheduled + past + not conducted)', () => {
      assert.match(MIG, /status = 'scheduled'/);
      assert.match(MIG, /conducted_at IS NULL/);
      assert.match(MIG, /scheduled_at < now\(\)/);
    });

    it('STEP 2 — resets the application to interview_pending + clears cutoff_approved_email_sent_at', () => {
      assert.match(MIG, /SET status = 'interview_pending'/);
      assert.match(MIG, /SET cutoff_approved_email_sent_at = NULL/);
    });

    it('STEP 3 — re-dispatches via notify_selection_cutoff_approved', () => {
      assert.match(MIG, /v_notify := public\.notify_selection_cutoff_approved\(p_application_id\)/);
    });

    it('atomic: notify is NOT wrapped in an EXCEPTION handler (a notify failure rolls the rescue back)', () => {
      // The whole function body has no EXCEPTION clause — unhandled notify RAISE => full rollback.
      assert.doesNotMatch(MIG, /EXCEPTION\s+WHEN/i, 'no exception handler — atomicity comes from the implicit (sub)transaction');
    });

    it('authority gate: committee lead OR can_by_member(manage_member)', () => {
      assert.match(MIG, /can_by_member\(v_caller\.id, 'manage_member'::text\)/);
      assert.match(MIG, /selection_committee[\s\S]*?role = 'lead'/);
    });

    it('cron-aware bypass (ADR-0028): no-JWT or service_role context skips the per-caller gate', () => {
      assert.match(MIG, /current_setting\('request\.jwt\.claims', true\) IS NULL OR auth\.role\(\) = 'service_role'/);
      assert.match(MIG, /IF NOT v_is_cron THEN/);
    });

    it('authenticated ghost still RAISEs (member not found) — bypass not reachable with a JWT', () => {
      assert.match(MIG, /RAISE EXCEPTION 'Unauthorized: member not found'/);
    });

    it('SEDIMENT-239b.A — admin_audit_log.actor_id sourced from v_caller.id (NOT auth.uid())', () => {
      const auditIdx = MIG.indexOf('INSERT INTO public.admin_audit_log');
      assert.ok(auditIdx > -1, 'must write an audit row');
      const auditBlock = MIG.slice(auditIdx, auditIdx + 400);
      assert.match(auditBlock, /v_caller\.id,\s*\n\s*'selection\.stuck_interview_rescued'/, 'actor_id is the resolved caller id');
      assert.doesNotMatch(auditBlock, /auth\.uid\(\)/, 'never insert auth.uid() as actor_id (it is auth.users id, wrong FK)');
    });

    it('audit action literal is selection.stuck_interview_rescued + dispatch_source flag', () => {
      assert.match(MIG, /'selection\.stuck_interview_rescued'/);
      assert.match(MIG, /'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END/);
    });

    it('GRANT EXECUTE to authenticated + service_role; REVOKE from public/anon', () => {
      assert.match(MIG, /REVOKE ALL ON FUNCTION public\.selection_rescue_stuck_interview\(uuid\) FROM PUBLIC, anon/);
      assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.selection_rescue_stuck_interview\(uuid\) TO authenticated, service_role/);
    });

    it('NOTIFY pgrst reload schema + WHAT/WHY/ROLLBACK provenance', () => {
      assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
      assert.match(MIG, /-- WHAT:/);
      assert.match(MIG, /-- ROLLBACK:/);
      assert.match(MIG, /SEDIMENT-239b\.A/);
    });
  });

  describe('frontend (selection.astro) — F4 modal banner + button', () => {
    it('renders the rescue banner gated on the server flag row.meta.interview_stuck', () => {
      assert.match(PAGE, /if \(row\.meta\?\.interview_stuck === true\) \{/);
      assert.match(PAGE, /data-testid="rescue-stuck-banner"/);
    });

    it('renders #rescue-stuck-btn with app id + name + i18n label', () => {
      assert.match(
        PAGE,
        /id="rescue-stuck-btn" data-app-id="\$\{esc\(row\.id\)\}" data-app-name="\$\{esc\(row\.applicant_name \|\| ''\)\}"[^>]*>\$\{T\.modal\.rescueStuckBtn\}</,
      );
    });

    it('handler calls sb.rpc(selection_rescue_stuck_interview, {p_application_id: row.id})', () => {
      assert.match(PAGE, /sb\.rpc\('selection_rescue_stuck_interview', \{ p_application_id: row\.id \}\)/);
    });

    it('handler is confirm-gated before dispatch', () => {
      const h = PAGE.slice(PAGE.indexOf("'#rescue-stuck-btn'"), PAGE.indexOf("'#rescue-stuck-btn'") + 1200);
      const confirmIdx = h.indexOf('confirm(');
      const rpcIdx = h.indexOf("sb.rpc('selection_rescue_stuck_interview'");
      assert.ok(confirmIdx > -1 && rpcIdx > -1 && confirmIdx < rpcIdx, 'confirm must precede the RPC dispatch');
    });

    it('success path re-renders the modal + refreshes dashboard', () => {
      const h = PAGE.slice(PAGE.indexOf("'#rescue-stuck-btn'"), PAGE.indexOf("'#rescue-stuck-btn'") + 1200);
      assert.ok(h.includes('loadInterviewForm(row);'));
      assert.ok(h.includes('loadDashboard();'));
    });
  });

  describe('T object dual-slot wiring (runtime bridge + fallback)', () => {
    it('runtime T.modal bridge wires the 6 rescueStuck* keys via t() helper', () => {
      for (const k of ['rescueStuckTitle','rescueStuckHint','rescueStuckBtn','rescueStuckConfirm','rescueStuckToast','rescueStuckError']) {
        assert.match(PAGE, new RegExp(`${k}:\\s*t\\('admin\\.selection\\.modal\\.${k}', lang\\)`));
      }
    });
    for (const key of ['rescueStuckTitle','rescueStuckHint','rescueStuckBtn','rescueStuckConfirm','rescueStuckToast','rescueStuckError']) {
      it(`${key} appears in BOTH T slots (count exactly 2 in source)`, () => {
        const occurrences = PAGE.match(new RegExp(`\\b${key}:`, 'g')) || [];
        assert.strictEqual(occurrences.length, 2, `expected ${key}: 2x (bridge + fallback); found ${occurrences.length}`);
      });
    }
  });

  describe('i18n parity across 3 dictionaries', () => {
    for (const key of I18N_KEYS) {
      it(`pt-BR has ${key}`, () => assert.ok(I18N_PT.includes(key)));
      it(`en-US has ${key}`, () => assert.ok(I18N_EN.includes(key)));
      it(`es-LATAM has ${key}`, () => assert.ok(I18N_ES.includes(key)));
    }
  });
});
