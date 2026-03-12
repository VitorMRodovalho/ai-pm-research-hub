-- Cleanup wrong lineage + create dynamic cycle_tribe_dim + project_memberships
-- Date: 2026-03-16
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Remove 4 incorrect tribe_lineage entries (frozen tribes, not continuations)
-- ═══════════════════════════════════════════════════════════════════════════
DELETE FROM public.tribe_lineage WHERE id IN (4, 5, 6, 7);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Clean 'tribe_leader' from Fabrício's designations (redundant with operational_role)
-- ═══════════════════════════════════════════════════════════════════════════
UPDATE public.members
SET designations = array_remove(designations, 'tribe_leader')
WHERE id = '92d26057-5550-4f15-a3bf-b00eed5f32f9';

UPDATE public.member_cycle_history
SET designations = array_remove(designations, 'tribe_leader')
WHERE member_id = '92d26057-5550-4f15-a3bf-b00eed5f32f9'
  AND cycle_code = 'cycle_3';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Materialized view: cycle_tribe_dim
--    Dynamic dimension built from union of:
--    - tribes (current cycle active tribes)
--    - member_cycle_history (historical tribes per cycle, with leaders)
--    - legacy_tribes (curated legacy records)
--    - tribe_lineage (parent relationships)
--    Each row = one unique (cycle, tribe) combination.
-- ═══════════════════════════════════════════════════════════════════════════
DROP MATERIALIZED VIEW IF EXISTS public.cycle_tribe_dim CASCADE;

CREATE MATERIALIZED VIEW public.cycle_tribe_dim AS

-- Current cycle tribes (from tribes table)
WITH current_tribes AS (
  SELECT
    t.id AS tribe_number,
    'cycle_3' AS cycle_code,
    t.name AS tribe_name,
    CASE
      WHEN t.workstream_type = 'operational' THEN 'operational'
      ELSE 'research'
    END AS tribe_type,
    t.quadrant,
    t.quadrant_name,
    t.is_active,
    ldr.id AS leader_id,
    ldr.name AS leader_name,
    ldr.photo_url AS leader_photo,
    (SELECT count(*) FROM public.members m
     WHERE m.tribe_id = t.id AND m.is_active = true) AS member_count
  FROM public.tribes t
  LEFT JOIN public.members ldr
    ON ldr.tribe_id = t.id
    AND ldr.operational_role = 'tribe_leader'
    AND ldr.is_active = true
),

-- Historical tribes (from member_cycle_history, grouped by cycle+tribe)
historical_tribes AS (
  SELECT DISTINCT ON (mch.cycle_code, mch.tribe_id)
    mch.tribe_id AS tribe_number,
    mch.cycle_code,
    mch.tribe_name,
    'research' AS tribe_type,
    NULL::integer AS quadrant,
    NULL::text AS quadrant_name,
    false AS is_active,
    ldr.member_id AS leader_id,
    ldr.member_name_snapshot AS leader_name,
    ldr_m.photo_url AS leader_photo,
    (SELECT count(*) FROM public.member_cycle_history mc2
     WHERE mc2.cycle_code = mch.cycle_code
       AND mc2.tribe_id = mch.tribe_id) AS member_count
  FROM public.member_cycle_history mch
  LEFT JOIN LATERAL (
    SELECT mc3.member_id, mc3.member_name_snapshot
    FROM public.member_cycle_history mc3
    WHERE mc3.cycle_code = mch.cycle_code
      AND mc3.tribe_id = mch.tribe_id
      AND mc3.operational_role = 'tribe_leader'
    LIMIT 1
  ) ldr ON true
  LEFT JOIN public.members ldr_m ON ldr_m.id = ldr.member_id
  WHERE mch.tribe_id IS NOT NULL
    AND mch.cycle_code IN ('pilot', 'cycle_1', 'cycle_2')
  ORDER BY mch.cycle_code, mch.tribe_id, mch.created_at
),

-- Operational subprojects (Hub de Comunicação, Webinars, Curadoria)
subprojects AS (
  SELECT * FROM (VALUES
    (0, 'cycle_2', 'Hub de Comunicação', 'operational', NULL::integer, NULL::text, false,
     'a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7'::uuid, 'Débora Moura', NULL::text, 0::bigint),
    (0, 'cycle_3', 'Hub de Comunicação', 'operational', NULL, NULL, true,
     NULL::uuid, 'Mayanna Duarte', NULL, 0),
    (0, 'cycle_3', 'Webinars', 'subproject', NULL, NULL, true,
     NULL::uuid, 'Vitor Maia Rodovalho (GP)', NULL, 0),
    (0, 'cycle_3', 'Comitê de Curadoria', 'subproject', NULL, NULL, true,
     NULL::uuid, 'Fabrício Costa, Sarah Faria, Roberto Macêdo', NULL, 3)
  ) AS t(tribe_number, cycle_code, tribe_name, tribe_type, quadrant, quadrant_name,
         is_active, leader_id, leader_name, leader_photo, member_count)
),

