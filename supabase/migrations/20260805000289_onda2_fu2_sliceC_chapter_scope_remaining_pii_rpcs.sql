-- Onda 2 — FU-2 Slice C: chapter-scope (or GP/sede-restrict) the REMAINING view_pii SECDEF RPCs.
--
-- Slice A (mig …288) closed the raw member-directory PII leak for 6 RPCs via caller_chapter_scope().
-- Slice C completes the surface with PER-RPC judgment (the RPCs are heterogeneous). Grounded
-- 2026-06-28: all chapters share ONE organization_id, so the org-fences already present in several
-- of these RPCs are a NO-OP for chapter isolation; and can()/rls_can_for_tribe grant on organization/
-- global scope REGARDLESS of resource (org-scope subsumes initiative/tribe), so an org-scoped view_pii
-- holder (a partner-chapter leader — 11 live: CE/DF/MG/RS sponsors + tribe_leaders) could read other
-- chapters'/tribes'/initiatives' PII. GP/sede (caller_chapter_scope() IS NULL) stay unrestricted.
--
-- Three judgment buckets:
--  (A) member-directory PII → chapter-scope like Slice A (own-chapter allowed, cross-chapter denied/
--      suppressed): get_member_xp_pillars, get_member_champions_history, resolve_whatsapp_link,
--      admin_list_member_consents.
--  (B) org-governance / IP-legal / audit (entries NOT chapter-tagged) → restrict the non-owner/
--      privileged path to GP/sede: get_exclusion_declaration, export_anexo_i, export_audit_log_csv,
--      get_governance_change_log.
--  (C) initiative/tribe contacts (org-scope subsumes the resource gate) → require RESOURCE-SPECIFIC
--      standing for chapter-restricted callers, preserving legitimate cross-chapter collaboration:
--      get_initiative_member_contacts (active engagement in the initiative), get_tribe_member_contacts
--      (own tribe_id or a tribe-scoped engagement).
--
-- NOT touched (verified by grounding): record_ai_validation (write; selection-COI lane = ADR-0109),
-- revoke_exclusion_declaration (owner-only; 'view_pii' appears only in a comment), admin_get_tribe_allocations
-- (already manage_platform-gated → no partner-chapter exposure). No seed change, no new scope value, no
-- ACL change (CREATE OR REPLACE preserves grants). Cross-ref: ADR-0105, docs/reference/V4_AUTHORITY_MODEL.md
-- (Caminho 3), handoff pt7 FU-2, issue #952.

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- BUCKET A — member-directory PII: chapter-scope (Slice A pattern)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

