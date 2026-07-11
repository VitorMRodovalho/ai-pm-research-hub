-- #1295 [EPIC #1020 Onda C] integracao no offboard — pre-flight por-item + auto-park (sem orfanizar).
--
-- Hoje admin_offboard_member(p_reassign_to) so move board_items para UM alvo — sem roteamento por-item
-- nem garantia de que nada foi orfanizado. O membro que sai pode possuir cards/checklist/curation/action
-- items/drive grants/lideranca de tribo que ficam sem dono, detectados so depois
-- (detect_orphan_assignees_from_offboards).
--
-- Esta onda amarra A+B+D no fluxo de offboard (reusa, nao reimplementa):
--   * prepare_member_offboard(member) — pre-flight read: inventario (Onda A) + risco de orfao.
--   * offboard_member_with_handoffs(member, status, cat, detail, routing[], due) — orquestrador:
--       - para cada item das 6 superficies de atribuicao: park (Onda B) com sucessor do mapa de
--         roteamento (place imediato) OU sem sucessor (TBD, auto-park) — NUNCA orfaniza.
--       - lideranca de tribo: nominate_tribe_successor (Onda D) — sucessor -> place; sem -> headless.
--       - finaliza via admin_offboard_member(..., p_reassign_to => NULL) (reatribuicao ja tratada).
--       - roda detect_orphan e retorna a contagem (deve ser 0 pelo novo fluxo).
--   * detect_orphan_assignees_from_offboards — torna-se HANDOFF-AWARE: um board_item com handoff pending
--     NAO e orfao (esta rastreado/parked), entao nao gera alerta. Semantica do modelo pending-successor.
--
-- Roteamento por-item = jsonb array [{item_type, item_ref, successor_member_id}], match por (type,ref).
-- Gate: manage_member (mesmo de admin_offboard_member) via caller. anon revogado.
-- GC-097: apply em chunks (WAF), arquivo local byte-identico, repair, NOTIFY, phantom cleanup.
-- Rollback: DROP FUNCTION prepare_member_offboard, offboard_member_with_handoffs; restaurar
--   detect_orphan_assignees_from_offboards (versao pre-handoff-aware).

-- ── detect_orphan: handoff-aware (parked = nao-orfao) ────────────────────────────
CREATE OR REPLACE FUNCTION public.detect_orphan_assignees_from_offboards(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer;
BEGIN
  WITH offenders AS (
    SELECT bi.id AS item_id, bi.board_id, bi.assignee_id, bi.title,
           m.id AS member_id, m.name AS member_name, m.member_status
    FROM public.board_items bi
    JOIN public.members m ON m.id = bi.assignee_id
    WHERE bi.assignee_id IS NOT NULL
      AND bi.status NOT IN ('archived','done')
      AND m.is_active = false
      AND m.member_status IN ('alumni','observer','inactive')
      AND (p_member_id IS NULL OR bi.assignee_id = p_member_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.board_taxonomy_alerts a
        WHERE a.alert_code = 'orphan_assignee_offboard'
          AND (a.payload->>'board_item_id') = bi.id::text
          AND a.resolved_at IS NULL
      )
      -- #1295 Onda C: um item com handoff pending NAO e orfao (esta rastreado/parked)
      AND NOT EXISTS (
        SELECT 1 FROM public.responsibility_handoffs h
        WHERE h.item_ref = bi.id::text
          AND h.item_type IN ('board_items_assigned','cards_owned','curation_assignments')
          AND h.status = 'pending'
      )
  )
  INSERT INTO public.board_taxonomy_alerts (alert_code, severity, board_id, payload)
  SELECT 'orphan_assignee_offboard', 'warning', o.board_id,
         jsonb_build_object(
           'board_item_id', o.item_id,
           'item_title', o.title,
           'assignee_id', o.assignee_id,
           'assignee_name', o.member_name,
           'assignee_status', o.member_status,
           'detected_at', now()
         )
  FROM offenders o;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

COMMENT ON FUNCTION public.detect_orphan_assignees_from_offboards(uuid) IS
  '#1295 [EPIC #1020 Onda C] deteccao de board_items assignee de membros offboarded — agora HANDOFF-AWARE: itens com responsibility_handoff pending nao sao orfaos (rastreados/parked). Nao gera alerta para o que o novo fluxo de offboard ja parked.';

-- ── prepare_member_offboard: pre-flight read (inventario + risco de orfao) ────────
CREATE OR REPLACE FUNCTION public.prepare_member_offboard(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_inv jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_member')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;

  v_inv := public.get_member_responsibility_inventory(p_member_id);
  IF v_inv ? 'error' THEN RETURN v_inv; END IF;

  RETURN jsonb_build_object(
    'member_id', p_member_id,
    'member_name', v_inv->'member_name',
    'inventory', v_inv->'surfaces',
    'total_owned', v_inv->'total_items',
    'requires_routing', (v_inv->>'total_items')::int > 0,
    'guidance', 'Rote cada item para um sucessor no mapa de routing; o nao-roteado sera auto-park (TBD) — nada orfaniza.'
  );
END;
$function$;

COMMENT ON FUNCTION public.prepare_member_offboard(uuid) IS
  '#1295 [EPIC #1020 Onda C] pre-flight read do offboard: inventario das 7 superfícies (Onda A) + flag requires_routing. Gate manage_member + service_role.';

-- ── offboard_member_with_handoffs: orquestrador (place routed / auto-park resto) ──
CREATE OR REPLACE FUNCTION public.offboard_member_with_handoffs(
  p_member_id uuid,
  p_new_status text,
  p_reason_category text,
  p_reason_detail text DEFAULT NULL,
  p_routing jsonb DEFAULT '[]'::jsonb,
  p_default_due_date date DEFAULT NULL
) RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_offboard := public.admin_offboard_member(p_member_id, p_new_status, p_reason_category, p_reason_detail, NULL);
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
$function$;

COMMENT ON FUNCTION public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date) IS
  '#1295 [EPIC #1020 Onda C] offboard governado que NAO orfaniza: roteia cada posse (7 superfícies) para um sucessor (place, Onda B/D) ou auto-park (TBD, Onda B) antes de finalizar via admin_offboard_member. Gate manage_member. detect_orphan (handoff-aware) deve retornar 0.';

REVOKE ALL ON FUNCTION public.prepare_member_offboard(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_member_offboard(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date) TO authenticated, service_role;
