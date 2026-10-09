-- =====================================================================================
-- trg_auto_submit_curation_on_reviewer_assign: paridade com as demais entradas na curadoria
-- (#2447: so artefato publicavel entra na curadoria). Card que nao e artefato publicavel segue
-- com a designacao, sem envio automatico.
--
-- Corpo montado sobre o vivo (md5 normalizado == captura 20260718000000, conferido em 09/10).
-- Assinatura, SECURITY DEFINER, search_path e grants nao mudam (CREATE OR REPLACE); o gatilho
-- que chama a funcao nao muda.
-- ROLLBACK: reaplicar a captura 20260718000000 de trg_auto_submit_curation_on_reviewer_assign.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.trg_auto_submit_curation_on_reviewer_assign()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_item public.board_items%ROWTYPE;
BEGIN
  IF NEW.role IS DISTINCT FROM 'curation_reviewer' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = NEW.item_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Paridade com as demais entradas na curadoria (#2447): so artefato publicavel.
  IF v_item.status = 'done' AND v_item.curation_status = 'draft'
     AND public._board_item_needs_curation(NEW.item_id) THEN
    UPDATE public.board_items
    SET curation_status = 'curation_pending',
        updated_at = now()
    WHERE id = NEW.item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      NEW.item_id,
      'submitted_for_curation',
      'Auto-submit (trigger): curation_reviewer assigned to completed card. Distinct from manual submit_for_curation() RPC call.',
      -- p197 fix H5: NULL guard for bulk/system inserts (Trello sync, migration backfill)
      COALESCE(NEW.assigned_by, v_item.assignee_id)
    );
  END IF;

  RETURN NEW;
END;
$$;
