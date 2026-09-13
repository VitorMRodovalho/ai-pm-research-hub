-- #2265 — a reemissao do link de onboarding para candidatura JA APROVADA.
--
-- O DEFEITO, medido em 13/09: `dispatch_pending_welcomes` seleciona apenas
-- `status = 'submitted'` + ciclo aberto + `ai_analysis IS NULL`. Quem foi APROVADO e nao concluiu o
-- onboarding nao e alcancado por ele — nem por nenhuma outra funcao. Nao e so "falta reemissao
-- self-service": nao existe reemissao NENHUMA depois da submissao, nem administrativa. A recuperacao
-- hoje exige inserir token a mao no banco.
--
-- A DIMENSAO: dos 114 tokens de onboarding emitidos desde 29/04, 75 foram consumidos (66%). Os 39
-- restantes se dividem em 22 que nunca abriram o e-mail e 20 que abriram e nao clicaram. E a
-- hipotese de nao-entrega esta REFUTADA nessa coorte: 0 nao entregues, 0 bounce, 0 reclamacao. O
-- e-mail chega; o que falta e uma segunda chance.
--
-- ⚠️ ESTA MIGRATION NAO RESOLVE OS 39. Ela resolve a recuperacao de quem JA passou da janela, que e o
-- caso das 4 pessoas travadas hoje. O lembrete ANTES de expirar (que e o que atenderia os 39) e outro
-- conserto, deliberadamente fora daqui: ele dispara e-mail em lote por cron e merece PR propria.
--
-- Cross-ref: #2265, #2241, #2245, #2130, #2188.

CREATE OR REPLACE FUNCTION public.reissue_onboarding_link(
  p_application_id uuid,
  p_ttl_days integer DEFAULT 14,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_token text;
  v_token_hash text;
  v_url text;
  v_first_name text;
  v_role_label text;
  v_expires timestamptz;
  v_ativos int;
  v_role_labels jsonb := jsonb_build_object(
    'leader', 'Líder de Tribo',
    'researcher', 'Pesquisador',
    'manager', 'Gerente de Projeto',
    'both', 'Pesquisador / Líder'
  );
BEGIN
  -- Mesmo portao de `dispatch_pending_welcomes`: reemitir link de acesso e ato de ciclo de vida.
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member';
  END IF;

  IF p_ttl_days IS NULL OR p_ttl_days < 1 OR p_ttl_days > 90 THEN
    RAISE EXCEPTION 'p_ttl_days fora da faixa 1..90: %', p_ttl_days;
  END IF;

  SELECT a.id, a.applicant_name, a.email, a.role_applied, a.chapter,
         a.organization_id, a.status
    INTO v_app
  FROM public.selection_applications a
  WHERE a.id = p_application_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Candidatura nao encontrada: %', p_application_id;
  END IF;

  -- Aceita `submitted` E `approved`. O recorte so-`submitted` do dispatch e exatamente o defeito:
  -- ele assume que o onboarding acontece ANTES da aprovacao, e a coorte de 13/09 mostra 4 pessoas
  -- aprovadas e travadas DEPOIS dela.
  IF v_app.status NOT IN ('submitted', 'approved') THEN
    RAISE EXCEPTION 'Reemissao so vale para candidatura submitted ou approved; esta esta em %', v_app.status;
  END IF;

  -- Nao reemite por cima de link VIVO: dois links validos para a mesma pessoa e convite para usar o
  -- errado, e o mais antigo continuaria valendo ate expirar.
  SELECT count(*) INTO v_ativos
  FROM public.onboarding_tokens t
  WHERE t.source_id = v_app.id
    AND t.source_type = 'pmi_application'
    AND t.scopes @> ARRAY['profile_completion']::text[]
    AND t.consumed_at IS NULL
    AND t.expires_at > now();

  IF v_ativos > 0 AND NOT p_dry_run THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'link_ativo_existente',
      'detail', format('%s link(s) de onboarding ainda valido(s); reemitir criaria ambiguidade', v_ativos),
      'application_id', v_app.id
    );
  END IF;

  v_first_name := split_part(v_app.applicant_name, ' ', 1);
  v_role_label := COALESCE(v_role_labels->>v_app.role_applied, v_app.role_applied, 'Voluntário');
  v_expires := now() + (p_ttl_days || ' days')::interval;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true,
      'dry_run', true,
      'application_id', v_app.id,
      'status', v_app.status,
      'to_email', v_app.email,
      'role_label', v_role_label,
      'links_ativos_hoje', v_ativos,
      'would_expire_at', v_expires
    );
  END IF;

  v_token := translate(
    regexp_replace(encode(extensions.gen_random_bytes(32), 'base64'), '=+$', '', 'g'),
    '+/', '-_'
  );
  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  INSERT INTO public.onboarding_tokens (
    token, source_type, source_id, scopes,
    issued_at, expires_at, issued_by, organization_id
  ) VALUES (
    v_token, 'pmi_application', v_app.id,
    ARRAY['profile_completion', 'video_screening', 'consent_giving'],
    now(), v_expires, v_caller.id, v_app.organization_id
  );

  v_url := 'https://nucleoia.vitormr.dev/pmi-onboarding/' || v_token;

  PERFORM public.campaign_send_one_off(
    p_template_slug := 'pmi_welcome_with_token',
    p_to_email := v_app.email,
    p_variables := jsonb_build_object(
      'first_name', v_first_name,
      'role_label', v_role_label,
      'chapter', COALESCE(v_app.chapter, 'Núcleo IA & GP'),
      'onboarding_url', v_url,
      'expires_in_days', p_ttl_days
    ),
    p_metadata := jsonb_build_object(
      'source', 'reissue_onboarding_link',
      'application_id', v_app.id,
      'onboarding_token_hash', v_token_hash,
      'application_status', v_app.status,
      'rpc_version', 'i2265_v1'
    )
  );

  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.onboarding_link_reissued',
    'selection_application',
    v_app.id,
    jsonb_build_object(
      'token_hash', v_token_hash,
      'expires_in_days', p_ttl_days,
      'application_status', v_app.status
    ),
    jsonb_build_object(
      'source', 'reissue_onboarding_link',
      'rpc_version', 'i2265_v1',
      'incident', 'i2265-sem-caminho-de-volta'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', false,
    'application_id', v_app.id,
    'status', v_app.status,
    'token_hash', v_token_hash,
    'expires_at', v_expires
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.reissue_onboarding_link(uuid, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reissue_onboarding_link(uuid, integer, boolean) TO authenticated;

COMMENT ON FUNCTION public.reissue_onboarding_link(uuid, integer, boolean) IS
  '#2265 — reemite o link de onboarding para candidatura submitted OU approved. Existe porque dispatch_pending_welcomes so alcanca `submitted`, e a coorte de 13/09 mostrou 4 pessoas aprovadas e travadas sem nenhum caminho de volta (nem administrativo). Dry-run por padrao; recusa reemitir por cima de link ainda valido; grava admin_audit_log. NAO atende os 39 que deixaram a janela passar — isso e lembrete antes de expirar, outro conserto.';

NOTIFY pgrst, 'reload schema';
