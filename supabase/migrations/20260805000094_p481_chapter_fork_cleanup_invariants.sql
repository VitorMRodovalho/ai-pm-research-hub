-- ════════════════════════════════════════════════════════════════
-- #481 — finish the chapter-metric fork cleanup (follow-up to #479 / PR #480)
-- ════════════════════════════════════════════════════════════════
-- #479 made get_chapter_metrics() the canonical chapter source and repointed the
-- 4 RENDERED surfaces. The council review (code-reviewer + data-architect) flagged
-- the systemic completeness gaps this migration closes:
--
--   1. The 3 UNRENDERED chapter RPCs still read count(DISTINCT members.chapter)=7
--      (noise-prone: Outro / PMI-SP) → repoint to get_chapter_metrics()->>'signed'=5.
--   2. partner_entities had no geography column, so get_chapter_metrics excluded the
--      international PMI-WDC by a brittle name ILIKE '%washington%' match. Add an explicit
--      is_international flag, backfill PMI-WDC, switch the helper to NOT is_international.
--   3. Two new schema invariants: Y_chapter_pipeline_parity + Z_webinar_status_domain.
--   4. get_public_impact_data.chapters_summary still enumerated members.chapter (7 rows incl
--      noise) while the headline read partner_entities (5). Unify the grid onto the 5 signed
--      chapters (PII-neutral: the 2 dropped noise rows had null sponsor; the 5 public chapter
--      ambassador names — same class as the leader/author names this RPC already publishes —
--      are unchanged). Also fold the 2 inline get_chapter_metrics() calls into one local.
--   5. get_cycle_evolution per-cycle chapter literals documented as editorial point-in-time
--      history (COMMENT ON FUNCTION; no body change — they are not the current canonical metric).
--
-- Live antes → depois (grounded 2026-06-02):
--   get_homepage_stats.chapters         7 → 5
--   get_public_platform_stats.total_chapters 7 → 5
--   get_executive_kpis.chapters         7 → 5
--   get_public_impact_data.chapters_summary  7 rows → 5 rows (signed only)
--   get_chapter_metrics()               {5,10,15} unchanged (is_international ≡ name match today)
--
-- NOTE: get_admin_dashboard's 3x inline get_chapter_metrics() call (perf code-smell, "low",
--   negligible at 16 rows per #481 item 5) is DEFERRED — rewriting a 7.2k-char rendered
--   surface for ~zero perf gain is pure regression risk; tracked as a remaining #481 note.
--
-- ROLLBACK: re-apply migration 20260805000093 (get_chapter_metrics with %washington% match;
--   3 unrendered RPCs on count(DISTINCT chapter); chapters_summary on members.chapter) and
--   20260805000077 (check_schema_invariants without Y/Z), then
--   ALTER TABLE public.partner_entities DROP COLUMN is_international.
-- ════════════════════════════════════════════════════════════════

-- ── 1. partner_entities.is_international (retire the %washington% name-match) ──
ALTER TABLE public.partner_entities
  ADD COLUMN IF NOT EXISTS is_international boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.partner_entities.is_international IS
  'TRUE for chapters/partners outside Brazil (e.g. PMI-WDC Washington DC). Excluded from get_chapter_metrics in_negotiation/engaged (which report BR figures). Retires the brittle name ILIKE ''%washington%'' match — #481.';

UPDATE public.partner_entities
  SET is_international = true
  WHERE entity_type = 'pmi_chapter' AND name ILIKE '%washington%';

