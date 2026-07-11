-- #1296 [EPIC #1020 Onda D] sucessao de lideranca first-class — headless/nomeacao SOBRE
-- admin_change_tribe_leader.
--
-- admin_change_tribe_leader(integer,uuid,text) JA existe (swap duro: exige sucessor imediato;
-- promove operational_role, seta tribes.leader_member_id, loga member_cycle_history + admin_audit_log;
-- trata lider-antigo NULL graciosamente). O que faltava e o ESTADO INTERMEDIARIO: quando um
-- tribe_leader nao renova e o sucessor so sera conhecido depois (caso real da virada), nao havia
-- headless explicito — a tribo ficaria sem lider silenciosamente ou o offboard travaria.
--
-- Esta onda adiciona uma camada de NOMEACAO sobre o swap existente (reusa, nao reimplementa):
--   * nominate_tribe_successor(tribe, successor=NULL, due, reason)
--       - successor NULL  -> HEADLESS explicito: vaga a tribo (leader_member_id=NULL) e ESTACIONA
--                            um handoff pending (Onda B, item_type 'tribe_leadership') com due_date;
--                            visivel (nao silencioso) — feed p/ reconciliacao (Onda E) e #1290/#1291.
--       - successor dado   -> delega a place_tribe_successor (promocao+swap imediatos).
--   * place_tribe_successor(tribe, successor, reason)
--       - promove+troca via admin_change_tribe_leader (o swap governado, com historico/audit) e
--         marca o handoff pending 'placed' se existir.
--   * get_headless_tribes() — leitura: tribos ativas sem lider + o handoff pending (due/from/owner).
--
-- Nota de reuso: admin_change_tribe_leader ja PROMOVE (operational_role='tribe_leader') no proprio
-- swap; promote_to_leader_track(p_application_id,...) opera sobre a APLICACAO de selecao (trilha de
-- lider), nao sobre member_id, e exige uma selection_application que pode nao existir na virada —
-- portanto a promocao operacional aqui e a do proprio admin_change_tribe_leader (o swap governado),
-- nao promote_to_leader_track.
--
-- admin_change_tribe_leader RAISE 'authentication_required' se auth.uid() IS NULL — logo as funcoes
-- de escrita aqui exigem um GP autenticado (nao service_role/postgres puro). Consistente com a base.
--
-- Gate (nominate/place): manage_platform (can_by_member). get_headless_tribes: manage_platform +
-- service_role. anon revogado.
-- GC-097: 3 SECDEF RPCs. apply_migration em chunks (WAF do endpoint MCP barra >10KB) -> arquivo local
--   byte-identico -> repair --status applied -> NOTIFY pgrst -> phantom tracking-rows limpas.
-- Rollback: DROP FUNCTION nominate_tribe_successor, place_tribe_successor, get_headless_tribes.

-- ── place_tribe_successor: promocao+swap governado + marca handoff placed ─────────
CREATE OR REPLACE FUNCTION public.place_tribe_successor(
  p_tribe_id integer,
  p_successor_member_id uuid,
  p_reason text DEFAULT NULL
) RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_tribe record;
  v_change jsonb;
  v_hid uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe.id IS NULL THEN
    RETURN jsonb_build_object('error', 'tribe not found');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members WHERE id = p_successor_member_id) THEN
    RETURN jsonb_build_object('error', 'successor_member not found');
  END IF;

  -- reusa o swap governado (promove operational_role + member_cycle_history + admin_audit_log)
  v_change := public.admin_change_tribe_leader(p_tribe_id, p_successor_member_id,
                coalesce(p_reason, 'Sucessao de lideranca (Onda D)'));

  -- marca o handoff pending de tribe_leadership desta tribo como placed, se existir
  UPDATE public.responsibility_handoffs
     SET successor_member_id = p_successor_member_id, status = 'placed',
         placed_at = now(), placed_by = v_caller
   WHERE item_type = 'tribe_leadership' AND item_ref = p_tribe_id::text AND status = 'pending'
   RETURNING id INTO v_hid;

  RETURN jsonb_build_object('state', 'placed', 'tribe_id', p_tribe_id,
    'successor_member_id', p_successor_member_id, 'handoff_placed', v_hid IS NOT NULL,
    'handoff_id', v_hid, 'change', v_change);
END;
$function$;

