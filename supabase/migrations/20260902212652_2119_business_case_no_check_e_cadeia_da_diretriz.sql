-- WHAT: `business_case` entra no CHECK de `governance_documents.doc_type` E ganha cadeia em
--       `resolve_default_gates`, na mesma migration. Um sem o outro e o defeito da #2119.
--
-- WHY:  a lane do CPMAI precisa registrar o business case do Grupo de Estudos e hoje usa
--       `governance_guideline` com o titulo desambiguando, porque nao havia tipo proprio. O tipo
--       existir resolve a leitura (filtro por doc_type volta a significar algo) sem mudar a
--       cadeia que ela ja exercita.
--
-- POR QUE OS DOIS PASSOS NA MESMA MIGRATION, E NAO SO O CHECK: ampliar o CHECK admite o valor e
--       NAO cria o caminho que ele percorre. Foi exatamente assim que `accession_term`,
--       `data_processing_agreement` e `declaration_template` ficaram admitidos e sem cadeia por
--       meses (#2119): cada um ja tinha documento na base, `resolve_default_gates` devolvia NULL,
--       a cadeia nunca se montava, e travava em silencio. O guard da #2119 hoje reprova essa
--       combinacao, entao um CHECK ampliado sozinho ficaria vermelho — e isso e o portao
--       funcionando, nao um obstaculo.
--
-- QUAL CADEIA, E POR DECISAO DE QUEM: identica a `governance_guideline` (curator threshold=all ->
--       leader_awareness threshold=0 -> submitter_acceptance threshold=1). Decisao do dono em
--       02/09/2026, com as tres candidatas medidas na frente (a do TAP com 2 portoes, a da
--       diretriz com 3, ou fora-do-fluxo com motivo). Escolheu a da diretriz: e a que a lane ja
--       vem exercitando, entao o tipo novo nao muda o comportamento de quem ja o usa na pratica.
--
-- SCOPE LOCK: os 14 ramos existentes de `resolve_default_gates` sao reproduzidos IDENTICOS, a
--       partir de `pg_get_functiondef` da funcao viva — nao transcritos de memoria nem de trecho.
--       A funcao e LANGUAGE sql, VOLATILE (default), NAO e SECURITY DEFINER, e tem
--       `SET search_path TO 'public','pg_temp'`: todos preservados, porque CREATE OR REPLACE que
--       omite atributo o resseta em silencio. A ACL tambem e preservada por CREATE OR REPLACE —
--       o que importa aqui porque a #2149 acabou de revogar PUBLIC e anon desta funcao, e um
--       DROP+CREATE reabriria tudo (CREATE FUNCTION nasce com EXECUTE para PUBLIC).
--
-- NOTA SOBRE O CONTROLE NEGATIVO, porque a primeira versao desta migration ABORTOU nele: o INSERT
--       de sonda so informava doc_type/title/status e bateu no NOT NULL de `organization_id` ANTES
--       de chegar ao CHECK. Ele teria capturado a excecao errada e se declarado satisfeito. As
--       cinco colunas NOT NULL sem default (doc_type, title, organization_id, visibility_class,
--       acknowledgement_mode) agora sao preenchidas a partir de uma linha existente, para a sonda
--       exercer o CHECK e nao a nulidade.
--
-- ROLLBACK: remover 'business_case' do CHECK (DROP+ADD) e o ramo WHEN correspondente.
--
-- CROSS-REF: #2119 (o guard que exige caminho OU motivo) · #2149 (a ACL que esta migration nao
--       pode reabrir) · #2136 (a lane do CPMAI)

-- 1. O CHECK. DROP + ADD com o nome EXPLICITO: `ADD CONSTRAINT` sem nome gera nome automatico e
--    a proxima migration nao acha a constraint pelo nome que espera.
ALTER TABLE public.governance_documents
  DROP CONSTRAINT governance_documents_doc_type_check;

ALTER TABLE public.governance_documents
  ADD CONSTRAINT governance_documents_doc_type_check CHECK (
    doc_type = ANY (ARRAY[
      'manual'::text,
      'cooperation_agreement'::text,
      'framework_reference'::text,
      'cooperation_addendum'::text,
      'volunteer_addendum'::text,
      'policy'::text,
      'volunteer_term_template'::text,
      'executive_summary'::text,
      'project_charter'::text,
      'editorial_guide'::text,
      'governance_guideline'::text,
      'declaration_template'::text,
      'accession_term'::text,
      'data_processing_agreement'::text,
      'assignment_term'::text,
      'business_case'::text
    ])
  );

