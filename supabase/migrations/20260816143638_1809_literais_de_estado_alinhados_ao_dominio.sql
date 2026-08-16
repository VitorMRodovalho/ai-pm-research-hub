-- #1809 — literais de estado alinhados ao dominio do CHECK (a metade de nome COMPARTILHADO)
--
-- Continuacao do #1805, que fechou as colunas de estado de dono UNICO e deixou declaradamente
-- aberta a metade cujo nome pertence a varias tabelas. Aqui o alias e resolvido POR CONSULTA
-- (que tabelas com aquela coluna o corpo referencia; exatamente uma = resolvivel), nao por regex.
--
-- Nenhum corpo foi transcrito: cada funcao foi extraida da sua captura no repositorio, provada
-- identica ao corpo vivo por md5 normalizado, editada como arquivo e concatenada aqui.

-- 1. visitor_leads: o dominio nunca mudou.
-- A tabela nasceu em 20260319100033 com CHECK inline, que o Postgres nomeia
-- visitor_leads_status_check sozinho. A ARM-1 (20260516890000) tentou trocar o dominio com
-- ADD CONSTRAINT usando ESSE MESMO nome: bateu duplicate_object, e o proprio handler
-- "WHEN duplicate_object THEN NULL" — escrito para dar idempotencia — engoliu a mudanca.
-- Resultado: promote_lead_to_application e dismiss_visitor_lead falhavam em TODA chamada, e
-- auto_promote_eligible_leads_for_cycle falhava por lead dentro do EXCEPTION WHEN OTHERS,
-- desfazendo junto a candidatura recem-inserida. Zero eventos visitor_lead.* no audit log.
-- DROP + ADD (e nao ADD isolado) e o que faz a troca de dominio acontecer de fato.
ALTER TABLE public.visitor_leads DROP CONSTRAINT IF EXISTS visitor_leads_status_check;
ALTER TABLE public.visitor_leads
  ADD CONSTRAINT visitor_leads_status_check
  CHECK (status IS NULL OR status IN ('new','contacted','promoted','dismissed'));

-- 2. get_tribe_credly_status: lia certificates.type/status, mas os badges vivem em
-- members.credly_badges (jsonb). O dominio de certificates.type nao tem trail/cpmai/
-- cert_pmi_senior, e nenhuma linha jamais teve: os tres contadores valiam ZERO.
-- As categorias vem da EF verify-credly, que e quem escreve ('trail', 'cert_cpmai',
-- 'cert_pmi_senior'). Semantica de presenca preservada do original.
CREATE OR REPLACE FUNCTION public.get_tribe_credly_status(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_total int;
  v_with_credly int;
  v_trail_completed int;
  v_cpmai_certified int;
  v_pmi_senior int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_is_admin
     AND NOT (v_caller_role = 'tribe_leader' AND v_caller_tribe = p_tribe_id)
     AND v_caller_tribe IS DISTINCT FROM p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE m.credly_url IS NOT NULL AND length(trim(m.credly_url)) > 0)
  INTO v_total, v_with_credly
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id AND m.member_status = 'active';

  SELECT
    count(DISTINCT m.id) FILTER (WHERE b.value->>'category' = 'trail'),
    count(DISTINCT m.id) FILTER (WHERE b.value->>'category' = 'cert_cpmai'),
    count(DISTINCT m.id) FILTER (WHERE b.value->>'category' = 'cert_pmi_senior')
  INTO v_trail_completed, v_cpmai_certified, v_pmi_senior
  FROM public.members m
  CROSS JOIN LATERAL jsonb_array_elements(COALESCE(m.credly_badges, '[]'::jsonb)) AS b(value)
  WHERE m.tribe_id = p_tribe_id AND m.member_status = 'active';

  RETURN jsonb_build_object(
    'tribe_id', p_tribe_id,
    'members_total', coalesce(v_total, 0),
    'members_with_credly_linked', coalesce(v_with_credly, 0),
    'credly_link_rate', CASE WHEN v_total > 0 THEN ROUND(v_with_credly::numeric / v_total, 2) ELSE 0 END,
    'trail_completed_count', coalesce(v_trail_completed, 0),
    'trail_completion_rate', CASE WHEN v_total > 0 THEN ROUND(v_trail_completed::numeric / v_total, 2) ELSE 0 END,
    'cpmai_certified_count', coalesce(v_cpmai_certified, 0),
    'pmi_senior_count', coalesce(v_pmi_senior, 0),
    'fetched_at', now()
  );
