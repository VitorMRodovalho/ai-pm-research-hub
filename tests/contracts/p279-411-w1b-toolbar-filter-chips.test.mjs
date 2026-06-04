import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

// p279 #411 Wave 1b — toolbar filter chips (F2): "Sem entrevista" + "Stuck scheduled"
//
// Wave 1b surfaces the two interview-invite lifecycle gaps as toolbar filter chips on
// /admin/selection so the PM can find (a) candidates with no scheduled interview who are
// not yet decided (the cutoff-invite dispatch queue) and (b) candidates whose scheduled
// interview lapsed without being conducted or cancelled (the rescue queue).
//
// The "Stuck scheduled" predicate needs the latest interview's conducted_at + past
// scheduled_at, which the dashboard payload did NOT expose. Wave 1b adds a precise,
// server-computed meta.interview_stuck boolean to get_selection_dashboard (read-surface
// extension, same class as Wave 1a's migration 52). The chip + the Wave-1d rescue button
// both read it.
//
// Scope of THIS test: Wave 1b only (migration read-surface + 2 chips + i18n). Wave 1c bulk,
// 1d rescue, 2a/2b crons are separate tests in later PRs.

const MIG_PATH = 'supabase/migrations/20260805000103_p279_411_w1b_get_selection_dashboard_interview_stuck.sql';
const SELECTION_PAGE_PATH = 'src/pages/admin/selection.astro';
const I18N_KEYS = [
  "'admin.selection.noInterview'",
  "'admin.selection.noInterviewHint'",
  "'admin.selection.stuckScheduled'",
  "'admin.selection.stuckScheduledHint'",
];

const MIG_EXISTS = existsSync(MIG_PATH);
const MIG = MIG_EXISTS ? readFileSync(MIG_PATH, 'utf8') : '';
const PAGE = readFileSync(SELECTION_PAGE_PATH, 'utf8');
const I18N_PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const I18N_EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const I18N_ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

