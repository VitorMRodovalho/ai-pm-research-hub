-- #1297 [EPIC #1020 Onda E] reconciliacao — get_pending_handoffs_report.
--
-- Sem um relatorio dos handoffs pendentes, o estado TBD (Onda B, #1294) nao fecha o loop — um handoff
-- estacionado pode VENCER sem ninguem ver. A virada #1004 ja pedia "reconciliacao pos-corte" a mao.
--
-- RPC read-only que lista todos os responsibility_handoffs pending, enriquecidos (nomes de from/owner/
-- successor + due_date + dias em atraso + flag overdue), com sumario (total, overdue, breakdown por
-- item_type). Fecha o loop de reconciliacao do #1004; consumido pela superficie MCP/admin e pelo runbook
-- de virada de ciclo. 0 pendente vencido silencioso.
--
-- Gate: manage_platform (can_by_member) OU service_role. anon revogado. Read-only, STABLE -> fora do
-- sweep de side-effect SECDEF (#965); padrao do #1293/#1296.
-- GC-097: 1 SECDEF RPC. apply_migration -> arquivo local byte-identico -> repair -> NOTIFY -> phantom cleanup.
-- Rollback: DROP FUNCTION public.get_pending_handoffs_report();

CREATE OR REPLACE FUNCTION public.get_pending_handoffs_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_items jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'handoff_id', h.id,
    'item_type', h.item_type,
    'item_ref', h.item_ref,
    'from_member_id', h.from_member_id,
    'from_member_name', fm.name,
    'owner_member_id', h.owner_member_id,
    'owner_member_name', om.name,
    'successor_member_id', h.successor_member_id,
    'due_date', h.due_date,
    'is_overdue', h.due_date IS NOT NULL AND h.due_date < current_date,
    'days_overdue', CASE WHEN h.due_date IS NOT NULL AND h.due_date < current_date
                         THEN (current_date - h.due_date) ELSE 0 END,
    'reason', h.reason,
    'since', h.created_at
  ) ORDER BY (h.due_date IS NOT NULL AND h.due_date < current_date) DESC, h.due_date ASC NULLS LAST), '[]'::jsonb)
  INTO v_items
  FROM public.responsibility_handoffs h
  LEFT JOIN public.members fm ON fm.id = h.from_member_id
  LEFT JOIN public.members om ON om.id = h.owner_member_id
  WHERE h.status = 'pending';

  RETURN jsonb_build_object(
    'pending_handoffs', v_items,
    'total_pending', jsonb_array_length(v_items),
    'overdue_count', (SELECT count(*) FROM jsonb_array_elements(v_items) e WHERE (e->>'is_overdue')::boolean),
    'by_item_type', (SELECT coalesce(jsonb_object_agg(item_type, cnt), '{}'::jsonb)
                     FROM (SELECT e->>'item_type' AS item_type, count(*) AS cnt
                           FROM jsonb_array_elements(v_items) e GROUP BY e->>'item_type') t),
    'generated_for', current_date
  );
END;
$function$;

COMMENT ON FUNCTION public.get_pending_handoffs_report() IS
  '#1297 [EPIC #1020 Onda E] reconciliacao read-only dos responsibility_handoffs pending (enriquecido + overdue flag + dias em atraso + sumario por item_type). Fecha o loop #1004. Gate manage_platform + service_role.';

REVOKE ALL ON FUNCTION public.get_pending_handoffs_report() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pending_handoffs_report() TO authenticated, service_role;