END;
$$;

-- 3. get_tribe_members_with_credly: mesma troca de fonte.
CREATE OR REPLACE FUNCTION public.get_tribe_members_with_credly(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');

  -- Permission: admin (any) OR tribe_leader of own tribe OR researcher in own tribe (sumarizado)
  IF NOT v_is_admin
     AND NOT (v_caller_role = 'tribe_leader' AND v_caller_tribe = p_tribe_id)
     AND v_caller_tribe IS DISTINCT FROM p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized: TL of tribe or admin required');
  END IF;

  WITH tribe_members AS (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations, m.chapter,
      m.member_status, m.is_active, m.person_id,
      m.credly_url,
      m.credly_verified_at,
      m.tribe_id,
      m.current_cycle_active
    FROM public.members m
    WHERE m.tribe_id = p_tribe_id
      AND m.member_status = 'active'
  ),
  badges AS (
    SELECT
      m.id AS member_id,
      count(*) FILTER (WHERE b.value->>'category' = 'trail') AS trail_count,
      bool_or(b.value->>'category' = 'trail') AS trail_completed,
      bool_or(b.value->>'category' = 'cert_pmi_senior') AS cert_pmi_senior,
      bool_or(b.value->>'category' = 'cert_cpmai') AS cpmai_certified,
      count(*) AS total_badges
    FROM public.members m
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(m.credly_badges, '[]'::jsonb)) AS b(value)
    GROUP BY m.id
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', tm.id,
    'name', tm.name,
    'photo_url', tm.photo_url,
    'operational_role', tm.operational_role,
    'designations', tm.designations,
    'chapter', tm.chapter,
    'current_cycle_active', tm.current_cycle_active,
    'person_id', tm.person_id,
    'credly_url', tm.credly_url,
    'credly_verified_at', tm.credly_verified_at,
    'badges_summary', jsonb_build_object(
      'trail_count', coalesce(b.trail_count, 0),
      'trail_completed', coalesce(b.trail_completed, false),
      'cert_pmi_senior', coalesce(b.cert_pmi_senior, false),
      'cpmai_certified', coalesce(b.cpmai_certified, false),
      'total_badges', coalesce(b.total_badges, 0)
    )
  ) ORDER BY tm.name), '[]'::jsonb)
  INTO v_result
  FROM tribe_members tm
  LEFT JOIN badges b ON b.member_id = tm.id;

  RETURN jsonb_build_object(
    'tribe_id', p_tribe_id,
    'members', v_result,
    'fetched_at', now()
  );
END;
$function$;