-- ── nominate_tribe_successor: headless (TBD) ou delega ao place imediato ──────────
CREATE OR REPLACE FUNCTION public.nominate_tribe_successor(
  p_tribe_id integer,
  p_successor_member_id uuid DEFAULT NULL,
  p_due_date date DEFAULT NULL,
  p_reason text DEFAULT NULL
) RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_tribe record;
  v_current_leader uuid;
  v_park jsonb;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe.id IS NULL THEN
    RETURN jsonb_build_object('error', 'tribe not found');
  END IF;
  IF v_tribe.is_active IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'tribe is not active');
  END IF;

  -- sucessor conhecido -> colocacao imediata (promocao+swap governado)
  IF p_successor_member_id IS NOT NULL THEN
    RETURN public.place_tribe_successor(p_tribe_id, p_successor_member_id, p_reason);
  END IF;

  -- sucessor TBD -> HEADLESS explicito
  v_current_leader := v_tribe.leader_member_id;
  IF v_current_leader IS NULL THEN
    RETURN jsonb_build_object('error', 'tribe already headless with no prior leader to hand off from');
  END IF;

  -- vaga a tribo (headless visivel)
  UPDATE public.tribes SET leader_member_id = NULL, updated_at = now() WHERE id = p_tribe_id;

  -- estaciona o handoff pending (Onda B) — torna o headless due-tracked + reconciliavel
  v_park := public.park_responsibility_handoff(
    v_current_leader, 'tribe_leadership', p_tribe_id::text, v_caller,
    p_due_date, coalesce(p_reason, 'Lideranca vaga aguardando sucessor'), NULL);

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller, 'tribe.headless', 'tribe', NULL,
    jsonb_build_object('tribe_id', p_tribe_id, 'tribe_name', v_tribe.name,
      'previous_leader_id', v_current_leader, 'due_date', p_due_date,
      'handoff_id', v_park->>'handoff_id', 'reason', p_reason));

  RETURN jsonb_build_object('state', 'headless', 'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name,
    'previous_leader_id', v_current_leader, 'handoff_id', v_park->>'handoff_id', 'due_date', p_due_date);
END;
$function$;

-- ── get_headless_tribes: leitura — headless visivel (feed Onda E / #1290-1291) ────
CREATE OR REPLACE FUNCTION public.get_headless_tribes()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_result jsonb;
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
    'tribe_id', t.id, 'tribe_name', t.name, 'quadrant', t.quadrant,
    'handoff_id', h.id, 'from_member_id', h.from_member_id,
    'owner_member_id', h.owner_member_id, 'due_date', h.due_date, 'since', h.created_at
  ) ORDER BY t.id), '[]'::jsonb)
  INTO v_result
  FROM public.tribes t
  LEFT JOIN public.responsibility_handoffs h
    ON h.item_type = 'tribe_leadership' AND h.item_ref = t.id::text AND h.status = 'pending'
  WHERE t.is_active = true AND t.leader_member_id IS NULL;

  RETURN jsonb_build_object('headless_tribes', v_result, 'count', jsonb_array_length(v_result));
END;
$function$;

COMMENT ON FUNCTION public.place_tribe_successor(integer, uuid, text) IS
  '#1296 [EPIC #1020 Onda D] promove+troca o lider via admin_change_tribe_leader (swap governado) e marca o handoff pending de tribe_leadership placed. Gate manage_platform.';
COMMENT ON FUNCTION public.nominate_tribe_successor(integer, uuid, date, text) IS
  '#1296 [EPIC #1020 Onda D] nomeacao de sucessor de tribo: successor NULL -> headless explicito (vaga + park handoff TBD, visivel); successor dado -> delega a place_tribe_successor. Gate manage_platform.';
COMMENT ON FUNCTION public.get_headless_tribes() IS
  '#1296 [EPIC #1020 Onda D] leitura das tribos ativas sem lider (headless) + handoff pending (due/from/owner). Torna o headless visivel (feed reconciliacao Onda E / #1290-1291). Gate manage_platform + service_role.';

