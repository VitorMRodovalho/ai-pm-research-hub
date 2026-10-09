-- Curadoria: o prazo do item acompanha os curadores ativos.
--
-- Medido em 08/10/2026: um item reatribuido pela varredura de prazo (curation_reviewer_sla_sweep -> _curation_assign_one)
-- tinha curation_due_at no prazo original (01/10) e os curadores ativos com prazo 09/10. O e-mail de lembrete le o prazo
-- do curador; o painel e a fila leem o do item, e mostravam "7d atrasado". Era o unico item defasado na data.
--
-- Corpo de partida = corpo vivo (md5 conferido contra a captura 20260924140723), com so esta mudanca. CREATE OR REPLACE
-- mantem a ACL; atributos repetidos.

CREATE OR REPLACE FUNCTION public._curation_assign_one(
  p_item_id uuid, p_round integer, p_reviewer_id uuid, p_source text, p_assigned_by uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_item     public.board_items%ROWTYPE;
  v_name     text;
  v_sla_days int;
  v_due      timestamptz;
  v_id       uuid;
BEGIN
  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT sla_days INTO v_sla_days FROM public.board_sla_config WHERE board_id = v_item.board_id;
  v_due := now() + make_interval(days => coalesce(v_sla_days, 7));

  INSERT INTO public.curation_reviewer_assignments
    (board_item_id, review_round, reviewer_id, source, assigned_by, due_at)
  VALUES (p_item_id, p_round, p_reviewer_id, p_source, p_assigned_by, v_due)
  ON CONFLICT (board_item_id, review_round, reviewer_id) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN false; END IF;

  -- O prazo do ITEM acompanha os curadores ATIVOS. A substituicao por prazo vencido gravava o prazo novo so no
  -- curador, e o painel (que le board_items.curation_due_at) continuava mostrando o prazo vencido: medido em
  -- 08/10/2026, e-mail dizia "ate 09/10" e o painel "7d atrasado" para o mesmo item.
  -- So a rodada desta atribuicao e so quem ainda deve parecer: parecer dado nao grava released_at, e rodada antiga
  -- continuaria "ativa" (achado do data-architect, 09/10). Mesmo criterio de pendencia da varredura.
  UPDATE public.board_items bi
     SET curation_due_at = (SELECT max(ca.due_at) FROM public.curation_reviewer_assignments ca
                             WHERE ca.board_item_id = p_item_id AND ca.review_round = p_round
                               AND ca.released_at IS NULL
                               AND NOT EXISTS (SELECT 1 FROM public.curation_review_log r
                                                WHERE r.board_item_id = ca.board_item_id AND r.curator_id = ca.reviewer_id
                                                  AND r.review_round = ca.review_round))
   WHERE bi.id = p_item_id AND bi.curation_status = 'curation_pending';

  SELECT name INTO v_name FROM public.members WHERE id = p_reviewer_id;

  -- A designacao manual ja grava o proprio evento; so a automatica e a substituicao gravam aqui.
  IF p_source <> 'manual' THEN
    INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id, review_round, sla_deadline)
    VALUES (v_item.board_id, p_item_id, 'reviewer_assigned',
            CASE p_source WHEN 'reassign' THEN 'Revisor redesignado (prazo vencido): ' ELSE 'Revisor designado (rodizio): ' END
              || coalesce(v_name, '?'),
            p_assigned_by, p_round, v_due);

    IF v_item.curation_status = 'curation_pending' THEN
      PERFORM public.enqueue_curation_drive_grant_for_member(p_item_id, p_reviewer_id, 'reviewer_assignment');
    END IF;
  END IF;

  PERFORM public.create_notification(
    p_reviewer_id,
    'curation_review_assigned',
    'Parecer de curadoria para você',
    '"' || v_item.title || '" aguarda o seu parecer no Comitê de Curadoria até '
      || to_char(v_due AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '.',
    '/admin/curatorship',
    'board_item',
    p_item_id
  );
  RETURN true;
END;
$fn$;

-- Dado: todo item pendente cujo prazo difere do maior prazo entre os curadores que ainda devem parecer na rodada mais
-- recente passa a usar esse prazo.
-- Derivado da regra, nao de uma lista de itens. Pos-condicao: nenhum item pendente defasado.
DO $$
DECLARE v_n integer;
BEGIN
  UPDATE public.board_items bi
     SET curation_due_at = x.max_due
    FROM (SELECT ca.board_item_id, max(ca.due_at) AS max_due
            FROM public.curation_reviewer_assignments ca
           WHERE ca.released_at IS NULL
             AND ca.review_round = (SELECT max(c2.review_round) FROM public.curation_reviewer_assignments c2
                                     WHERE c2.board_item_id = ca.board_item_id)
             AND NOT EXISTS (SELECT 1 FROM public.curation_review_log r
                              WHERE r.board_item_id = ca.board_item_id AND r.curator_id = ca.reviewer_id
                                AND r.review_round = ca.review_round)
           GROUP BY ca.board_item_id) x
   WHERE bi.id = x.board_item_id
     AND bi.curation_status = 'curation_pending'
     AND bi.curation_due_at IS DISTINCT FROM x.max_due;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'curadoria: % item(ns) com prazo realinhado', v_n;

  IF EXISTS (
    SELECT 1 FROM public.board_items bi
      JOIN (SELECT ca.board_item_id, max(ca.due_at) AS max_due FROM public.curation_reviewer_assignments ca
             WHERE ca.released_at IS NULL
               AND ca.review_round = (SELECT max(c2.review_round) FROM public.curation_reviewer_assignments c2
                                       WHERE c2.board_item_id = ca.board_item_id)
               AND NOT EXISTS (SELECT 1 FROM public.curation_review_log r
                                WHERE r.board_item_id = ca.board_item_id AND r.curator_id = ca.reviewer_id
                                  AND r.review_round = ca.review_round)
             GROUP BY ca.board_item_id) x ON x.board_item_id = bi.id
     WHERE bi.curation_status = 'curation_pending' AND bi.curation_due_at IS DISTINCT FROM x.max_due
  ) THEN
    RAISE EXCEPTION 'curadoria: ainda ha item pendente com prazo defasado dos curadores ativos';
  END IF;
END $$;
