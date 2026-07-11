-- #1294 [EPIC #1020 Onda B] estado pending-successor — tabela responsibility_handoffs + park/place/cancel.
--
-- admin_offboard_member reatribui SO board_items.assignee_id, para UM unico alvo, sem estado
-- "reatribuir depois". Quando o sucessor ainda nao e conhecido (caso real da virada C4->C5: sucessor
-- de tribo so definido na semana seguinte, apos onboarding da coorte nova), a unica saida hoje e
-- orfanizar silenciosamente ou segurar o offboard.
--
-- Esta onda modela um HANDOFF ESTACIONADO com sucessor TBD (successor_member_id NULL):
--   * park_responsibility_handoff(...)  — cria entrada pending (TBD) com due_date + owner.
--   * place_responsibility_handoff(...) — atribui sucessor e APLICA a reatribuicao ATOMICAMENTE
--                                          na superficie de origem, no mesmo txn; idempotente.
--   * cancel_responsibility_handoff(...)— encerra sem colocar; idempotente.
--
-- Os 7 item_type espelham exatamente as superficies do inventario da Onda A (#1293).
--
-- GROUNDING (live, prod ldrfrvwhxsmgaabwmaik, 2026-07-10):
--   * responsibility_handoffs NAO existe (to_regclass NULL). Head migration = ...404 (#1293).
--   * 1 org (2b4f58ab-7c45-4170-8718-b77ee69ff906); members tem organization_id.
--   * Supabase auto-concede a anon+authenticated em toda tabela public nova ⇒ deny-all exige
--     ENABLE RLS (sem policy) + REVOKE explicito de anon, authenticated (padrao #988).
--   * admin_change_tribe_leader(integer,uuid,text) existe (swap duro, gate manage_member); a
--     Onda D encapsula promocao+swap sobre ela. Aqui place faz o swap cru de tribes.leader_member_id
--     para ser auto-suficiente; created_by de card e IMUTAVEL (regra de merito) ⇒ cards_owned roteia
--     para assignee_id, nao para created_by.
--
-- Gate (park/place/cancel): manage_platform (can_by_member) OU service_role. anon revogado.
-- GC-097: nova tabela + 3 SECDEF RPCs. apply_migration MCP -> arquivo local byte-identico ->
--   repair --status applied -> NOTIFY pgrst -> phantom tracking-row limpa.
-- Rollback: DROP FUNCTION park_/place_/cancel_responsibility_handoff; DROP TABLE responsibility_handoffs.

-- ── Tabela ──────────────────────────────────────────────────────────────────────
CREATE TABLE public.responsibility_handoffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  from_member_id uuid NOT NULL REFERENCES public.members(id),
  item_type text NOT NULL CHECK (item_type IN (
    'board_items_assigned', 'cards_owned', 'checklist_items', 'tribe_leadership',
    'curation_assignments', 'action_items', 'drive_grants')),
  item_ref text NOT NULL,                                    -- id do item de origem (uuid ou int como texto)
  successor_member_id uuid REFERENCES public.members(id),    -- NULL = TBD (pending-successor)
  due_date date,
  owner_member_id uuid NOT NULL REFERENCES public.members(id),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'placed', 'cancelled')),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES public.members(id),
  placed_at timestamptz,
  placed_by uuid REFERENCES public.members(id)
);

-- no maximo UM handoff pending por item de origem (idempotencia do auto-park da Onda C)
CREATE UNIQUE INDEX ux_responsibility_handoffs_pending_item
  ON public.responsibility_handoffs (item_type, item_ref) WHERE status = 'pending';
CREATE INDEX ix_responsibility_handoffs_from
  ON public.responsibility_handoffs (from_member_id) WHERE status = 'pending';
CREATE INDEX ix_responsibility_handoffs_owner_due
  ON public.responsibility_handoffs (owner_member_id, due_date) WHERE status = 'pending';

