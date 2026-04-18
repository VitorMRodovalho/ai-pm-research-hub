-- ADR-0015 Phase 5 Fase A2 Commit 3 — Batch 2 mid-size readers
--
-- 5 RPCs refatorados aplicando patterns 1-4 de A2 C2:
--   1. get_campaign_analytics (~8.6K) — LEFT JOIN tribes via m.tribe_id in recipients
--   2. get_adoption_dashboard (~6.7K) — tribe_stats CTE + members output
--   3. sign_volunteer_agreement (~9.5K) — reads m.tribe_id (dropped from SELECT, derived via helper)
--   4. get_tribe_events_timeline (~4.6K) — member count filter
--   5. exec_cross_tribe_comparison (~4.4K) — multi-subquery tribe filter
--
-- Patterns aplicados: ver header de migration 20260428130000.
-- Output shapes preservados byte-for-byte.

-- ============================================================================
-- 1. get_campaign_analytics — LEFT JOIN tribes via helper
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_campaign_analytics(p_send_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = v_caller_id
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_send_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'send', (
        SELECT jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'subject', ct.subject,
          'sent_at', cs.sent_at, 'created_at', cs.created_at, 'status', cs.status
        )
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.id = p_send_id
      ),
      'funnel', jsonb_build_object(
        'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id),
        'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (delivered_at IS NOT NULL OR delivered = true)),
        'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true)),
        'human_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
        'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
        'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND clicked_at IS NOT NULL),
        'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND bounced_at IS NOT NULL),
        'complained', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND complained_at IS NOT NULL)
      ),
      'rates', jsonb_build_object(
        'delivery_rate', (
          SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate', (
          SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate_total', (
          SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'click_rate', (
          SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric
            / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        )
      ),
      'recipients', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'member_name', COALESCE(m.name, cr.external_name, ''),
          'email', COALESCE(m.email, cr.external_email, ''),
          'role', m.operational_role, 'tribe_name', t.name,
          'delivered', (cr.delivered_at IS NOT NULL OR cr.delivered = true),
          'opened', (cr.opened_at IS NOT NULL OR cr.opened = true),
          'open_count', cr.open_count, 'bot_suspected', cr.bot_suspected,
          'clicked', cr.clicked_at IS NOT NULL, 'click_count', cr.click_count,
          'bounced', cr.bounced_at IS NOT NULL, 'bounce_type', cr.bounce_type,
          'complained', cr.complained_at IS NOT NULL,
          'status', CASE
            WHEN cr.complained_at IS NOT NULL THEN 'complained'
            WHEN cr.bounced_at IS NOT NULL THEN 'bounced'
            WHEN cr.clicked_at IS NOT NULL THEN 'clicked'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false THEN 'opened'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true THEN 'bot_opened'
            WHEN cr.delivered_at IS NOT NULL OR cr.delivered = true THEN 'delivered'
            ELSE 'sent'
          END
        ) ORDER BY cr.delivered_at DESC NULLS LAST), '[]'::jsonb)
        FROM campaign_recipients cr
        LEFT JOIN members m ON m.id = cr.member_id
        LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
        WHERE cr.send_id = p_send_id
      ),
      'by_role', (
        SELECT COALESCE(jsonb_agg(sub), '[]'::jsonb) FROM (
          SELECT jsonb_build_object(
            'role', COALESCE(m.operational_role, 'external'),
            'total', count(*),
            'delivered', count(*) FILTER (WHERE cr.delivered_at IS NOT NULL OR cr.delivered = true),
            'opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false),
            'bot_opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true),
            'clicked', count(*) FILTER (WHERE cr.clicked_at IS NOT NULL)
          ) AS sub
          FROM campaign_recipients cr LEFT JOIN members m ON m.id = cr.member_id
          WHERE cr.send_id = p_send_id
          GROUP BY COALESCE(m.operational_role, 'external')
        ) agg
      )
    ) INTO v_result;
  ELSE
    SELECT jsonb_build_object(
      'total_sends', (SELECT count(*) FROM campaign_sends WHERE status = 'sent'),
      'total_recipients', (SELECT count(*) FROM campaign_recipients),
      'total_delivered', (SELECT count(*) FROM campaign_recipients WHERE delivered_at IS NOT NULL OR delivered = true),
      'total_opened', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
      'total_opened_incl_bots', (SELECT count(*) FROM campaign_recipients WHERE opened_at IS NOT NULL OR opened = true),
      'total_bot_opens', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
      'total_clicked', (SELECT count(*) FROM campaign_recipients WHERE clicked_at IS NOT NULL),
      'total_bounced', (SELECT count(*) FROM campaign_recipients WHERE bounced_at IS NOT NULL),
      'overall_rates', jsonb_build_object(
        'delivery_rate', (SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1) FROM campaign_recipients),
        'open_rate', (SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'open_rate_total', (SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'click_rate', (SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1) FROM campaign_recipients)
      ),
      'recent_sends', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'sent_at', cs.sent_at, 'created_at', cs.created_at,
          'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id),
          'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (delivered_at IS NOT NULL OR delivered = true)),
          'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
          'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
          'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND clicked_at IS NOT NULL),
          'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND bounced_at IS NOT NULL)
        ) ORDER BY cs.created_at DESC), '[]'::jsonb)
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.status = 'sent' LIMIT 20
      )
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 2. get_adoption_dashboard — tribe_stats CTE + output tribe_id derived
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_adoption_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager', 'sponsor', 'chapter_liaison'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  WITH tier_stats AS (
    SELECT operational_role, count(*)::integer as total,
      count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(*) FILTER (WHERE last_seen_at IS NULL)::integer as never,
      ROUND(AVG(total_sessions)::numeric, 1) as avg_sessions
    FROM members WHERE is_active = true GROUP BY operational_role
  ),
  tribe_stats AS (
    SELECT t.id as tribe_id, t.name as tribe_name,
      count(m.id)::integer as total,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(m.id) FILTER (WHERE m.last_seen_at IS NULL)::integer as never,
      ROUND(AVG(m.total_sessions)::numeric, 1) as avg_sessions
    FROM tribes t
    LEFT JOIN members m ON public.get_member_tribe(m.id) = t.id AND m.is_active = true
    WHERE t.is_active = true GROUP BY t.id, t.name
  ),
  daily AS (
    SELECT session_date, count(DISTINCT member_id)::integer as cnt, sum(pages_visited)::integer as pvs
    FROM member_activity_sessions WHERE session_date > CURRENT_DATE - 30 GROUP BY session_date
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'summary', jsonb_build_object(
      'total_active', (SELECT count(*) FROM members WHERE is_active = true AND current_cycle_active = true),
      'total_registered', (SELECT count(*) FROM members),
      'ever_logged_in', (SELECT count(*) FROM members WHERE is_active = true AND auth_id IS NOT NULL),
      'seen_last_7d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '7 days'),
      'seen_last_30d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '30 days'),
      'never_seen', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at IS NULL),
      'adoption_pct_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'adoption_pct_30d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'avg_sessions_per_member', (SELECT ROUND(AVG(total_sessions)::numeric, 1) FROM members WHERE is_active = true AND total_sessions > 0)
    ),
    'lifecycle', jsonb_build_object(
      'total_ever', (SELECT count(*) FROM members),
      'active_c3', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni' OR (NOT is_active AND operational_role IN ('alumni','observer','guest'))),
      'observers_active', (SELECT count(*) FROM members WHERE is_active AND operational_role = 'observer'),
      'founders_total', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations)),
      'founders_active', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND is_active AND current_cycle_active),
      'founders_with_auth', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND auth_id IS NOT NULL),
      'sponsors_total', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active),
      'sponsors_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active AND auth_id IS NOT NULL),
      'liaisons_total', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active),
      'liaisons_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active AND auth_id IS NOT NULL),
      'retention_c2_c3', (SELECT ROUND(
        count(DISTINCT mh3.member_id)::numeric * 100 / NULLIF(count(DISTINCT mh2.member_id), 0), 1)
        FROM member_cycle_history mh2
        LEFT JOIN member_cycle_history mh3 ON mh3.member_id = mh2.member_id AND mh3.cycle_code = 'cycle_3'
        WHERE mh2.cycle_code = 'cycle_2')
    ),
    'by_tier', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tier', ts.operational_role, 'total', ts.total, 'seen_7d', ts.seen_7d,
      'seen_30d', ts.seen_30d, 'never', ts.never, 'avg_sessions', ts.avg_sessions
    )), '[]'::jsonb) FROM tier_stats ts),
    'by_tribe', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tribe_id', ts.tribe_id, 'tribe_name', ts.tribe_name, 'total', ts.total,
      'seen_7d', ts.seen_7d, 'seen_30d', ts.seen_30d, 'never', ts.never,
      'avg_sessions', ts.avg_sessions
    ) ORDER BY ts.tribe_id), '[]'::jsonb) FROM tribe_stats ts),
    'daily_activity', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'date', d.dt::text, 'unique_members', COALESCE(dy.cnt, 0),
      'total_pageviews', COALESCE(dy.pvs, 0)
    ) ORDER BY d.dt), '[]'::jsonb)
    FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE, '1 day') d(dt)
    LEFT JOIN daily dy ON dy.session_date = d.dt),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'tier', m.operational_role,
      'designations', m.designations,
      'tribe_id', public.get_member_tribe(m.id), 'tribe_name', t.name,
      'has_auth', m.auth_id IS NOT NULL, 'last_seen', m.last_seen_at,
      'total_sessions', m.total_sessions, 'last_pages', m.last_active_pages,
      'is_founder', 'founder' = ANY(m.designations),
      'status', CASE
        WHEN m.last_seen_at IS NULL THEN 'never'
        WHEN m.last_seen_at > now() - interval '7 days' THEN 'active'
        WHEN m.last_seen_at > now() - interval '30 days' THEN 'inactive'
        ELSE 'dormant' END
    ) ORDER BY m.last_seen_at DESC NULLS LAST), '[]'::jsonb)
    FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
    WHERE m.is_active = true),
    'mcp_usage', (SELECT get_mcp_adoption_stats()),
    'auth_providers', (SELECT get_auth_provider_stats()),
    'designation_counts', (
      SELECT COALESCE(jsonb_object_agg(d, cnt), '{}'::jsonb) FROM (
        SELECT unnest(designations) as d, count(*) as cnt
        FROM members WHERE is_active = true AND designations != '{}'
        GROUP BY d
      ) x
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 3. sign_volunteer_agreement — drop m.tribe_id from SELECT, derive via helper
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sign_volunteer_agreement(p_language text DEFAULT 'pt-BR'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_template record; v_cert_id uuid; v_code text; v_hash text;
  v_content jsonb; v_cycle int; v_existing uuid; v_issuer_id uuid; v_vep record;
  v_period_start date; v_period_end date;
  v_member_role_for_vep text; v_history record; v_source text;
  v_missing_fields text[] := '{}';
  v_engagement_updated boolean := false;
  v_chapter_cnpj text; v_chapter_legal_name text;
BEGIN
  -- tribe_id dropado do SELECT direto; tribe_name derivado via helper-based JOIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
    m.phone, m.address, m.city, m.state, m.country, m.birth_date,
    t.name as tribe_name
  INTO v_member
  FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
  WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF v_member.pmi_id IS NULL OR length(trim(v_member.pmi_id)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'pmi_id');
  END IF;
  IF v_member.phone IS NULL OR length(trim(v_member.phone)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'phone');
  END IF;
  IF v_member.address IS NULL OR length(trim(v_member.address)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'address');
  END IF;
  IF v_member.city IS NULL OR length(trim(v_member.city)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'city');
  END IF;
  IF v_member.state IS NULL OR length(trim(v_member.state)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'state');
  END IF;
  IF v_member.country IS NULL OR length(trim(v_member.country)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'country');
  END IF;
  IF v_member.birth_date IS NULL THEN
    v_missing_fields := array_append(v_missing_fields, 'birth_date');
  END IF;

  IF array_length(v_missing_fields, 1) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'profile_incomplete',
      'message', 'Você precisa completar seu perfil antes de assinar o Termo de Voluntariado.',
      'missing_fields', to_jsonb(v_missing_fields),
      'profile_url', '/profile'
    );
  END IF;

  SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
  FROM chapter_registry cr
  WHERE cr.chapter_code = v_member.chapter AND cr.is_active = true;

  IF v_chapter_cnpj IS NULL THEN
    SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
    FROM chapter_registry cr
    WHERE cr.is_contracting_chapter = true AND cr.is_active = true
    LIMIT 1;
  END IF;

  IF v_chapter_cnpj IS NULL THEN
    v_chapter_cnpj := '06.065.645/0001-99';
    v_chapter_legal_name := 'PMI Goias';
  END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates
  WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents
  WHERE doc_type = 'volunteer_term_template' AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = v_member.chapter AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
  END IF;

  v_member_role_for_vep := CASE
    WHEN v_member.operational_role IN ('manager', 'deputy_manager') THEN 'manager'
    WHEN v_member.operational_role = 'tribe_leader' THEN 'leader'
    ELSE 'researcher'
  END;

  SELECT vo.* INTO v_vep FROM selection_applications sa
  JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
    AND vo.role_default = v_member_role_for_vep
    AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
  ORDER BY sa.created_at DESC LIMIT 1;

  IF v_vep.opportunity_id IS NOT NULL THEN
    v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_match';
  ELSE
    SELECT vo.* INTO v_vep FROM selection_applications sa
    JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
      AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
    ORDER BY sa.created_at DESC LIMIT 1;
    IF v_vep.opportunity_id IS NOT NULL THEN
      v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_year_match';
    ELSE
      SELECT cycle_code, cycle_start, cycle_end INTO v_history
      FROM member_cycle_history WHERE member_id = v_member.id
      ORDER BY cycle_start DESC LIMIT 1;
      IF v_history.cycle_code IS NOT NULL THEN
        v_period_start := v_history.cycle_start;
        v_period_end := (v_history.cycle_start + interval '12 months' - interval '1 day')::date;
        v_source := 'cycle_history:' || v_history.cycle_code;
      ELSE
        SELECT * INTO v_vep FROM vep_opportunities
        WHERE EXTRACT(YEAR FROM start_date) = v_cycle
          AND role_default = v_member_role_for_vep AND is_active = true
        ORDER BY start_date DESC LIMIT 1;
        IF v_vep.opportunity_id IS NOT NULL THEN
          v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'founder_role_vep';
        ELSE
          RETURN jsonb_build_object('error', 'cannot_derive_period',
            'message', 'No application, cycle history, or matching VEP found. Admin must set period manually.',
            'member_id', v_member.id, 'member_name', v_member.name);
        END IF;
      END IF;
    END IF;
  END IF;

  v_content := jsonb_build_object(
    'template_id', v_template.id, 'template_version', v_template.version, 'template_title', v_template.title,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name, 'member_pmi_id', v_member.pmi_id, 'member_chapter', v_member.chapter,
    'member_phone', v_member.phone, 'member_address', v_member.address,
    'member_city', v_member.city, 'member_state', v_member.state,
    'member_country', v_member.country, 'member_birth_date', v_member.birth_date,
    'language', p_language, 'signed_at', now(),
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name,
    'vep_opportunity_id', v_vep.opportunity_id, 'vep_title', v_vep.title,
    'period_start', v_period_start::text, 'period_end', v_period_end::text,
    'period_source', v_source
  );

  v_code := 'TERM-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));
  v_hash := encode(sha256(convert_to(v_content::text || v_member.id::text || now()::text || 'nucleo-ia-volunteer-salt', 'UTF8')), 'hex');

  INSERT INTO certificates (
    member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id
  ) VALUES (
    v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle
      WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
      ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(), v_issuer_id, v_code,
    v_period_start::text, v_period_end::text,
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text
  ) RETURNING id INTO v_cert_id;

  UPDATE public.engagements
  SET agreement_certificate_id = v_cert_id
  WHERE person_id = (SELECT id FROM public.persons WHERE legacy_member_id = v_member.id)
    AND kind = 'volunteer'
    AND status = 'active'
    AND agreement_certificate_id IS NULL;

  IF FOUND THEN v_engagement_updated := true; END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object('verification_code', v_code, 'cycle', v_cycle, 'chapter', v_member.chapter,
      'chapter_cnpj', v_chapter_cnpj,
      'period_source', v_source, 'engagement_linked', v_engagement_updated));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'volunteer_agreement_signed',
    v_member.name || ' assinou o Termo de Voluntariado',
    'Capitulo: ' || COALESCE(v_member.chapter, '—') || '. Codigo: ' || v_code,
    '/admin/certificates', 'certificate', v_cert_id
  FROM members m
  WHERE m.is_active = true AND m.id != v_member.id
    AND (m.operational_role = 'manager' OR m.is_superadmin = true
         OR ('chapter_board' = ANY(m.designations) AND m.chapter = v_member.chapter));

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code,
    'signature_hash', v_hash, 'signed_at', now(),
    'period_start', v_period_start, 'period_end', v_period_end, 'period_source', v_source,
    'engagement_linked', v_engagement_updated,
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name);
END;
$function$;