describe('p279 #411 Wave 1b — toolbar filter chips', () => {
  describe('migration (dashboard read-surface extension: meta.interview_stuck)', () => {
    it('migration file exists at canonical timestamp 20260805000103', () => {
      assert.ok(MIG_EXISTS, `migration must exist at ${MIG_PATH}`);
    });

    it('preserves get_selection_dashboard signature (p_cycle_code text DEFAULT NULL)', () => {
      assert.match(
        MIG,
        /CREATE OR REPLACE FUNCTION public\.get_selection_dashboard\(p_cycle_code text DEFAULT NULL\)/,
        'SEDIMENT-238.C: DEFAULT clause must stay byte-identical (CREATE OR REPLACE, not DROP+CREATE)'
      );
    });

    it('preserves SECURITY DEFINER + pinned search_path public,pg_temp + RETURNS jsonb', () => {
      assert.match(MIG, /SECURITY DEFINER/);
      assert.match(MIG, /SET search_path TO 'public', 'pg_temp'/);
      assert.match(MIG, /RETURNS jsonb/);
      assert.match(MIG, /LANGUAGE plpgsql/);
    });

    it('preserves the prior Wave-1a field cutoff_approved_email_sent_at (no regression)', () => {
      assert.match(
        MIG,
        /'cutoff_approved_email_sent_at',\s*a\.cutoff_approved_email_sent_at/,
        'read-surface extension must keep migration-52 fields intact'
      );
    });

    it('adds interview_stuck projection inside the per-app meta object', () => {
      assert.match(MIG, /'interview_stuck',\s*\(/, 'new boolean key must be present in meta');
    });

    it('interview_stuck uses the canonical predicate (app interview_scheduled + past, not-conducted scheduled interview)', () => {
      // Anchored on app.status AND an interview-row EXISTS subquery with the precise stuck shape.
      assert.match(MIG, /a\.status = 'interview_scheduled'/);
      assert.match(MIG, /si\.status = 'scheduled'/);
      assert.match(MIG, /si\.conducted_at IS NULL/);
      assert.match(MIG, /si\.scheduled_at < now\(\)/);
    });

    it('NOTIFY pgrst reload schema at end', () => {
      assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
    });

    it('header includes WHAT/WHY/SCOPE/ROLLBACK + SEDIMENT-238.C + 269.A provenance', () => {
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

  describe('migration body forward-defense (read-only additive)', () => {
    it('does NOT change the function signature (no DROP FUNCTION)', () => {
      assert.doesNotMatch(MIG, /DROP FUNCTION[^;]*get_selection_dashboard/);
    });

    it('does NOT widen RLS or mutate selection_applications', () => {
      assert.doesNotMatch(MIG, /CREATE POLICY|DROP POLICY|ALTER TABLE public\.selection_applications/);
      assert.doesNotMatch(MIG, /UPDATE public\.selection_applications/);
      assert.doesNotMatch(MIG, /DELETE FROM public\.selection_applications/);
      assert.doesNotMatch(MIG, /INSERT INTO public\.selection_applications/);
    });
  });

  describe('frontend (selection.astro) — two new chips', () => {
    it('renders #filter-no-interview chip with i18n label + hint', () => {
      assert.match(
        PAGE,
        /id="filter-no-interview"[\s\S]{0,260}title=\{t\('admin\.selection\.noInterviewHint', lang\)\}>\{t\('admin\.selection\.noInterview', lang\)\}</,
        'no-interview chip must use the noInterview/noInterviewHint i18n keys'
      );
    });

    it('renders #filter-stuck-scheduled chip with i18n label + hint', () => {
      assert.match(
        PAGE,
        /id="filter-stuck-scheduled"[\s\S]{0,300}title=\{t\('admin\.selection\.stuckScheduledHint', lang\)\}>\{t\('admin\.selection\.stuckScheduled', lang\)\}</,
        'stuck-scheduled chip must use the stuckScheduled/stuckScheduledHint i18n keys'
      );
    });

    it('declares filter state vars (default OFF)', () => {
      assert.match(PAGE, /let filterNoInterview = false;/);
      assert.match(PAGE, /let filterStuckScheduled = false;/);
    });

    it('applyFilters predicate — Sem entrevista: interview_status none|needs_reschedule AND not terminal', () => {
      assert.match(
        PAGE,
        /filterNoInterview && !\(\['none', 'needs_reschedule'\]\.includes\(r\.interview_status\) && !\['rejected', 'approved', 'interview_done', 'final_eval'\]\.includes\(r\.status\)\)/,
        'predicate must match the SPEC F2 "Sem entrevista" definition'
      );
    });

    it('applyFilters predicate — Stuck scheduled: reads server-computed meta.interview_stuck', () => {
      assert.match(
        PAGE,
        /filterStuckScheduled && r\.meta\?\.interview_stuck !== true/,
        'chip must filter on the server flag (not a fragile client approximation)'
      );
    });

    it('wires click handlers that toggle data-active + re-run applyFilters', () => {
      const noIntvHandler = PAGE.split("getElementById('filter-no-interview')")[1] || '';
      assert.ok(noIntvHandler.includes('filterNoInterview = !filterNoInterview;'), 'no-interview toggle must flip state');
      const stuckHandler = PAGE.split("getElementById('filter-stuck-scheduled')")[1] || '';
      assert.ok(stuckHandler.includes('filterStuckScheduled = !filterStuckScheduled;'), 'stuck toggle must flip state');
    });

    it('chips stack additively (predicates are independent early-returns inside applyFilters)', () => {
      // Both predicates appear inside the same .filter() body alongside the existing chips.
      const filterBody = PAGE.slice(PAGE.indexOf('function applyFilters()'), PAGE.indexOf('filteredRows.sort'));
      assert.ok(filterBody.includes('filterNoInterview'), 'no-interview predicate inside applyFilters');
      assert.ok(filterBody.includes('filterStuckScheduled'), 'stuck predicate inside applyFilters');
      assert.ok(filterBody.includes('filterInterviewToday'), 'stacks with the pre-existing interview-today chip');
    });
  });

  describe('i18n parity across 3 dictionaries', () => {
    for (const key of I18N_KEYS) {
      it(`pt-BR has ${key}`, () => assert.ok(I18N_PT.includes(key), `pt-BR.ts must declare ${key}`));
      it(`en-US has ${key}`, () => assert.ok(I18N_EN.includes(key), `en-US.ts must declare ${key}`));
      it(`es-LATAM has ${key}`, () => assert.ok(I18N_ES.includes(key), `es-LATAM.ts must declare ${key}`));
    }
  });
});
