-- =====================================================================================
-- #704 — get_duplicate_identity_candidates: standing radar for duplicate PMI identity
--        across selection_applications (same physical person under >1 pmi_id/email/name).
--
-- WHY (grounded 2026-06-15): the application dedup key is (vep_application_id,
--   vep_opportunity_id) — per VEP ACCOUNT, never per PERSON. So one human with two PMI
--   registrations (different pmi_id + email + name) appears as independent candidates.
--   Live scan today: EXACTLY 1 confirmed case (Ana — pmi_id 8712551 ↔ 12568385). persons
--   and members are clean (0 fuzzy dups; Ana not yet onboarded → no member/person leak yet).
--   The leak would materialize at the onboarding/conversion boundary, NOT now. This RPC is
--   the RADAR so the dimension is monitored as VEP waves accumulate — it does NOT merge or
--   mutate any data (PM decision 2026-06-14: do not touch Ana's data).
--
-- DETECTION = multi-signal fuzzy match (NOT group-by-name — the anchor case has DIFFERENT
--   names per account: "Ana Pacheco" vs "Ana Sofia Pires Pacheco"):
--   * exact corroborators, name-independent → confidence HIGH:
--       same email / phone / linkedin / resume_url across DIFFERENT pmi_id.
--   * fuzzy name (pmi_id distinct AND email distinct):
--       same first+last normalized token (len>2)              → 'fuzzy_name_strong' (HIGH)
--       trigram similarity(name) >= 0.55                       → 'fuzzy_name'        (MEDIUM)
--   Name normalization: lower + manual unaccent (translate) + strip non-alpha. Mirrors the
--   live grounding query that produced the n=1 dimension. The 0.35–0.45 tail (coincidental
--   BR surnames: Pimenta/Vidal, Oliveira/Silva variants) is deliberately EXCLUDED.
--
-- AUTHORITY: can_by_member(caller,'manage_member'). Identity reconciliation / dedup is
--   member-lifecycle work; manage_member is the authority that already reads every
--   application via admin surfaces, so this surfaces ZERO new PII to a new audience.
--   No new seed in engagement_kind_permissions (anti-pattern; V4_AUTHORITY_MODEL.md).
--
-- LGPD Art. 37 logging DEFERRED — same rationale as the other selection readers
--   (track_q_d batch3a1, 2026-04-26): log_pii_access expects MEMBER ids, but applicants are
--   PRE-MEMBER. The manage_member gate is the access control; nominal application reads are
--   not member-PII reads. (Future: an applicant-scoped audit trail, out of scope for #704.)
--
-- NOT STABLE in practice (reads mutable selection_applications) — left VOLATILE (default).
-- ROLLBACK: DROP FUNCTION IF EXISTS public.get_duplicate_identity_candidates();
-- =====================================================================================

-- similarity()/trigram dependency — idempotent, already present on the live project; declared
-- here so a fresh local stack (supabase start) resolves similarity() without manual setup.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE OR REPLACE FUNCTION public.get_duplicate_identity_candidates()
RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result    jsonb;
BEGIN
  -- Auth-resolve + V4 gate (canonical can_by_member, ADR-0007).
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires member-management authority';
  END IF;

  WITH n AS (
    SELECT
      a.id,
      a.pmi_id,
      a.applicant_name,
      a.status,
      a.vep_application_id,
      a.vep_opportunity_id,
      lower(trim(a.email))                                                       AS email_n,
      nullif(trim(a.phone),'')                                                   AS phone_n,
      lower(nullif(trim(coalesce(a.linkedin_url, a.profile_linkedin_url)),''))   AS li_n,
      nullif(trim(a.resume_url),'')                                              AS resume_n,
      regexp_replace(
        translate(lower(trim(coalesce(a.applicant_name, a.first_name||' '||a.last_name))),
          'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),
        '[^a-z ]+',' ','g')                                                      AS name_n
    FROM public.selection_applications a
  ), n2 AS (
    SELECT *,
      (regexp_split_to_array(btrim(name_n),'\s+'))[1]                                              AS first_tok,
      (regexp_split_to_array(btrim(name_n),'\s+'))[array_length(regexp_split_to_array(btrim(name_n),'\s+'),1)] AS last_tok
    FROM n
  ), raw_pairs AS (
    -- exact corroborators (name-independent) — HIGH confidence
    SELECT a.id AS a_id, b.id AS b_id, 'exact_email'::text AS sig, 1.0::numeric AS sim
      FROM n2 a JOIN n2 b ON a.id < b.id
      WHERE a.email_n = b.email_n AND coalesce(a.pmi_id,'∅') <> coalesce(b.pmi_id,'∅')
    UNION ALL
    SELECT a.id, b.id, 'exact_phone', 1.0 FROM n2 a JOIN n2 b ON a.id < b.id
      WHERE a.phone_n = b.phone_n AND coalesce(a.pmi_id,'∅') <> coalesce(b.pmi_id,'∅')
    UNION ALL
    SELECT a.id, b.id, 'exact_linkedin', 1.0 FROM n2 a JOIN n2 b ON a.id < b.id
      WHERE a.li_n = b.li_n AND coalesce(a.pmi_id,'∅') <> coalesce(b.pmi_id,'∅')
    UNION ALL
    SELECT a.id, b.id, 'exact_resume', 1.0 FROM n2 a JOIN n2 b ON a.id < b.id
      WHERE a.resume_n = b.resume_n AND coalesce(a.pmi_id,'∅') <> coalesce(b.pmi_id,'∅')
    UNION ALL
    -- fuzzy name (pmi_id distinct AND email distinct)
    SELECT a.id, b.id,
      CASE WHEN a.first_tok = b.first_tok AND a.last_tok = b.last_tok AND length(a.last_tok) > 2
           THEN 'fuzzy_name_strong' ELSE 'fuzzy_name' END,
      round(similarity(a.name_n, b.name_n)::numeric, 3)
    FROM n2 a JOIN n2 b ON a.id < b.id
    WHERE coalesce(a.pmi_id,'∅') <> coalesce(b.pmi_id,'∅')
      AND a.email_n <> b.email_n
      AND ( (a.first_tok = b.first_tok AND a.last_tok = b.last_tok AND length(a.last_tok) > 2)
            OR similarity(a.name_n, b.name_n) >= 0.55 )
  ), agg AS (
    SELECT a_id, b_id,
      array_agg(DISTINCT sig ORDER BY sig)                          AS signals,
      max(sim)                                                      AS top_sim,
      bool_or(sig LIKE 'exact_%' OR sig = 'fuzzy_name_strong')      AS is_high
    FROM raw_pairs GROUP BY a_id, b_id
  )
  SELECT jsonb_build_object(
    'generated_at',       now(),
    'total_applications', (SELECT count(*) FROM public.selection_applications),
    'count',              (SELECT count(*) FROM agg),
    'candidate_pairs', COALESCE(jsonb_agg(jsonb_build_object(
        'confidence',      CASE WHEN g.is_high THEN 'high' ELSE 'medium' END,
        'signals',         to_jsonb(g.signals),
        'name_similarity', g.top_sim,
        'a', jsonb_build_object(
               'application_id', na.id, 'name', na.applicant_name, 'email', na.email_n,
               'pmi_id', na.pmi_id, 'status', na.status,
               'vep_application_id', na.vep_application_id, 'vep_opportunity_id', na.vep_opportunity_id),
        'b', jsonb_build_object(
               'application_id', nb.id, 'name', nb.applicant_name, 'email', nb.email_n,
               'pmi_id', nb.pmi_id, 'status', nb.status,
               'vep_application_id', nb.vep_application_id, 'vep_opportunity_id', nb.vep_opportunity_id)
      ) ORDER BY g.is_high DESC, g.top_sim DESC), '[]'::jsonb)
  ) INTO v_result
  FROM agg g
  JOIN n2 na ON na.id = g.a_id
  JOIN n2 nb ON nb.id = g.b_id;

  RETURN v_result;
END; $function$;

-- Lock down: SECDEF radar exposing candidate identity. anon never; authenticated EXECUTE is
-- gated by the in-function can_by_member check (RAISE on non-manager) — the canonical pattern.
REVOKE ALL ON FUNCTION public.get_duplicate_identity_candidates() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_duplicate_identity_candidates() TO authenticated;

COMMENT ON FUNCTION public.get_duplicate_identity_candidates() IS
  '#704 radar: multi-signal fuzzy scan of selection_applications for duplicate PMI identity '
  '(same person, distinct pmi_id). Read-only, manage_member-gated. Does not merge/mutate data.';
