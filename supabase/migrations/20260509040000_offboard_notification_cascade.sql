-- Migration: #91 G6 — offboarding notification cascade
-- Issue: quando admin offboarda um membro (alumni/observer/inactive), GPs/DMs e
--        líderes/co-líderes da tribo não recebem notificação automática.
--        Hoje o PM notifica manualmente via WhatsApp — não existe trail estruturado.
-- Design: AFTER UPDATE OF member_status trigger que insere `notifications` para
--         stakeholders relevantes. Skip do actor (offboarded_by) e do próprio membro.
-- Delivery: notifications table é atômica — não há `delivery_mode` ainda (ADR-0022 W1
--           Proposed, não shipped). O consumer de email já existente decide push/digest.
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_notify_offboard_cascade ON public.members;
--   DROP FUNCTION IF EXISTS public.notify_offboard_cascade();

CREATE OR REPLACE FUNCTION public.notify_offboard_cascade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_actor         uuid;
  v_title         text;
  v_body          text;
  v_link          text;
  v_stakeholders  uuid[];
BEGIN
  -- Second gate (WHEN clause é o primeiro, mas defesa em profundidade):
  -- só processa transições entrando em estado terminal.
  IF NEW.member_status NOT IN ('alumni','observer','inactive') THEN
    RETURN NEW;
  END IF;

  v_actor := NEW.offboarded_by;  -- pode ser NULL em paths manuais (SQL direto)

  v_title := CASE NEW.member_status
    WHEN 'alumni'   THEN COALESCE(NEW.name,'Membro') || ' saiu da equipe (alumni)'
    WHEN 'observer' THEN COALESCE(NEW.name,'Membro') || ' passou a observador(a)'
    WHEN 'inactive' THEN COALESCE(NEW.name,'Membro') || ' foi desativado(a)'
  END;
  v_body := NULLIF(TRIM(COALESCE(NEW.status_change_reason,'')), '');
  v_link := '/admin/members/' || NEW.id::text;

  -- Stakeholders: GPs/DMs globais + líderes/co-líderes da tribe da pessoa.
  -- Exclui: próprio membro, actor da mudança.
  SELECT array_agg(DISTINCT m.id)
  INTO v_stakeholders
  FROM public.members m
  WHERE m.is_active = true
    AND m.id <> NEW.id
    AND m.id IS DISTINCT FROM v_actor
    AND (
      m.operational_role IN ('manager','deputy_manager')
      OR (
        NEW.tribe_id IS NOT NULL
        AND m.tribe_id = NEW.tribe_id
        AND m.operational_role IN ('tribe_leader','co_leader')
      )
    );

  IF v_stakeholders IS NULL OR cardinality(v_stakeholders) = 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications
    (recipient_id, type, title, body, link, source_type, source_id, actor_id)
  SELECT rid, 'member_offboarded', v_title, v_body, v_link, 'member', NEW.id, v_actor
  FROM unnest(v_stakeholders) AS rid;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_offboard_cascade() IS
  '#91 G6 — emits notifications to GPs/DMs + tribe leaders/co-leaders when a member transitions to alumni/observer/inactive. Skips actor + self.';

-- Trigger: AFTER UPDATE OF member_status + WHEN (status changed) double-gates.
-- OF clause requires the UPDATE to SET member_status (spurious col changes ignored).
-- WHEN clause filters no-op transitions (status same).
DROP TRIGGER IF EXISTS trg_notify_offboard_cascade ON public.members;
CREATE TRIGGER trg_notify_offboard_cascade
AFTER UPDATE OF member_status ON public.members
FOR EACH ROW
WHEN (OLD.member_status IS DISTINCT FROM NEW.member_status)
EXECUTE FUNCTION public.notify_offboard_cascade();

COMMENT ON TRIGGER trg_notify_offboard_cascade ON public.members IS
  'Offboarding notification cascade — #91 G6. Fires on member_status transition.';