-- ============================================================================
-- 4. get_tribe_events_timeline — member count via EXISTS engagements
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_tribe_events_timeline(p_tribe_id integer, p_upcoming_limit integer DEFAULT 3, p_past_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_next_recurring jsonb;
  v_tribe_member_count int;
  v_tribe_initiative_id uuid;
  v_now_brt timestamptz := NOW() AT TIME ZONE 'America/Sao_Paulo';
  v_today_brt date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  SELECT count(*) INTO v_tribe_member_count
  FROM public.members m
  WHERE m.is_active = true
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison')
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date', row_data->>'title'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link,
      'audience_level', e.audience_level,
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'agenda_text', e.agenda_text,
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff', 'lideranca'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
      AND (
        e.date > v_today_brt
        OR (
          e.date = v_today_brt
          AND (
            e.date::timestamp
            + COALESCE(
                (SELECT tms.time_start FROM tribe_meeting_slots tms
                 WHERE tms.tribe_id = i.legacy_tribe_id AND tms.is_active LIMIT 1),
                '19:30'::time
              )
            + (COALESCE(e.duration_minutes, 60) || ' minutes')::interval
          )::timestamp > v_now_brt::timestamp
        )
      )
    ORDER BY e.date ASC
    LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'youtube_url', e.youtube_url,
      'recording_url', e.recording_url,
      'recording_type', e.recording_type,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= v_today_brt
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
    ORDER BY e.date DESC
    LIMIT p_past_limit
  ) sub;

  SELECT jsonb_build_object(
    'day_of_week', tms.day_of_week,
    'time_start', tms.time_start,
    'time_end', tms.time_end,
    'day_name_pt', CASE tms.day_of_week
      WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça'
      WHEN 3 THEN 'Quarta' WHEN 4 THEN 'Quinta' WHEN 5 THEN 'Sexta' WHEN 6 THEN 'Sábado'
    END,
    'day_name_en', CASE tms.day_of_week
      WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' WHEN 6 THEN 'Saturday'
    END
  ) INTO v_next_recurring
  FROM tribe_meeting_slots tms
  WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true
  LIMIT 1;

  RETURN jsonb_build_object(
    'upcoming', v_upcoming,
    'past', v_past,
    'next_recurring', COALESCE(v_next_recurring, 'null'::jsonb),
    'tribe_member_count', v_tribe_member_count
  );