-- ── 2. get_chapter_metrics: is_international flag instead of name-match ──
CREATE OR REPLACE FUNCTION public.get_chapter_metrics()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- #479 canonical chapter metrics. Source = partner_entities (entity_type='pmi_chapter').
  -- #481: ALL THREE counts are domestic (Brazilian) — international chapters (e.g. PMI-WDC) excluded via the
  --   explicit is_international flag (was a brittle name ILIKE '%washington%' match). The filter is applied to
  --   signed too (not just in_negotiation/engaged) so the identity engaged == signed + in_negotiation stays exact
  --   even if an international chapter is ever onboarded to status='active' (council review: code-reviewer + data-architect).
  --   signed=domestic active ; in_negotiation=domestic negotiation ; engaged=signed+in_negotiation.
  --   Live 2026-06-02: signed=5, in_negotiation=10, engaged=15.
  SELECT jsonb_build_object(
    'signed', (SELECT count(*)::int FROM public.partner_entities WHERE entity_type = 'pmi_chapter' AND status = 'active' AND NOT COALESCE(is_international, false)),
    'in_negotiation', (SELECT count(*)::int FROM public.partner_entities WHERE entity_type = 'pmi_chapter' AND status = 'negotiation' AND NOT COALESCE(is_international, false)),
    'engaged', (SELECT count(*)::int FROM public.partner_entities WHERE entity_type = 'pmi_chapter' AND status IN ('active', 'negotiation') AND NOT COALESCE(is_international, false))
  );
$function$;

-- #481 (security review): re-state the grant ladder so this migration is self-contained on rollback
-- (CREATE OR REPLACE preserves grants, so this is idempotent on the sequential deploy path).
REVOKE ALL ON FUNCTION public.get_chapter_metrics() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_chapter_metrics() TO anon, authenticated, service_role;

-- ── 3. Repoint the 3 UNRENDERED chapter RPCs onto get_chapter_metrics()->>'signed' ──

CREATE OR REPLACE FUNCTION public.get_homepage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    -- #481: canonical signed-chapter count (was count(DISTINCT members.chapter)=7 incl noise)
    'chapters', (public.get_chapter_metrics()->>'signed')::int,
    -- ADR-0100 #419 metric 1: impact_hours = the single canonical source (was an inline 4th formula).
    -- round() keeps the hero's integer display; cycle_report reads this value and auto-converges.
    'impact_hours', round(public.get_impact_hours_canonical())
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    'active_members', (SELECT COUNT(*) FROM members WHERE is_active AND current_cycle_active),
    'total_tribes', (SELECT COUNT(*) FROM tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    -- #481: canonical signed-chapter count (was count(DISTINCT chapter) WHERE chapter != 'Externo'=7; the
    -- !='Externo' filter was a no-op since no member carries chapter='Externo').
    'total_chapters', (public.get_chapter_metrics()->>'signed')::int,
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-01-01'),
    'total_resources', (SELECT COUNT(*) FROM hub_resources WHERE is_active),
    'retention_rate', (
      SELECT ROUND(
        COUNT(*) FILTER (WHERE current_cycle_active)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE is_active OR member_status = 'alumni'), 0) * 100, 1
      )
      FROM members WHERE member_status IN ('active','alumni','observer')
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_executive_kpis()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_total_active INT; v_total_verified INT; v_multi_cycle INT;
  v_retention_pct NUMERIC; v_total_artifacts INT; v_total_tribes INT;
  v_avg_per_tribe NUMERIC; v_chapters INT;
BEGIN
  SELECT COUNT(*) INTO v_total_active FROM members WHERE is_active = true AND current_cycle_active = true;
  SELECT COUNT(*) INTO v_total_verified FROM members WHERE pmi_id_verified = true AND COALESCE(current_cycle_active, is_active, false) = true;
  SELECT COUNT(*) INTO v_multi_cycle FROM members WHERE is_active = true AND current_cycle_active = true AND array_length(cycles, 1) > 1;
  IF v_total_active > 0 THEN v_retention_pct := ROUND((v_multi_cycle::NUMERIC / v_total_active) * 100, 1); ELSE v_retention_pct := 0; END IF;

  -- ADR-0012 archival: publication_submissions (ex-artifacts)
  SELECT COUNT(*) INTO v_total_artifacts FROM publication_submissions WHERE status = 'published'::submission_status;

  SELECT COUNT(*) INTO v_total_tribes FROM tribes WHERE is_active = true;
  IF v_total_tribes > 0 THEN
    SELECT ROUND(AVG(cnt), 1) INTO v_avg_per_tribe FROM (
      SELECT COUNT(*) AS cnt FROM members
      WHERE tribe_id IS NOT NULL AND COALESCE(current_cycle_active, is_active, false) = true
      GROUP BY tribe_id) sub;
  ELSE v_avg_per_tribe := 0; END IF;

  -- #481: canonical signed-chapter count (was COUNT(DISTINCT members.chapter)=7 incl noise)
  v_chapters := (public.get_chapter_metrics()->>'signed')::int;

  RETURN json_build_object(
    'total_active', v_total_active, 'pmi_verified', v_total_verified,
    'multi_cycle', v_multi_cycle, 'retention_pct', v_retention_pct,
    'published_artifacts', v_total_artifacts, 'active_tribes', v_total_tribes,
    'avg_per_tribe', v_avg_per_tribe, 'chapters', v_chapters
  );