COMMENT ON TABLE public.responsibility_handoffs IS
  '#1294 [EPIC #1020 Onda B] handoff de responsabilidade estacionado com sucessor TBD (successor_member_id NULL). item_type espelha as 7 superficies do inventario (#1293). Escrito so via park_/place_/cancel_responsibility_handoff (SECDEF, gate manage_platform). Deny-all RLS.';

-- deny-all: RLS habilitada SEM policy; acesso apenas pelas SECDEF RPCs abaixo.
ALTER TABLE public.responsibility_handoffs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.responsibility_handoffs FROM anon, authenticated;

-- ── park ────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.park_responsibility_handoff(
  p_from_member_id uuid,
  p_item_type text,
  p_item_ref text,
  p_owner_member_id uuid,
  p_due_date date DEFAULT NULL,
  p_reason text DEFAULT NULL,
  p_successor_member_id uuid DEFAULT NULL
) RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_org uuid;
  v_id uuid;
  v_existing uuid;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT v_is_service AND (v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  SELECT organization_id INTO v_org FROM public.members WHERE id = p_from_member_id;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('error', 'from_member not found');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members WHERE id = p_owner_member_id) THEN
    RETURN jsonb_build_object('error', 'owner_member not found');
  END IF;
  IF p_successor_member_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.members WHERE id = p_successor_member_id) THEN
    RETURN jsonb_build_object('error', 'successor_member not found');
  END IF;

  -- idempotente: um handoff pending ja existe para este item de origem
  SELECT id INTO v_existing FROM public.responsibility_handoffs
   WHERE item_type = p_item_type AND item_ref = p_item_ref AND status = 'pending';
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('handoff_id', v_existing, 'status', 'pending', 'already_parked', true);
  END IF;

  INSERT INTO public.responsibility_handoffs (
    organization_id, from_member_id, item_type, item_ref, successor_member_id,
    due_date, owner_member_id, reason, created_by
  ) VALUES (
    v_org, p_from_member_id, p_item_type, p_item_ref, p_successor_member_id,
    p_due_date, p_owner_member_id, p_reason, v_caller
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('handoff_id', v_id, 'status', 'pending', 'already_parked', false);
END;
$function$;

-- ── place: atribui sucessor + reatribuicao atomica na superficie de origem ────────
CREATE OR REPLACE FUNCTION public.place_responsibility_handoff(
  p_handoff_id uuid,
  p_successor_member_id uuid
) RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_h record;
  v_successor_name text;
  v_rows integer;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT v_is_service AND (v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  SELECT * INTO v_h FROM public.responsibility_handoffs WHERE id = p_handoff_id FOR UPDATE;
  IF v_h.id IS NULL THEN
    RETURN jsonb_build_object('error', 'handoff not found');
  END IF;
  IF v_h.status = 'placed' THEN
    -- idempotente: ja colocado, no-op
    RETURN jsonb_build_object('handoff_id', v_h.id, 'status', 'placed',
      'item_type', v_h.item_type, 'applied', false, 'already_placed', true);
  END IF;
  IF v_h.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'handoff already cancelled');
  END IF;

  SELECT name INTO v_successor_name FROM public.members WHERE id = p_successor_member_id;
  IF v_successor_name IS NULL THEN
    RETURN jsonb_build_object('error', 'successor_member not found');
  END IF;

  -- reatribuicao atomica na superficie de origem
  CASE v_h.item_type
    WHEN 'board_items_assigned' THEN
      UPDATE public.board_items SET assignee_id = p_successor_member_id, updated_at = now()
       WHERE id = v_h.item_ref::uuid;
    WHEN 'cards_owned' THEN
      -- created_by e imutavel (regra de merito); roteia o card aberto ao sucessor via assignee
      UPDATE public.board_items SET assignee_id = p_successor_member_id, updated_at = now()
       WHERE id = v_h.item_ref::uuid;
    WHEN 'checklist_items' THEN
      UPDATE public.board_item_checklists
         SET assigned_to = p_successor_member_id, assigned_at = now(), assigned_by = v_caller
       WHERE id = v_h.item_ref::uuid;
    WHEN 'tribe_leadership' THEN
      -- swap cru; a Onda D encapsula promocao + admin_change_tribe_leader sobre este caminho
      UPDATE public.tribes SET leader_member_id = p_successor_member_id, updated_at = now()
       WHERE id = v_h.item_ref::integer;
    WHEN 'curation_assignments' THEN
      UPDATE public.board_items SET reviewer_id = p_successor_member_id, updated_at = now()
       WHERE id = v_h.item_ref::uuid;
    WHEN 'action_items' THEN
      UPDATE public.meeting_action_items
         SET assignee_id = p_successor_member_id, assignee_name = v_successor_name, updated_at = now()
       WHERE id = v_h.item_ref::uuid;
    WHEN 'drive_grants' THEN
      -- registra o novo grantee; a re-provisao no Google e feita pelo fluxo de dispatch de Drive
      UPDATE public.drive_curation_grants SET grantee_member_id = p_successor_member_id, updated_at = now()
       WHERE id = v_h.item_ref::uuid;
    ELSE
      RETURN jsonb_build_object('error', 'unknown item_type: ' || v_h.item_type);
  END CASE;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('error', 'source item not found for reassignment',
      'item_type', v_h.item_type, 'item_ref', v_h.item_ref);
  END IF;

  UPDATE public.responsibility_handoffs
     SET successor_member_id = p_successor_member_id, status = 'placed',
         placed_at = now(), placed_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('handoff_id', v_h.id, 'status', 'placed',
    'item_type', v_h.item_type, 'successor_member_id', p_successor_member_id, 'applied', true);
END;
$function$;

-- ── cancel ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_responsibility_handoff(
  p_handoff_id uuid,
  p_reason text DEFAULT NULL
) RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_h record;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT v_is_service AND (v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  SELECT * INTO v_h FROM public.responsibility_handoffs WHERE id = p_handoff_id FOR UPDATE;
  IF v_h.id IS NULL THEN
    RETURN jsonb_build_object('error', 'handoff not found');
  END IF;
  IF v_h.status = 'cancelled' THEN
    RETURN jsonb_build_object('handoff_id', v_h.id, 'status', 'cancelled', 'already_cancelled', true);
  END IF;
  IF v_h.status = 'placed' THEN
    RETURN jsonb_build_object('error', 'cannot cancel a placed handoff');
  END IF;

  UPDATE public.responsibility_handoffs
     SET status = 'cancelled', reason = coalesce(p_reason, reason)
   WHERE id = v_h.id;

  RETURN jsonb_build_object('handoff_id', v_h.id, 'status', 'cancelled', 'already_cancelled', false);
END;
$function$;

COMMENT ON FUNCTION public.park_responsibility_handoff(uuid, text, text, uuid, date, text, uuid) IS
  '#1294 [EPIC #1020 Onda B] estaciona um handoff pending (sucessor TBD se NULL). Idempotente por (item_type,item_ref) pending. Gate manage_platform + service_role.';
COMMENT ON FUNCTION public.place_responsibility_handoff(uuid, uuid) IS
  '#1294 [EPIC #1020 Onda B] coloca o sucessor e APLICA a reatribuicao atomica na superficie de origem no mesmo txn. Idempotente (no-op se ja placed). Gate manage_platform + service_role.';
COMMENT ON FUNCTION public.cancel_responsibility_handoff(uuid, text) IS
  '#1294 [EPIC #1020 Onda B] cancela um handoff pending (nao aplica reatribuicao). Idempotente. Gate manage_platform + service_role.';

REVOKE ALL ON FUNCTION public.park_responsibility_handoff(uuid, text, text, uuid, date, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.park_responsibility_handoff(uuid, text, text, uuid, date, text, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.place_responsibility_handoff(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.place_responsibility_handoff(uuid, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.cancel_responsibility_handoff(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_responsibility_handoff(uuid, text) TO authenticated, service_role;
