-- #1022 — member exit-state semantics: canonical alumni metric + dead-metric removal + observer retired
-- as an offboard target. Body-only CREATE OR REPLACE on two SECDEF functions (signatures unchanged →
-- grants + SECURITY DEFINER preserved). No transition-rule change (see Part D note below).
--
-- Part A (data-correctness): get_adoption_dashboard counted "alumni" with a LOOSE definition
--   (member_status='alumni' OR (NOT is_active AND operational_role IN ('alumni','observer','guest'))),
--   giving 22 while the canonical strict definition (member_status='alumni', matching get_cycle_report
--   and get_chapter_dashboard) gives 21. External decks pulling "alumni" got an ambiguous number.
--   Fix: strict member_status='alumni' everywhere. (Verified live 2026-07-01: strict=21, loose=22.)
--
-- Part B (dead metric): get_adoption_dashboard.observers_active counted
--   (is_active AND operational_role='observer'), which is STRUCTURALLY impossible — the
--   sync_member_status_consistency trigger forces member_status IN ('observer','alumni','inactive')
--   ⇒ is_active=false, and operational_role='observer' only via that status. Always 0. Removed.
--
-- Part C (governance/LGPD): admin_offboard_member accepted p_new_status='observer'. An "ouvinte"/observer
--   is a NON-VOLUNTEER not bound by the volunteer term, leaving the data/IP/LGPD policy unbound — the PM
--   pulled that function back. 0 members currently hold member_status='observer' and no RLS policy
--   references it, so it was a dormant-but-reachable exposure. Retire 'observer' as an offboard TARGET.
--   NOT the same as engagement.kind='observer' (a participatory engagement, ~13 active, untouched). The
--   member_status='observer' enum value is RETAINED for any historical row + defense-in-depth invariants,
--   but is no longer creatable. Supersedes ADR-0071 Foundation "active → observer" offboard path.
--
-- Part D (reframe, NO code change): #1022-D asked to make 'inactive' terminal. Grounding showed that
--   premise is wrong — inactive is REVERSIBLE by design: admin_reactivate_member's non-alumni branch
--   reactivates it directly (the "sabbatical" path, ADR-0071 Amendment 2), and #976 Camada 5 disengages
--   lapsed re-acceptors to a REVERSIBLE 'inactive'. Blocking inactive→active would break the reaccept
--   flow. validate_status_transition is therefore intentionally UNCHANGED.

-- ─────────────────────────────────────────────────────────────────────────────
-- A + B: get_adoption_dashboard — canonical alumni + drop dead observers_active
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_adoption_dashboard()
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
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

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
      -- #1022-A: canonical alumni = member_status='alumni' (was a loose OR that pulled in
      -- inactive/observer/guest → 22 vs canonical 21; matches get_cycle_report/get_chapter_dashboard).
      'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
      -- #1022-B: removed dead metric observers_active — (is_active AND operational_role='observer') is
      -- structurally impossible (sync_member_status_consistency forces observer ⇒ is_active=false).
      'founders_total', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations)),
      'founders_active', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND is_active AND current_cycle_active),
      'founders_with_auth', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND auth_id IS NOT NULL),
      'sponsors_total', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active),
      'sponsors_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active AND auth_id IS NOT NULL),
      'liaisons_total', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active),
      'liaisons_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active AND auth_id IS NOT NULL),
      -- #692: canonical cohort-survival (last closed transition), SSOT-driven (was hardcoded cycle_2/cycle_3).
      'retention_c2_c3', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
      'retention_basis', (public.get_member_retention_canonical() -> 'headline' ->> 'basis')
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

