-- =====================================================================================
-- #727 (#625 follow-up) — admin_list_members: surface member geo (country + state) so the
--        /admin/members list can offer client-side geo + affiliation-status filters.
--
-- WHAT CHANGES (body-only CREATE OR REPLACE — signature/return type unchanged = jsonb):
--   Two extra keys ('country', 'state') are added to each member object, read straight from
--   members.country / members.state. No signature change (client-side filtering per the #996
--   pattern — the list is not paginated, the whole cohort is already loaded), no new join, and
--   the affiliation farol keeps being DERIVED CLIENT-SIDE from the affiliation_* fields already
--   surfaced (SSOT single — no farol logic replicated in SQL).
--
-- INVARIANTS PRESERVED (not re-litigated):
--   - Gate unchanged: can_by_member(view_internal_analytics); fail-closed on caller NULL.
--   - No new PII beyond geo already stored on the member row (surfaced to the same admin gate).
--   - Cohort/filter predicates unchanged.
--
-- ROLLBACK: re-apply the pre-#727 body (migration that last defined admin_list_members).
-- =====================================================================================
CREATE OR REPLACE FUNCTION public.admin_list_members(p_search text DEFAULT NULL::text, p_tier text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_status text DEFAULT 'active'::text, p_initiative_id uuid DEFAULT NULL::uuid, p_chapter text DEFAULT NULL::text, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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
      -- #727 (#625 follow-up): geo surfaced for client-side estado/país filters
      'country', m.country,
      'state', m.state,
      'auth_id', m.auth_id,
      'last_seen_at', m.last_seen_at,
      'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_username', m.credly_url,
      'offboarded_at', m.offboarded_at,
      'status_change_reason', m.status_change_reason,
      'vep_status_raw', vep.vep_status_raw,
      'vep_last_seen_at', vep.vep_last_seen_at,
      'is_pre_onboarding', public.member_is_pre_onboarding(m.person_id, m.member_status),
      -- #625 F1: farol de filiacao (cache + ultima verificacao da trilha append-only)
      'pmi_id_verified', COALESCE(m.pmi_id_verified, false),
      'affiliation_last_verified_at', aff.last_verified_at,
      'affiliation_active', aff.membership_active,
      'affiliation_expires_on', aff.membership_expires_on,
      'affiliation_method', aff.method,
      -- #625 C2: V4-native — engagements ativos com vocabulario do catalogo (display_name PT + display_i18n)
      'engagements', COALESCE(eng.engagements, '[]'::jsonb),
      -- #625 C2: ciclos em que o membro participou (member_cycle_history)
      'cycles', COALESCE(cyc.cycles, '[]'::jsonb),
      -- #625 C2 (D2=B1): farol do termo de voluntario. amber = existe engagement ativo que
      -- exige termo e ainda nao tem certificado; green = nenhum pendente. 'vencido' = #571.
      'term_status', CASE WHEN EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.engagement_kinds ek ON ek.slug = e.kind
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND ek.requires_agreement IS TRUE AND e.agreement_certificate_id IS NULL
        ) THEN 'amber' ELSE 'green' END
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
    LEFT JOIN LATERAL (
      SELECT mav.created_at AS last_verified_at, mav.membership_active,
             mav.membership_expires_on, mav.method
      FROM public.member_affiliation_verifications mav
      WHERE mav.member_id = m.id
      ORDER BY mav.created_at DESC
      LIMIT 1
    ) aff ON true
    -- #625 C2: engagements ativos (vinculo V4) + titulo da iniciativa + labels do catalogo
    LEFT JOIN LATERAL (
      SELECT jsonb_agg(jsonb_build_object(
        'kind', e.kind,
        'role', e.role,
        'initiative_id', e.initiative_id,
        'initiative_title', i.title,
        'kind_display_name', ek.display_name,
        'kind_display_i18n', ek.display_i18n
      ) ORDER BY e.granted_at NULLS LAST) AS engagements
      FROM public.engagements e
      JOIN public.engagement_kinds ek ON ek.slug = e.kind
      LEFT JOIN public.initiatives i ON i.id = e.initiative_id
      WHERE e.person_id = m.person_id AND e.status = 'active'
    ) eng ON true
    -- #625 C2: ciclos distintos do historico
    LEFT JOIN LATERAL (
      SELECT jsonb_agg(jsonb_build_object('cycle_code', d.cycle_code, 'cycle_label', d.cycle_label)
                       ORDER BY d.cycle_code) AS cycles
      FROM (SELECT DISTINCT mch.cycle_code, mch.cycle_label
            FROM public.member_cycle_history mch
            WHERE mch.member_id = m.id) d
    ) cyc ON true
    WHERE (p_status = 'all'
        OR (p_status = 'active' AND m.member_status = 'active')
        OR (p_status = 'inactive' AND m.member_status = 'inactive')
        OR (p_status = 'observer' AND m.member_status = 'observer')
        OR (p_status = 'alumni' AND m.member_status = 'alumni')
        OR (p_status = 'pre_onboarding' AND public.member_is_pre_onboarding(m.person_id, m.member_status)))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
      AND (p_chapter IS NULL OR m.chapter = p_chapter)
      -- #625 C2: filtro por iniciativa via engagement ativo (nao so tribo)
      AND (p_initiative_id IS NULL OR EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id AND e.status = 'active' AND e.initiative_id = p_initiative_id))
      -- #625 C2: filtro por ciclo (participou/participa)
      AND (p_cycle IS NULL OR EXISTS (
        SELECT 1 FROM public.member_cycle_history mch
        WHERE mch.member_id = m.id AND mch.cycle_code = p_cycle))
  );
END;
$function$;
