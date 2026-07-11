-- #1029 fix(metas): nudge operacional para webinar que passou da data mas segue sem status terminal
--
-- Sintoma: a meta "Webinares realizados" (exec_portfolio_health → get_webinars_count(...,realized))
--   lê 0/N mesmo com webinares já ocorridos, porque `realized` = status='completed' (#479, correto)
--   e NÃO existe mecanismo que avance planned/confirmed → completed depois do evento. O único caminho
--   é o organizador editar o status à mão (upsert_webinar), e isso é esquecido.
--
-- Decisão (owner 2026-07-11, opção B): NÃO auto-transicionar. Re-aterrado ao vivo, os past-dated presos
--   são placeholders sem event_id nem presença — 0 sinal confiável de que ocorreram; um cron marcaria
--   como realizado algo talvez nunca feito, re-inflando a métrica que o #479 corrigiu. Em vez disso,
--   um NUDGE: destacar no admin de webinares a fila de past-dated sem status terminal, e o humano marca
--   Concluído OU Cancelado por webinar. Sem auto-escrita.
--
-- Fix: list_webinars_v2 passa a expor o flag computado `needs_status_review`
--   (status IN planned|confirmed AND scheduled_at < now()). O admin badge-a a fila; a UI conta.
--   Sem mudança de assinatura (payload jsonb via row_to_json) → CREATE OR REPLACE.
--
-- Base: corpo VIVO (pg_get_functiondef); adiciona SÓ a coluna needs_status_review no SELECT interno.
CREATE OR REPLACE FUNCTION public.list_webinars_v2(p_status text DEFAULT NULL::text, p_chapter text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.description, w.scheduled_at, w.duration_min,
      w.status, w.chapter_code,
      i.legacy_tribe_id AS tribe_id,
      w.organizer_id,
      w.co_manager_ids, w.meeting_link, w.youtube_url, w.notes,
      w.event_id, w.board_item_id,
      w.created_at, w.updated_at,
      m.name AS organizer_name,
      i.title AS tribe_name,
      e.date AS event_date,
      e.type AS event_type,
      (SELECT COUNT(*) FROM public.attendance a WHERE a.event_id = w.event_id AND a.present = true) AS attendee_count,
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', cm.id, 'name', cm.name)), '[]'::jsonb)
       FROM public.members cm WHERE cm.id = ANY(w.co_manager_ids)) AS co_managers,
      bi.title AS board_item_title,
      bi.status AS board_item_status,
      -- #1029 nudge: webinar já passou da data mas segue sem status terminal (completed|cancelled).
      -- Sem cron de auto-transição (past-dated sem event/presença não têm sinal confiável de que
      -- ocorreram) — o organizador marca à mão. Este flag só destaca a fila no admin. Ver #479.
      (w.status IN ('planned', 'confirmed') AND w.scheduled_at < now()) AS needs_status_review
    FROM public.webinars w
    LEFT JOIN public.members m ON m.id = w.organizer_id
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.events e ON e.id = w.event_id
    LEFT JOIN public.board_items bi ON bi.id = w.board_item_id
    WHERE (p_status IS NULL OR w.status = p_status)
      AND (p_chapter IS NULL OR w.chapter_code = p_chapter)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND public.rls_can_see_initiative(w.initiative_id)
  ) r;
  RETURN v_result;
END; $function$
;
