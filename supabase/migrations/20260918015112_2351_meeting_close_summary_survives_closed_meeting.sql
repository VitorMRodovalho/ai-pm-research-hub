-- #2351 — o resumo do close deixa de evaporar em reuniao ja fechada.
--
-- Medido em 17/09 (exercicio com impersonacao, BEGIN/ROLLBACK, dois bracos):
--   braco A (reuniao ja fechada): summary_appended=false, notes=0 chars  -> resumo perdido
--   braco B (mesma fn/evento/chamador, NAO fechada): summary_appended=true, notes=80 chars
-- A unica diferenca era o estado fechado, e o resumo sumia retornando success:true.
--
-- Causa: `notes` so era atualizado dentro de `IF NOT v_already_closed`; o ramo ELSE
-- so gravava suggested_champion_ids. Como `upsert_event_minutes` (rota action='write')
-- carimba minutes_posted_at na PRIMEIRA ata, a sequencia natural write -> close cai
-- sempre no ELSE, e todo resumo de reconciliacao evaporava.
--
-- Conserto (opcao (b), decisao do dono 17/09): anexar o resumo TAMBEM no ramo ELSE,
-- com protecao anti-duplicata (nao reanexa um resumo que ja esta em notes), e tornar
-- `summary_appended` no retorno um relato do que de fato aconteceu, nao da branch.
CREATE OR REPLACE FUNCTION public.meeting_close(
  p_event_id uuid,
  p_summary text DEFAULT NULL::text,
  p_suggested_champion_ids uuid[] DEFAULT NULL::uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event record;
  v_already_closed boolean;
  v_action_count int;
  v_decision_count int;
  v_unresolved_count int;
  v_markdown_action_count int;
  v_structured_drift int;
  v_links_total int;
  v_showcase_count int;
  v_validated_suggestions uuid[];
  v_invalid_suggestions uuid[];
  v_blocks_total int;
  v_blocks_pending int;
  v_blocks_pending_list jsonb;
  v_summary_in text;
  v_summary_dup boolean;
  v_summary_appended boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- #1383: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  SELECT id, title, date, minutes_text, minutes_posted_at, notes
  INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  v_already_closed := v_event.minutes_posted_at IS NOT NULL;

  -- #2351: o resumo e aceito independentemente de a reuniao ja estar fechada.
  -- Anti-duplicata: um close repetido com o MESMO texto nao reanexa o bloco.
  v_summary_in  := NULLIF(trim(COALESCE(p_summary, '')), '');
  v_summary_dup := v_summary_in IS NOT NULL
                   AND position(v_summary_in in COALESCE(v_event.notes, '')) > 0;

  IF p_suggested_champion_ids IS NOT NULL AND cardinality(p_suggested_champion_ids) > 0 THEN
    IF cardinality(p_suggested_champion_ids) > 10 THEN
      RETURN jsonb_build_object('error', 'too_many_suggestions', 'detail', 'max 10 suggested member ids per meeting_close');
    END IF;

    SELECT array_agg(DISTINCT s ORDER BY s) INTO v_validated_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    SELECT array_agg(DISTINCT s) INTO v_invalid_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    IF v_invalid_suggestions IS NOT NULL AND cardinality(v_invalid_suggestions) > 0 THEN
      RETURN jsonb_build_object(
        'error', 'invalid_suggestions',
        'detail', 'unknown or out-of-org member ids: ' || array_to_string(v_invalid_suggestions, ', ')
      );
    END IF;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE kind = 'action'),
    COUNT(*) FILTER (WHERE kind = 'decision'),
    COUNT(*) FILTER (WHERE kind IN ('action','followup') AND resolved_at IS NULL)
  INTO v_action_count, v_decision_count, v_unresolved_count
  FROM public.meeting_action_items WHERE event_id = p_event_id;

  v_markdown_action_count := COALESCE(
    (SELECT array_length(regexp_split_to_array(v_event.minutes_text, E'(^|\\n)\\s*-\\s*\\[\\s*\\]'), 1) - 1),
    0
  );
  v_markdown_action_count := GREATEST(0, v_markdown_action_count);
  v_structured_drift := GREATEST(0, v_markdown_action_count - v_action_count);

  SELECT COUNT(*) INTO v_links_total
  FROM public.board_item_event_links WHERE event_id = p_event_id;

  SELECT COUNT(*) INTO v_showcase_count
  FROM public.event_showcases WHERE event_id = p_event_id;

  -- #1548: bloco reservado que nunca foi confirmado nem marcado no_show.
  SELECT COUNT(*), COUNT(*) FILTER (WHERE b.status = 'reserved')
  INTO v_blocks_total, v_blocks_pending
  FROM public.event_agenda_blocks b WHERE b.event_id = p_event_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', b.id,
           'sort_order', b.sort_order,
           'title', b.title,
           'format_slug', b.format_slug,
           'duration_min', b.duration_min,
           'owner_member_id', b.owner_member_id,
           'owner_name', bm.name
         ) ORDER BY b.sort_order), '[]'::jsonb)
  INTO v_blocks_pending_list
  FROM public.event_agenda_blocks b
  JOIN public.members bm ON bm.id = b.owner_member_id
  WHERE b.event_id = p_event_id AND b.status = 'reserved';

  -- #2351: o resumo passa a ser anexado nos DOIS ramos. O que muda entre eles e
  -- apenas o carimbo de fechamento (minutes_posted_at/by), nunca o resumo.
  v_summary_appended := v_summary_in IS NOT NULL AND NOT v_summary_dup;

  IF NOT v_already_closed THEN
    UPDATE public.events
    SET minutes_posted_at = now(),
        minutes_posted_by = v_caller_id,
        notes = CASE
          WHEN v_summary_appended
            THEN COALESCE(notes, '') ||
                 CASE WHEN COALESCE(notes, '') <> '' THEN E'\n\n' ELSE '' END ||
                 '## Meeting close summary (' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' ||
                 E'\n' || v_summary_in
          ELSE notes
        END,
        suggested_champion_ids = COALESCE(v_validated_suggestions, suggested_champion_ids),
        updated_at = now()
    WHERE id = p_event_id;
  ELSE
    IF v_summary_appended OR v_validated_suggestions IS NOT NULL THEN
      UPDATE public.events
      SET notes = CASE
            WHEN v_summary_appended
              THEN COALESCE(notes, '') ||
                   CASE WHEN COALESCE(notes, '') <> '' THEN E'\n\n' ELSE '' END ||
                   '## Meeting close summary (' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' ||
                   E'\n' || v_summary_in
            ELSE notes
          END,
          suggested_champion_ids = COALESCE(v_validated_suggestions, suggested_champion_ids),
          updated_at = now()
      WHERE id = p_event_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_event.title,
    'already_closed', v_already_closed,
    'closed_at', CASE WHEN v_already_closed THEN v_event.minutes_posted_at ELSE now() END,
    'action_count', v_action_count,
    'decision_count', v_decision_count,
    'unresolved_actions', v_unresolved_count,
    'markdown_action_count', v_markdown_action_count,
    'structured_drift', v_structured_drift,
    'links_total', v_links_total,
    'showcase_count', v_showcase_count,
    'drift_signal', v_structured_drift > 0,
    'agenda_blocks_total', v_blocks_total,
    'agenda_blocks_pending', v_blocks_pending,
    'agenda_blocks_pending_list', v_blocks_pending_list,
    'blocks_pending_signal', v_blocks_pending > 0,
    'summary_appended', v_summary_appended,
    'summary_duplicate', COALESCE(v_summary_dup, false),
    'suggestions_count', COALESCE(cardinality(v_validated_suggestions), 0),
    'suggestions_stored', v_validated_suggestions
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- #2351 — helper de EXERCICIO para o guard (camada VIVA, nao leitura de catalogo).
--
-- Por que existe: `tests/contracts/*` roda por supabase-js, que NAO consegue setar
-- `request.jwt.claims` e chamar a RPC na MESMA transacao (nota ja registrada em
-- 1477-tcv-carveout / 1326-my-meetings-audience-scope). Sem este helper o guard so
-- conseguiria afirmar sobre o TEXTO da migration, e texto nao exercita banco.
--
-- Segue o precedente de `_test_invariants_with_synthetic_breach`: SECURITY DEFINER,
-- portao de service_role, e EXECUTE revogado de anon/authenticated (funcao nova nasce
-- com EXECUTE para anon — precisa ser tirado a mao).
--
-- Roda os DOIS bracos e NAO deixa rastro: as escritas acontecem num sub-bloco que
-- termina em RAISE, entao a sub-transacao inteira volta atras. Variaveis de PL/pgSQL
-- nao sao revertidas pelo rollback, entao as observacoes sobrevivem para o retorno.
CREATE OR REPLACE FUNCTION public._test_meeting_close_summary_roundtrip()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_event_id uuid;
  v_auth_id  uuid;
  v_canary   text := '__test_2351_' || replace(gen_random_uuid()::text, '-', '');
  v_ret_a jsonb; v_ret_b jsonb;
  v_notes_a text; v_notes_b text;
  v_sentinel constant text := '__ROLLBACK_2351__';