-- 4. list_initiative_engagements: o dominio de engagements e
-- pending/active/suspended/expired/offboarded/anonymized. Os filtros 'revoked' e 'onboarding'
-- comparavam com literais fora dele e devolviam vazio sempre — e a tool MCP anuncia os dois.
-- withdraw_from_initiative grava 'offboarded'. Os NOMES dos filtros ficam (contrato publico).
CREATE OR REPLACE FUNCTION public.list_initiative_engagements(
  p_initiative_id uuid,
  p_status_filter text DEFAULT 'active'
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_person_id uuid;
  v_can_see_detail boolean;
  v_is_member boolean;
  v_authority text;
  v_result jsonb;
BEGIN
  SELECT p.id INTO v_caller_person_id
  FROM public.persons p
  WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_status_filter NOT IN ('active', 'all', 'revoked', 'onboarding') THEN
    RETURN jsonb_build_object('error', format('Invalid p_status_filter: %s. Use active|all|revoked|onboarding', p_status_filter));
  END IF;

  v_can_see_detail := public.can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id)
                    OR public.can(v_caller_person_id, 'view_pii', 'initiative', p_initiative_id);

  v_is_member := EXISTS (
    SELECT 1 FROM public.engagements e
    WHERE e.person_id = v_caller_person_id
      AND e.initiative_id = p_initiative_id
      AND e.status = 'active'
  );

  IF NOT (v_can_see_detail OR v_is_member) THEN
    RETURN jsonb_build_object('error', 'Not authorized to list engagements for this initiative');
  END IF;

  v_authority := CASE WHEN v_can_see_detail THEN 'admin' WHEN v_is_member THEN 'member' ELSE 'none' END;

  SELECT coalesce(jsonb_agg(row_to_json(eng) ORDER BY eng.role_order, eng.start_date DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      e.id AS engagement_id,
      e.kind,
      e.role,
      e.status,
      e.start_date,
      e.end_date,
      e.granted_at,
      e.revoked_at,
      e.revoke_reason,
      e.legal_basis,
      p.id AS person_id,
      COALESCE(p.name, mb.name) AS person_name,
      COALESCE(p.photo_url, mb.photo_url) AS photo_url,
      mb.id AS member_id,
      gp.name AS granted_by_name,
      e.granted_by AS granted_by_person_id,
      e.metadata->>'source' AS source,
      CASE WHEN v_can_see_detail THEN e.metadata->>'motivation' ELSE NULL END AS motivation,
      ek.display_name AS kind_display,
      CASE e.role
        WHEN 'leader' THEN 0
        WHEN 'coordinator' THEN 1
        WHEN 'owner' THEN 1
        WHEN 'participant' THEN 2
        WHEN 'observer' THEN 3
        ELSE 4
      END AS role_order
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    LEFT JOIN public.members mb ON mb.id = p.legacy_member_id
    LEFT JOIN public.persons gp ON gp.id = e.granted_by
    LEFT JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE e.initiative_id = p_initiative_id
      AND (
        (p_status_filter = 'active' AND e.status = 'active')
        OR (p_status_filter = 'all')
        OR (p_status_filter = 'revoked' AND e.status = 'offboarded')
        OR (p_status_filter = 'onboarding' AND e.status = 'pending')
      )
  ) eng;

  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'status_filter', p_status_filter,
    'authority', v_authority,
    'engagements', v_result
  );
END;
$$;

-- 5. get_invitation_health: 'canceled' nao existe no dominio de initiative_invitations
-- (que tem 'revoked', ja contado em chave propria). Contador morto, removido.
CREATE OR REPLACE FUNCTION public.get_invitation_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_counts jsonb;
  v_stale integer;
  v_last_cron jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT jsonb_build_object(
    'pending', count(*) FILTER (WHERE status='pending'),
    'accepted', count(*) FILTER (WHERE status='accepted'),
    'declined', count(*) FILTER (WHERE status='declined'),
    'expired', count(*) FILTER (WHERE status='expired'),
    'revoked', count(*) FILTER (WHERE status='revoked'),
    'total', count(*),
    'expired_last_7_days', count(*) FILTER (WHERE status='expired' AND created_at >= now() - interval '7 days'),
    'created_last_24h', count(*) FILTER (WHERE created_at >= now() - interval '24 hours')
  )
  INTO v_counts
  FROM public.initiative_invitations;

  -- Stale: any pending invitation past expires_at + 1h grace (cron should've caught it)
  SELECT count(*) INTO v_stale
  FROM public.initiative_invitations
  WHERE status='pending' AND expires_at < now() - interval '1 hour';

  -- Last cron run (succeeded/failed), if accessible
  SELECT jsonb_build_object(
    'last_run_at', max(start_time),
    'last_status', (
      SELECT status FROM cron.job_run_details d
      WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1
    ),
    'last_5_status', (
      SELECT jsonb_agg(jsonb_build_object('start', start_time, 'status', status, 'msg', return_message) ORDER BY start_time DESC)
      FROM (
        SELECT start_time, status, return_message
        FROM cron.job_run_details d2
        WHERE d2.jobid = j.jobid
        ORDER BY start_time DESC
        LIMIT 5
      ) t
    )
  )
  INTO v_last_cron
  FROM cron.job j
  LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
  WHERE j.jobname = 'expire-stale-invitations-hourly'
  GROUP BY j.jobid;

  RETURN jsonb_build_object(
    'counts', v_counts,
    'stale_pending_past_expires_grace_1h', v_stale,
    'cron', coalesce(v_last_cron, jsonb_build_object('error', 'cron job not found')),
    'health_signal', CASE
      WHEN v_stale = 0 THEN 'green'
      WHEN v_stale < 5 THEN 'yellow'
      ELSE 'red'
    END,
    'fetched_at', now()
  );
END;
$$;

-- 6. get_application_ai_analysis_runs: selection_committee.role e evaluator/lead/observer.
-- 'member' nao existe, entao o predicado valia role='lead' sozinho — e nao ha lead algum em
-- ciclo em andamento. O padrao do catalogo para LEITURA sobre candidatura e ('evaluator','lead').
CREATE OR REPLACE FUNCTION public.get_application_ai_analysis_runs(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_runs jsonb;
  v_topics_views jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id
    AND member_id = v_caller.id
    AND role IN ('lead','evaluator');

  IF v_committee IS NULL
     AND NOT public.can_by_member(v_caller.id, 'manage_member'::text)
     AND NOT public.can_by_member(v_caller.id, 'view_internal_analytics'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee member or have manage_member/view_internal_analytics';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'run_index', r.run_index,
      'triggered_by', r.triggered_by,
      'status', r.status,
      'ai_analysis_snapshot', r.ai_analysis_snapshot,
      'fields_changed', r.fields_changed,
      'model_version', r.model_version,
      'input_token_estimate', r.input_token_estimate,
      'output_token_estimate', r.output_token_estimate,
      'duration_ms', r.duration_ms,
      'error_message', r.error_message,
      'started_at', r.started_at,
      'completed_at', r.completed_at
    )
    ORDER BY r.run_index DESC
  ) INTO v_runs
  FROM public.ai_analysis_runs r
  WHERE r.application_id = p_application_id;

  SELECT jsonb_build_object(
    'count', count(*),
    'first_view_at', min(viewed_at),
    'last_view_at', max(viewed_at),
    'samples', (
      SELECT jsonb_agg(jsonb_build_object(
        'viewed_at', tv.viewed_at,
        'ip', tv.ip_address::text,
        'ua_excerpt', left(tv.user_agent, 60)
      ) ORDER BY tv.viewed_at DESC)
      FROM (
        SELECT viewed_at, ip_address, user_agent FROM public.selection_topic_views
        WHERE application_id = p_application_id
        ORDER BY viewed_at DESC LIMIT 5
      ) tv
    )
  ) INTO v_topics_views
  FROM public.selection_topic_views
  WHERE application_id = p_application_id;

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'enrichment_count', v_app.enrichment_count,
    'last_enrichment_at', v_app.last_enrichment_at,
    'runs', COALESCE(v_runs, '[]'::jsonb),
    'topics_views', v_topics_views
  );
