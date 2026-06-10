-- Migration: 20260805000142_p625_c0_admin_list_members_pre_onboarding
-- Issue: #625 Camada 0 — coorte pré-onboarding contada como ativo pleno em /admin/members
-- Refs: ADR-0100/G6 (classe denominador, mesma família do #419), ADR-0006/0007 (V4),
--       grounded 2026-06-10: 26 members do ciclo 4 criados 'active' na aprovação com TODOS
--       os engagements ainda pendentes de termo → "Ativos" inflado de ~47 para 73.
--       Body regenerado do LIVE prosrc; assinatura idêntica (4 params c/ DEFAULTs — probe feito).
--
-- WHAT
--   admin_list_members ganha:
--   1. Campo derivado `is_pre_onboarding` (por member): member_status='active' E tem >=1
--      engagement ativo E NENHUM engagement ativo é "operacional" — operacional = kind que
--      não exige termo OU termo já satisfeito (agreement_certificate_id). Um membro
--      existente assumindo papel novo (termo lateral pendente) NÃO vira pré-onboarding,
--      porque os engagements antigos operacionais continuam contando.
--   2. p_status = 'pre_onboarding' (aditivo): retorna só essa coorte.
--   COMPAT: p_status='active' mantém a semântica legada (todos member_status='active') —
--   o island particiona client-side pelo flag; o consumidor MCP recebe o campo novo de
--   forma aditiva (campo extra em jsonb não quebra nada).
--
-- ROLLBACK
--   Restore o body da captura anterior (20260681000000 / drift-capture) — remove o LATERAL
--   `pre` + o campo + o ramo de filtro.
--
-- OPERATIONAL KINDS at ship time (requires_agreement=false → count as operational): observer,
-- guest, chapter_board, sponsor, committee_member, committee_coordinator, workgroup_member,
-- workgroup_coordinator, ambassador, study_group_participant, speaker, external partners etc.
-- NOT operational while term pending (requires_agreement=true): volunteer, study_group_owner,
-- external_reviewer. An observer-only active member is therefore OPERATING (deliberate light
-- role), not pre-onboarding. Source of truth: engagement_kinds.requires_agreement (config).
--
-- After apply: NOTIFY pgrst, 'reload schema'.

CREATE OR REPLACE FUNCTION public.admin_list_members(
  p_search text DEFAULT NULL::text,
  p_tier text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_status text DEFAULT 'active'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'full_name', m.name,
      'email', m.email,
      'photo_url', m.photo_url,
      'operational_role', m.operational_role,
      'designations', m.designations,
      'is_superadmin', m.is_superadmin,
      'is_active', m.is_active,
      'member_status', m.member_status,
      'tribe_id', m.tribe_id,
      'tribe_name', tc.name,
      'chapter', m.chapter,
      'auth_id', m.auth_id,
      'last_seen_at', m.last_seen_at,
      'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_username', m.credly_url,
      'offboarded_at', m.offboarded_at,
      'status_change_reason', m.status_change_reason,
      'vep_status_raw', vep.vep_status_raw,
      'vep_last_seen_at', vep.vep_last_seen_at,
      'is_pre_onboarding', COALESCE(pre.flag, false)
    ) ORDER BY m.name), '[]'::jsonb)
    FROM public.members m
    LEFT JOIN public.tribes tc ON tc.id = m.tribe_id
    LEFT JOIN LATERAL (
      SELECT a.vep_status_raw, a.vep_last_seen_at
      FROM public.selection_applications a
      WHERE lower(a.email) = lower(m.email)
        AND a.vep_status_raw IS NOT NULL
      ORDER BY a.vep_last_seen_at DESC NULLS LAST
      LIMIT 1
    ) vep ON true
    -- #625 C0: pré-onboarding = ativo cujo ÚNICO vínculo são engagements aguardando termo.
    -- Operacional = kind sem exigência de termo OU termo satisfeito; existir 1 operacional
    -- tira o membro da coorte (papel lateral pendente não rebaixa membro existente).
    LEFT JOIN LATERAL (
      SELECT (
        m.member_status = 'active'
        AND EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.engagement_kinds ek ON ek.slug = e.kind
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND (ek.requires_agreement IS NOT TRUE OR e.agreement_certificate_id IS NOT NULL)
        )
      ) AS flag
    ) pre ON true
    WHERE (p_status = 'all'
        OR (p_status = 'active' AND m.member_status = 'active')
        OR (p_status = 'inactive' AND m.member_status = 'inactive')
        OR (p_status = 'observer' AND m.member_status = 'observer')
        OR (p_status = 'alumni' AND m.member_status = 'alumni')
        OR (p_status = 'pre_onboarding' AND m.member_status = 'active' AND COALESCE(pre.flag, false)))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
  );
END;
$function$;

-- ACL unchanged but restated for single-file auditability (CREATE OR REPLACE preserves it).
REVOKE ALL ON FUNCTION public.admin_list_members(text, text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_members(text, text, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_members(text, text, integer, text) TO service_role;

NOTIFY pgrst, 'reload schema';
