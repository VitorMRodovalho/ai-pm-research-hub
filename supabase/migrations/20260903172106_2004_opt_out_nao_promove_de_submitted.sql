-- #2004 (reincidencia medida em 03/09/2026): o opt-out de video NAO promove mais, de origem nenhuma.
--
-- CONTEXTO. A decisao de 28/08 (opcao C, "portao primeiro") restringiu a origem da promocao a
-- `submitted`. Mas a propria medicao que embasou aquela decisao, registrada no cabecalho do guard,
-- dizia isto sobre as transicoes para o estado de aguardando entrevista:
--
--     (null)                8 transicoes, 8 ja tinham avaliacao   <- fase objetiva
--     interview_scheduled   1 transicao,  1 ja tinha avaliacao    <- retorno de cancelamento
--     submitted             1 transicao,  0 tinham avaliacao      <- o opt-out, o caso da issue
--
-- Ou seja: foram removidas as QUATRO origens que nunca haviam sido exercidas e mantida a UNICA que
-- produzia o defeito. O portao passou a barrar os estados onde a avaliacao ja comecou (onde existe
-- regua parcial) e a liberar justamente o estado onde ela nao comecou.
--
-- REINCIDENCIA. Em 03/09/2026, as 13:44:48.599305 UTC, uma candidatura real percorreu o mesmo
-- caminho: 5 pilares gravados `opted_out` e promocao `submitted` -> aguardando entrevista, no MESMO
-- microssegundo (transacao unica), rodando como `anon`. Cinco segundos depois, entre 13:44:53 e
-- 13:45:16, o despachante tentou QUATRO vezes emitir o token de agendamento e as quatro foram
-- recusadas com `GATE_NO_PEER_REVIEW`, porque nao havia avaliacao. Resultado: a pessoa ficou presa
-- (escolheu entrevista ao vivo e o convite nao sai) e DOIS required checks ficaram vermelhos por
-- caminhos diferentes — o ratchet do #2004 subindo de 1 para 2, e o guard do #1636 vendo tentativa
-- de portao sem ator em candidatura real (#2171).
--
-- DECISAO. O opt-out deixa de promover. A promocao para o estado de aguardando entrevista passa a
-- vir apenas dos caminhos que olham a regua.
--
-- O QUE NAO MUDA. A escolha do candidato continua registrada nos 5 pilares, em QUALQUER status: o
-- portao limita a PROMOCAO, nunca o direito de escolher entrevista ao vivo. O INSERT dos pilares
-- segue ANTES do bloco de auditoria, de proposito, e o guard afirma essa ordem.
--
-- FORMA DO CORPO. A recusa passa a ser INCONDICIONAL e o corpo executavel deixa de mencionar o nome
-- do estado. Isso permite um guard muito mais forte que o anterior: em vez de casar a forma do IF
-- (que nao distingue "promover a partir da lista" de "recusar a partir da lista"), o guard passa a
-- exigir que o corpo, sem comentarios, NAO cite o estado. Se alguem reintroduzir a promocao, tera
-- de escrever o nome, e o guard reprova.
--
-- Assinatura, SECURITY DEFINER, search_path e volatilidade preservados identicos ao corpo vivo
-- capturado em 03/09/2026 (`pg_get_functiondef`).
--
-- Cross-ref: #2004 (esta issue), #2171 (o sintoma a jusante), #1613 (o portao da OUTRA transicao),
-- #2012 (recusa que nao commita nao existe — dai o rastro em admin_audit_log).

CREATE OR REPLACE FUNCTION public.opt_out_all_pillars(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_organization_id uuid;
  v_app_status text;
  v_pillars text[] := ARRAY['background','communication','proactivity','teamwork','culture_alignment'];
  v_question_indices int[] := ARRAY[1,2,3,4,5];
  v_promoted boolean := false;
  i int;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'video_screening' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing video_screening scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type does not support video screening (got %)', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;
  v_organization_id := v_token_row.organization_id;

  SELECT status INTO v_app_status FROM selection_applications WHERE id = v_application_id;

  FOR i IN 1..5 LOOP
    INSERT INTO pmi_video_screenings (
      application_id, pillar, question_index, question_text,
      storage_provider, status, organization_id
    ) VALUES (
      v_application_id, v_pillars[i], v_question_indices[i],
      'Optou por entrevista ao vivo (cobre os 5 pilares)',
      'opted_out', 'opted_out', v_organization_id
    )
    ON CONFLICT (application_id, pillar, question_index) DO UPDATE SET
      storage_provider = 'opted_out',
      status = 'opted_out',
      drive_file_id = NULL,
      drive_folder_id = NULL,
      drive_file_name = NULL,
      youtube_url = NULL,
      uploaded_at = NULL,
      failure_reason = NULL,
      retry_count = 0,
      updated_at = now();
  END LOOP;

  -- A escolha ja esta gravada acima. O que fica aqui e so o rastro de que ela NAO promoveu,
  -- registrado sempre: silencio nao se distingue de "nao aconteceu" (#2012).
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (NULL, 'selection.opt_out_promotion_refused', 'selection_application', v_application_id,
    jsonb_build_object(
      'reason', 'o opt-out nao promove: a fase objetiva e pre-requisito do convite de entrevista (#2004)',
      'app_status', v_app_status,
      'refused_at', now()
    ));

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'pillars_opted_out', 5,
    'app_status_before', v_app_status,
    'promoted', v_promoted,
    'app_status_after', v_app_status
  );
END;
$function$;

COMMENT ON FUNCTION public.opt_out_all_pillars(text) IS
  '#2004: registra a escolha do candidato por entrevista ao vivo nos 5 pilares e NAO promove a '
  'candidatura. A promocao vem apenas dos caminhos que olham a avaliacao objetiva. A recusa fica '
  'em admin_audit_log como selection.opt_out_promotion_refused.';
