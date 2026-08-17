-- #1836: nota de briefing que o entrevistador lê ANTES da entrevista
--
-- Não havia onde guardar isso. `early_acceptance_reason` é write-only (3 escritores, nenhum
-- leitor) e a RPC o ignora quando a candidatura já tem avaliação (#1572).
-- `selection_evaluations.notes` é rotulado "Notas privadas (só você vê)".
-- `selection_interviews.notes` é o único campo que as DUAS superfícies pedidas já leem: o
-- histórico no frontend e `get_application_interviews` no MCP. Faltava apenas o escritor.
--
-- Função NOVA em vez de acrescentar p_notes a schedule_interview, de propósito: a nota precisa
-- ser editável DEPOIS do agendamento (contexto novo não deve exigir remarcação) e precisa
-- alcançar entrevistas que já existem. Um parâmetro no agendamento não faria nem uma nem outra.
--
-- Autoridade espelha schedule_interview: líder do comitê do ciclo OU manage_platform.
-- Audita de propósito: a nota entra no preparo de uma decisão sobre pessoa real.

CREATE OR REPLACE FUNCTION public.set_interview_notes(
  p_interview_id uuid,
  p_notes text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_app       record;
  v_is_lead   boolean;
  v_antes     text;
  v_novo      text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT a.*, si.notes AS notas_atuais
    INTO v_app
  FROM public.selection_interviews si
  JOIN public.selection_applications a ON a.id = si.application_id
  WHERE si.id = p_interview_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller_id AND role = 'lead'
  ) INTO v_is_lead;

  IF NOT v_is_lead AND NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  -- ADR-0109: candidato ativo do ciclo é recusado da superfície de seleção.
  IF public.selection_coi_recused(v_caller_id, v_app.cycle_id) THEN
    RAISE EXCEPTION 'recused_conflict_of_interest';
  END IF;

  v_antes := v_app.notas_atuais;
  v_novo  := NULLIF(TRIM(COALESCE(p_notes, '')), '');

  UPDATE public.selection_interviews
  SET notes = v_novo
  WHERE id = p_interview_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'selection.interview_notes_set', 'selection_interview', p_interview_id,
    jsonb_build_object(
      'had_notes', (v_antes IS NOT NULL),
      'has_notes', (v_novo  IS NOT NULL),
      'len_before', coalesce(length(v_antes), 0),
      'len_after',  coalesce(length(v_novo), 0)
    ),
    jsonb_build_object(
      'application_id', v_app.id,
      'cycle_id', v_app.cycle_id,
      'rpc_version', 'p1836',
      'note', 'O conteudo da nota NAO vai para o audit: ela e PII de preparo de entrevista. O log guarda a mudanca, nao o texto.'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'interview_id', p_interview_id,
    'application_id', v_app.id,
    'has_notes', (v_novo IS NOT NULL),
    'length', coalesce(length(v_novo), 0)
  );
END;
$function$;

-- CREATE FUNCTION concede EXECUTE a PUBLIC por padrão; esta é SECDEF e escreve.
REVOKE ALL ON FUNCTION public.set_interview_notes(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_interview_notes(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.set_interview_notes(uuid, text) IS
  '#1836: grava selection_interviews.notes, a nota de briefing lida pelo entrevistador no historico do frontend e por get_application_interviews no MCP. Editavel depois do agendamento. Lider do comite do ciclo ou manage_platform, com recusa por COI (ADR-0109). Audita a mudanca, nunca o texto.';

NOTIFY pgrst, 'reload schema';
