-- p95 #90: MOU stage enum + Integração Nacional dashboard RPC
-- ====================================================================
-- get_chapter_dashboard(p_chapter) JÁ EXISTE (descoberto p95) — #106 backend done.
-- Frontend page /chapters/[code] (#106 UX) deferred to dedicated session.
--
-- Smoke validated p95 2026-05-05: 16 chapters backfilled
-- (5 active + 5 agreed + 6 prospecting). RPC gated correctly.

ALTER TABLE public.partner_entities
  ADD COLUMN IF NOT EXISTS mou_stage text;

ALTER TABLE public.partner_entities
  ADD CONSTRAINT partner_entities_mou_stage_check
  CHECK (mou_stage IS NULL OR mou_stage IN (
    'prospecting',
    'agreed',
    'mou_drafted',
    'mou_sent',
    'mou_signed',
    'active',
    'declined',
    'inactive'
  ));

CREATE INDEX IF NOT EXISTS ix_partner_entities_mou_stage
  ON public.partner_entities (mou_stage)
  WHERE entity_type = 'pmi_chapter' AND mou_stage IS NOT NULL;

UPDATE public.partner_entities SET mou_stage = 'active'
WHERE entity_type = 'pmi_chapter' AND status = 'active' AND mou_stage IS NULL;

UPDATE public.partner_entities SET mou_stage = 'agreed'
WHERE entity_type = 'pmi_chapter' AND status = 'negotiation'
  AND (next_action ILIKE '%enviar%mou%' OR next_action ILIKE '%enviar termo%')
  AND mou_stage IS NULL;

UPDATE public.partner_entities SET mou_stage = 'agreed'
WHERE entity_type = 'pmi_chapter' AND status = 'negotiation'
  AND next_action ILIKE '%aguardando contato%'
  AND mou_stage IS NULL;

UPDATE public.partner_entities SET mou_stage = 'prospecting'
WHERE entity_type = 'pmi_chapter' AND status = 'negotiation'
  AND next_action ILIKE '%aguardando conversa%'
  AND mou_stage IS NULL;

UPDATE public.partner_entities SET mou_stage = 'prospecting'
WHERE entity_type = 'pmi_chapter' AND status = 'negotiation' AND mou_stage IS NULL;

COMMENT ON COLUMN public.partner_entities.mou_stage IS
  'p95 #90: granular MOU lifecycle for entity_type=pmi_chapter. NULL for non-chapter entities. States: prospecting → agreed → mou_drafted → mou_sent → mou_signed → active. Terminal: declined | inactive.';

CREATE OR REPLACE FUNCTION public.get_in_dashboard()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'manage_partner')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or manage_partner';
  END IF;

  WITH stages AS (
    SELECT mou_stage, count(*) AS n
    FROM partner_entities
    WHERE entity_type = 'pmi_chapter'
    GROUP BY mou_stage
  ),
  chapters AS (
    SELECT id, name, mou_stage, next_action, follow_up_date, last_interaction_at
    FROM partner_entities
    WHERE entity_type = 'pmi_chapter'
    ORDER BY
      CASE mou_stage
        WHEN 'active' THEN 1
        WHEN 'mou_signed' THEN 2
        WHEN 'mou_sent' THEN 3
        WHEN 'mou_drafted' THEN 4
        WHEN 'agreed' THEN 5
        WHEN 'prospecting' THEN 6
        ELSE 9
      END, name
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM partner_entities WHERE entity_type='pmi_chapter'),
    'by_stage', (SELECT jsonb_object_agg(coalesce(mou_stage,'unset'), n) FROM stages),
    'chapters', (SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'mou_stage', mou_stage,
      'next_action', next_action, 'follow_up_date', follow_up_date,
      'last_interaction_at', last_interaction_at
    )) FROM chapters),
    'computed_at', now()
  ) INTO v_result;

  RETURN v_result;
END $function$;

REVOKE EXECUTE ON FUNCTION public.get_in_dashboard() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.get_in_dashboard() IS
  'p95 #90: Integração Nacional dashboard. Returns chapter count by mou_stage + per-chapter detail. Gated by view_internal_analytics OR manage_partner.';

NOTIFY pgrst, 'reload schema';
