-- p171 TIER C — Auto-rule trigger lideranca extension
--
-- Workspace Fix D (p170 migration 20260674900000) shipped trigger
-- _auto_audience_rule_on_meeting_tag que cobria só `general_meeting` +
-- `tribe_meeting` tags. Eventos do tipo `lideranca` (auto-tagged
-- `leadership_meeting` via earlier trigger) ficaram sem auto-rule.
--
-- Carry de p170: estender pra criar 3 role rules
-- (manager, deputy_manager, tribe_leader) quando leadership_meeting
-- attached, mantendo idempotência (skip se mandatory rules já existem).
--
-- Backfill: 2 eventos atuais (Liderança #2 + #3) sem mandatory rules.
-- Outros 7 lideranca events já têm 3 rules manuais (insert via DML p170).
--
-- Rollback:
--   Restore previous trigger body (sem CASE 'leadership_meeting');
--   DELETE FROM event_audience_rules WHERE event_id IN (...) AND target_type='role';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 1 — Extend trigger
-- ─────────────────────────────────────────────────────────────────────────────
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

  -- p171 TIER C: extended para incluir leadership_meeting
  IF v_tag_name NOT IN ('general_meeting', 'tribe_meeting', 'leadership_meeting') THEN
    RETURN NEW;
  END IF;

  -- Idempotency: se já tem mandatory rules, skip
  IF EXISTS (
    SELECT 1 FROM public.event_audience_rules
    WHERE event_id = NEW.event_id AND attendance_type = 'mandatory'
  ) THEN
    RETURN NEW;
  END IF;

  IF v_tag_name = 'general_meeting' THEN
    INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
    VALUES (NEW.event_id, 'mandatory', 'all_active_operational', NULL);

  ELSIF v_tag_name = 'tribe_meeting' THEN
    SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.id = NEW.event_id;

    IF v_legacy_tribe_id IS NOT NULL THEN
      INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
      VALUES (NEW.event_id, 'mandatory', 'tribe', v_legacy_tribe_id::text);
    END IF;

  ELSIF v_tag_name = 'leadership_meeting' THEN
    -- p171 TIER C: 3 role rules (manager + deputy_manager + tribe_leader)
    -- Pattern espelha o que foi feito em DML manual em p170 pra Liderança #1
    INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
    VALUES
      (NEW.event_id, 'mandatory', 'role', 'manager'),
      (NEW.event_id, 'mandatory', 'role', 'deputy_manager'),
      (NEW.event_id, 'mandatory', 'role', 'tribe_leader');
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public._auto_audience_rule_on_meeting_tag() IS
  'p171 TIER C — Estendido para cobrir leadership_meeting tag. Cria 3 role rules (manager/deputy_manager/tribe_leader) para eventos do tipo lideranca. Idempotente — skip se mandatory rules existem.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 2 — Backfill 2 lideranca events sem mandatory rules
-- ─────────────────────────────────────────────────────────────────────────────
-- Liderança #2 (bff3a051) + Liderança #3 (e860e775). Idempotent via NOT EXISTS.
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
SELECT e.id, 'mandatory'::text, 'role'::text, role_name
FROM public.events e
CROSS JOIN unnest(ARRAY['manager', 'deputy_manager', 'tribe_leader']) AS role_name
WHERE e.type = 'lideranca'
  AND NOT EXISTS (
    SELECT 1 FROM public.event_audience_rules ear
    WHERE ear.event_id = e.id AND ear.attendance_type = 'mandatory'
  );

NOTIFY pgrst, 'reload schema';
