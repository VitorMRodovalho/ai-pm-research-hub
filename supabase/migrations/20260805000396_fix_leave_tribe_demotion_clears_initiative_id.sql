-- Fix: leave-tribe demotion must also clear members.initiative_id, not only tribe_id.
--
-- Root cause (found in live QA 2026-07-10, researcher Tiele Lara): withdraw_from_initiative
-- offboards the tribe engagement and the AFTER trigger _sync_tribe_id_from_engagement clears
-- members.tribe_id -- BUT members carries a dual-write pair (tribe_id + initiative_id, ADR-0005).
-- The BEFORE-UPDATE bridge trigger sync_tribe_from_initiative re-derives tribe_id from the STILL-SET
-- initiative_id (legacy_tribe_id lookup), so members.tribe_id was immediately re-set to its old value.
-- Net effect: leaving a tribe never cleared members.tribe_id -> get_my_tribe_request_context kept
-- returning has_tribe -> the picker never reopened (the researcher was stuck in the dead-end).
--
-- Fix: in the demotion branch, clear BOTH tribe_id AND initiative_id in the same UPDATE. With both
-- NULL, both bridge triggers (sync_tribe_from_initiative / sync_initiative_from_tribe) no-op. We only
-- null initiative_id when it currently references a research_tribe initiative, so a member's link to a
-- NON-tribe initiative (if any) is preserved. The promotion branch and the atomic-switch path (#1263)
-- are unchanged: activating a tribe engagement re-sets tribe_id and the bridge re-derives initiative_id.
CREATE OR REPLACE FUNCTION public._sync_tribe_id_from_engagement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_legacy_tribe_id integer;
  v_member_id uuid;
BEGIN
  SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives i
  WHERE i.id = NEW.initiative_id AND i.kind = 'research_tribe';

  IF v_legacy_tribe_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.person_id = NEW.person_id;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NEW.status = 'active' THEN
    UPDATE public.members
       SET tribe_id = v_legacy_tribe_id
     WHERE id = v_member_id
       AND tribe_id IS DISTINCT FROM v_legacy_tribe_id;
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status <> 'active' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.engagements e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id AND i2.kind = 'research_tribe'
      WHERE e2.person_id = NEW.person_id
        AND e2.kind = 'volunteer'
        AND e2.status = 'active'
        AND e2.id <> NEW.id
    ) THEN
      UPDATE public.members m
         SET tribe_id = NULL,
             initiative_id = CASE
               WHEN m.initiative_id IN (SELECT id FROM public.initiatives WHERE kind = 'research_tribe')
                 THEN NULL
               ELSE m.initiative_id
             END
       WHERE m.id = v_member_id
         AND (
           m.tribe_id IS NOT NULL
           OR m.initiative_id IN (SELECT id FROM public.initiatives WHERE kind = 'research_tribe')
         );
    END IF;
  END IF;

  RETURN NULL;
END; $function$;