-- ── get_member_xp_pillars: org-scoped view_pii must not bypass another chapter's gamification opt-out ──
CREATE OR REPLACE FUNCTION public.get_member_xp_pillars(p_member_id uuid DEFAULT NULL::uuid, p_cycle_code text DEFAULT NULL::text, p_scope text DEFAULT 'lifetime'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_target_id uuid;
  v_target members%ROWTYPE;
  v_is_self boolean;
  v_can_view_pii boolean;
  v_scope text;
  v_cycle_code text;
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF p_scope NOT IN ('cycle','lifetime') THEN
    RETURN jsonb_build_object('error','invalid_scope','detail','must be cycle or lifetime');
  END IF;

  v_target_id := COALESCE(p_member_id, v_caller.id);
  v_is_self := (v_target_id = v_caller.id);

  SELECT * INTO v_target FROM members WHERE id = v_target_id;
  IF v_target.id IS NULL THEN
    RETURN jsonb_build_object('error','member_not_found');
  END IF;
  IF v_target.organization_id != v_caller.organization_id THEN
    RETURN jsonb_build_object('error','member_not_in_org');
  END IF;

  IF NOT v_is_self THEN
    v_can_view_pii := public.can_by_member(v_caller.id, 'view_pii'::text);
    -- FU-2 Slice C: an org-scoped view_pii grant must not elevate a chapter-restricted caller
    -- (partner-chapter leader) past another chapter's gamification opt-out. GP/sede (scope NULL)
    -- keep the elevation; everyone else falls back to the public/opt-out path cross-chapter.
    v_scope := public.caller_chapter_scope();
    IF v_can_view_pii AND v_scope IS NOT NULL AND v_target.chapter IS DISTINCT FROM v_scope THEN
      v_can_view_pii := false;
    END IF;
    IF NOT v_can_view_pii AND COALESCE(v_target.gamification_opt_out, false) THEN
      RETURN jsonb_build_object('error','member_opted_out_from_public');
    END IF;
  END IF;

  IF p_scope = 'cycle' THEN
    IF p_cycle_code IS NULL THEN
      SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
        INTO v_cycle_code, v_cycle_start, v_cycle_end
      FROM cycles WHERE is_current = true LIMIT 1;
    ELSE
      SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
        INTO v_cycle_code, v_cycle_start, v_cycle_end
      FROM cycles WHERE cycle_code = p_cycle_code LIMIT 1;
      IF v_cycle_code IS NULL THEN
        RETURN jsonb_build_object('error','cycle_not_found');
      END IF;
    END IF;
  END IF;
  -- lifetime: v_cycle_* stay NULL

  WITH points_filtered AS (
    SELECT gp.category, gp.points
    FROM gamification_points gp
    WHERE gp.member_id = v_target_id
      AND gp.organization_id = v_caller.organization_id
      AND (
        p_scope = 'lifetime'
        OR (gp.created_at >= v_cycle_start
            AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + interval '1 day')))
      )
  ),
  rule_breakdown AS (
    SELECT
      r.pillar,
      r.slug,
      r.display_name_i18n,
      r.description_i18n,
      r.base_points,
      r.cap_points,
      r.trigger_source,
      COALESCE(SUM(p.points), 0)::int AS pts,
      COUNT(p.points)::int AS earned_count
    FROM gamification_rules r
    LEFT JOIN points_filtered p ON p.category = r.slug
    WHERE r.organization_id = v_caller.organization_id
      AND r.active = true
    GROUP BY r.pillar, r.slug, r.display_name_i18n, r.description_i18n, r.base_points, r.cap_points, r.trigger_source
  ),
  pillar_agg AS (
    SELECT
      pillar,
      SUM(pts)::int AS total_pts,
      SUM(earned_count)::int AS earned_count,
      jsonb_agg(
        jsonb_build_object(
          'slug', slug,
          'display_name_i18n', display_name_i18n,
          'description_i18n', description_i18n,
          'base_points', base_points,
          'cap_points', cap_points,
          'trigger_source', trigger_source,
          'pts', pts,
          'count', earned_count
        ) ORDER BY pts DESC, slug
      ) AS rules
    FROM rule_breakdown
    GROUP BY pillar
  )
  SELECT jsonb_build_object(
    'member_id', v_target_id,
    'member_name', v_target.name,
    'is_self', v_is_self,
    'scope', p_scope,
    'cycle_code', v_cycle_code,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
    'total_pts', COALESCE((SELECT SUM(total_pts)::int FROM pillar_agg), 0),
    'pillars', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'pillar', pillar,
          'total_pts', total_pts,
          'earned_count', earned_count,
          'rules', rules
        )
        ORDER BY CASE pillar
          WHEN 'presenca' THEN 1
          WHEN 'trilha' THEN 2
          WHEN 'certificacoes' THEN 3
          WHEN 'producao' THEN 4
          WHEN 'curadoria' THEN 5
          WHEN 'champions' THEN 6
        END
      ) FROM pillar_agg
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ── get_member_champions_history: same opt-out-bypass demotion cross-chapter ──
CREATE OR REPLACE FUNCTION public.get_member_champions_history(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_target_id uuid;
  v_is_self boolean;
  v_can_view_pii boolean;
  v_target_opted_out boolean;
  v_scope text;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  v_target_id := coalesce(p_member_id, v_caller.id);
  v_is_self := (v_target_id = v_caller.id);

  IF NOT v_is_self THEN
    v_can_view_pii := public.can_by_member(v_caller.id, 'view_pii'::text);
    SELECT coalesce(gamification_opt_out, false) INTO v_target_opted_out
    FROM members WHERE id = v_target_id;
    -- FU-2 Slice C: org-scoped view_pii must not bypass another chapter's opt-out for a
    -- chapter-restricted caller. GP/sede (scope NULL) keep the elevation.
    v_scope := public.caller_chapter_scope();
    IF v_can_view_pii AND v_scope IS NOT NULL
       AND (SELECT chapter FROM members WHERE id = v_target_id) IS DISTINCT FROM v_scope THEN
      v_can_view_pii := false;
    END IF;
    IF NOT v_can_view_pii AND v_target_opted_out THEN
      RETURN jsonb_build_object('error','member_opted_out_from_public');
    END IF;
  END IF;

  WITH history AS (
    SELECT
      ca.id AS champion_id,
      ca.surface,
      ca.context_kind,
      ca.context_id,
      ca.criteria_met,
      ca.justification,
      ca.points_awarded,
      ca.status,
      ca.revoked_at,
      ca.revoked_reason,
      ca.created_at AS awarded_at,
      jsonb_build_object('id', awarder.id, 'name', awarder.name) AS awarded_by,
      CASE WHEN ca.initiative_id IS NOT NULL THEN
        jsonb_build_object('id', ca.initiative_id,
          'name', (SELECT name FROM initiatives WHERE id = ca.initiative_id))
      ELSE NULL END AS initiative
    FROM champions_awarded ca
    LEFT JOIN members awarder ON awarder.id = ca.awarded_by
    WHERE ca.recipient_id = v_target_id
      AND ca.organization_id = v_caller.organization_id
    ORDER BY ca.created_at DESC
  ),
  totals AS (
    SELECT
      count(*) FILTER (WHERE status='active')::int AS active_count,
      count(*) FILTER (WHERE status='revoked')::int AS revoked_count,
      coalesce(sum(points_awarded) FILTER (WHERE status='active'), 0)::int AS active_points,
      count(*) FILTER (WHERE status='active' AND surface='general')::int AS general_count,
      count(*) FILTER (WHERE status='active' AND surface='tribe')::int AS tribe_count,
      count(*) FILTER (WHERE status='active' AND surface='deliverable')::int AS deliverable_count
    FROM history
  )
  SELECT jsonb_build_object(
    'member_id', v_target_id,
    'is_self', v_is_self,
    'totals', (SELECT to_jsonb(totals.*) FROM totals),
    'history', coalesce((SELECT jsonb_agg(to_jsonb(history.*)) FROM history), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ── resolve_whatsapp_link: deny cross-chapter via org view_pii; keep own-chapter, same-tribe, manager ──
CREATE OR REPLACE FUNCTION public.resolve_whatsapp_link(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_clean_phone text;
  v_scope text;
begin
  -- Get caller
  select id, tribe_id, operational_role, is_superadmin
    into v_caller from public.members where auth_id = v_caller_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Caller not found');
  end if;

  -- Get target
  select id, phone, tribe_id, share_whatsapp, chapter
    into v_target from public.members where id = p_member_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  -- Check opt-in
  if v_target.share_whatsapp is not true then
    return jsonb_build_object('success', false, 'error', 'Member has not opted in');
  end if;

  -- p180 ADR-0011 V4: hybrid V3+V4 PII access gate.
  -- V3 paths preserved (admin override + same-tribe). V4 path added via
  -- can_by_member('view_pii') — covers chapter_board, committee/workgroup
  -- coordinators+leaders, study_group owners, volunteer × {co_gp, leader,
  -- deputy_manager, manager}. Defense-in-depth: V3 stays as fallback if
  -- catalog drifts.
  if not (
    v_caller.is_superadmin = true
    or v_caller.operational_role in ('manager', 'deputy_manager')
    or public.can_by_member(v_caller.id, 'view_pii')
    or (v_caller.tribe_id is not null and v_caller.tribe_id = v_target.tribe_id)
  ) then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  -- FU-2 Slice C: an org-scoped view_pii grant must not unlock a cross-chapter WhatsApp link for a
  -- chapter-restricted caller (partner-chapter leader). Own-chapter and same-tribe stay allowed;
  -- GP/sede/manager (caller_chapter_scope() = NULL) are unrestricted.
  v_scope := public.caller_chapter_scope();
  if v_scope is not null
     and v_target.chapter is distinct from v_scope
     and not (v_caller.tribe_id is not null and v_caller.tribe_id = v_target.tribe_id)
  then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  -- No phone registered
  if v_target.phone is null or v_target.phone = '' then
    return jsonb_build_object('success', false, 'error', 'No phone registered');
  end if;

  -- Clean phone: keep only digits
  v_clean_phone := regexp_replace(v_target.phone, '[^0-9]', '', 'g');

  return jsonb_build_object(
    'success', true,
    'url', 'https://wa.me/' || v_clean_phone
  );
end;
$function$;

-- ── admin_list_member_consents: deny cross-chapter (single-target); org fence is a no-op for chapter ──
CREATE OR REPLACE FUNCTION public.admin_list_member_consents(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org_id uuid;
  v_target_org_id uuid;
  v_scope text;
  v_result jsonb;
BEGIN
  SELECT m.id, m.organization_id INTO v_caller_id, v_caller_org_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  -- Multi-tenant fence (CRITICAL): SECDEF bypasses the RESTRICTIVE org-scope RLS policy, and
  -- can_by_member('view_pii') is satisfied by the caller holding view_pii in ANY engagement —
  -- it does NOT bound the TARGET. Re-enforce org isolation here.
  SELECT m.organization_id INTO v_target_org_id FROM public.members m WHERE m.id = p_member_id;
  IF v_target_org_id IS NULL OR v_caller_org_id IS NULL OR v_target_org_id <> v_caller_org_id THEN
    RAISE EXCEPTION 'Access denied: target member not in caller organization';
  END IF;

  -- FU-2 Slice C: chapter-scope — a non-GP/non-sede caller may not read another chapter's consent
  -- history (the org fence above is a no-op while all chapters share one organization). Self always allowed.
  v_scope := public.caller_chapter_scope();
  IF v_scope IS NOT NULL AND p_member_id <> v_caller_id
     AND (SELECT chapter FROM public.members WHERE id = p_member_id) IS DISTINCT FROM v_scope THEN
    RAISE EXCEPTION 'Access denied: cross-chapter member consents';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cr.id,
    'member_id', cr.member_id,
    'application_id', cr.application_id,
    'policy_type', cr.policy_type,
    'policy_version', cr.policy_version,
    'policy_document_id', cr.policy_document_id,
    'accepted_at', cr.accepted_at,
    'channel', cr.channel,
    -- capture-evidence hashes (pseudonymized) — relevant to a consent audit; view_pii-gated + logged.
    'email_hash', cr.email_hash,
    'ip_hash', cr.ip_hash,
    'user_agent_hash', cr.user_agent_hash,
    'revoked_at', cr.revoked_at,
    'revocation_reason', cr.revocation_reason,
    'is_active', (cr.revoked_at IS NULL),
    'created_at', cr.created_at
  ) ORDER BY cr.accepted_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.consent_records cr
  WHERE cr.member_id = p_member_id
    AND cr.organization_id = v_caller_org_id;

  -- Accountability (Art. 37): log EVERY admin read of consent history, incl. self-reads via this path.
  INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, accessed_at)
  VALUES (v_caller_id, p_member_id, ARRAY['consent_history']::text[], 'admin_list_member_consents', 'consent audit', now());

  RETURN v_result;
END;
$function$;

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- BUCKET B — org-governance / IP-legal / audit: restrict non-owner/privileged path to GP/sede
-- ════════════════════════════════════════════════════════════════════════════════════════════════

-- ── get_exclusion_declaration: PI-exclusion fiscalization (non-owner) is GP/sede-only ──
CREATE OR REPLACE FUNCTION public.get_exclusion_declaration(p_declaration_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id  uuid;
  v_caller_org uuid;
  v_owner      uuid;
  v_decl_org   uuid;
  v_is_admin   boolean := false;
  v_result     jsonb;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_caller_org FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT declarant_member_id, organization_id INTO v_owner, v_decl_org
  FROM public.pi_exclusion_declarations WHERE id = p_declaration_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Declaration not found'; END IF;

  IF v_owner <> v_member_id THEN
    -- fiscalization path: view_pii + org fence (SECDEF bypasses RLS; view_pii doesn't bound the target).
    IF NOT public.can_by_member(v_member_id, 'view_pii') THEN
      RAISE EXCEPTION 'Access denied: not the declarant and missing view_pii';
    END IF;
    IF v_decl_org IS NULL OR v_caller_org IS NULL OR v_decl_org <> v_caller_org THEN
      RAISE EXCEPTION 'Access denied: declaration not in caller organization';
    END IF;
    -- FU-2 Slice C: PI-exclusion fiscalization is an org-governance/legal function (declarations are
    -- not chapter-tagged); restrict the non-owner path to GP/sede. A partner-chapter view_pii holder
    -- is not a fiscalizer.
    IF public.caller_chapter_scope() IS NOT NULL THEN
      RAISE EXCEPTION 'Access denied: PI-exclusion fiscalization restricted to GP/sede';
    END IF;
    v_is_admin := true;
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, accessed_at)
    VALUES (v_member_id, v_owner, ARRAY['pi_exclusion_declaration']::text[], 'get_exclusion_declaration', 'PI exclusion fiscalization', now());
  END IF;

  SELECT jsonb_build_object(
    'id', d.id,
    'title', d.title,
    'status', d.status,
    'declarant_member_id', d.declarant_member_id,
    'governance_document_id', d.governance_document_id,
    'created_at', d.created_at,
    'viewed_as', CASE WHEN v_is_admin THEN 'fiscalization' ELSE 'declarant' END,
    'assets', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'seq', a.seq, 'title', a.title, 'nature', a.nature,
        'author_label', a.author_label, 'work_created_on', a.work_created_on, 'source_ref', a.source_ref,
        'sha256', a.sha256, 'ots_status', a.ots_status, 'has_proof', (a.ots_proof IS NOT NULL),
        'bitcoin_block', a.bitcoin_block, 'attested_at', a.attested_at, 'reinforcement', a.reinforcement
      ) ORDER BY a.seq)
      FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id AND a.organization_id = d.organization_id
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.pi_exclusion_declarations d WHERE d.id = p_declaration_id;

  RETURN v_result;
END;
$function$;

-- ── export_anexo_i: PI-exclusion fiscalization export (non-owner) is GP/sede-only ──
CREATE OR REPLACE FUNCTION public.export_anexo_i(p_declaration_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id  uuid;
  v_caller_org uuid;
  v_owner      uuid;
  v_decl_org   uuid;
  v_total      integer;
  v_confirmed  integer;
  v_pending    integer;
  v_unstamped  integer;
  v_error      integer;
  v_rows       jsonb;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_caller_org FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT declarant_member_id, organization_id INTO v_owner, v_decl_org
  FROM public.pi_exclusion_declarations WHERE id = p_declaration_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Declaration not found'; END IF;

  IF v_owner <> v_member_id THEN
    IF NOT public.can_by_member(v_member_id, 'view_pii') THEN
      RAISE EXCEPTION 'Access denied: not the declarant and missing view_pii';
    END IF;
    IF v_decl_org IS NULL OR v_caller_org IS NULL OR v_decl_org <> v_caller_org THEN
      RAISE EXCEPTION 'Access denied: declaration not in caller organization';
    END IF;
    -- FU-2 Slice C: fiscalization export restricted to GP/sede (declarations are not chapter-tagged).
    IF public.caller_chapter_scope() IS NOT NULL THEN
      RAISE EXCEPTION 'Access denied: PI-exclusion fiscalization restricted to GP/sede';
    END IF;
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, accessed_at)
    VALUES (v_member_id, v_owner, ARRAY['pi_exclusion_anexo_i']::text[], 'export_anexo_i', 'PI exclusion fiscalization export', now());
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE ots_status = 'confirmed'),
         count(*) FILTER (WHERE ots_status = 'pending'),
         count(*) FILTER (WHERE ots_status = 'unstamped'),
         count(*) FILTER (WHERE ots_status = 'error')
  INTO v_total, v_confirmed, v_pending, v_unstamped, v_error
  FROM public.pi_exclusion_assets WHERE declaration_id = p_declaration_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'seq', a.seq,
    'titulo', a.title,
    'natureza', a.nature,
    'autor_capitulo', a.author_label,
    'data_criacao', a.work_created_on,
    'caminho_url', a.source_ref,
    'sha256', a.sha256,
    'prova_ots', (a.ots_proof IS NOT NULL),
    'status', a.ots_status,
    'ancoragem', CASE WHEN a.ots_status = 'confirmed'
      THEN jsonb_build_object('bloco', a.bitcoin_block, 'utc', a.attested_at) ELSE NULL END,
    'reforco', a.reinforcement
  ) ORDER BY a.seq), '[]'::jsonb)
  INTO v_rows
  FROM public.pi_exclusion_assets a WHERE a.declaration_id = p_declaration_id;

  RETURN jsonb_build_object(
    'declaration_id', p_declaration_id,
    'total_assets', v_total,
    'confirmed_assets', v_confirmed,
    'pending_assets', v_pending,        -- aguardando ancoragem Bitcoin (carimbo já submetido)
    'unstamped_assets', v_unstamped,    -- ainda não carimbados
    'error_assets', v_error,            -- falha permanente do pipeline (≥5 tentativas) — NÃO é "aguardando"
    'all_confirmed', (v_total > 0 AND v_confirmed = v_total),  -- eficácia probatória plena exige TODOS confirmed
    'anexo_i', v_rows,
    'digest_only_notice', 'Carimbo de tempo digest-only: a plataforma atesta que o hash SHA-256 existia na data ancorada na blockchain; NÃO armazena a obra nem verifica que o digest corresponde ao arquivo final (responsabilidade do declarante — doc9 §B vi).',
    'exported_at', now()
  );