-- Lineage parent mapping
lineage AS (
  SELECT
    tl.current_tribe_id,
    tl.legacy_tribe_id,
    tl.relation_type,
    tl.cycle_scope
  FROM public.tribe_lineage tl
  WHERE tl.is_active = true
)

-- UNION ALL: current + historical + subprojects
SELECT
  row_number() OVER (ORDER BY
    CASE cycle_code
      WHEN 'pilot' THEN 0
      WHEN 'cycle_1' THEN 1
      WHEN 'cycle_2' THEN 2
      WHEN 'cycle_3' THEN 3
      ELSE 9
    END,
    tribe_type,
    tribe_number
  ) AS dim_id,
  cycle_code,
  tribe_number,
  tribe_name,
  tribe_type,
  quadrant,
  quadrant_name,
  is_active,
  leader_id,
  leader_name,
  leader_photo,
  member_count,
  (SELECT tl.legacy_tribe_id FROM lineage tl
   WHERE tl.current_tribe_id = sub.tribe_number
     AND sub.cycle_code = 'cycle_3'
   LIMIT 1) AS parent_legacy_tribe_id,
  (SELECT tl.relation_type FROM lineage tl
   WHERE tl.current_tribe_id = sub.tribe_number
     AND sub.cycle_code = 'cycle_3'
   LIMIT 1) AS parent_relation_type
FROM (
  SELECT * FROM current_tribes
  UNION ALL
  SELECT * FROM historical_tribes
  UNION ALL
  SELECT * FROM subprojects
) sub;

CREATE UNIQUE INDEX idx_cycle_tribe_dim_id ON public.cycle_tribe_dim (dim_id);
CREATE INDEX idx_cycle_tribe_dim_cycle ON public.cycle_tribe_dim (cycle_code);
CREATE INDEX idx_cycle_tribe_dim_active ON public.cycle_tribe_dim (is_active);

-- RPC to refresh the materialized view (call after data changes)
CREATE OR REPLACE FUNCTION public.refresh_cycle_tribe_dim()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.cycle_tribe_dim;
END;
$$;

GRANT EXECUTE ON FUNCTION public.refresh_cycle_tribe_dim() TO authenticated;

-- Grant read access
GRANT SELECT ON public.cycle_tribe_dim TO authenticated, anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. project_memberships — scoped access for subprojects (webinars, etc.)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.project_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  cycle_code text NOT NULL,
  project_name text NOT NULL,
  project_type text NOT NULL DEFAULT 'subproject'
    CHECK (project_type IN ('research', 'operational', 'subproject', 'committee')),
  role text NOT NULL DEFAULT 'member'
    CHECK (role IN ('member', 'co_manager', 'lead', 'reviewer', 'external_gp')),
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (member_id, cycle_code, project_name, role)
);

CREATE INDEX idx_project_memberships_project
  ON public.project_memberships (project_name, cycle_code);

CREATE OR REPLACE FUNCTION public.project_memberships_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN new.updated_at = now(); RETURN new; END; $$;

CREATE TRIGGER trg_project_memberships_updated
  BEFORE UPDATE ON public.project_memberships
  FOR EACH ROW EXECUTE FUNCTION public.project_memberships_set_updated_at();

ALTER TABLE public.project_memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY project_memberships_read ON public.project_memberships
  FOR SELECT TO authenticated USING (true);

CREATE POLICY project_memberships_write ON public.project_memberships
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.get_my_member_record() r
      WHERE r.is_superadmin IS true
        OR r.operational_role IN ('manager', 'deputy_manager')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.get_my_member_record() r
      WHERE r.is_superadmin IS true
        OR r.operational_role IN ('manager', 'deputy_manager')
    )
  );

-- Seed: Comitê de Curadoria members (C2+C3)
INSERT INTO public.project_memberships (member_id, cycle_code, project_name, project_type, role, notes)
SELECT m.id, 'cycle_2', 'Comitê de Curadoria', 'committee', 'reviewer', 'Membro desde C2'
FROM public.members m WHERE m.name IN ('Fabricio Costa', 'Sarah Faria Alcantara Macedo', 'Roberto Macêdo')
ON CONFLICT DO NOTHING;

INSERT INTO public.project_memberships (member_id, cycle_code, project_name, project_type, role, notes)
SELECT m.id, 'cycle_3', 'Comitê de Curadoria', 'committee', 'reviewer', 'Continuidade C2→C3'
FROM public.members m WHERE m.name IN ('Fabricio Costa', 'Sarah Faria Alcantara Macedo', 'Roberto Macêdo')
ON CONFLICT DO NOTHING;

-- Seed: Hub de Comunicação C3 lead
INSERT INTO public.project_memberships (member_id, cycle_code, project_name, project_type, role, notes)
SELECT m.id, 'cycle_3', 'Hub de Comunicação', 'operational', 'lead', 'Líder operacional C3'
FROM public.members m WHERE m.name = 'Mayanna Duarte'
ON CONFLICT DO NOTHING;
