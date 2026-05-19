-- p199-c (BUG-paulo-attendance-cancellation, 2026-05-19): semantic alignment
-- between event cancellation and attendance rows + uniformity of mark RPCs
--
-- Bug reported by PM (2026-05-19 ~16:30): Paulo Alves Jr aparecia com
-- attendance row no evento Talentos & Upskilling 2026-05-04 (cancelado as
-- 16:09:31), e PM nao conseguia "tirar presenca" via /attendance UI.
--
-- Root cause:
-- 1. mark_member_present(p_present=false) faz UPSERT present=false em vez
--    de DELETE -- divergente de admin_bulk_mark_attendance que DELETA.
--    Resultado: a row permanecia no DB. Cell grid resolver mapeava como
--    'na' (porque event.status='cancelled' tem prioridade), mas a row
--    ainda existia em outras agregacoes.
-- 2. Cancelar um evento nao limpa attendance rows existentes. Rows orfas
--    apontando para events cancelados poderiam aparecer em agregacoes
--    nao-gated em event.status (KPIs, ranking, get_attendance_panel) e
--    confundir o operador que tenta "tirar presenca".
--
-- This migration:
-- 1. Adds trigger AFTER UPDATE OF status ON events: ao transicionar para
--    'cancelled', DELETE all attendance rows para esse event.
-- 2. Refactors mark_member_present(p_present=false) para DELETE row
--    (alinha com admin_bulk_mark_attendance e expectativa semantica do PM).
-- 3. Backfill: DELETE rows existentes em cancelled events (1 row hoje:
--    Paulo Alves Jr, fb8f75ae).
--
-- Rationale para DELETE-on-cancel:
-- Semanticamente, evento cancelado "nao ocorreu". Attendance rows para
-- non-events nao fazem sentido. O grid resolver ja tem fallback para 'na'
-- via CASE ge.status='cancelled' THEN 'na', mas ter rows orfas no DB:
-- - Infla counts em agregacoes nao gated em event.status
-- - Confunde tribe leaders tentando "tirar presenca"
-- - Cria inconsistencia entre UI render (cell 'na') e DB state (row exists)
--
-- DELETE eh reversivel via INSERT manual recall (admin) -- nao usamos
-- soft-delete porque attendance eh high-volume e a row nao carrega dado
-- insubstituivel (audit de marked_by/registered_by vive em members.id
-- relations, nao na propria row).
--
-- ROLLBACK:
--   DROP TRIGGER trg_cleanup_attendance_on_event_cancel ON public.events;
--   DROP FUNCTION public._cleanup_cancelled_event_attendance();
--   -- Revert mark_member_present para UPSERT-with-false body (ver prior
--   --   body em supabase_migrations.schema_migrations antes desta versao)
--   -- Backfill nao eh reversivel -- as rows deletadas nao tinham dado
--   -- util (Paulo: present=false, marked_by=NULL, excused=false)

-- 1) Trigger function: cleanup attendance on event cancellation
CREATE OR REPLACE FUNCTION public._cleanup_cancelled_event_attendance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_deleted int;
BEGIN
  -- Only act on transitions INTO cancelled (idempotent against repeat updates)
  IF NEW.status = 'cancelled' AND (OLD.status IS DISTINCT FROM 'cancelled') THEN
    DELETE FROM public.attendance WHERE event_id = NEW.id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    -- Audit row not necessary; the events.cancelled_at + cancelled_by + cancellation_reason
    -- columns carry the human-meaningful audit, and per-attendance row history is not
    -- considered material here (rows had no irreplaceable signal).
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cleanup_attendance_on_event_cancel ON public.events;
CREATE TRIGGER trg_cleanup_attendance_on_event_cancel
  AFTER UPDATE OF status ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public._cleanup_cancelled_event_attendance();

COMMENT ON FUNCTION public._cleanup_cancelled_event_attendance() IS
  'p199-c (2026-05-19): cleanup orphan attendance rows when event transitions to status=cancelled. Triggered AFTER UPDATE OF status ON events. Idempotent against repeat updates (no-op if OLD.status was already cancelled). LGPD-neutral (no PII access).';

-- 2) Refactor mark_member_present(p_present=false) to DELETE
CREATE OR REPLACE FUNCTION public.mark_member_present(p_event_id uuid, p_member_id uuid, p_present boolean)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires manage_event permission';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, true, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = true, excused = false, updated_at = now();
  ELSE
    -- p199-c (2026-05-19): p_present=false now DELETEs the attendance row
    -- (was UPSERT present=false). Aligns with admin_bulk_mark_attendance
    -- semantic where "tirar presenca" removes the registro.
    -- Edge case: rows previously marked as excused=true lose that flag on
    -- DELETE -- if dedicated excused-management is needed, use
    -- mark_member_excused() instead of toggling mark_member_present.
    DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$function$;

COMMENT ON FUNCTION public.mark_member_present(uuid, uuid, boolean) IS
  'p199-c (2026-05-19) refactor: p_present=true does INSERT/UPSERT (present=true, excused=false); p_present=false now DELETEs the row (was UPSERT present=false). Aligns with admin_bulk_mark_attendance contract and resolves UI toggle semantic ambiguity. Self-check-in (caller=member) does not require manage_event; admin-marking does.';

-- 3) Backfill: delete attendance rows in cancelled events (1 row at p199-c)
DELETE FROM public.attendance a
USING public.events e
WHERE a.event_id = e.id AND e.status = 'cancelled';

NOTIFY pgrst, 'reload schema';