END;
$function$;

-- ── export_audit_log_csv: org-wide governance artifact (not chapter-tagged) → GP/sede-only ──
CREATE OR REPLACE FUNCTION public.export_audit_log_csv(p_category text DEFAULT 'all'::text, p_start_date text DEFAULT NULL::text, p_end_date text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_csv text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN 'Unauthorized'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RETURN 'Unauthorized: requires view_pii permission';
  END IF;
  -- FU-2 Slice C: the audit-log CSV is an org-wide governance artifact (entries are not chapter-tagged
  -- — member status/role changes, settings, partnerships); restrict to GP/sede.
  IF public.caller_chapter_scope() IS NOT NULL THEN
    RETURN 'Unauthorized: audit-log export restricted to GP/sede';
  END IF;

  SELECT string_agg(
    category||','||to_char(event_date,'YYYY-MM-DD HH24:MI')||','||
    COALESCE(replace(actor_name,',',';'),'')||','||
    COALESCE(replace(action,',',';'),'')||','||
    COALESCE(replace(subject,',',';'),'')||','||
    COALESCE(replace(summary,',',';'),'')||','||
    COALESCE(replace(detail,',',';'),''),
    E'\n'
  ) INTO v_csv
  FROM (
    SELECT
      'members' AS category,
      al.created_at AS event_date,
      actor.name AS actor_name,
      CASE al.action
        WHEN 'member.status_transition' THEN 'status_change'
        WHEN 'member.role_change' THEN 'role_change'
        ELSE al.action
      END AS action,
      target.name AS subject,
      CASE al.action
        WHEN 'member.status_transition' THEN
          COALESCE(al.changes->>'previous_status','') || ' → ' || COALESCE(al.changes->>'new_status','')
        WHEN 'member.role_change' THEN
          COALESCE(al.changes->>'old_value','') || ' → ' || COALESCE(al.changes->>'new_value','')
        ELSE al.changes::text
      END AS summary,
      COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor  ON actor.id  = al.actor_id
    LEFT JOIN public.members target ON target.id = al.target_id
    WHERE (p_category = 'all' OR p_category = 'members')
      AND al.action IN ('member.status_transition','member.role_change')
      AND (p_start_date IS NULL OR al.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR al.created_at <= (p_end_date::date + 1)::timestamptz)
    UNION ALL
    SELECT
      'settings', al.created_at, actor.name, 'setting_changed',
      COALESCE(al.metadata->>'setting_key', '(unknown)'),
      COALESCE(al.changes->>'previous_value','?') || ' → ' || COALESCE(al.changes->>'new_value','?'),
      al.metadata->>'reason'
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE (p_category='all' OR p_category='settings')
      AND al.action = 'platform.setting_changed'
      AND (p_start_date IS NULL OR al.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR al.created_at <= (p_end_date::date + 1)::timestamptz)
    UNION ALL
    SELECT
      'partnerships', pi.created_at, actor.name, pi.interaction_type, pe.name,
      pi.summary, pi.outcome
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
    WHERE (p_category='all' OR p_category='partnerships')
      AND (p_start_date IS NULL OR pi.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR pi.created_at <= (p_end_date::date + 1)::timestamptz)
    ORDER BY event_date DESC
  ) entries;

  RETURN 'Categoria,Data,Actor,Ação,Assunto,Resumo,Detalhe' || E'\n' || COALESCE(v_csv,'');
END;
$function$;

-- ── get_governance_change_log: privileged (org-wide) feed → GP/sede only; others get own-actor events ──
CREATE OR REPLACE FUNCTION public.get_governance_change_log(p_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 200, p_include_payload boolean DEFAULT true)
 RETURNS TABLE(event_time timestamp with time zone, event_source text, event_kind text, actor_id uuid, actor_name text, target_type text, target_id uuid, target_label text, payload jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_is_privileged boolean;
  v_since timestamptz;
  v_limit int;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- FU-2 Slice C: the privileged (org-wide) governance feed — incl. the pii_access_log + admin_audit_log
  -- rows — is restricted to GP/sede; a chapter-restricted caller (partner-chapter leader) falls back to
  -- their own-actor events only. Entries are not chapter-tagged, so there is no per-chapter view.
  v_is_privileged := public.can_by_member(v_member_id, 'view_pii') AND public.caller_chapter_scope() IS NULL;
  v_since := COALESCE(p_since, now() - interval '90 days');
  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 200), 1000));

  RETURN QUERY
  WITH events AS (
    SELECT cr.submitted_at AS event_time, 'change_request'::text AS event_source, 'cr_submitted'::text AS event_kind,
      cr.requested_by AS actor_id, am.name AS actor_name, 'change_request'::text AS target_type, cr.id AS target_id,
      ('CR#' || cr.cr_number || ' — ' || cr.title) AS target_label,
      jsonb_build_object('cr_number', cr.cr_number, 'title', cr.title, 'cr_type', cr.cr_type, 'impact_level', cr.impact_level, 'status', cr.status) AS payload
    FROM public.change_requests cr
    LEFT JOIN public.members am ON am.id = cr.requested_by
    WHERE cr.submitted_at IS NOT NULL AND cr.submitted_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR v_member_id = ANY(cr.approved_by_members))
    UNION ALL
    SELECT cr.approved_at, 'change_request'::text, 'cr_approved'::text, NULL::uuid, NULL::text, 'change_request'::text, cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object('cr_number', cr.cr_number, 'approved_by_members', cr.approved_by_members, 'impact_level', cr.impact_level)
    FROM public.change_requests cr
    WHERE cr.approved_at IS NOT NULL AND cr.approved_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR v_member_id = ANY(cr.approved_by_members))
    UNION ALL
    SELECT cr.reviewed_at, 'change_request'::text, 'cr_reviewed'::text, cr.reviewed_by, rm.name, 'change_request'::text, cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object('cr_number', cr.cr_number, 'review_notes', cr.review_notes)
    FROM public.change_requests cr
    LEFT JOIN public.members rm ON rm.id = cr.reviewed_by
    WHERE cr.reviewed_at IS NOT NULL AND cr.reviewed_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR cr.reviewed_by = v_member_id)
    UNION ALL
    SELECT cr.implemented_at, 'change_request'::text, 'cr_implemented'::text, cr.implemented_by, im.name, 'change_request'::text, cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object('cr_number', cr.cr_number, 'manual_version_from', cr.manual_version_from, 'manual_version_to', cr.manual_version_to)
    FROM public.change_requests cr
    LEFT JOIN public.members im ON im.id = cr.implemented_by
    WHERE cr.implemented_at IS NOT NULL AND cr.implemented_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR cr.implemented_by = v_member_id)
    UNION ALL
    SELECT dv.authored_at, 'document_version'::text, 'version_authored'::text, dv.authored_by, am.name, 'document_version'::text, dv.id,
      (gd.title || ' — ' || dv.version_label),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_number', dv.version_number, 'version_label', dv.version_label, 'is_draft', (dv.locked_at IS NULL))
    FROM public.document_versions dv
    JOIN public.governance_documents gd ON gd.id = dv.document_id
    LEFT JOIN public.members am ON am.id = dv.authored_by
    WHERE dv.authored_at >= v_since AND (v_is_privileged OR dv.authored_by = v_member_id)
    UNION ALL
    SELECT dv.locked_at, 'document_version'::text, 'version_locked'::text, dv.locked_by, lm.name, 'document_version'::text, dv.id,
      (gd.title || ' — ' || dv.version_label),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_number', dv.version_number, 'version_label', dv.version_label, 'published_at', dv.published_at)
    FROM public.document_versions dv
    JOIN public.governance_documents gd ON gd.id = dv.document_id
    LEFT JOIN public.members lm ON lm.id = dv.locked_by
    WHERE dv.locked_at IS NOT NULL AND dv.locked_at >= v_since
      AND (v_is_privileged OR dv.locked_by = v_member_id)
    UNION ALL
    SELECT ac.opened_at, 'approval_chain'::text, 'chain_opened'::text, ac.opened_by, om.name, 'approval_chain'::text, ac.id,
      (gd.title || ' — chain opened'),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_id', ac.version_id, 'status', ac.status, 'gates_count', jsonb_array_length(ac.gates))
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    LEFT JOIN public.members om ON om.id = ac.opened_by
    WHERE ac.opened_at IS NOT NULL AND ac.opened_at >= v_since
      AND (v_is_privileged OR ac.opened_by = v_member_id)
    UNION ALL
    SELECT ac.approved_at, 'approval_chain'::text, 'chain_approved'::text, NULL::uuid, NULL::text, 'approval_chain'::text, ac.id,
      (gd.title || ' — chain approved'),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_id', ac.version_id)
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    WHERE ac.approved_at IS NOT NULL AND ac.approved_at >= v_since
      AND v_is_privileged
    UNION ALL
    SELECT ac.activated_at, 'approval_chain'::text, 'chain_activated'::text, NULL::uuid, NULL::text, 'approval_chain'::text, ac.id,
      (gd.title || ' — activated'),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_id', ac.version_id)
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    WHERE ac.activated_at IS NOT NULL AND ac.activated_at >= v_since
      AND v_is_privileged
    UNION ALL
    SELECT s.signed_at, 'approval_signoff'::text, 'signoff_recorded'::text, s.signer_id, sm.name, 'approval_signoff'::text, s.id,
      (gd.title || ' — gate ' || s.gate_kind),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'chain_id', s.approval_chain_id, 'gate_kind', s.gate_kind, 'signoff_type', s.signoff_type)
    FROM public.approval_signoffs s
    JOIN public.approval_chains ac ON ac.id = s.approval_chain_id
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    LEFT JOIN public.members sm ON sm.id = s.signer_id
    WHERE s.signed_at >= v_since AND (v_is_privileged OR s.signer_id = v_member_id)
    UNION ALL
    SELECT p.accessed_at, 'pii_access'::text, 'pii_accessed'::text, p.accessor_id, am.name, 'member'::text, p.target_member_id,
      ('PII access — ' || COALESCE(tm.name, 'target') || ' via ' || COALESCE(p.context, 'unknown')),
      jsonb_build_object('fields_accessed', p.fields_accessed, 'context', p.context, 'reason', p.reason)
    FROM public.pii_access_log p
    LEFT JOIN public.members am ON am.id = p.accessor_id
    LEFT JOIN public.members tm ON tm.id = p.target_member_id
    WHERE p.accessed_at >= v_since
      AND (v_is_privileged OR p.accessor_id = v_member_id OR p.target_member_id = v_member_id)
    UNION ALL
    SELECT a.created_at, 'admin_audit'::text, a.action, a.actor_id, am.name, a.target_type, a.target_id,
      (COALESCE(a.target_type, 'entity') || ' ' || COALESCE(a.action, 'action')),
      jsonb_build_object('changes', a.changes, 'metadata', a.metadata)
    FROM public.admin_audit_log a
    LEFT JOIN public.members am ON am.id = a.actor_id
    WHERE a.created_at >= v_since AND (v_is_privileged OR a.actor_id = v_member_id)
  )
  SELECT
    e.event_time, e.event_source, e.event_kind,
    e.actor_id, e.actor_name, e.target_type, e.target_id, e.target_label,
    CASE WHEN p_include_payload THEN e.payload ELSE NULL::jsonb END AS payload
  FROM events e
  ORDER BY e.event_time DESC NULLS LAST
  LIMIT v_limit;