END;
$function$;

-- 7. get_application_communications: mesmo gate, mesma correcao.
CREATE OR REPLACE FUNCTION public.get_application_communications(p_application_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id
    AND member_id = v_caller.id
    AND role IN ('lead','evaluator');

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee member or have manage_member';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'send_id', cs.id,
      'template_name', ct.name,
      'template_slug', ct.slug,
      'template_category', ct.category,
      'send_status', cs.status,
      'send_created_at', cs.created_at,
      'send_sent_at', cs.sent_at,
      'send_error_log', cs.error_log,
      'audience_source', cs.audience_filter->>'source',
      'recipient_id', cr.id,
      'recipient_email', cr.external_email,
      'recipient_delivered', cr.delivered,
      'recipient_delivered_at', cr.delivered_at,
      'recipient_error_message', cr.error_message,
      'recipient_bounce_type', cr.bounce_type,
      'recipient_bounced_at', cr.bounced_at,
      'recipient_opened_at', cr.first_opened_at,
      'recipient_open_count', cr.open_count,
      'recipient_clicked_at', cr.clicked_at,
      'recipient_click_count', cr.click_count,
      'recipient_complained_at', cr.complained_at,
      'recipient_bot_suspected', cr.bot_suspected
    )
    ORDER BY cs.created_at DESC
  ) INTO v_result
  FROM public.campaign_recipients cr
  JOIN public.campaign_sends cs ON cs.id = cr.send_id
  JOIN public.campaign_templates ct ON ct.id = cs.template_id
  WHERE lower(cr.external_email) = lower(v_app.email);

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'applicant_email', v_app.email,
    'communications', COALESCE(v_result, '[]'::jsonb)
  );
END;
$function$;