END;
$function$;

-- ── 4. get_public_impact_data: chapters_summary → partner_entities (5 signed) + perf fold ──
CREATE OR REPLACE FUNCTION public.get_public_impact_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_chapters jsonb := public.get_chapter_metrics();  -- #481: fold 2 inline calls into one local
BEGIN
  SELECT jsonb_build_object(
    'chapters', (v_chapters->>'signed')::int,
    'chapters_engaged', (v_chapters->>'engaged')::int,
    'active_members', (SELECT COUNT(*) FROM members WHERE is_active = true AND current_cycle_active = true),
    'tribes', (SELECT COUNT(*) FROM tribes),
    'articles_published', (SELECT COUNT(*) FROM public_publications WHERE is_published = true),
    'articles_approved', (
      SELECT COUNT(*) FROM board_lifecycle_events WHERE action = 'curation_review' AND new_status = 'approved'
    ),
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-03-01'),
    'total_attendance_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE e.date >= '2026-03-01'
    ),
    'impact_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
    ),
    'webinars', public.get_webinars_count(NULL, NULL, 'realized'),
    'ia_pilots', (SELECT COUNT(*) FROM ia_pilots WHERE status IN ('active','completed')),
    'partner_count', (SELECT COUNT(*) FROM partner_entities WHERE status = 'active'),
    'courses_count', (SELECT COUNT(*) FROM courses),
    'recent_publications', COALESCE((
      SELECT jsonb_agg(sub ORDER BY sub.publication_date DESC NULLS LAST)
      FROM (SELECT title, authors, external_platform AS platform, publication_date, external_url
            FROM public_publications WHERE is_published = true
            ORDER BY publication_date DESC NULLS LAST LIMIT 5) sub
    ), '[]'::jsonb),
    'tribes_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'quadrant_name', t.quadrant_name,
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active),
        'leader_name', (SELECT name FROM members WHERE id = t.leader_member_id)
      ) ORDER BY t.id)
      FROM tribes t
    ), '[]'::jsonb),
    -- #481: chapters_summary is the 5 SIGNED chapters (partner_entities), matching the headline + the
    -- 5-column grid. Was members.chapter (7 rows incl noise Outro/PMI-SP). member_count/sponsor still come
    -- from members (distribution), filtered to the signed chapter names. PII-neutral: dropped rows had null
    -- sponsor; the 5 sponsor names are public chapter ambassadors (same class as the leader_name above).
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'chapter', pe.name,
          'member_count', (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active),
          'sponsor', (SELECT ms.name FROM members ms WHERE ms.chapter = pe.name AND 'sponsor' = ANY(ms.designations) AND ms.is_active LIMIT 1)
        )
        ORDER BY (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active) DESC, pe.name
      )
      FROM partner_entities pe
      WHERE pe.entity_type = 'pmi_chapter' AND pe.status = 'active' AND NOT COALESCE(pe.is_international, false)
    ), '[]'::jsonb),
    'partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'type', entity_type, 'status', status))
      FROM partner_entities WHERE status = 'active'
    ), '[]'::jsonb),
    'recognitions', jsonb_build_array(
      jsonb_build_object(
        'title', 'Finalista — Prêmio "Carlos Novello" Voluntário do Ano',
        'organization', 'PMI LATAM Excellence Awards 2025',
        'recipient', 'Vitor Maia Rodovalho (GP)',
        'date', '2026-02-26',
        'category', 'Volunteer of the Year — LATAM Brasil',
        'description', 'Nomeado pelo PMI Goiás pelo trabalho à frente do Núcleo de IA & GP'
      )
    ),
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Patrocínio Ivan Lourenço. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026', 'title', 'Escala', 'description', '44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado.')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ── 5. get_cycle_evolution: document the per-cycle chapter literals as editorial history ──
-- The literals (pilot=1, cycle_1=2, cycle_2=2, cycle_3=5) are point-in-time snapshots of how many
-- chapters were partnered AT each cycle — NOT the current canonical get_chapter_metrics() count, which
-- reports only "now". cycle_3=5 aligns with the current signed count (5). Documented (not rewritten):
-- deriving historical counts from partner_entities.partnership_date is a larger change out of #481 scope.
COMMENT ON FUNCTION public.get_cycle_evolution() IS
  'Per-cycle evolution narrative. The chapters/tribes/members literals per cycle are EDITORIAL point-in-time history (how many existed at that cycle), NOT the canonical current get_chapter_metrics() value. cycle_3 chapters=5 matches the current signed count. Reconcile via partner_entities.partnership_date only if a future cycle needs derived history (#481 item 6).';

