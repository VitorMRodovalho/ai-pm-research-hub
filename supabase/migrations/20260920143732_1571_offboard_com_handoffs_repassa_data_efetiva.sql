-- #1571: `offboard_member_with_handoffs` passa a aceitar e repassar a data efetiva.
--
-- Contexto medido em 20/09/2026. A correcao de 03/08 (#1570) alcancou `admin_offboard_member` e o
-- wrapper `offboard_member`, e FUNCIONA em producao: tres registros de 11/09 carregam data efetiva
-- distinta da data de registro, um deles retroagido 58 dias. Esta rota ficou de fora: ela nao tinha
-- o parametro, entao todo offboarding com handoffs voltava a carimbar a data de hoje.
--
-- DROP + CREATE, e nao CREATE OR REPLACE, porque a CONTAGEM de parametros muda: um `CREATE OR
-- REPLACE` com assinatura diferente cria SOBRECARGA em vez de substituir, e duas versoes da mesma
-- funcao com semanticas diferentes e o defeito que se quer evitar. Medido antes: existe exatamente
-- 1 sobrecarga hoje, 0 funcoes e 0 crons a chamam, e 1 chamador no `src/`.
--
-- Os grants sao restaurados explicitamente porque DROP os leva junto. Medidos antes do DROP:
-- authenticated, service_role, postgres. NAO ha anon nem PUBLIC nesta funcao, e o restore mantem
-- assim de proposito.

DROP FUNCTION IF EXISTS public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date);

CREATE FUNCTION public.offboard_member_with_handoffs(
  p_member_id uuid,
  p_new_status text,
  p_reason_category text,
  p_reason_detail text DEFAULT NULL::text,
  p_routing jsonb DEFAULT '[]'::jsonb,
  p_default_due_date date DEFAULT NULL::date,
  p_effective_date date DEFAULT NULL::date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$

DECLARE
  v_caller uuid;
  v_rec record;
  v_succ uuid;
  v_park jsonb;
  v_hid uuid;
  v_placed integer := 0;
  v_parked integer := 0;
  v_headless integer := 0;
  v_offboard jsonb;
  v_orphans integer;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members WHERE id = p_member_id) THEN
    RETURN jsonb_build_object('error', 'Member not found');
  END IF;

  -- 6 superfícies de atribuicao: park (sucessor do routing -> place; senao TBD)
  FOR v_rec IN
    SELECT 'board_items_assigned' AS t, bi.id::text AS ref FROM public.board_items bi
      WHERE bi.assignee_id = p_member_id AND bi.status NOT IN ('done','archived')
    UNION ALL
    SELECT 'cards_owned', bi.id::text FROM public.board_items bi
      WHERE bi.created_by = p_member_id AND bi.status NOT IN ('done','archived')
    UNION ALL
    SELECT 'checklist_items', c.id::text FROM public.board_item_checklists c
      WHERE c.assigned_to = p_member_id AND c.is_completed = false
    UNION ALL
    SELECT 'curation_assignments', bi.id::text FROM public.board_items bi
      WHERE bi.reviewer_id = p_member_id AND bi.curation_status IN ('curation_pending','leader_review')
    UNION ALL
    SELECT 'action_items', a.id::text FROM public.meeting_action_items a
      WHERE a.assignee_id = p_member_id AND a.status = 'open'
    UNION ALL
    SELECT 'drive_grants', g.id::text FROM public.drive_curation_grants g
      WHERE g.grantee_member_id = p_member_id AND g.revoked_at IS NULL
  LOOP
    SELECT r.successor_member_id INTO v_succ
      FROM jsonb_to_recordset(p_routing) AS r(item_type text, item_ref text, successor_member_id uuid)
     WHERE r.item_type = v_rec.t AND r.item_ref = v_rec.ref
     LIMIT 1;

    v_park := public.park_responsibility_handoff(
      p_member_id, v_rec.t, v_rec.ref, v_caller, p_default_due_date, 'offboard: ' || p_reason_category, v_succ);
    v_hid := (v_park->>'handoff_id')::uuid;
    IF v_succ IS NOT NULL AND v_hid IS NOT NULL THEN
      PERFORM public.place_responsibility_handoff(v_hid, v_succ);
      v_placed := v_placed + 1;
    ELSE
      v_parked := v_parked + 1;
    END IF;
  END LOOP;

  -- lideranca de tribo: nominate_tribe_successor (Onda D) — sucessor -> place; senao headless
  FOR v_rec IN
    SELECT t.id AS tribe_id FROM public.tribes t WHERE t.leader_member_id = p_member_id AND t.is_active = true
  LOOP
    SELECT r.successor_member_id INTO v_succ
      FROM jsonb_to_recordset(p_routing) AS r(item_type text, item_ref text, successor_member_id uuid)
     WHERE r.item_type = 'tribe_leadership' AND r.item_ref = v_rec.tribe_id::text
     LIMIT 1;
    PERFORM public.nominate_tribe_successor(v_rec.tribe_id, v_succ, p_default_due_date, 'offboard: ' || p_reason_category);
    IF v_succ IS NOT NULL THEN v_placed := v_placed + 1; ELSE v_headless := v_headless + 1; END IF;
  END LOOP;

  -- finaliza o offboard (reatribuicao ja tratada -> p_reassign_to NULL)
  -- #1571: p_effective_date repassado. Sem ele esta rota carimbava now()/CURRENT_DATE nos quatro
  -- destinos de admin_offboard_member, inclusive no TEXTO do certificado alumni, que e documento
  -- entregue ao voluntario. p_reassign_to segue NULL porque a reatribuicao ja foi tratada acima.
  v_offboard := public.admin_offboard_member(p_member_id, p_new_status, p_reason_category, p_reason_detail, NULL, p_effective_date);
  IF v_offboard ? 'error' THEN
    RETURN jsonb_build_object('error', 'offboard finalize failed: ' || (v_offboard->>'error'),
      'handoffs_placed', v_placed, 'handoffs_parked', v_parked, 'tribes_headless', v_headless);
  END IF;

  -- verificacao: nada orfao (handoff-aware detect)
  v_orphans := public.detect_orphan_assignees_from_offboards(p_member_id);

  RETURN jsonb_build_object(
    'member_id', p_member_id, 'status', p_new_status,
    'handoffs_placed', v_placed, 'handoffs_parked', v_parked, 'tribes_headless', v_headless,
    'orphans_detected', v_orphans, 'offboard', v_offboard);
END;
$$;

GRANT EXECUTE ON FUNCTION public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date, date) TO service_role;
