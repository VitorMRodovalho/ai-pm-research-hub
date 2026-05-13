-- p155 G-NEW: members.initiative_id sync gap fix
--
-- Problem: 11 members têm engagement V4 ativo mas members.initiative_id=NULL (legacy V3).
-- TribeKanbanIsland + BoardEngine + outras UIs/RPCs ainda filtram por members.initiative_id —
-- esses 11 membros (Herlon, Ivan, Roberto, Sarah, Vitor, etc) ficam invisíveis em board kanban
-- assignee picker e listings legacy.
--
-- Strategy:
--   (1) Backfill: para members com engagement ativo + initiative_id NULL, set primary
--       initiative pela prioridade research_tribe > study_group > committee > workgroup > congress.
--   (2) Forward trigger: AFTER INSERT em engagements status=active, se member tem initiative_id NULL,
--       set member.initiative_id = NEW.initiative_id. Previne NULL_DRIFT futuro.
--   (3) Não toca os 13 CONFLICT (intencional V3+V4 hybrid — primary tribe + extras workgroups).
--
-- Out of scope (backlog ADR-0078): migrar frontend (TribeKanbanIsland.tsx:398, BoardEngine.tsx:93) +
-- 100+ RPCs legacy do filtro V3 para o canonical V4 engagements.

-- =============== (1) BACKFILL ===============

WITH ranked AS (
  SELECT m.id AS member_id,
         e.initiative_id,
         i.kind,
         e.created_at,
         ROW_NUMBER() OVER (
           PARTITION BY m.id
           ORDER BY
             CASE i.kind
               WHEN 'research_tribe' THEN 1
               WHEN 'study_group'    THEN 2
               WHEN 'committee'      THEN 3
               WHEN 'workgroup'      THEN 4
               WHEN 'congress'       THEN 5
               WHEN 'workshop'       THEN 6
               WHEN 'book_club'      THEN 7
               ELSE 99
             END,
             e.created_at ASC
         ) AS rnk
  FROM members m
  JOIN engagements e ON e.person_id = m.person_id AND e.status = 'active' AND e.initiative_id IS NOT NULL
  JOIN initiatives i ON i.id = e.initiative_id
  WHERE m.initiative_id IS NULL
)
UPDATE members m
SET initiative_id = r.initiative_id,
    updated_at    = now()
FROM ranked r
WHERE m.id = r.member_id AND r.rnk = 1;

INSERT INTO data_anomaly_log (anomaly_type, severity, description, context)
VALUES (
  'members_initiative_id_backfill',
  'info',
  'p155 G-NEW: backfilled members.initiative_id from active engagements (NULL_DRIFT fix)',
  jsonb_build_object(
    'strategy', 'priority research_tribe > study_group > committee > workgroup > congress > workshop > book_club',
    'trigger_added', 'trg_sync_member_initiative_from_engagement',
    'affected_members', (
      SELECT array_agg(DISTINCT m.id)
      FROM members m
      JOIN engagements e ON e.person_id = m.person_id AND e.status='active'
      WHERE m.initiative_id IS NOT NULL AND m.updated_at > now() - interval '5 seconds'
    )
  )
);

-- =============== (2) FORWARD TRIGGER ===============

CREATE OR REPLACE FUNCTION public._sync_member_initiative_from_engagement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM 'active' OR NEW.initiative_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_member_id
  FROM public.members
  WHERE person_id = NEW.person_id
    AND initiative_id IS NULL
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.members
  SET initiative_id = NEW.initiative_id, updated_at = now()
  WHERE id = v_member_id AND initiative_id IS NULL;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public._sync_member_initiative_from_engagement() IS
  'AFTER INSERT/UPDATE em engagements: se member.initiative_id IS NULL, propaga NEW.initiative_id como primary tribe legacy. Nunca overwrite existing (preserva V3+V4 hybrid). Mitigates NULL_DRIFT pendente da migração V4 canonical engagements. p155 G-NEW (2026-05-13).';

DROP TRIGGER IF EXISTS trg_sync_member_initiative_from_engagement ON public.engagements;

CREATE TRIGGER trg_sync_member_initiative_from_engagement
  AFTER INSERT OR UPDATE OF status, initiative_id ON public.engagements
  FOR EACH ROW
  EXECUTE FUNCTION public._sync_member_initiative_from_engagement();