-- ── 6. check_schema_invariants: + Y_chapter_pipeline_parity, Z_webinar_status_domain ──
-- Full body sourced verbatim from migration 20260805000077 (latest definition; A1..X byte-identical,
-- Phase-C parity verified there); appends two #481 invariants before END.
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.member_emails me WHERE lower(me.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT p.id AS parecer_id
    FROM public.blind_review_pareceres p
    WHERE NOT EXISTS (
      SELECT 1 FROM public.blind_review_assignments a
      WHERE a.session_id = p.session_id
        AND a.reviewer_member_id = p.reviewer_member_id
        AND a.status = 'active'
    )
  )
  SELECT 'X_blind_review_pareceres_session_product_match'::text,
         'blind_review_pareceres.reviewer_member_id must have an active blind_review_assignments row in the same session (assignment-parecer integrity; ADR-0099 §2.7 + §7 step 11). Defense-in-depth complement to FK constraints; catches drift if assignment is withdrawn while parecer remains. #382 PR-B.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(parecer_id ORDER BY parecer_id) FROM (SELECT parecer_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH pe AS (
    SELECT name AS k FROM public.partner_entities
    WHERE entity_type = 'pmi_chapter' AND status = 'active' AND NOT COALESCE(is_international, false)
  ),
  ch AS (
    SELECT 'PMI-' || code AS k FROM public.chapters WHERE status = 'active'
  ),
  drift AS (
    SELECT k FROM pe WHERE k NOT IN (SELECT k FROM ch)
    UNION ALL
    SELECT k FROM ch WHERE k NOT IN (SELECT k FROM pe)
  )
  SELECT 'Y_chapter_pipeline_parity'::text,
         'every active domestic pmi_chapter in partner_entities must have a matching active chapters row (by name = ''PMI-'' || chapters.code) and vice-versa — MEMBERSHIP parity (not just count), so it catches single-table inserts/archives even when row counts coincide. Drift = get_chapter_metrics()->>signed forks from the V4 chapters table (#481).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS webinar_id FROM public.webinars
    WHERE status IS NULL OR status NOT IN ('planned','confirmed','completed','cancelled')
  )
  SELECT 'Z_webinar_status_domain'::text,
         'webinars.status must be within planned|confirmed|completed|cancelled (the realized=completed canonical definition depends on it; defense-in-depth complement to webinars_status_check — #479/#481).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(webinar_id ORDER BY webinar_id) FROM (SELECT webinar_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

NOTIFY pgrst, 'reload schema';

-- Sanity: the two new invariants must report 0 violations at deploy (live parity holds).
DO $sanity$
DECLARE v_y integer; v_z integer;
BEGIN
  SELECT violation_count INTO v_y FROM public.check_schema_invariants() WHERE invariant_name = 'Y_chapter_pipeline_parity';
  SELECT violation_count INTO v_z FROM public.check_schema_invariants() WHERE invariant_name = 'Z_webinar_status_domain';
  IF v_y IS DISTINCT FROM 0 THEN RAISE EXCEPTION '#481 Y_chapter_pipeline_parity reports % violation(s) post-apply', v_y; END IF;
  IF v_z IS DISTINCT FROM 0 THEN RAISE EXCEPTION '#481 Z_webinar_status_domain reports % violation(s) post-apply', v_z; END IF;
END
$sanity$;
