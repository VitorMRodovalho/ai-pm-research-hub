import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

// p271 #411 Wave 1a — modal single-dispatch button for notify_selection_cutoff_approved
//
// Locks the original orphan-RPC regression class (cutoff_approved_email_sent_at had been
// load-bearing in the schema since p228 2026-05-21 but had ZERO UI call sites until 2026-05-26
// session p270 wired the first DO-block dispatch). Wave 1a closes the gap by surfacing a
// modal-tab Entrevista button + sent badge bound to the RPC via the SAME render predicate
// the SPEC documents:
//   status IN ('screening','interview_pending')
//   AND cutoff_approved_email_sent_at IS NULL
//   AND no active interview row (= this is the empty-interviews branch of loadInterviewForm)
//
// Scope of THIS test: Wave 1a only. Wave 1b chips, 1c bulk, 1d rescue, 2a/2b crons are
// separate tests in later PRs.

const MIG_PATH = 'supabase/migrations/20260805000052_p271_411_w1a_get_selection_dashboard_cutoff_approved.sql';
const SELECTION_PAGE_PATH = 'src/pages/admin/selection.astro';
const I18N_KEYS = [
  "'admin.selection.modal.cutoffInviteBtn'",
  "'admin.selection.modal.cutoffInviteSent'",
  "'admin.selection.modal.cutoffInviteToast'",
  "'admin.selection.modal.cutoffInviteError'",
  "'admin.selection.modal.cutoffInviteConfirm'",
];

const MIG_EXISTS = existsSync(MIG_PATH);
const MIG = MIG_EXISTS ? readFileSync(MIG_PATH, 'utf8') : '';
const PAGE = readFileSync(SELECTION_PAGE_PATH, 'utf8');
const I18N_PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const I18N_EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const I18N_ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