REVOKE ALL ON FUNCTION public.place_tribe_successor(integer, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.place_tribe_successor(integer, uuid, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.nominate_tribe_successor(integer, uuid, date, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nominate_tribe_successor(integer, uuid, date, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_headless_tribes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_headless_tribes() TO authenticated, service_role;

-- ── FIX (bloqueador descoberto pelo QA-ao-vivo da Onda D, LL #588 licao 1) ────────
-- admin_change_tribe_leader (o swap governado que place_tribe_successor reusa) estava QUEBRADO
-- para QUALQUER troca de lider com ciclo corrente: member_cycle_history.cycle_start/cycle_end sao
-- colunas DATE, mas a funcao inseria os timestamps como texto (now cast p/ text) e cycles.cycle_start
-- hoje e DATE (nao mais text), disparando 42804 "COALESCE types date and text cannot be matched".
-- Latente ate a 1a troca de lider apos cycle_start virar date. Fix minimo: os 2 literais passam a
-- usar now()::date (colunas date). Behavior-neutral fora do crash.
-- (2) NOVO caminho da Onda D: colocar sucessor numa tribo JA headless (leader_member_id NULL) pulava
-- o bloco que atribui v_old_leader, e o RETURN final acessava v_old_leader.name num record nao-atribuido
-- (erro 55000). Fix: variavel v_old_leader_name (default NULL, setada so quando ha lider antigo).
-- Corpo baseado no VIVO (pg_get_functiondef); so os 2 casts + o guard de record mudam. Desbloqueia a
-- sucessao de lider (Onda D) e a propria virada C4->C5.
CREATE OR REPLACE FUNCTION public.admin_change_tribe_leader(p_tribe_id integer, p_new_leader_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_tribe record;
  v_old_leader record;
  v_old_leader_name text;
  v_new_leader record;
  v_cycle record;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'permission_denied: manage_member required';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  SELECT * INTO v_new_leader FROM public.members WHERE id = p_new_leader_id;
  IF v_new_leader IS NULL THEN RAISE EXCEPTION 'New leader member not found: %', p_new_leader_id; END IF;

  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  IF v_tribe.leader_member_id IS NOT NULL THEN
    SELECT * INTO v_old_leader FROM public.members WHERE id = v_tribe.leader_member_id;

    IF v_old_leader IS NOT NULL THEN
      v_old_leader_name := v_old_leader.name;
      INSERT INTO public.member_cycle_history (
        member_id, cycle_code, cycle_label, cycle_start, cycle_end,
        operational_role, designations, tribe_id, tribe_name,
        chapter, is_active, member_name_snapshot, notes
      ) VALUES (
        v_old_leader.id,
        COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
        COALESCE(v_cycle.cycle_start, now()::date), now()::date,
        v_old_leader.operational_role, v_old_leader.designations,
        v_old_leader.tribe_id, v_tribe.name,
        v_old_leader.chapter, true, v_old_leader.name,
        'LEADER_REMOVED: Replaced by ' || v_new_leader.name || '. Reason: ' || p_reason || '. By: ' || v_caller_name
      );

      UPDATE public.members SET operational_role = 'researcher'
      WHERE id = v_old_leader.id AND operational_role = 'tribe_leader';

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_caller_id, 'role.demoted', 'member', v_old_leader.id,
        jsonb_build_object('old_role', 'tribe_leader', 'new_role', 'researcher',
          'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));
    END IF;
  END IF;

  UPDATE public.members SET operational_role = 'tribe_leader', tribe_id = p_tribe_id
  WHERE id = p_new_leader_id;

  UPDATE public.tribes SET leader_member_id = p_new_leader_id WHERE id = p_tribe_id;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_new_leader_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::date), NULL,
    'tribe_leader', v_new_leader.designations, p_tribe_id, v_tribe.name,
    v_new_leader.chapter, true, v_new_leader.name,
    'LEADER_ASSIGNED: Promoted to leader of ' || v_tribe.name || '. Reason: ' || p_reason || '. By: ' || v_caller_name
  );

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'role.promoted', 'member', p_new_leader_id,
    jsonb_build_object('old_role', v_new_leader.operational_role, 'new_role', 'tribe_leader',
      'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));

  RETURN jsonb_build_object(
    'success', true, 'tribe', v_tribe.name,
    'old_leader', COALESCE(v_old_leader_name, 'N/A'),
    'new_leader', v_new_leader.name, 'reason', p_reason
  );
END;
$function$;

COMMENT ON FUNCTION public.admin_change_tribe_leader(integer, uuid, text) IS
  '#1296 [EPIC #1020 Onda D] swap governado de lider de tribo (promove operational_role + member_cycle_history + admin_audit_log). Fix: cycle_start/cycle_end sao DATE -> now()::date (era now()::text, quebrava 42804 apos cycle_start virar date). Reusado por place_tribe_successor.';