-- ─────────────────────────────────────────────────────────────────────────────
-- C: admin_offboard_member — retire 'observer' as an offboard target
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_offboard_member(p_member_id uuid, p_new_status text, p_reason_category text, p_reason_detail text DEFAULT NULL::text, p_reassign_to uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller             record;
  v_member             record;
  v_audit_id           uuid;
  v_new_role           text;
  v_items_reassigned   integer := 0;
  v_engagements_closed integer := 0;
  v_vol_terms_skipped  integer := 0;
  v_prev_status        text;
  v_reason_record      record;
  v_certificate_id     uuid;
  v_certificate_code   text;
  v_emit_error         text;
  v_current_cycle_int  integer;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  -- #1022-C: 'observer' retired as an offboard target (governance/LGPD — an "ouvinte"/observer is a
  -- non-volunteer not bound by the volunteer term, leaving data/IP/LGPD policy unbound; PM pulled it
  -- back). Only 'alumni' (friendly, re-invitable) and 'inactive' (administrative, reversible) remain.
  -- This is NOT engagement.kind='observer' (a participatory engagement kind, untouched).
  IF p_new_status NOT IN ('alumni','inactive') THEN
    RETURN jsonb_build_object('error','Invalid status: ' || p_new_status);
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  v_prev_status := COALESCE(v_member.member_status,'active');

  IF v_prev_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  BEGIN
    PERFORM public.validate_status_transition(v_prev_status, p_new_status);
  EXCEPTION WHEN sqlstate '22023' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id, 'member.status_transition_blocked', 'member', p_member_id,
      jsonb_build_object('attempted_from', v_prev_status, 'attempted_to', p_new_status),
      jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition')
    );
    RETURN jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition');
  END;

  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'inactive' THEN 'none'
  END;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'member.status_transition', 'member', p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', v_prev_status, 'new_status', p_new_status,
      'previous_tribe_id', v_member.tribe_id
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'reason_category', p_reason_category, 'reason_detail', p_reason_detail,
      'items_reassigned_to', p_reassign_to
    ))
  )
  RETURNING id INTO v_audit_id;

  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id, 'member.role_change', 'member', p_member_id,
      jsonb_build_object(
        'field', 'operational_role',
        'old_value', to_jsonb(v_member.operational_role),
        'new_value', to_jsonb(v_new_role),
        'effective_date', CURRENT_DATE
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'change_type', 'role_changed',
        'reason', p_reason_detail,
        'authorized_by', v_caller.id
      ))
    );
  END IF;

  UPDATE public.members SET
    member_status        = p_new_status,
    operational_role     = v_new_role,
    is_active            = false,
    designations         = '{}'::text[],
    offboarded_at        = now(),
    offboarded_by        = v_caller.id,
    status_changed_at    = now(),
    status_change_reason = COALESCE(p_reason_detail, p_reason_category),
    updated_at           = now()
  WHERE id = p_member_id;

  IF v_member.person_id IS NOT NULL THEN
    UPDATE public.engagements SET
      status = 'offboarded', end_date = CURRENT_DATE,
      revoked_at = now(), revoked_by = v_caller.person_id,
      revoke_reason = COALESCE(p_reason_detail, p_reason_category),
      updated_at = now()
    WHERE person_id = v_member.person_id AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  IF p_reassign_to IS NOT NULL THEN
    UPDATE public.board_items SET assignee_id = p_reassign_to
    WHERE assignee_id = p_member_id AND status != 'archived';
    GET DIAGNOSTICS v_items_reassigned = ROW_COUNT;
  END IF;

  -- #322 offboarding extension: auto-skip any open volunteer_term step for
  -- the offboarded member. Idempotent via status='pending' filter. Respects
  -- #321 trigger ordering: if a cert was inserted before offboard, the step
  -- is already 'completed' and gets filtered out here.
  UPDATE public.onboarding_progress
  SET
    status = 'skipped',
    completed_at = now(),
    updated_at = now(),
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'completed_via', 'p234_322_offboarding_extension',
      'reason', 'offboarded_pre_signing',
      'offboarded_to_status', p_new_status,
      'offboarded_at', now(),
      'migration', '20260805000019'
    )
  WHERE member_id = p_member_id
    AND step_key = 'volunteer_term'
    AND status = 'pending';
  GET DIAGNOSTICS v_vol_terms_skipped = ROW_COUNT;

  IF v_vol_terms_skipped > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (
      v_caller.id,
      'onboarding.volunteer_term_skipped_on_offboard',
      'member',
      p_member_id,
      jsonb_build_object(
        'rows_affected', v_vol_terms_skipped,
        'offboarded_to_status', p_new_status,
        'reason', 'offboarded_pre_signing',
        'migration', '20260805000019'
      )
    );
  END IF;

  -- ARM-9 G3: auto-emit alumni_recognition certificate
  IF p_new_status = 'alumni' AND p_reason_category IS NOT NULL THEN
    SELECT * INTO v_reason_record FROM public.offboard_reason_categories
    WHERE code = p_reason_category;

    IF FOUND AND v_reason_record.preserves_return_eligibility = true THEN
      BEGIN
        -- Safe cycle extraction: digits from cycle_code text, fallback 3
        SELECT COALESCE(NULLIF(regexp_replace(cycle_code, '[^0-9]', '', 'g'), '')::int, 3)
        INTO v_current_cycle_int
        FROM public.cycles WHERE is_current = true LIMIT 1;
        v_current_cycle_int := COALESCE(v_current_cycle_int, 3);

        v_certificate_code := 'CERT-' || extract(year FROM now())::text || '-' || upper(substr(md5(random()::text), 1, 6));

        INSERT INTO public.certificates (
          member_id, type, title, description, cycle, function_role,
          language, issued_by, verification_code, issued_at, source
        ) VALUES (
          p_member_id,
          'alumni_recognition',
          'Reconhecimento Alumni — Núcleo IA & GP',
          'Em reconhecimento à contribuição como voluntário(a) ao programa Núcleo IA & GP. Saída amigável em ' || to_char(now(), 'DD/MM/YYYY') || ' (' || v_reason_record.label_pt || '). Elegível para retorno via re-engagement pipeline.',
          v_current_cycle_int,
          v_member.operational_role,
          'pt-BR',
          v_caller.id,
          v_certificate_code,
          now(),
          'arm9_g3_auto_emit'
        )
        RETURNING id INTO v_certificate_id;

        PERFORM public.create_notification(
          p_member_id,
          'certificate_issued',
          'Certificado Alumni emitido',
          'Você recebeu o certificado Reconhecimento Alumni — válido para perfil profissional e LinkedIn.',
          '/gamification',
          'certificate',
          v_certificate_id
        );
      EXCEPTION WHEN OTHERS THEN
        v_emit_error := SQLERRM;
        v_certificate_id := NULL;
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller.id, 'arm9.alumni_badge_emit_failed', 'member', p_member_id,
          jsonb_build_object('reason_category', p_reason_category),
          jsonb_build_object('error', v_emit_error)
        );
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'transition_id', v_audit_id,
    'member_name', v_member.name,
    'previous_status', v_prev_status,
    'new_status', p_new_status,
    'new_role', v_new_role,
    'items_reassigned', v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'vol_terms_skipped', v_vol_terms_skipped,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0),
    'alumni_certificate_id', v_certificate_id,
    'alumni_certificate_emit_error', v_emit_error
  );
END;
$function$;

-- PostgREST schema reload (RPC bodies changed; signatures unchanged so grants/SECDEF preserved).
NOTIFY pgrst, 'reload schema';
