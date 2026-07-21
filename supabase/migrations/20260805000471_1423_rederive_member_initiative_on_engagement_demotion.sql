-- #1423 (corrected): re-derive members.initiative_id when a NON-tribe initiative
-- engagement is demoted (remove/expire/offboard). The set/clear asymmetry lived in
-- _sync_member_initiative_from_engagement(): it only SET the bridge on an active
-- engagement and never re-derived it on demotion, so removing a study_group /
-- workgroup / committee / congress participant left members.initiative_id pointing
-- at an initiative the person no longer engages in (the Nicolas/CPMAI orphan, #1423).
--
-- research_tribe removal stays owned by _sync_tribe_id_from_engagement (clears both
-- tribe_id and initiative_id for kind='volunteer'); this trigger must NOT touch the
-- tribe case, because the members-level dual-write triggers (sync_initiative_from_tribe)
-- rebuild initiative_id from a still-present tribe_id and would fight it (#1270/#1273).
--
-- When the orphaned bridge is cleared and the person still has a tribe membership,
-- setting initiative_id = NULL lets sync_initiative_from_tribe rebuild it from
-- tribe_id (bridge lands on their tribe — exactly the #1270/#1273 manual fix). With
-- no tribe, it points at another active non-tribe initiative, else NULL. Never points
-- at a research_tribe here (that requires a volunteer membership, #1313).
--
-- Preventive: 0 live orphans of this class remain (reconciled 2026-07-20). No backfill.
CREATE OR REPLACE FUNCTION public._sync_member_initiative_from_engagement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_new_initiative uuid;
  v_has_tribe boolean;
BEGIN
  -- Resolve member via person_id (V4 canonical link).
  SELECT id INTO v_member_id
  FROM public.members
  WHERE person_id = NEW.person_id
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- SET path — an active, initiative-scoped engagement appears. Populate the
  -- bridge only when currently NULL (never overwrite an existing primary tribe).
  IF NEW.status = 'active' AND NEW.initiative_id IS NOT NULL THEN
    UPDATE public.members
       SET initiative_id = NEW.initiative_id, updated_at = now()
     WHERE id = v_member_id AND initiative_id IS NULL;
    RETURN NEW;
  END IF;

  -- DEMOTION / re-derivation (#1423) — a NON-tribe initiative engagement left
  -- 'active'. Skip research_tribe (owned by _sync_tribe_id_from_engagement).
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'active'
     AND NEW.status IS DISTINCT FROM 'active'
     AND NEW.initiative_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.initiatives i
       WHERE i.id = NEW.initiative_id AND i.kind = 'research_tribe'
     ) THEN

    -- Only act on an orphaned bridge: it points at the demoted initiative and the
    -- person has no remaining active engagement there.
    IF EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = v_member_id AND m.initiative_id = NEW.initiative_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = NEW.person_id
        AND e.initiative_id = NEW.initiative_id
        AND e.status = 'active'
    ) THEN

      SELECT (m.tribe_id IS NOT NULL) INTO v_has_tribe
      FROM public.members m WHERE m.id = v_member_id;

      IF v_has_tribe THEN
        -- Tribe membership wins: clearing lets sync_initiative_from_tribe rebuild
        -- initiative_id from tribe_id (the person's tribe).
        v_new_initiative := NULL;
      ELSE
        -- No tribe: point at another remaining active non-tribe initiative, else
        -- NULL. Never a research_tribe (needs a volunteer membership — #1313).
        SELECT e.initiative_id INTO v_new_initiative
        FROM public.engagements e
        JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.person_id = NEW.person_id
          AND e.status = 'active'
          AND e.initiative_id IS DISTINCT FROM NEW.initiative_id
          AND i.kind <> 'research_tribe'
        ORDER BY e.created_at ASC
        LIMIT 1;
      END IF;

      UPDATE public.members
         SET initiative_id = v_new_initiative, updated_at = now()
       WHERE id = v_member_id AND initiative_id = NEW.initiative_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
