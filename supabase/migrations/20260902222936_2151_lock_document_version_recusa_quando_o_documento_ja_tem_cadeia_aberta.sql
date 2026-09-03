-- WHAT: `lock_document_version` passa a RECUSAR quando o DOCUMENTO ja tem cadeia aberta, em vez de
--       lacrar e abrir uma segunda em paralelo. Uma guarda nova; o resto do corpo fica identico.
--
-- WHY:  a guarda que existia perguntava a coisa errada:
--
--         SELECT ac.id FROM approval_chains ac WHERE ac.version_id = p_version_id
--
--       Isso pergunta se existe cadeia para AQUELA VERSAO. Versao nova e sempre `version_id` novo,
--       entao a guarda nunca disparava, e lacrar pelo caminho direto abria uma segunda cadeia com a
--       anterior ainda em `review`. Medido em 02/09/2026: dois documentos de Propriedade
--       Intelectual carregavam duas cadeias abertas cada um, uma de maio e outra de 30/08.
--
-- DE QUEM E A DECISAO, E O TRADE-OFF QUE FOI PESADO (dono, 02/09/2026): a alternativa era a RPC
--       SUPERSEDAR sozinha a cadeia anterior, fazendo os dois caminhos convergirem. Foi rejeitada
--       porque significa uma funcao chamada "lock" FECHANDO um processo de aprovacao em curso — e a
--       cadeia anterior pode ter portoes ja cumpridos, com pessoas que assinaram. Fechar isso sem
--       ninguem pedir e o tipo de acao que so se descobre depois.
--       Recusar transforma um defeito silencioso em erro visivel no momento da chamada, e o caminho
--       completo ja existe: `recirculate_governance_doc` supersede, lacra, notifica e audita.
--
-- POR QUE ISTO NAO QUEBRA `recirculate_governance_doc`: ela supersede a cadeia corrente ANTES de
--       chamar `lock_document_version`. Quando o lock roda por ali, nao ha mais cadeia aberta e a
--       guarda nao dispara. A ordem esta no corpo dela e foi conferida.
--
-- O FORMATO DA RECUSA acompanha o que ja existia: `success:false` mais `error`, e nao uma excecao.
--       O chamador (`ReviewChainIsland`) ja trata esse shape para `chain_already_exists`; levantar
--       excecao aqui mudaria o contrato de erro da funcao para um caso que e esperado.
--
-- OS ESTADOS QUE CONTAM COMO ABERTA sao os mesmos que a migration 20260805000370 (#1187) usa para
--       decidir o que supersedar: draft, review, approved. Reaproveitar a lista importa: se este
--       gate e o supersede do #1187 discordarem do que e "aberta", um vai criar o estado que o
--       outro tenta impedir.
--
-- SCOPE LOCK: o corpo veio de `pg_get_functiondef` da funcao viva. Assinatura (incluindo o
--       `DEFAULT NULL::text` de p_change_class), LANGUAGE plpgsql, SECURITY DEFINER, VOLATILE e
--       `search_path` ficam identicos. `CREATE OR REPLACE` preserva a ACL.
--
-- ROLLBACK: remover o bloco marcado `#2151` e a declaracao de `v_open_doc_chain`.
--
-- CROSS-REF: #2151 · #1187 e a migration 20260805000370 (a lista de estados abertos) · a migration
--       20260902212957 (que corrigiu o acervo que este gate impede de reincidir)

CREATE OR REPLACE FUNCTION public.lock_document_version(p_version_id uuid, p_gates jsonb, p_change_class text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_chain_id uuid;
  v_existing_chain uuid;
  v_open_doc_chain uuid;
  v_notif_count int;
  v_class text;
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- include dv.change_class so COALESCE below sees a pre-set draft classification
  SELECT dv.id, dv.document_id, dv.organization_id, dv.version_number, dv.version_label, dv.locked_at, dv.change_class
  INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_version_id;

  IF v_version.id IS NULL THEN
    RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_version.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'document_version already locked at % — create a new version instead', v_version.locked_at
      USING ERRCODE = 'check_violation';
  END IF;

  -- #571 Camada 5 PR-1: resolve change_class (Material/Editorial). Precedence:
  -- explicit param > value pre-set on the draft. Validate when present; never default.
  -- NULL allowed (backward-compat); UI lock modal requires a deliberate choice.
  v_class := COALESCE(p_change_class, v_version.change_class);
  IF v_class IS NOT NULL AND v_class NOT IN ('editorial','material') THEN
    RAISE EXCEPTION 'change_class must be editorial or material (got %)', v_class
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_gates IS NULL OR jsonb_typeof(p_gates) <> 'array' OR jsonb_array_length(p_gates) = 0 THEN
    RAISE EXCEPTION 'gates must be a non-empty jsonb array' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_gates) g
    WHERE NOT (g ? 'kind' AND g ? 'order' AND g ? 'threshold')
  ) THEN
    RAISE EXCEPTION 'each gate must have kind, order, threshold keys' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id INTO v_existing_chain
  FROM public.approval_chains ac
  WHERE ac.version_id = p_version_id LIMIT 1;
  IF v_existing_chain IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'chain_already_exists',
      'chain_id', v_existing_chain,
      'version_id', p_version_id
    );
  END IF;

  -- #2151: a guarda acima pergunta pela VERSAO; esta pergunta pelo DOCUMENTO.
  -- Versao nova e sempre version_id novo, entao a de cima nunca dispara em troca de rodada, e a
  -- cadeia anterior ficava aberta em `review` ao lado da nova. Quem quer trocar de rodada tem de
  -- passar por `recirculate_governance_doc`, que supersede a corrente ANTES de lacrar a proxima,
  -- e ainda notifica e audita. Estados abertos = os mesmos do supersede do #1187.
  SELECT ac.id INTO v_open_doc_chain
  FROM public.approval_chains ac
  WHERE ac.document_id = v_version.document_id
    AND ac.status IN ('draft', 'review', 'approved')
  ORDER BY ac.opened_at DESC
  LIMIT 1;
  IF v_open_doc_chain IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'document_has_open_chain',
      'chain_id', v_open_doc_chain,
      'document_id', v_version.document_id,
      'version_id', p_version_id,
      'hint', 'use recirculate_governance_doc(p_chain_id) — ela supersede a cadeia corrente e lacra a proxima no mesmo ato'
    );
  END IF;

  UPDATE public.document_versions
    SET locked_at = now(),
        locked_by = v_member.id,
        published_at = now(),
        published_by = v_member.id,
        change_class = v_class,
        updated_at = now()
    WHERE id = p_version_id;

  INSERT INTO public.approval_chains (
    document_id, version_id, organization_id, status, gates, opened_at, opened_by
  ) VALUES (
    v_version.document_id, p_version_id, v_version.organization_id, 'review', p_gates, now(), v_member.id
  ) RETURNING id INTO v_chain_id;

  UPDATE public.governance_documents
    SET current_version_id = p_version_id,
        updated_at = now()
    WHERE id = v_version.document_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id, 'document_version.locked', 'document_version', p_version_id,
    jsonb_build_object(
      'document_id', v_version.document_id,
      'version_number', v_version.version_number,
      'version_label', v_version.version_label,
      'chain_id', v_chain_id,
      'change_class', v_class,
      'gates', p_gates
    )
  );

  v_notif_count := public._enqueue_gate_notifications(v_chain_id, 'chain_opened', NULL);

  RETURN jsonb_build_object(
    'success', true,
    'version_id', p_version_id,
    'chain_id', v_chain_id,
    'change_class', v_class,
    'notifications_enqueued', v_notif_count,
    'locked_at', now()
  );