END;
$function$;

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- BUCKET C — initiative/tribe contacts: require RESOURCE-specific standing for chapter-restricted callers
-- (org-scope subsumes the resource gate in can()/rls_can_for_tribe → an org view_pii holder would
--  otherwise read ANY initiative/tribe; cross-chapter members of one's OWN resource stay visible).
-- ════════════════════════════════════════════════════════════════════════════════════════════════

-- ── get_initiative_member_contacts: chapter-restricted caller must be actively engaged in the initiative ──
CREATE OR REPLACE FUNCTION public.get_initiative_member_contacts(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_can_view_pii boolean;
  v_accessed_ids uuid[];
  v_result jsonb;
BEGIN
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  v_can_view_pii := can(v_caller_person_id, 'view_pii', 'initiative', p_initiative_id);

  IF NOT v_can_view_pii THEN
    RETURN '{}'::jsonb;
  END IF;

  -- FU-2 Slice C: can() grants on org/global scope regardless of resource, so an org-scoped view_pii
  -- holder (partner-chapter leader) would otherwise read ANY initiative's contacts. A chapter-restricted
  -- caller must have standing IN this initiative (an active engagement). GP/sede (scope NULL) unrestricted.
  IF public.caller_chapter_scope() IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM engagements e
       WHERE e.person_id = v_caller_person_id
         AND e.initiative_id = p_initiative_id
         AND e.status = 'active'
     ) THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT array_agg(m.id)
  INTO v_accessed_ids
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id
    AND e.status = 'active';

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['email','phone','share_whatsapp']::text[],
    'get_initiative_member_contacts',
    'initiative ' || p_initiative_id::text
  );

  SELECT jsonb_object_agg(
    m.id::text,
    jsonb_build_object(
      'email', m.email,
      'phone', m.phone,
      'share_whatsapp', m.share_whatsapp
    )
  ) INTO v_result
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id
    AND e.status = 'active';

  RETURN coalesce(v_result, '{}'::jsonb);