-- 8. exec_chapter_comparison: board_items.curation_status nao tem 'approved'; publicado e 'published'.
CREATE OR REPLACE FUNCTION public.exec_chapter_comparison()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'access_denied'; END IF;
  -- ADR-0111 amendment: external aggregate auditor (view_aggregate_analytics) joins GP (manage_platform).
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF public.can_by_member(v_caller_id, 'view_aggregate_analytics')
     AND NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    -- EXTERNAL auditor path: k-anonymity small-cell bucketing (RoPA/LIA s2.3/s8). Chapters with
    -- < 5 active members collapse into one "Outros (<5 ativos)" bucket so a single-member chapter is
    -- never an individual record keyed by a real chapter code.
    WITH base AS (
      SELECT
        m.chapter,
        count(*)::bigint AS total_members,
        count(*) FILTER (WHERE m.current_cycle_active)::bigint AS active_members,
        count(*) FILTER (WHERE m.cpmai_certified)::bigint AS cpmai_certified,
        COALESCE((SELECT count(*) FROM public.board_item_assignments bia2
          JOIN public.board_items bi2 ON bi2.id = bia2.item_id
          WHERE bia2.member_id = ANY(array_agg(m.id))
          AND bi2.curation_status = 'published'), 0)::bigint AS articles_approved,
        COALESCE((SELECT count(DISTINCT a2.event_id) FROM public.attendance a2
          WHERE a2.member_id = ANY(array_agg(m.id))
          AND a2.present = true), 0)::bigint AS attendance_events
      FROM public.members m
      WHERE m.chapter IS NOT NULL
      GROUP BY m.chapter
    ),
    shaped AS (
      SELECT chapter, total_members, active_members, cpmai_certified, articles_approved, attendance_events
      FROM base
      WHERE active_members >= 5
      UNION ALL
      SELECT 'Outros (<5 ativos)'::text, sum(total_members)::bigint, sum(active_members)::bigint,
             sum(cpmai_certified)::bigint, sum(articles_approved)::bigint, sum(attendance_events)::bigint
      FROM base
      WHERE active_members < 5
      HAVING count(*) > 0
    )
    SELECT jsonb_agg(row_to_json(s) ORDER BY s.active_members DESC) INTO v_result
    FROM shaped s;
  ELSE
    -- internal / GP path: ORIGINAL query verbatim (byte-neutral full named list).
    SELECT jsonb_agg(row_to_json(r)) INTO v_result
    FROM (
      SELECT
        m.chapter,
        count(*) AS total_members,
        count(*) FILTER (WHERE m.current_cycle_active) AS active_members,
        count(*) FILTER (WHERE m.cpmai_certified) AS cpmai_certified,
        COALESCE((SELECT count(*) FROM board_item_assignments bia2
          JOIN board_items bi2 ON bi2.id = bia2.item_id
          WHERE bia2.member_id = ANY(array_agg(m.id))
          AND bi2.curation_status = 'published'), 0) AS articles_approved,
        COALESCE((SELECT count(DISTINCT a2.event_id) FROM attendance a2
          WHERE a2.member_id = ANY(array_agg(m.id))
          AND a2.present = true), 0) AS attendance_events
      FROM members m
      WHERE m.chapter IS NOT NULL
      GROUP BY m.chapter
      ORDER BY count(*) FILTER (WHERE m.current_cycle_active) DESC
    ) r;
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$function$;

