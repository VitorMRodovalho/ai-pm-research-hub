-- p170 Workspace dropout fix D — backfill mandatory rules + auto-create trigger
--
-- PM ask 2026-05-16: /workspace painel mostra 6 dropout falsos + 4 sem presença,
-- mas members têm attendance recente. Root cause: apenas 4/13 general_meeting +
-- 9/85 tribe_meeting events têm event_audience_rules mandatory. Sem rule,
-- is_event_mandatory_for_member() retorna false → denominator artificialmente
-- pequeno + attendances reais não contam.
--
-- Fix D (PM ratified):
--   1. Backfill: events tagged general_meeting sem rule → INSERT mandatory rule
--      target_type='all_active_operational'
--   2. Backfill: events tagged tribe_meeting sem rule → INSERT mandatory rule
--      target_type='tribe', target_value derived from initiative.legacy_tribe_id
--   3. Trigger AFTER INSERT em event_tag_assignments quando tag é general_meeting
--      ou tribe_meeting → auto-cria rule se não existir (futuros bug-proof)
--
-- Rollback:
--   DELETE FROM event_audience_rules WHERE created_at >= now() - interval '5 minutes'
--     AND target_type IN ('all_active_operational', 'tribe');
--   DROP TRIGGER trg_auto_audience_rule_on_meeting_tag ON event_tag_assignments;

-- ============================================================
-- Backfill 1: general_meeting tagged events without mandatory rule
-- ============================================================
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value, created_at)
SELECT DISTINCT eta.event_id, 'mandatory', 'all_active_operational', NULL, now()
FROM public.event_tag_assignments eta
JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'general_meeting'
WHERE NOT EXISTS (
  SELECT 1 FROM public.event_audience_rules er
  WHERE er.event_id = eta.event_id AND er.attendance_type = 'mandatory'
);

-- ============================================================
-- Backfill 2: tribe_meeting tagged events without mandatory rule
-- Derive target_value (tribe_id) from event.initiative_id.legacy_tribe_id
-- ============================================================
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value, created_at)
SELECT DISTINCT eta.event_id, 'mandatory', 'tribe', i.legacy_tribe_id::text, now()
FROM public.event_tag_assignments eta
JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'tribe_meeting'
JOIN public.events e ON e.id = eta.event_id
LEFT JOIN public.initiatives i ON i.id = e.initiative_id
WHERE i.legacy_tribe_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.event_audience_rules er
    WHERE er.event_id = eta.event_id AND er.attendance_type = 'mandatory'
  );

-- ============================================================
-- Trigger function: auto-create rule when general_meeting/tribe_meeting tag added
-- ============================================================
CREATE OR REPLACE FUNCTION public._auto_audience_rule_on_meeting_tag()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tag_name text;
  v_legacy_tribe_id int;
BEGIN
  SELECT name INTO v_tag_name FROM public.tags WHERE id = NEW.tag_id;
  IF v_tag_name NOT IN ('general_meeting', 'tribe_meeting') THEN
    RETURN NEW;
  END IF;

  -- Idempotency: skip if event already has any mandatory rule
  IF EXISTS (
    SELECT 1 FROM public.event_audience_rules
    WHERE event_id = NEW.event_id AND attendance_type = 'mandatory'
  ) THEN
    RETURN NEW;
  END IF;

  IF v_tag_name = 'general_meeting' THEN
    INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
    VALUES (NEW.event_id, 'mandatory', 'all_active_operational', NULL);
  ELSE
    -- tribe_meeting: derive tribe_id from initiative
    SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.id = NEW.event_id;

    IF v_legacy_tribe_id IS NOT NULL THEN
      INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
      VALUES (NEW.event_id, 'mandatory', 'tribe', v_legacy_tribe_id::text);
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public._auto_audience_rule_on_meeting_tag() IS
  'p170 — Auto-cria event_audience_rules mandatory quando tag general_meeting/tribe_meeting é adicionada a event. Previne regressão do bug /workspace dropout (events sem rule → is_event_mandatory_for_member retorna false → denominator zero).';

DROP TRIGGER IF EXISTS trg_auto_audience_rule_on_meeting_tag ON public.event_tag_assignments;
CREATE TRIGGER trg_auto_audience_rule_on_meeting_tag
  AFTER INSERT ON public.event_tag_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public._auto_audience_rule_on_meeting_tag();

COMMENT ON TRIGGER trg_auto_audience_rule_on_meeting_tag ON public.event_tag_assignments IS
  'p170 — Auto-create mandatory rule on meeting-tag attach. Idempotente (skip se já há rule). Sem deletion (admin pode remover manualmente para evento opt-out).';

NOTIFY pgrst, 'reload schema';