BEGIN
  IF current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: _test_meeting_close_summary_roundtrip requires service_role';
  END IF;

  -- Um evento JA FECHADO e alguem que possa fecha-lo. Se nao houver, aborta com
  -- "nao medido" em vez de devolver um verde que nao mediu nada.
  SELECT e.id, m.auth_id INTO v_event_id, v_auth_id
  FROM public.events e
  CROSS JOIN LATERAL (
    SELECT mm.id, mm.auth_id FROM public.members mm
    WHERE mm.auth_id IS NOT NULL AND public._manage_event_scope_ok(mm.id, e.id)
    LIMIT 1
  ) m
  WHERE e.minutes_posted_at IS NOT NULL
  ORDER BY e.date DESC
  LIMIT 1;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'not_measured: no closed event with an authorized closer';
  END IF;

  BEGIN
    PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_auth_id, 'role', 'authenticated')::text, true);

    -- BRACO A (o que a #2351 conserta): reuniao JA FECHADA + resumo.
    v_ret_a := public.meeting_close(v_event_id, v_canary || '_A', NULL);
    SELECT notes INTO v_notes_a FROM public.events WHERE id = v_event_id;

    -- CONTROLE POSITIVO B: mesma funcao, mesmo evento, mesmo chamador, NAO fechada.
    -- Se B falhar, o instrumento esta quebrado e A nao prova nada.
    UPDATE public.events SET minutes_posted_at = NULL, notes = NULL WHERE id = v_event_id;
    v_ret_b := public.meeting_close(v_event_id, v_canary || '_B', NULL);
    SELECT notes INTO v_notes_b FROM public.events WHERE id = v_event_id;

    RAISE EXCEPTION '%', v_sentinel;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> v_sentinel THEN RAISE; END IF;
  END;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'canary', v_canary,
    'arm_a', jsonb_build_object(
      'already_closed',   v_ret_a->'already_closed',
      'summary_appended', v_ret_a->'summary_appended',
      'notes_has_canary', COALESCE(v_notes_a, '') LIKE '%' || v_canary || '_A%'),
    'arm_b_control', jsonb_build_object(
      'already_closed',   v_ret_b->'already_closed',
      'summary_appended', v_ret_b->'summary_appended',
      'notes_has_canary', COALESCE(v_notes_b, '') LIKE '%' || v_canary || '_B%')
  );
END;
$function$;

REVOKE ALL ON FUNCTION public._test_meeting_close_summary_roundtrip() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._test_meeting_close_summary_roundtrip() FROM anon;
REVOKE ALL ON FUNCTION public._test_meeting_close_summary_roundtrip() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._test_meeting_close_summary_roundtrip() TO service_role;