describe('p271 #411 Wave 1a — cutoff-approved modal button', () => {
  describe('migration (dashboard read-surface extension)', () => {
    it('migration file exists at canonical timestamp 20260805000052', () => {
      assert.ok(MIG_EXISTS, `migration must exist at ${MIG_PATH}`);
    });

    it('preserves get_selection_dashboard signature (p_cycle_code text DEFAULT NULL)', () => {
      assert.match(
        MIG,
        /CREATE OR REPLACE FUNCTION public\.get_selection_dashboard\(p_cycle_code text DEFAULT NULL\)/,
        'SEDIMENT-238.C: DEFAULT clause must stay byte-identical (CREATE OR REPLACE, not DROP+CREATE)'
      );
    });

    it('preserves SECURITY DEFINER + pinned search_path public,pg_temp', () => {
      assert.match(MIG, /SECURITY DEFINER/);
      assert.match(MIG, /SET search_path TO 'public', 'pg_temp'/);
    });

    it('preserves RETURNS jsonb + LANGUAGE plpgsql', () => {
      assert.match(MIG, /RETURNS jsonb/);
      assert.match(MIG, /LANGUAGE plpgsql/);
    });

    it('jsonb_build_object includes cutoff_approved_email_sent_at projection', () => {
      assert.match(
        MIG,
        /'cutoff_approved_email_sent_at',\s*a\.cutoff_approved_email_sent_at/,
        'new field must read column verbatim from selection_applications via the existing a alias'
      );
    });

    it('NOTIFY pgrst reload schema at end', () => {
      assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
    });

    it('header includes WHAT/WHY/SCOPE/ROLLBACK provenance + SEDIMENT-238.C + 269.A notes', () => {
      assert.match(MIG, /-- WHAT:/);
      assert.match(MIG, /-- WHY:/);
      assert.match(MIG, /-- SCOPE:/);
      assert.match(MIG, /-- ROLLBACK:/);
      assert.match(MIG, /SEDIMENT-238\.C/);
      assert.match(MIG, /SEDIMENT-269\.A/);
    });

    it('preserves the authority gate can_by_member(view_internal_analytics)', () => {
      assert.match(
        MIG,
        /public\.can_by_member\(v_caller_id, 'view_internal_analytics'\)/,
        'authz must not be widened or removed by this read-surface extension'
      );
    });
  });

  describe('migration body forward-defense', () => {
    it('does NOT change the function signature (no DROP FUNCTION, no extra args)', () => {
      assert.doesNotMatch(
        MIG,
        /DROP FUNCTION[^;]*get_selection_dashboard/,
        'CREATE OR REPLACE preserves consumers + the surviving overload; never DROP+CREATE for additive read extension'
      );
    });

    it('does NOT silently widen RLS (selection_applications still goes through SECDEF only)', () => {
      assert.doesNotMatch(
        MIG,
        /CREATE POLICY|DROP POLICY|ALTER TABLE public\.selection_applications/,
        'Wave 1a is read-side only; any RLS or table change must be a separate migration'
      );
    });

    it('does NOT add UPDATE / DELETE / INSERT on selection_applications inside the RPC body', () => {
      // Body is read-only — additive jsonb_build_object only.
      assert.doesNotMatch(MIG, /UPDATE public\.selection_applications/);
      assert.doesNotMatch(MIG, /DELETE FROM public\.selection_applications/);
      assert.doesNotMatch(MIG, /INSERT INTO public\.selection_applications/);
    });
  });

  describe('frontend (selection.astro) — render gate + button', () => {
    it('reads cutoff_approved_email_sent_at from row payload (no extra fetch)', () => {
      assert.match(
        PAGE,
        /const cutoffSentAt = row\.cutoff_approved_email_sent_at;/,
        'render predicate must source from the dashboard payload field shipped by migration 52; never via direct SELECT (selection_applications has rpc_only_deny_all)'
      );
    });

    it('declares eligibility status list as ["screening","interview_pending"] (spec render gate)', () => {
      assert.match(
        PAGE,
        /const cutoffEligibleStatus = \['screening', 'interview_pending'\]\.includes\(row\.status\);/,
        'button visibility must match SPEC SELECTION_INTERVIEW_INVITE_LIFECYCLE exactly — no waitlist, no objective_eval, no interview_scheduled'
      );
    });

    it('renders sent badge with data-testid + i18n key when cutoffSentAt is truthy', () => {
      assert.match(
        PAGE,
        /data-testid="cutoff-invite-sent-badge"[^>]*>\$\{T\.modal\.cutoffInviteSent\}/,
        'sent state must be detectable from automation (data-testid) and i18n-driven'
      );
    });

    it('renders #cutoff-invite-btn with data-app-id + data-app-name + i18n key', () => {
      assert.match(
        PAGE,
        /id="cutoff-invite-btn"\s+data-app-id="\$\{esc\(row\.id\)\}"\s+data-app-name="\$\{esc\(row\.applicant_name \|\| ''\)\}"[^>]*>\$\{T\.modal\.cutoffInviteBtn\}</,
        'button must carry app id + escaped name for the confirm/toast labels and be labeled via the cutoffInviteBtn key'
      );
    });

    it('button + badge are mutually exclusive (sent-branch wins via if/else if)', () => {
      // The render block uses `if (cutoffSentAt) { ...badge... } else if (cutoffEligibleStatus) { ...button... }`.
      // Verify the structural pattern: the sent branch precedes the button branch.
      const badgeIdx = PAGE.indexOf('data-testid="cutoff-invite-sent-badge"');
      const buttonIdx = PAGE.indexOf('id="cutoff-invite-btn"');
      assert.ok(badgeIdx > -1 && buttonIdx > -1, 'both branches must be present in source');
      assert.ok(
        badgeIdx < buttonIdx,
        'sent-branch must appear BEFORE button-branch in source so the else-if mutual exclusion holds visually'
      );
    });

    it('click handler calls sb.rpc("notify_selection_cutoff_approved", { p_application_id: row.id })', () => {
      assert.match(
        PAGE,
        /sb\.rpc\('notify_selection_cutoff_approved',\s*\{\s*p_application_id:\s*row\.id\s*\}\)/,
        'RPC name + param shape must match SECDEF signature shipped in p228 migration 20260805000011 / p251 migration 20260805000030'
      );
    });

    it('handler gates dispatch behind window.confirm using cutoffInviteConfirm + name', () => {
      assert.match(
        PAGE,
        /if \(!confirm\(`\$\{T\.modal\.cutoffInviteConfirm\}\s\$\{name\}\?`\)\)\s*return;/,
        'confirm step is part of acceptance criteria (Wave 1a single-click dispatch — but explicit user intent)'
      );
    });

    it('handler optimistically stamps row.cutoff_approved_email_sent_at post-success', () => {
      assert.match(
        PAGE,
        /row\.cutoff_approved_email_sent_at\s*=\s*data\?\.dispatched_at\s*\|\|\s*data\?\.previously_sent_at\s*\|\|\s*new Date\(\)\.toISOString\(\)/,
        'local stamp avoids stale re-render after success; falls back to previously_sent_at when RPC short-circuits via already_sent envelope'
      );
    });

    it('handler error branch surfaces RPC raise via T.modal.cutoffInviteError', () => {
      assert.match(
        PAGE,
        /toast\(e\.message \|\| T\.modal\.cutoffInviteError, 'error'\)/,
        'error branch must prefer the RPC raise message; falls back to localized generic error'
      );
    });

    it('success path triggers BOTH loadInterviewForm(row) and loadDashboard()', () => {
      // Match the cutoff-invite handler closely — re-render modal AND refresh the underlying table.
      const handlerBlock = PAGE.split("'#cutoff-invite-btn'")[1] || '';
      assert.ok(handlerBlock.includes('loadInterviewForm(row);'), 'must re-render modal to flip button → badge');
      assert.ok(handlerBlock.includes('loadDashboard();'), 'must refresh dashboard so list view also reflects sent state');
    });
  });

  describe('frontend forward-defense — no idempotency violations', () => {
    it('button render branch does NOT execute when cutoffSentAt is truthy (else-if guard)', () => {
      // Capture the cutoff render block (between the dual-track mirror block and the live-start CTA).
      const startIdx = PAGE.indexOf('Wave 1a F1 — cutoff-approved invite');
      assert.ok(startIdx > -1, 'cutoff render block header comment must exist (provenance)');
      const blockSlice = PAGE.slice(startIdx, startIdx + 1200);
      assert.match(
        blockSlice,
        /if \(cutoffSentAt\) \{[\s\S]+?\} else if \(cutoffEligibleStatus\) \{/,
        'render block must use if/else-if so badge and button are mutually exclusive'
      );
    });

    it('handler does NOT bypass the canonical RPC by writing cutoff_approved_email_sent_at directly via supabase.from()', () => {
      assert.doesNotMatch(
        PAGE,
        /sb\.from\('selection_applications'\)[\s\S]{0,400}\.update\([^)]*cutoff_approved_email_sent_at/,
        'direct UPDATE would bypass SECDEF + admin_audit_log + selection_dispatch_url_log; must go through notify_selection_cutoff_approved'
      );
    });

    it('handler does NOT call notify_selection_cutoff_approved without explicit user confirmation', () => {
      // Locate the click handler body and assert confirm() appears before the sb.rpc() call.
      const handlerStart = PAGE.indexOf("'#cutoff-invite-btn'");
      assert.ok(handlerStart > -1);
      const handlerSlice = PAGE.slice(handlerStart, handlerStart + 2000);
      const confirmIdx = handlerSlice.indexOf('confirm(');
      const rpcIdx = handlerSlice.indexOf("sb.rpc('notify_selection_cutoff_approved'");
      assert.ok(confirmIdx > -1 && rpcIdx > -1, 'both confirm() and sb.rpc() must exist in handler');
      assert.ok(confirmIdx < rpcIdx, 'confirm() must appear BEFORE the RPC dispatch — never silent fire');
    });
  });

  describe('T object wiring (frontmatter fallback + runtime bridge)', () => {
    it('fallback T.modal declares the 5 cutoffInvite* keys with literal pt-BR strings', () => {
      assert.match(PAGE, /cutoffInviteBtn:\s*'📧 Enviar convite p\/ agendar'/);
      assert.match(PAGE, /cutoffInviteSent:\s*'✓ Convite enviado em'/);
      assert.match(PAGE, /cutoffInviteToast:\s*'Convite enviado para'/);
      assert.match(PAGE, /cutoffInviteError:\s*'Erro ao enviar convite'/);
      assert.match(PAGE, /cutoffInviteConfirm:\s*'Enviar convite de agendamento para'/);
    });

    // p275 #411 W1a hotfix — bug surfaced in prod: badge rendered "undefined 26/05/2026, 22:13 SP"
    // because the runtime T object (served to browser) is built via the t('admin.selection.modal.X', lang)
    // bridge AT THE TOP of the frontmatter, separate from the fallback T at line ~666.
    // Adding keys to ONLY the fallback leaves T.modal.cutoffInviteSent = undefined at runtime.
    // This block locks the regression class so ANY new modal key in the future also lands in BOTH slots.
    it('runtime T.modal bridge wires the 5 cutoffInvite* keys via t() helper', () => {
      assert.match(PAGE, /cutoffInviteBtn:\s*t\('admin\.selection\.modal\.cutoffInviteBtn',\s*lang\)/);
      assert.match(PAGE, /cutoffInviteSent:\s*t\('admin\.selection\.modal\.cutoffInviteSent',\s*lang\)/);
      assert.match(PAGE, /cutoffInviteToast:\s*t\('admin\.selection\.modal\.cutoffInviteToast',\s*lang\)/);
      assert.match(PAGE, /cutoffInviteError:\s*t\('admin\.selection\.modal\.cutoffInviteError',\s*lang\)/);
      assert.match(PAGE, /cutoffInviteConfirm:\s*t\('admin\.selection\.modal\.cutoffInviteConfirm',\s*lang\)/);
    });

    // Forward-defense: each key must appear EXACTLY twice in selection.astro (once in runtime bridge,
    // once in fallback). Anything less means one slot was forgotten; anything more is suspicious.
    for (const key of ['cutoffInviteBtn','cutoffInviteSent','cutoffInviteToast','cutoffInviteError','cutoffInviteConfirm']) {
      it(`${key} appears in BOTH T slots (count exactly 2 in source)`, () => {
        const occurrences = PAGE.match(new RegExp(`\\b${key}:`, 'g')) || [];
        assert.strictEqual(
          occurrences.length,
          2,
          `expected ${key}: to appear 2x (runtime bridge + fallback); found ${occurrences.length} — likely missed one T slot`
        );
      });
    }
  });

  describe('i18n parity across 3 dictionaries (SEDIMENT-235.A: all 3 langs in same PR)', () => {
    for (const key of I18N_KEYS) {
      it(`pt-BR has ${key}`, () => assert.ok(I18N_PT.includes(key), `pt-BR.ts must declare ${key}`));
      it(`en-US has ${key}`, () => assert.ok(I18N_EN.includes(key), `en-US.ts must declare ${key}`));
      it(`es-LATAM has ${key}`, () => assert.ok(I18N_ES.includes(key), `es-LATAM.ts must declare ${key}`));
    }
  });
});