-- 9. exec_chapter_dashboard: events.type e 'geral' (nao 'general'); e o mesmo 'approved' acima.
CREATE OR REPLACE FUNCTION public.exec_chapter_dashboard(p_chapter text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_result jsonb;
  v_year_start date;
  v_members jsonb;
  v_production jsonb;
  v_engagement jsonb;
  v_certification jsonb;
BEGIN
  -- ACL: V4 view_internal_analytics OR own-chapter access (Path Y per ADR-0030)
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT (
    public.can_by_member(v_caller_id, 'view_internal_analytics')
    OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')
    OR v_caller_chapter = p_chapter
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- k-anonymity small-cell suppression (RoPA/LIA s2.3/s8, ADR-0111 amendment): an EXTERNAL
  -- aggregate auditor (holds view_aggregate_analytics but NOT view_internal_analytics) must not
  -- receive re-identifying detail for a chapter whose active cohort is below k (5). Internal
  -- controllers are unaffected -- full detail unchanged (behavior-neutral for the live admin UI).
  IF public.can_by_member(v_caller_id, 'view_aggregate_analytics')
     AND NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    DECLARE v_active_n int;
    BEGIN
      SELECT count(*) FILTER (WHERE current_cycle_active) INTO v_active_n
      FROM public.members WHERE chapter = p_chapter;
      IF COALESCE(v_active_n, 0) < 5 THEN
        RETURN jsonb_build_object(
          'chapter', p_chapter, 'suppressed', true,
          'reason', 'small_cell_below_threshold', 'threshold', 5);
      END IF;
    END;
  END IF;

  -- Temporal anchor (year kickoff)
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  BEGIN
    SELECT date INTO v_year_start
    FROM public.events
    WHERE type = 'geral'
      AND title ILIKE '%kick%off%'
      AND EXTRACT(year FROM date) = EXTRACT(year FROM now())
    ORDER BY date ASC
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  END;
  v_year_start := COALESCE(v_year_start, make_date(EXTRACT(year FROM now())::int, 1, 1));

  -- Members
  SELECT jsonb_build_object(
    'total', count(*),
    'active', count(*) FILTER (WHERE current_cycle_active),
    'by_role', COALESCE((SELECT jsonb_object_agg(operational_role, cnt) FROM (SELECT operational_role, count(*) cnt FROM public.members WHERE chapter = p_chapter AND current_cycle_active GROUP BY operational_role) sub), '{}'::jsonb),
    'tribes', COALESCE((SELECT jsonb_agg(DISTINCT t.name) FROM public.members m2 JOIN public.tribes t ON t.id = m2.tribe_id WHERE m2.chapter = p_chapter AND m2.current_cycle_active), '[]'::jsonb)
  ) INTO v_members
  FROM public.members
  WHERE chapter = p_chapter;

  -- Production
  BEGIN
    SELECT jsonb_build_object(
      'articles_in_pipeline', count(*) FILTER (WHERE bi.curation_status IS NOT NULL AND bi.curation_status != 'draft'),
      'articles_published', count(*) FILTER (WHERE bi.curation_status = 'published'),
      'board_items_total', count(*)
    ) INTO v_production
    FROM public.board_item_assignments bia
    JOIN public.members m ON m.id = bia.member_id
    JOIN public.board_items bi ON bi.id = bia.item_id
    WHERE m.chapter = p_chapter AND bi.created_at >= v_year_start;
  EXCEPTION WHEN OTHERS THEN
    v_production := jsonb_build_object('articles_in_pipeline', 0, 'articles_published', 0, 'board_items_total', 0);
  END;

  -- Engagement
  BEGIN
    SELECT jsonb_build_object(
      'attendance_events', count(DISTINCT a.event_id),
      'total_hours', COALESCE(round(SUM(e.duration_actual / 60.0)::numeric, 1), 0),
      'members_present', count(DISTINCT a.member_id)
    ) INTO v_engagement
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.members m ON m.id = a.member_id
    WHERE m.chapter = p_chapter AND e.date >= v_year_start AND a.present = true;
  EXCEPTION WHEN OTHERS THEN
    v_engagement := jsonb_build_object('attendance_events', 0, 'total_hours', 0, 'members_present', 0);
  END;

  -- Certification
  SELECT jsonb_build_object(
    'cpmai_certified', count(*) FILTER (WHERE cpmai_certified),
    'total_active', count(*)
  ) INTO v_certification
  FROM public.members
  WHERE chapter = p_chapter AND current_cycle_active;

  v_result := jsonb_build_object(
    'chapter', p_chapter,
    'members', v_members,
    'production', v_production,
    'engagement', v_engagement,
    'certification', v_certification
  );

  RETURN v_result;
END;
$function$;

-- 10. exec_cross_initiative_comparison: a acao registrada em board_lifecycle_events e
-- 'submitted_for_curation'; 'submission' nunca casou.
CREATE OR REPLACE FUNCTION public.exec_cross_initiative_comparison(p_kind text DEFAULT 'research_tribe'::text, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1);
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'initiatives', (
      SELECT jsonb_agg(row_obj ORDER BY sort_kind, sort_tribe, sort_title)
      FROM (
        SELECT
          i.kind AS sort_kind,
          COALESCE(t.id, 9999) AS sort_tribe,
          i.title AS sort_title,
          jsonb_build_object(
            'initiative_id', i.id,
            'initiative_kind', i.kind,
            'initiative_title', i.title,
            'tribe_id', t.id,
            'tribe_name', t.name,
            'quadrant', t.quadrant_name,
            'leader', (
              SELECT m.name FROM public.members m
              WHERE m.id = COALESCE(
                t.leader_member_id,
                (SELECT em.id
                 FROM public.engagements en
                 JOIN public.members em ON em.person_id = en.person_id
                 WHERE en.initiative_id = i.id
                   AND en.status = 'active'
                   AND en.kind ~ '(coordinator|owner|leader|manager)'
                 ORDER BY en.created_at ASC
                 LIMIT 1)
              )
            ),
            'member_count', public.get_initiative_roster_count(i.id),
            'members_inactive_30d', (
              SELECT COUNT(*) FROM public.members m
              WHERE m.id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
                )
                AND m.id NOT IN (
                  SELECT DISTINCT a.member_id FROM public.attendance a
                  JOIN public.events ev ON ev.id = a.event_id
                  WHERE ev.date >= (current_date - 30) AND ev.date <= CURRENT_DATE
                    AND ev.initiative_id = i.id  -- p194 GAP-194.A: strict scope (PM Option A)
                )
            ),
            'total_cards', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
            ),
            'cards_completed', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND bi.status IN ('done','approved','published')
            ),
            'articles_submitted', (
              SELECT COUNT(*) FROM public.board_lifecycle_events ble
              JOIN public.board_items bi ON bi.id = ble.item_id
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND ble.action = 'submitted_for_curation'
            ),
            'attendance_rate', CASE WHEN t.id IS NOT NULL THEN COALESCE((public.get_attendance_engagement_summary('tribe', t.id) ->> 'avg_rate')::numeric, 0) ELSE NULL END,
            'attendance_pct', CASE WHEN t.id IS NOT NULL THEN ROUND(COALESCE((public.get_attendance_engagement_summary('tribe', t.id) ->> 'avg_rate')::numeric, 0) * 100, 1) ELSE NULL END,
            'total_hours', (
              SELECT COALESCE(SUM(ev.duration_minutes / 60.0), 0)
              FROM public.attendance a JOIN public.events ev ON ev.id = a.event_id
              WHERE a.member_id IN (
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
              )
              AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
              AND ev.initiative_id = i.id  -- p194 GAP-192.C: strict scope (PM Option B)
            ),
            'meetings_count', (
              SELECT COUNT(*) FROM public.events ev
              WHERE ev.initiative_id = i.id
                AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
            ),
            'total_xp', (
              SELECT COALESCE(SUM(gp.points), 0) FROM public.gamification_points gp
              WHERE gp.member_id IN (
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
              )
            ),
            'avg_xp', (
              SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
              FROM (
                SELECT SUM(gp.points) AS total
                FROM public.gamification_points gp
                WHERE gp.member_id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
                )
                GROUP BY gp.member_id
              ) sub
            ),
            'last_meeting_date', (
              SELECT MAX(ev.date) FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            ),
            'days_since_last_meeting', (
              SELECT EXTRACT(DAY FROM now() - MAX(ev.date)::timestamp)::int
              FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            )
          ) AS row_obj
        FROM public.initiatives i
        LEFT JOIN public.tribes t ON t.id = i.legacy_tribe_id
        WHERE (p_kind IS NULL OR i.kind = p_kind)
          AND i.visibility <> 'confidential'  -- #932: exclude confidential initiative from cross-initiative list
      ) src
    ),
    'kinds_present', (
      SELECT array_to_json(ARRAY(SELECT DISTINCT i.kind FROM public.initiatives i WHERE i.visibility <> 'confidential' ORDER BY i.kind))::jsonb
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- 11. enforce_interview_audience_private: 'interview' e literal morto no dominio de events.type.
-- NAO era fail-open: 'entrevista', '1on1' e 'parceria' ja cobriam o caso. Limpeza.
CREATE OR REPLACE FUNCTION public.enforce_interview_audience_private()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  -- Only when type indicates a private 1:1/interview event
  IF NEW.type IN ('entrevista', '1on1', 'parceria') THEN
    -- Force audience_level/visibility to 'leadership' (no broad attendance expectation)
    IF NEW.audience_level IS NULL OR NEW.audience_level = 'all' THEN
      NEW.audience_level := 'leadership';
    END IF;
    IF NEW.visibility IS NULL OR NEW.visibility = 'all' THEN
      NEW.visibility := 'leadership';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