END;
$function$;

-- ============================================================================
-- 5. exec_cross_tribe_comparison — multi-subquery tribe filter via EXISTS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exec_cross_tribe_comparison(p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := '2026-03-01';
BEGIN
  SELECT id INTO v_caller_id FROM members
  WHERE auth_id = auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT jsonb_build_object(
    'tribes', (
      SELECT jsonb_agg(jsonb_build_object(
        'tribe_id', t.id,
        'tribe_name', t.name,
        'quadrant', t.quadrant_name,
        'leader', (SELECT name FROM members WHERE id = t.leader_member_id),
        'member_count', (
          SELECT COUNT(*) FROM public.members m
          WHERE m.is_active
            AND EXISTS (
              SELECT 1 FROM public.engagements e
              JOIN public.initiatives i ON i.id = e.initiative_id
              WHERE e.person_id = m.person_id
                AND e.kind = 'volunteer' AND e.status = 'active'
                AND i.kind = 'research_tribe' AND i.legacy_tribe_id = t.id
            )
        ),
        'members_inactive_30d', (
          SELECT COUNT(*) FROM public.members m
          WHERE m.is_active
            AND EXISTS (
              SELECT 1 FROM public.engagements e
              JOIN public.initiatives i ON i.id = e.initiative_id
              WHERE e.person_id = m.person_id
                AND e.kind = 'volunteer' AND e.status = 'active'
                AND i.kind = 'research_tribe' AND i.legacy_tribe_id = t.id
            )
            AND m.id NOT IN (
              SELECT DISTINCT a.member_id FROM public.attendance a
              JOIN public.events e2 ON e2.id = a.event_id
              WHERE e2.date >= (current_date - 30) AND e2.date <= CURRENT_DATE
            )
        ),
        'total_cards', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id
        ),
        'cards_completed', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id AND bi.status IN ('done','approved','published')
        ),
        'articles_submitted', (
          SELECT COUNT(*) FROM board_lifecycle_events ble
          JOIN board_items bi ON bi.id = ble.item_id
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id AND ble.action = 'submission'
        ),
        'attendance_rate', (
          SELECT COALESCE(
            ROUND(
              COUNT(*) FILTER (WHERE EXISTS (
                SELECT 1 FROM attendance a2
                WHERE a2.event_id = e.id
                  AND a2.member_id IN (
                    SELECT m2.id FROM public.members m2
                    WHERE m2.is_active
                      AND EXISTS (
                        SELECT 1 FROM public.engagements e3
                        JOIN public.initiatives i3 ON i3.id = e3.initiative_id
                        WHERE e3.person_id = m2.person_id
                          AND e3.kind = 'volunteer' AND e3.status = 'active'
                          AND i3.kind = 'research_tribe' AND i3.legacy_tribe_id = t.id
                      )
                  )
              ))::numeric
              / NULLIF(
                (
                  SELECT COUNT(*)::numeric FROM public.members m4
                  WHERE m4.is_active
                    AND EXISTS (
                      SELECT 1 FROM public.engagements e4
                      JOIN public.initiatives i4 ON i4.id = e4.initiative_id
                      WHERE e4.person_id = m4.person_id
                        AND e4.kind = 'volunteer' AND e4.status = 'active'
                        AND i4.kind = 'research_tribe' AND i4.legacy_tribe_id = t.id
                    )
                ) * COUNT(DISTINCT e.id), 0)
            , 2), 0)
          FROM events e
          LEFT JOIN initiatives i ON i.id = e.initiative_id
          WHERE (i.legacy_tribe_id = t.id OR e.initiative_id IS NULL) AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_hours', (
          SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
          FROM attendance a JOIN events e ON e.id = a.event_id
          WHERE a.member_id IN (
            SELECT m5.id FROM public.members m5
            WHERE m5.is_active
              AND EXISTS (
                SELECT 1 FROM public.engagements e5
                JOIN public.initiatives i5 ON i5.id = e5.initiative_id
                WHERE e5.person_id = m5.person_id
                  AND e5.kind = 'volunteer' AND e5.status = 'active'
                  AND i5.kind = 'research_tribe' AND i5.legacy_tribe_id = t.id
              )
          )
          AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'meetings_count', (
          SELECT COUNT(*) FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_xp', (
          SELECT COALESCE(SUM(gp.points), 0) FROM gamification_points gp
          WHERE gp.member_id IN (
            SELECT m6.id FROM public.members m6
            WHERE m6.is_active
              AND EXISTS (
                SELECT 1 FROM public.engagements e6
                JOIN public.initiatives i6 ON i6.id = e6.initiative_id
                WHERE e6.person_id = m6.person_id
                  AND e6.kind = 'volunteer' AND e6.status = 'active'
                  AND i6.kind = 'research_tribe' AND i6.legacy_tribe_id = t.id
              )
          )
        ),
        'avg_xp', (
          SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
          FROM (
            SELECT SUM(gp.points) AS total
            FROM gamification_points gp
            WHERE gp.member_id IN (
              SELECT m7.id FROM public.members m7
              WHERE m7.is_active
                AND EXISTS (
                  SELECT 1 FROM public.engagements e7
                  JOIN public.initiatives i7 ON i7.id = e7.initiative_id
                  WHERE e7.person_id = m7.person_id
                    AND e7.kind = 'volunteer' AND e7.status = 'active'
                    AND i7.kind = 'research_tribe' AND i7.legacy_tribe_id = t.id
                )
            )
            GROUP BY gp.member_id
          ) sub
        ),
        'last_meeting_date', (
          SELECT MAX(e.date) FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date <= CURRENT_DATE
        ),
        'days_since_last_meeting', (
          SELECT EXTRACT(DAY FROM now() - MAX(e.date)::timestamp)::int
          FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date <= CURRENT_DATE
        )
      ) ORDER BY t.id)
      FROM tribes t
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