END;
$function$;

-- ── get_tribe_member_contacts: chapter-restricted caller must belong to (or lead) this tribe ──
CREATE OR REPLACE FUNCTION public.get_tribe_member_contacts(p_tribe_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_can boolean;
  v_accessed_ids uuid[];
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN '{}'::json; END IF;

  -- V4: org-wide PII access OR tribe-scoped write authority (tribe_leader has write_for_tribe)
  v_can := public.can_by_member(v_caller_id, 'view_pii')
        OR public.rls_can_for_tribe('write'::text, p_tribe_id);
  IF NOT v_can THEN RETURN '{}'::json; END IF;

  -- FU-2 Slice C: both disjuncts grant on org/global scope (org-wide view_pii; org-scoped tribe write),
  -- so a partner-chapter leader could read ANY tribe's contacts. A chapter-restricted caller must belong
  -- to this tribe (own tribe_id) or hold a tribe-SPECIFIC (initiative-scoped) engagement for it. GP/sede
  -- (scope NULL) unrestricted; cross-chapter members of one's OWN tribe stay visible.
  -- (NULL-safe: COALESCE the caller's tribe_id so a NULL-tribe partner-chapter director — e.g. a
  -- chapter_board member — is denied rather than slipping through a NULL comparison.)
  IF public.caller_chapter_scope() IS NOT NULL
     AND COALESCE((SELECT tribe_id FROM public.members WHERE id = v_caller_id), -1) <> p_tribe_id
     AND NOT EXISTS (
       SELECT 1 FROM public.auth_engagements ae
       WHERE ae.auth_id = auth.uid() AND ae.is_authoritative = true AND ae.legacy_tribe_id = p_tribe_id
     ) THEN
    RETURN '{}'::json;
  END IF;

  SELECT array_agg(m.id) INTO v_accessed_ids
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true;

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['email','phone']::text[],
    'get_tribe_member_contacts',
    'tribe ' || p_tribe_id
  );

  RETURN (
    SELECT coalesce(
      json_object_agg(m.id, json_build_object('email', m.email, 'phone', m.phone)),
      '{}'::json
    )
    FROM public.members m
    WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