-- 2. O CAMINHO. Os 14 ramos anteriores identicos, mais business_case com a cadeia da diretriz.
CREATE OR REPLACE FUNCTION public.resolve_default_gates(p_doc_type text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_doc_type
    WHEN 'cooperation_agreement' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'cooperation_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'volunteer_term_template' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'volunteer_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'policy' THEN '[
      {"kind":"committee_majority","order":1,"threshold":"majority"},
      {"kind":"president_go","order":2,"threshold":1},
      {"kind":"partner_consultation","order":3,"threshold":"window_optional","blocking":false,"window_business_days":15}
    ]'::jsonb
    WHEN 'editorial_guide' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'governance_guideline' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    -- business_case: mesma cadeia da diretriz, por decisao do dono em 02/09/2026. Deliberadamente
    -- escrita por extenso em vez de reaproveitar o ramo acima com fall-through: os dois tipos
    -- coincidem HOJE, e nada garante que coincidam depois. Compartilhar o literal faria uma
    -- mudanca na diretriz mexer no business case sem ninguem pedir.
    WHEN 'business_case' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'manual' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"president_others","order":5,"threshold":4}
    ]'::jsonb
    WHEN 'executive_summary' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"submitter_acceptance","order":2,"threshold":1}
    ]'::jsonb
    WHEN 'framework_reference' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'project_charter' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0}
    ]'::jsonb
    WHEN 'accession_term' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1}
    ]'::jsonb
    WHEN 'data_processing_agreement' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"president_go","order":2,"threshold":1}
    ]'::jsonb
    WHEN 'assignment_term' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"president_go","order":2,"threshold":1}
    ]'::jsonb
    ELSE NULL
  END;
$function$;


-- 3. POS-CONDICOES.
DO $$
DECLARE
  v_tipos      text[];
  v_sem_camin  text[];
  v_bc         jsonb;
  v_gg         jsonb;
  v_org        uuid;
  v_vis        text;
  v_ack        text;
  v_aceitou    boolean := false;
BEGIN
  v_tipos := public._audit_doc_type_check_values();

  -- 3a. O CHECK cresceu para 16 e business_case esta dentro.
  IF array_length(v_tipos, 1) <> 16 THEN
    RAISE EXCEPTION 'POS-CONDICAO: o CHECK admite % tipos, esperava 16', array_length(v_tipos, 1);
  END IF;
  IF NOT ('business_case' = ANY (v_tipos)) THEN
    RAISE EXCEPTION 'POS-CONDICAO: business_case nao entrou no CHECK';
  END IF;

  -- 3b. A invariante da #2119, medida sobre o CHECK INTEIRO e nao so sobre o tipo novo: todo tipo
  --     admitido tem cadeia OU motivo. Se esta migration tivesse quebrado o ramo de outro tipo ao
  --     reescrever a funcao, e AQUI que apareceria.
  SELECT array_agg(t) INTO v_sem_camin
  FROM unnest(v_tipos) AS t
  WHERE public.resolve_default_gates(t) IS NULL
    AND public.governance_doc_type_out_of_flow(t) IS NULL;
  IF v_sem_camin IS NOT NULL THEN
    RAISE EXCEPTION 'POS-CONDICAO: tipos sem cadeia e sem motivo: %', v_sem_camin;
  END IF;

  -- 3c. A cadeia do tipo novo e exatamente a que o dono escolheu.
  v_bc := public.resolve_default_gates('business_case');
  v_gg := public.resolve_default_gates('governance_guideline');
  IF v_bc IS DISTINCT FROM v_gg THEN
    RAISE EXCEPTION 'POS-CONDICAO: business_case=% difere de governance_guideline=%', v_bc, v_gg;
  END IF;
  IF jsonb_array_length(v_bc) <> 3 THEN
    RAISE EXCEPTION 'POS-CONDICAO: business_case tem % portoes, esperava 3', jsonb_array_length(v_bc);
  END IF;

  -- As colunas NOT NULL sem default, tiradas de uma linha real para a sonda exercer o CHECK e nao
  -- a nulidade. Foi aqui que a primeira tentativa desta migration abortou.
  SELECT organization_id, visibility_class, acknowledgement_mode
    INTO v_org, v_vis, v_ack
    FROM public.governance_documents
   WHERE organization_id IS NOT NULL LIMIT 1;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'CONTROLE: nao achei linha modelo para montar a sonda';
  END IF;

  -- 3d. CONTROLE NEGATIVO: o CHECK tem de continuar REJEITANDO tipo invalido.
  BEGIN
    INSERT INTO public.governance_documents
      (doc_type, title, status, organization_id, visibility_class, acknowledgement_mode)
    VALUES ('nao_existe_este_tipo', 'sonda negativa #2153', 'draft', v_org, v_vis, v_ack);
    RAISE EXCEPTION 'CONTROLE: o CHECK aceitou doc_type invalido — a constraint nao esta valendo';
  EXCEPTION
    WHEN check_violation THEN
      NULL;  -- esperado
  END;

  -- 3e. CONTROLE POSITIVO no mesmo caminho: o tipo NOVO tem de ser ACEITO. Sem este, 3d passaria
  --     mesmo se o CHECK rejeitasse tudo, business_case inclusive.
  BEGIN
    INSERT INTO public.governance_documents
      (doc_type, title, status, organization_id, visibility_class, acknowledgement_mode)
    VALUES ('business_case', 'sonda positiva #2153', 'draft', v_org, v_vis, v_ack);
    v_aceitou := true;
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'CONTROLE: o CHECK rejeitou business_case, que acabou de ser adicionado';
  END;
  IF NOT v_aceitou THEN
    RAISE EXCEPTION 'CONTROLE: o insert de business_case nao completou';
  END IF;

  -- A sonda positiva nao pode deixar residuo no acervo.
  DELETE FROM public.governance_documents WHERE title = 'sonda positiva #2153';
  IF EXISTS (SELECT 1 FROM public.governance_documents WHERE title LIKE 'sonda % #2153') THEN
    RAISE EXCEPTION 'CONTROLE: a sonda deixou residuo no acervo';
  END IF;
END $$;
