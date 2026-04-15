-- Migration: workgroup initiative kind + member display fix
-- Rollback: DELETE FROM initiative_kinds WHERE slug='workgroup';
--           DELETE FROM engagement_kinds WHERE slug IN ('workgroup_member','workgroup_coordinator');
--           DELETE FROM engagement_kind_permissions WHERE kind IN ('workgroup_member','workgroup_coordinator');
--           UPDATE initiatives SET kind='committee' WHERE id IN ('9ea82b09-55c6-4cc3-ab7f-178518d0ab47','e885525e-a0f1-4e16-813c-497047209047');
--           UPDATE engagements SET kind=replace(kind,'workgroup_','committee_') WHERE kind LIKE 'workgroup_%';

-- 1. Create workgroup initiative kind
INSERT INTO initiative_kinds (
  slug, display_name, description, icon,
  has_board, has_meeting_notes, has_deliverables, has_attendance, has_certificate,
  allowed_engagement_kinds, required_engagement_kinds,
  organization_id
)
SELECT
  'workgroup', 'Equipe / Frente de Trabalho',
  'Grupo de trabalho operacional com quadro e entregas', 'briefcase',
  true, true, true, false, false,
  ARRAY['workgroup_member','workgroup_coordinator','observer','guest'],
  ARRAY['workgroup_member'],
  organization_id
FROM initiative_kinds WHERE slug = 'committee' LIMIT 1
ON CONFLICT DO NOTHING;

-- 2. Create workgroup engagement kinds
INSERT INTO engagement_kinds (slug, display_name, description, legal_basis, is_initiative_scoped, initiative_kinds_allowed, organization_id)
SELECT 'workgroup_member', 'Membro de Equipe', 'Membro ativo de uma frente de trabalho operacional',
       legal_basis, true, ARRAY['workgroup'], organization_id
FROM engagement_kinds WHERE slug = 'committee_member' LIMIT 1
ON CONFLICT DO NOTHING;

INSERT INTO engagement_kinds (slug, display_name, description, legal_basis, is_initiative_scoped, initiative_kinds_allowed, organization_id)
SELECT 'workgroup_coordinator', 'Coordenador de Equipe', 'Coordenador de uma frente de trabalho operacional',
       legal_basis, true, ARRAY['workgroup'], organization_id
FROM engagement_kinds WHERE slug = 'committee_coordinator' LIMIT 1
ON CONFLICT DO NOTHING;

-- 3. Copy permissions from committee → workgroup
INSERT INTO engagement_kind_permissions (kind, role, action, scope, description, organization_id)
SELECT
  CASE kind WHEN 'committee_member' THEN 'workgroup_member' WHEN 'committee_coordinator' THEN 'workgroup_coordinator' END,
  role, action, scope, description, organization_id
FROM engagement_kind_permissions
WHERE kind IN ('committee_member', 'committee_coordinator')
ON CONFLICT DO NOTHING;

-- 4. Update Hub de Comunicação and Publicações to workgroup
UPDATE initiatives SET kind = 'workgroup'
WHERE id IN ('9ea82b09-55c6-4cc3-ab7f-178518d0ab47', 'e885525e-a0f1-4e16-813c-497047209047');

-- 5. Update their engagements
UPDATE engagements
SET kind = CASE kind
  WHEN 'committee_member' THEN 'workgroup_member'
  WHEN 'committee_coordinator' THEN 'workgroup_coordinator'
  ELSE kind
END
WHERE initiative_id IN ('9ea82b09-55c6-4cc3-ab7f-178518d0ab47', 'e885525e-a0f1-4e16-813c-497047209047')
  AND kind IN ('committee_member', 'committee_coordinator');

-- 6. Update get_initiative_members to include kind_display
CREATE OR REPLACE FUNCTION public.get_initiative_members(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(row_to_json(m) ORDER BY m.role_order, m.name), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      e.id as engagement_id,
      e.kind,
      e.role,
      e.status,
      e.start_date,
      p.id as person_id,
      COALESCE(p.name, mb.name) as name,
      COALESCE(p.photo_url, mb.photo_url) as photo_url,
      mb.id as member_id,
      ek.display_name as kind_display,
      CASE e.role
        WHEN 'leader' THEN 0
        WHEN 'coordinator' THEN 1
        WHEN 'participant' THEN 2
        WHEN 'observer' THEN 3
        ELSE 4
      END as role_order
    FROM engagements e
    JOIN persons p ON p.id = e.person_id
    LEFT JOIN members mb ON mb.id = p.legacy_member_id
    LEFT JOIN engagement_kinds ek ON ek.slug = e.kind
    WHERE e.initiative_id = p_initiative_id
      AND e.status = 'active'
  ) m;

  RETURN v_result;
END;
$function$;
