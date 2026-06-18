-- #106 PR1 — chapter dashboard: cycle bug fix + by_tribe snapshot + movements 30d
--
-- LGPD (Bloco 2 — movimentações 30d): legal-counsel GO-with-conditions (2026-06-18).
--   Controlador: Núcleo IA (PMI-GO). Finalidade: gestão operacional de capítulo voluntário
--   pelo gestor own-chapter. Base legal: Art. 7, IX LGPD (legítimo interesse) + Art. 10
--   (proporcionalidade). Minimização (Art. 6, III): projeta SÓ reason_category_code
--   NEUTRALIZADO (health/policy_violation → 'other', pois revelam Art. 11/conduta disciplinar;
--   GP vê o motivo real via get_offboarding_dashboard, surface restrita) + nome + data +
--   return_interest; NÃO projeta texto livre (reason_detail/exit_interview_full_text/
--   lessons_learned/recommendation_for_future/attachment_urls). Exclui anonimizados
--   (anonymized_at IS NOT NULL — Art. 18, IV). SECDEF own-chapter gate; nenhum acesso anônimo.
--
-- Council: product-leader + ux-leader + data-architect GO-with-changes (SPEC_106_CHAPTER_DASHBOARD.md).

-- Índices compostos para os filtros do bloco de movimentações (data-architect).
CREATE INDEX IF NOT EXISTS idx_offboarding_chapter_at
  ON public.member_offboarding_records (chapter_at_offboard, offboarded_at DESC)
  WHERE chapter_at_offboard IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_members_chapter_created_at
  ON public.members (chapter, created_at DESC)
  WHERE chapter IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_chapter_dashboard(p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_chapter text;
  v_result jsonb;
  v_hub_members int;
  v_hub_avg_xp numeric;
  v_hub_certs int;
  v_ch_members int;
  v_current_cycle record;
BEGIN
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (Path Y per ADR-0030 precedent):
  -- Cross-chapter institutional access OR own-chapter member access
  IF public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  ELSIF p_chapter IS NULL OR p_chapter = v_caller_chapter THEN
    v_chapter := v_caller_chapter;
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF v_chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter specified');
  END IF;

  -- #106 PR1 bug fix: derive the current cycle from cycles.is_current (was hardcoded 'cycle', 3).
  SELECT cycle_code, cycle_label INTO v_current_cycle
  FROM public.cycles WHERE is_current = true LIMIT 1;

  SELECT count(*) INTO v_hub_members FROM public.members WHERE is_active AND current_cycle_active;
  SELECT count(*) INTO v_ch_members FROM public.members WHERE chapter = v_chapter AND is_active;
  SELECT COALESCE(avg(t.xp), 0) INTO v_hub_avg_xp FROM (SELECT sum(points) AS xp FROM public.gamification_points GROUP BY member_id) t;
  SELECT count(*) INTO v_hub_certs FROM public.gamification_points WHERE category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry');

  SELECT jsonb_build_object(
    'chapter', v_chapter,
    'cycle', v_current_cycle.cycle_label,
    'cycle_code', v_current_cycle.cycle_code,
    'cycle_label', v_current_cycle.cycle_label,
    'people', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE member_status = 'active'),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'hub_total', v_hub_members,
      'by_role', (SELECT jsonb_object_agg(role, cnt) FROM (SELECT operational_role AS role, count(*) AS cnt FROM public.members WHERE chapter = v_chapter AND member_status = 'active' GROUP BY operational_role) r),
      -- #106 PR1 Bloco 1: snapshot por tribo. Bucket '__none__' p/ membros sem tribo (ux R6);
      -- sum(by_tribe) == active (invariante de display checada no contrato).
      'by_tribe', (SELECT jsonb_object_agg(COALESCE(tname, '__none__'), cnt) FROM (
        SELECT tr.name AS tname, count(*) AS cnt
        FROM public.members m2
        LEFT JOIN public.tribes tr ON tr.id = m2.tribe_id
        WHERE m2.chapter = v_chapter AND m2.member_status = 'active'
        GROUP BY tr.name
      ) bt)
    ) FROM public.members WHERE chapter = v_chapter),
    'output', jsonb_build_object(
      'board_cards_completed', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_assignments bia ON bia.item_id = bi.id JOIN public.members m ON m.id = bia.member_id WHERE m.chapter = v_chapter AND bi.status = 'done'),
      'publications_submitted', (SELECT count(*) FROM public.publication_submissions ps JOIN public.members m ON m.id = ps.primary_author_id WHERE m.chapter = v_chapter)
    ),
    -- p277 #419 m3 PR5b: chapter attendance = canonical engagement (headline, Participacao) + reliability
    -- (ops diagnostic, raw counts). Chapter cohort = member_status='active' (carve-out KEPT). The volume
    -- helpers now share the {geral,kickoff,tribo,lideranca} type set + the cycles.is_current window (was a
    -- 90-day rolling window with no type filter — leaked entrevista/1on1/parceria/iniciativa).
    'attendance', jsonb_build_object(
      'engagement', public.get_attendance_engagement_summary('chapter', NULL, NULL, v_chapter),
      'reliability', public.get_attendance_reliability_summary('chapter', NULL, NULL, v_chapter),
      'hub_engagement_pct', ROUND(COALESCE((public.get_attendance_engagement_summary('global') ->> 'avg_rate')::numeric, 0) * 100, 1),
      'avg_events_per_member', (SELECT ROUND(COUNT(a.id)::numeric / NULLIF(v_ch_members, 0), 1) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.type IN ('geral','kickoff','tribo','lideranca') AND e.status IS DISTINCT FROM 'cancelled' AND e.date >= (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1)),
      'total_events_attended', (SELECT COUNT(a.id) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.type IN ('geral','kickoff','tribo','lideranca') AND e.status IS DISTINCT FROM 'cancelled' AND e.date >= (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1))
    ),
    'hours', (SELECT jsonb_build_object(
      'total_hours', COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0),
      'pdu_equivalent', LEAST(COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0), 25)
    ) FROM public.attendance a JOIN public.events e ON e.id = a.event_id JOIN public.members m ON m.id = a.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'certifications', (SELECT jsonb_build_object(
      'pmp', count(*) FILTER (WHERE gp.category = 'cert_pmi_senior'),
      'cpmai', count(*) FILTER (WHERE gp.category = 'cert_cpmai'),
      'total_certs', count(*) FILTER (WHERE gp.category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry')),
      'hub_total_certs', v_hub_certs
    ) FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'partnerships', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE pe.status = 'active'),
      'negotiation', count(*) FILTER (WHERE pe.status = 'negotiation'),
      'total', count(*)
    ) FROM public.partner_entities pe WHERE pe.chapter = v_chapter),
    'gamification', (SELECT jsonb_build_object(
      'avg_xp', COALESCE(round(avg(total_xp)), 0),
      'hub_avg_xp', round(v_hub_avg_xp),
      'top_contributors', (SELECT jsonb_agg(row_to_json(tc) ORDER BY tc.total_xp DESC) FROM (
        SELECT m.name, m.photo_url, sum(gp.points) AS total_xp
        FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id
        WHERE m.chapter = v_chapter AND m.member_status = 'active'
        GROUP BY m.id, m.name, m.photo_url
        ORDER BY total_xp DESC LIMIT 3
      ) tc)
    ) FROM (SELECT sum(gp.points) AS total_xp FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active' GROUP BY gp.member_id) t),
    'members', (SELECT jsonb_agg(row_to_json(ml) ORDER BY ml.total_xp DESC) FROM (
      SELECT m.id, m.name, m.photo_url, m.operational_role, m.designations,
        COALESCE((SELECT sum(points) FROM public.gamification_points WHERE member_id = m.id), 0) AS total_xp,
        COALESCE(ROUND(public.get_attendance_engagement_rate(m.id) * 100), 0) AS attendance_pct,
        (SELECT count(*) FROM public.gamification_points WHERE member_id = m.id AND category = 'trail') AS trail_count
      FROM public.members m WHERE m.chapter = v_chapter AND m.member_status = 'active'
    ) ml),
    -- #106 PR1 Bloco 2: movimentações 30d. LGPD ver header. Entradas = members.created_at 30d;
    -- saídas = member_offboarding_records (chapter_at_offboard snapshot) c/ categoria neutralizada.
    'movements', jsonb_build_object(
      'joined_30d', (SELECT count(*) FROM public.members m WHERE m.chapter = v_chapter AND m.created_at >= now() - interval '30 days' AND m.anonymized_at IS NULL),
      'left_30d', (SELECT count(*) FROM public.member_offboarding_records r JOIN public.members m ON m.id = r.member_id WHERE r.chapter_at_offboard = v_chapter AND r.offboarded_at >= now() - interval '30 days' AND m.anonymized_at IS NULL),
      'entries', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', m.name, 'created_at', m.created_at, 'operational_role', m.operational_role) ORDER BY m.created_at DESC), '[]'::jsonb)
        FROM public.members m WHERE m.chapter = v_chapter AND m.created_at >= now() - interval '30 days' AND m.anonymized_at IS NULL),
      'exits', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'name', m.name,
          'offboarded_at', r.offboarded_at,
          'reason_code', CASE WHEN r.reason_category_code IN ('health','policy_violation') THEN 'other' ELSE COALESCE(r.reason_category_code, 'other') END,
          'return_interest', r.return_interest
        ) ORDER BY r.offboarded_at DESC), '[]'::jsonb)
        FROM public.member_offboarding_records r JOIN public.members m ON m.id = r.member_id
        WHERE r.chapter_at_offboard = v_chapter AND r.offboarded_at >= now() - interval '30 days' AND m.anonymized_at IS NULL)
    ),
    'available_chapters', (SELECT jsonb_agg(DISTINCT m.chapter ORDER BY m.chapter) FROM public.members m WHERE m.chapter IS NOT NULL AND m.member_status = 'active')
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- Replayability (CREATE OR REPLACE preserves grants on the live DB; explicit for a fresh replay).
GRANT EXECUTE ON FUNCTION public.get_chapter_dashboard(text) TO authenticated;

-- ROLLBACK: CREATE OR REPLACE FUNCTION public.get_chapter_dashboard restoring the prior body
-- (mig 20260805000072); DROP INDEX idx_offboarding_chapter_at, idx_members_chapter_created_at.