END;
$function$;

-- POS-CONDICOES.
DO $$
DECLARE
  v_src        text;
  v_args       text;
  v_secdef     boolean;
  v_config     text;
BEGIN
  SELECT p.prosrc, pg_get_function_arguments(p.oid), p.prosecdef, array_to_string(p.proconfig, ',')
    INTO v_src, v_args, v_secdef, v_config
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'lock_document_version';

  -- 1. A guarda nova existe no corpo VIVO, e pergunta pelo documento.
  IF v_src NOT LIKE '%document_has_open_chain%' THEN
    RAISE EXCEPTION 'POS-CONDICAO: a recusa document_has_open_chain nao esta no corpo vivo';
  END IF;
  IF v_src NOT LIKE '%ac.document_id = v_version.document_id%' THEN
    RAISE EXCEPTION 'POS-CONDICAO: a guarda nova nao filtra por document_id';
  END IF;

  -- 2. A guarda ANTIGA continua: as duas perguntam coisas diferentes e as duas importam.
  IF v_src NOT LIKE '%chain_already_exists%' THEN
    RAISE EXCEPTION 'POS-CONDICAO: a guarda por version_id sumiu';
  END IF;

  -- 3. A ASSINATURA nao mudou. `CREATE OR REPLACE` que omite o DEFAULT de um parametro e recusado,
  --    mas omitir SECURITY DEFINER ou search_path passa e resseta em silencio — por isso os tres
  --    sao afirmados aqui, e nao so o corpo.
  IF v_args NOT LIKE '%p_change_class text DEFAULT NULL::text%' THEN
    RAISE EXCEPTION 'POS-CONDICAO: o DEFAULT de p_change_class se perdeu (args=%)', v_args;
  END IF;
  IF NOT v_secdef THEN
    RAISE EXCEPTION 'POS-CONDICAO: a funcao deixou de ser SECURITY DEFINER';
  END IF;
  IF v_config IS DISTINCT FROM 'search_path=public, pg_temp' THEN
    RAISE EXCEPTION 'POS-CONDICAO: search_path virou % em vez de public, pg_temp', v_config;
  END IF;

  -- 4. CONTROLE: o acervo esta limpo AGORA, entao nenhum documento existente seria recusado por
  --    esta guarda em uma troca de rodada legitima. Se houvesse documento com cadeia aberta
  --    duplicada, este gate transformaria um defeito silencioso em bloqueio operacional.
  IF EXISTS (
    SELECT 1 FROM public.approval_chains
     WHERE status IN ('draft','review','approved')
     GROUP BY document_id HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'CONTROLE: ainda ha documento com 2+ cadeias abertas; corrija o acervo antes do gate';
  END IF;
END $$;
