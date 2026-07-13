-- #1316 — Núcleo VEP contract as the SSOT determinant of an approved app's cohort cycle.
--
-- Root cause (re-triaged 2026-07-13, numbers re-measured live vs prod + enriched VEP export):
-- cycle assignment was a fragile heuristic over application_date / app_id sequence. The real
-- determinant is the Núcleo VEP CONTRACT START (serviceStartDateUTC, scoped to THIS opportunity):
-- a 1-year contract crosses two semesters, so submission/approval dates do not anchor the cohort.
-- Contract start has only two population values (2026-01-20 -> cycle3, 2026-07-01 -> cycle4) plus a
-- mid-window recruit (2026-04-01 -> b2). Reconciled live: the SSOT rule below matches the current
-- cycle_id of all 82 in-db approved apps (49 cycle4 + 32 cycle3 + 1 b2), 0 mismatches.
--
-- This migration: (1) adds dedicated contract columns (NOT the polluted lifetime
-- service_first_start_date/service_latest_end_date); (2) the cohort SSOT function (shared with the
-- worker's pickCohortCycleByContractStart); (3) a person-scoped status view (by pmi_id) that feeds
-- #1284's continuante-vs-desligado baixa; (4) paves the selection_cycles windows contiguous +
-- non-overlapping so rejected/pending apps (temporal lens) never fall in a gap/overlap; (5) backfills
-- the contract columns from the audited 2026-07-13 export; (6) re-stamps the 12 rejected apps whose
-- application_date now lands in a different paved window (approved apps are cohort-driven, untouched).

-- 1. Dedicated Núcleo contract columns ---------------------------------------------------------
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS nucleo_contract_start date,
  ADD COLUMN IF NOT EXISTS nucleo_contract_end   date;

COMMENT ON COLUMN public.selection_applications.nucleo_contract_start IS
  '#1316 Nucleo VEP contract start for THIS application/role (VEP serviceStartDateUTC, scoped to the opportunity). Cohort determinant. NOT service_first_start_date (lifetime cross-chapter VEP history).';
COMMENT ON COLUMN public.selection_applications.nucleo_contract_end IS
  '#1316 Nucleo VEP contract end for THIS application/role (VEP serviceEndDateUTC).';

-- 2. Cohort SSOT: cycle whose application window opened most recently on/before the contract start.
--    Returns NULL for pre-cycle3 legacy 2025 contracts (#1284) or when start is absent (temporal lens).
--    MUST stay byte-equivalent to the worker's pickCohortCycleByContractStart (cloudflare-workers/pmi-vep-sync/src/db.ts).
CREATE OR REPLACE FUNCTION public.nucleo_contract_cohort_cycle_id(p_contract_start date)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT sc.id
  FROM public.selection_cycles sc
  WHERE p_contract_start IS NOT NULL
    AND sc.open_date IS NOT NULL
    AND sc.open_date <= p_contract_start
  ORDER BY sc.open_date DESC
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.nucleo_contract_cohort_cycle_id(date) IS
  '#1316 SSOT: cohort cycle for an approved app = selection_cycle with greatest open_date <= contract start. Mirrors worker pickCohortCycleByContractStart. NULL for pre-cycle3 legacy 2025 contracts (#1284).';

-- 3. Person-scoped contract status view (keyed on pmi_id, NOT email: Paulo 1158211 holds his
--    researcher + leader apps under two different emails). security_invoker respects RLS.
--    superseded  = the same person holds an approved contract that STARTS later (promotion/role-change,
--                  e.g. researcher -> leader) so this app's role was superseded; NEVER a dismissal.
--    ended       = latest approved contract already ended (desligado / continuante nao-renovado).
--    active      = latest approved contract still running.
--    not_engaged = has offered contract dates but the app is not an active engagement (rejected/withdrawn).
--    no_contract = no contract dates (rejected/pending, temporal lens).
CREATE OR REPLACE VIEW public.v_nucleo_contract_status
WITH (security_invoker = true)
AS
WITH contracts AS (
  SELECT
    sa.id,
    sa.vep_application_id,
    sa.pmi_id,
    sa.email,
    sa.applicant_name,
    sa.role_applied,
    sa.status,
    sa.cycle_id,
    sa.nucleo_contract_start,
    sa.nucleo_contract_end,
    public.nucleo_contract_cohort_cycle_id(sa.nucleo_contract_start) AS cohort_cycle_id
  FROM public.selection_applications sa
),
later AS (
  SELECT
    c.id,
    EXISTS (
      SELECT 1 FROM contracts c2
      WHERE c2.pmi_id IS NOT NULL
        AND c2.pmi_id = c.pmi_id
        AND c2.id <> c.id
        AND c2.status IN ('approved', 'converted')
        AND c2.nucleo_contract_start IS NOT NULL
        AND c2.nucleo_contract_start > c.nucleo_contract_start
    ) AS has_later_contract
  FROM contracts c
  WHERE c.nucleo_contract_start IS NOT NULL
)
SELECT
  c.id,
  c.vep_application_id,
  c.pmi_id,
  c.email,
  c.applicant_name,
  c.role_applied,
  c.status,
  c.cycle_id,
  c.cohort_cycle_id,
  c.nucleo_contract_start,
  c.nucleo_contract_end,
  COALESCE(l.has_later_contract, false) AS has_later_contract,
  CASE
    WHEN c.nucleo_contract_start IS NULL THEN 'no_contract'
    WHEN c.status NOT IN ('approved', 'converted') THEN 'not_engaged'
    WHEN COALESCE(l.has_later_contract, false) THEN 'superseded'
    WHEN c.nucleo_contract_end IS NOT NULL AND c.nucleo_contract_end < CURRENT_DATE THEN 'ended'
    ELSE 'active'
  END AS contract_status
FROM contracts c
LEFT JOIN later l ON l.id = c.id;

COMMENT ON VIEW public.v_nucleo_contract_status IS
  '#1316 Per-app Nucleo contract status, person-scoped by pmi_id. Feeds #1284 baixa detection (desligado = person whose latest app is ended). superseded protects promotions (Paulo researcher->leader) from being read as dismissals.';

-- 4. Pave selection_cycles windows contiguous + non-overlapping. Rejected/pending apps use the
--    temporal lens; a gap (2026-02-01..03-27) or overlap (cycle4 opened 05-15 while b2 ran to 05-31)
--    misrouted them. Approved apps are cohort-driven (nucleo_contract_cohort_cycle_id) and unaffected.
UPDATE public.selection_cycles SET close_date = DATE '2026-03-27' WHERE cycle_code = 'cycle3-2026';
UPDATE public.selection_cycles SET close_date = DATE '2026-05-14' WHERE cycle_code = 'cycle3-2026-b2';

-- 5. Backfill the contract columns from the audited enriched export (2026-07-13). Join by
--    vep_application_id; only in-db rows update (legacy 62106 253xxx apps are not yet in
--    selection_applications and are handled by #1284).
UPDATE public.selection_applications sa
SET nucleo_contract_start = v.cstart,
    nucleo_contract_end   = v.cend
FROM (VALUES
  ('253136',DATE '2025-08-22',DATE '2026-07-31'),
  ('253137',DATE '2025-08-22',DATE '2026-03-24'),
  ('253215',DATE '2025-08-22',DATE '2027-06-30'),
  ('253336',DATE '2025-08-22',DATE '2026-04-22'),
  ('253882',DATE '2025-08-22',DATE '2026-07-31'),
  ('254558',DATE '2025-08-22',DATE '2026-07-31'),
  ('268846',DATE '2026-01-20',DATE '2026-12-19'),
  ('268857',DATE '2026-01-20',DATE '2026-12-19'),
  ('268964',DATE '2026-01-20',DATE '2026-12-19'),
  ('269052',DATE '2026-01-20',DATE '2026-12-19'),
  ('269068',DATE '2026-01-20',DATE '2026-07-02'),
  ('269234',DATE '2026-01-20',DATE '2026-07-06'),
  ('269280',DATE '2026-01-20',DATE '2026-12-19'),
  ('269294',DATE '2026-01-20',DATE '2026-03-26'),
  ('269352',DATE '2026-01-20',DATE '2026-12-31'),
  ('269358',DATE '2026-01-20',DATE '2026-04-22'),
  ('269537',DATE '2026-01-20',DATE '2026-12-31'),
  ('269554',DATE '2026-01-20',DATE '2026-12-31'),
  ('269580',DATE '2026-01-20',DATE '2026-12-19'),
  ('269774',DATE '2026-01-20',DATE '2026-12-19'),
  ('270218',DATE '2026-01-20',DATE '2026-12-31'),
  ('270480',DATE '2026-01-20',DATE '2026-03-23'),
  ('270549',DATE '2026-01-20',DATE '2026-12-19'),
  ('270611',DATE '2026-01-20',DATE '2026-06-11'),
  ('270634',DATE '2026-01-20',DATE '2026-04-14'),
  ('270695',DATE '2026-01-20',DATE '2026-12-19'),
  ('270896',DATE '2026-01-20',DATE '2026-12-19'),
  ('270961',DATE '2026-01-20',DATE '2026-12-19'),
  ('272305',DATE '2026-01-20',DATE '2026-12-19'),
  ('272692',DATE '2026-01-20',DATE '2026-04-21'),
  ('272946',DATE '2026-01-20',DATE '2026-05-30'),
  ('273006',DATE '2026-01-20',DATE '2026-12-19'),
  ('273139',DATE '2026-01-20',DATE '2026-04-18'),
  ('277570',DATE '2026-01-20',DATE '2026-12-31'),
  ('277595',DATE '2026-01-20',DATE '2026-12-31'),
  ('277596',DATE '2026-01-20',DATE '2026-03-20'),
  ('277718',DATE '2026-01-20',DATE '2026-12-19'),
  ('281787',DATE '2026-04-01',DATE '2027-03-31'),
  ('285243',DATE '2026-07-01',DATE '2027-06-30'),
  ('285254',DATE '2026-07-01',DATE '2027-06-30'),
  ('285777',DATE '2026-07-01',DATE '2027-06-30'),
  ('288274',DATE '2026-07-01',DATE '2027-06-30'),
  ('288697',DATE '2026-07-01',DATE '2027-06-30'),
  ('288761',DATE '2026-07-01',DATE '2027-06-30'),
  ('288934',DATE '2026-07-01',DATE '2027-06-30'),
  ('288999',DATE '2026-07-01',DATE '2027-06-30'),
  ('289025',DATE '2026-07-01',DATE '2027-06-30'),
  ('289081',DATE '2026-07-01',DATE '2027-06-30'),
  ('289167',DATE '2026-07-01',DATE '2027-06-30'),
  ('289429',DATE '2026-07-01',DATE '2027-06-30'),
  ('290004',DATE '2026-07-01',DATE '2027-06-30'),
  ('291120',DATE '2026-05-13',DATE '2027-06-30'),
  ('291291',DATE '2026-07-01',DATE '2027-06-30'),
  ('291346',DATE '2026-07-01',DATE '2027-06-30'),
  ('291360',DATE '2026-07-01',DATE '2027-06-30'),
  ('291365',DATE '2026-07-01',DATE '2027-06-30'),
  ('291371',DATE '2026-07-01',DATE '2027-06-30'),
  ('291513',DATE '2026-07-01',DATE '2027-06-30'),
  ('291679',DATE '2026-07-01',DATE '2027-06-30'),
  ('291889',DATE '2026-07-01',DATE '2027-06-30'),
  ('291910',DATE '2026-07-01',DATE '2027-06-30'),
  ('293483',DATE '2026-07-01',DATE '2027-06-30'),
  ('293508',DATE '2026-07-01',DATE '2027-06-30'),
  ('293887',DATE '2026-07-01',DATE '2027-06-30'),
  ('294010',DATE '2026-07-01',DATE '2027-06-30'),
  ('294671',DATE '2026-07-01',DATE '2027-06-30'),
  ('296074',DATE '2026-07-01',DATE '2027-06-30'),
  ('296132',DATE '2026-07-01',DATE '2027-06-30'),
  ('296696',DATE '2026-07-01',DATE '2027-06-30'),
  ('297142',DATE '2026-07-01',DATE '2027-06-30'),
  ('297258',DATE '2026-07-01',DATE '2027-06-30'),
  ('297310',DATE '2026-07-01',DATE '2027-06-30'),
  ('298086',DATE '2026-07-01',DATE '2027-06-30'),
  ('298301',DATE '2026-07-01',DATE '2027-06-30'),
  ('298582',DATE '2026-07-01',DATE '2027-06-30'),
  ('298761',DATE '2026-07-01',DATE '2027-06-30'),
  ('299975',DATE '2026-07-01',DATE '2027-06-30'),
  ('300011',DATE '2026-07-01',DATE '2027-06-30'),
  ('300220',DATE '2026-07-02',DATE '2027-06-30'),
  ('300230',DATE '2026-07-01',DATE '2027-06-30'),
  ('300234',DATE '2026-07-01',DATE '2027-06-30'),
  ('300397',DATE '2026-07-01',DATE '2027-06-30'),
  ('300446',DATE '2026-07-01',DATE '2027-06-30'),
  ('300448',DATE '2026-07-02',DATE '2027-06-30'),
  ('300469',DATE '2026-07-01',DATE '2027-06-30'),
  ('301116',DATE '2026-07-01',DATE '2027-06-30'),
  ('301587',DATE '2026-07-01',DATE '2027-06-30'),
  ('301701',DATE '2026-07-01',DATE '2027-06-30')
) AS v(app_id, cstart, cend)
WHERE sa.vep_application_id = v.app_id;

-- 6. Re-stamp NO-CONTRACT (rejected/pending) apps to their paved window. Approved apps have a
--    contract and are excluded (they are cohort-driven). Non-overlapping windows guarantee at most
--    one match per app. Measured live pre-apply: exactly 12 rows move (8 -> b2, 4 -> cycle3).
UPDATE public.selection_applications sa
SET cycle_id = w.id
FROM public.selection_cycles w
WHERE sa.nucleo_contract_start IS NULL
  AND sa.application_date IS NOT NULL
  AND sa.application_date >= w.open_date
  AND (w.close_date IS NULL OR sa.application_date <= w.close_date)
  AND sa.cycle_id IS DISTINCT FROM w.id;
