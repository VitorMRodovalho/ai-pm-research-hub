-- #1710 — o gate vem ANTES do lookup, e "nao encontrado" deixa de ser distinguivel de "negado".
--
-- Na onda A eu ordenei o contrario DE PROPOSITO, com um comentario dizendo que a checagem vinha
-- depois do lookup "para que 'nao encontrado' continue dizendo isso em vez de virar 'acesso
-- negado'". A preferencia era por qualidade de mensagem. Estava errada.
--
-- Responder "nao encontrado" a quem nao administra o evento diz a essa pessoa se aquele evento
-- EXISTE. Para um evento de iniciativa confidencial (ADR-0105) isso e um oraculo estreito, e e
-- exatamente a classe que o gate do #785 fecha. Com o gate primeiro, as duas situacoes devolvem a
-- MESMA recusa; o "nao encontrado" continua existindo, vindo do nucleo, para quem de fato
-- administra o evento e caiu numa corrida com uma remocao.
--
-- `unseal_event_attendance` tinha o mesmo desenho. Ela escapou do guard so por ainda ser writer
-- (DELETE + UPDATE, e o guard so varre leitoras), mas o oraculo era o mesmo — entao vai junto.
-- O irmao `seal_event_attendance` e reescrito na migration seguinte, junto da licao que ele custou.

CREATE OR REPLACE FUNCTION public.unseal_event_attendance(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_title     text;
  v_date      date;
  v_sealed_at timestamptz;
  v_removed   int := 0;
  v_kept      int := 0;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Mesma ordem do irmao, pela mesma razao: o gate primeiro, e so entao a leitura do evento.
  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event neste evento');
  END IF;

  SELECT e.title, e.date, e.roster_sealed_at INTO v_title, v_date, v_sealed_at
  FROM public.events e WHERE e.id = p_event_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;

  IF v_sealed_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não está selado',
      'reason', 'not_sealed', 'event_id', p_event_id, 'event_title', v_title);
  END IF;

  -- O que a reversao NAO toca: linha nascida do selo em que alguem encostou depois (marcou presenca
  -- ou justificou). Desfazer o selo nao pode apagar trabalho humano, entao essas ficam e sao
  -- CONTADAS, para o chamador saber que a reversao nao foi total.
  SELECT count(*) INTO v_kept
  FROM public.attendance a
  WHERE a.event_id = p_event_id
    AND a.notes = public._roster_seal_marker()
    AND (a.present = true OR a.excused = true);

  -- Limite conhecido e aceito: uma falta RE-AFIRMADA por gente sobre a linha do selo
  -- (`mark_member_present(..., false)`) fica indistinguivel da linha original — mesmo carimbo,
  -- mesmo `present=false`. Ela e apagada junto. O caminho para preservar a decisao humana e marcar
  -- presenca ou justificar, que e o que o aviso do #1726 pede ao lider.
  DELETE FROM public.attendance a
  WHERE a.event_id = p_event_id
    AND a.notes = public._roster_seal_marker()
    AND a.present = false
    AND a.excused = false;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  UPDATE public.events SET roster_sealed_at = NULL WHERE id = p_event_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller_id, 'attendance.roster_unsealed', 'event', p_event_id,
    jsonb_build_object(
      'event_title', v_title, 'event_date', v_date,
      'removed_absent_count', v_removed, 'kept_touched_count', v_kept,
      'was_sealed_at', v_sealed_at));

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_title,
    'event_date', v_date,
    'removed_absent_count', v_removed,
    'kept_touched_count', v_kept,
    'was_sealed_at', v_sealed_at
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
