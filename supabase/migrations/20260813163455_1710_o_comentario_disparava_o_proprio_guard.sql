-- #1710 — o gate vem antes do lookup TAMBEM no selo, e a prosa do comentario disparava o guard.
--
-- Duas coisas nesta migration, e a segunda e a interessante.
--
-- 1. Mesma correcao da migration anterior, aplicada a `seal_event_attendance`: o gate por recurso
--    vem antes de qualquer leitura da agenda, para que "nao existe" e "nao e seu" devolvam a MESMA
--    recusa a quem nao administra o evento (ADR-0105 / #785).
--
-- 2. A primeira tentativa de correcao continuou vermelha, e o motivo nao estava no codigo.
--    `_audit_secdef_initiative_reader_gates()` varre `prosrc`, que INCLUI comentarios — e o
--    comentario que eu havia escrito explicava, em portugues, que a funcao deixara de ler a tabela
--    da agenda, escrevendo o nome dela em ingles. Medido: com comentarios o corpo casava o padrao;
--    sem comentarios, nao casava. A funcao nao lia a tabela; a explicacao e que lia.
--
--    E o espelho de uma armadilha ja paga aqui: um guard de AUSENCIA que casa o proprio comentario.
--    Aqui um guard de PRESENCA casou a explicacao de por que a presenca tinha acabado.
--
--    A correcao e reescrever a prosa. NAO entra no ALLOWLIST do guard, porque entrar la afirmaria
--    que esta e uma leitora sem gate justificada, e ela nao e leitora nenhuma. E, por razao mais
--    forte, nao se escreve no comentario a palavra que faria `references_gate` virar true: seria
--    comprar o verde com um comentario, o que e pior do que o vermelho.

CREATE OR REPLACE FUNCTION public.seal_event_attendance(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- #1710: era `can_by_member(v_caller_id, 'manage_event')`, um gate SEM recurso. Medido em
  -- 13/08/2026: 622 pares (lider, evento) passavam por ele e nao pelo escopado, cada lider de tribo
  -- alcancando 49 a 55 eventos de OUTRAS tribos. Mesma classe do #1728.
  --
  -- O gate vem ANTES de qualquer leitura da agenda: para quem nao administra o evento, "nao existe"
  -- e "nao e seu" tem de ser a MESMA resposta (ADR-0105). Evento inexistente cai aqui, porque
  -- `_can_manage_event` devolve false quando nao acha a linha. O "nao encontrado" continua
  -- existindo, vindo do nucleo, para quem de fato administra e caiu numa corrida com uma remocao.
  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event neste evento');
  END IF;

  RETURN public._seal_event_attendance_apply(p_event_id, v_caller_id, false);
END;
$function$;

NOTIFY pgrst, 'reload schema';
