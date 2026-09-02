-- WHAT: (1) `assignment_term` entra no governance_documents_doc_type_check, que passa de 14 para
--       15 tipos; (2) resolve_default_gates ganha cadeia para accession_term,
--       data_processing_agreement e assignment_term, indo de 11 para 14 tipos cobertos;
--       (3) nasce `governance_doc_type_out_of_flow`, o mapa EXPLICITO de fora-do-fluxo com motivo
--       textual, para que `declaration_template` resolva NULL POR DESENHO e nao por omissao.
-- WHY:  ampliar o CHECK admite o valor e nao cria o caminho que ele percorre. Medido em
--       02/09/2026: o CHECK admitia 14 tipos e `resolve_default_gates` cobria 11. Os tres
--       descobertos (accession_term, data_processing_agreement, declaration_template) JA TINHAM
--       documento na base, um cada, e nenhum deles alcancava ratificacao: o resolvedor devolvia
--       NULL e a cadeia nunca se montava. Trava em silencio, que e o pior modo de travar.
--
-- AS TRES CADEIAS, decididas pelo dono e registradas na #2119 e na #2120 em 31/08:
--
--   accession_term (doc08): curator(all) > leader_awareness(0) > submitter_acceptance(1)
--                           > president_go(1)
--     Razao registrada: o instrumento existe para admitir capitulo SEM aditivo do Acordo (rito da
--     Cl. 14). Espelhar os 6 gates de cooperation_agreement, com chapter_witness(5) e
--     president_others(4), reintroduziria o peso que o "Simplificado" foi criado para evitar.
--
--   data_processing_agreement (doc09): curator(all) > president_go(1)
--     Razao registrada: visibility_class = legal_scoped, firmado entre PMI-GO controlador e a
--     plataforma operadora. Curadoria ampla e ciencia de lideres nao cabem em escopo legal restrito.
--
--   assignment_term (doc10): curator(all) > president_go(1)
--     Mesma regua do DPA, por decisao explicita do dono. Nome CONFIRMADO por ele em 31/08, e o
--     nome importa porque tipo em CHECK e caro de trocar depois (DROP + ADD mais as linhas).
--
-- DECLARATION_TEMPLATE FICA FORA DO FLUXO, POR DESENHO E POR ESCRITO. Hoje ele resolve NULL por
--       OMISSAO, e a decisao e que passe a resolver NULL por DESENHO. A diferenca tem de aparecer
--       em lugar que o guard leia, senao as duas situacoes seguem indistinguiveis, que e o defeito
--       original da #2119. Fundamento do proprio instrumento: ato unilateral cuja eficacia, pela
--       Clausula 5.1 dele mesmo, decorre do protocolo e do arquivamento, "independentemente de
--       homologacao de merito".
--       Mecanismo: `governance_doc_type_out_of_flow` devolve o MOTIVO textual, ou NULL para tipo
--       que deve ter cadeia. Assim o guard derivado do CHECK exige que cada tipo OU resolva gates
--       OU conste do mapa com motivo. Tipo que nao esteja em nenhum dos dois reprova.
--
-- OS 11 RAMOS EXISTENTES NAO PODEM MUDAR, e a migration NAO confia na minha transcricao: a
--       pos-condicao compara o hash da cadeia resolvida de cada um dos 11 contra o valor medido
--       imediatamente antes de aplicar. Qualquer divergencia aborta a transacao inteira.
--       Sao 6 cadeias distintas entre os 11 tipos (agreement e addendum coincidem, assim como
--       editorial/framework/governance e term_template/volunteer_addendum).
--
-- INVARIANTE DE GOVERNANCA (p35) PRESERVADA: nas tres cadeias novas o `curator` e o gate de ordem
--       1 com threshold "all". A unica excecao viva no acervo continua sendo `policy`, que abre
--       com committee_majority, e foi ela que quebrou os asserts do #1340.
--
-- SCOPE LOCK: a criacao do documento de Termo de Cessao em si NAO entra aqui e continua esperando
--       o texto voltar do juridico (#2120). Nenhuma policy de RLS e tocada. Nenhum documento
--       existente muda de doc_type.
-- ROLLBACK: restaurar o CHECK de 14 tipos, o corpo anterior de resolve_default_gates, e
--       DROP FUNCTION public.governance_doc_type_out_of_flow(text).
-- CROSS-REF: #2119 · #2120 · #632 (o pacote revisado) · p35 (a invariante do curator)

-- 1. O mapa explicito de fora-do-fluxo, com motivo.
CREATE OR REPLACE FUNCTION public.governance_doc_type_out_of_flow(p_doc_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $fn$
  SELECT CASE p_doc_type
    WHEN 'declaration_template' THEN
      'Ato unilateral. Pela Clausula 5.1 do proprio instrumento, a eficacia decorre do protocolo e '
      'do arquivamento, independentemente de homologacao de merito. Decisao do dono registrada na '
      '#2119 em 31/08/2026: fica fora do fluxo de ratificacao POR DESENHO, e nao por omissao.'
    ELSE NULL
  END;
$fn$;

REVOKE ALL ON FUNCTION public.governance_doc_type_out_of_flow(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.governance_doc_type_out_of_flow(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.governance_doc_type_out_of_flow(text) IS
  'Devolve o MOTIVO textual de um doc_type ficar fora do fluxo de ratificacao, ou NULL quando o tipo deve ter cadeia em resolve_default_gates. Existe para separar "sem cadeia por desenho" de "sem cadeia por lacuna": antes da #2119 as duas situacoes eram o mesmo NULL e o guard nao as distinguia.';

-- 2. O CHECK admite o 15o tipo. DROP + ADD porque ALTER de CHECK nao existe.
ALTER TABLE public.governance_documents
  DROP CONSTRAINT IF EXISTS governance_documents_doc_type_check;
ALTER TABLE public.governance_documents
  ADD CONSTRAINT governance_documents_doc_type_check
  CHECK (doc_type = ANY (ARRAY[
    'manual'::text, 'cooperation_agreement'::text, 'framework_reference'::text,
    'cooperation_addendum'::text, 'volunteer_addendum'::text, 'policy'::text,
    'volunteer_term_template'::text, 'executive_summary'::text, 'project_charter'::text,
    'editorial_guide'::text, 'governance_guideline'::text, 'declaration_template'::text,
    'accession_term'::text, 'data_processing_agreement'::text, 'assignment_term'::text
  ]));

-- 3. O resolvedor: 11 ramos preservados, 3 acrescentados.
CREATE OR REPLACE FUNCTION public.resolve_default_gates(p_doc_type text)
RETURNS jsonb
LANGUAGE sql
SET search_path TO 'public', 'pg_temp'
AS $fn$
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
$fn$;

-- NAO ha REVOKE em resolve_default_gates de proposito. Ela e funcao EXISTENTE e hoje concede
-- EXECUTE a anon e a PUBLIC. `CREATE OR REPLACE` preserva ACL, entao ela continua como estava.
-- Apertar permissao de funcao viva e mudanca de comportamento em producao que esta issue nao
-- pediu, e apertar de carona numa entrega de outra coisa e como as surpresas nascem. Fica
-- registrado como superficie para decisao propria: a funcao devolve template de portao, sem PII.
-- As DUAS funcoes NOVAS acima nascem fechadas, porque CREATE FUNCTION nasce aberto para PUBLIC.

-- 3b. O leitor do CHECK, para o guard poder DERIVAR o denominador em vez de repetir uma lista.
-- Sem ele o teste teria de manter os 15 nomes a mao, que e exatamente o defeito da #2119.
CREATE OR REPLACE FUNCTION public._audit_doc_type_check_values()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $fn$
  SELECT array_agg(replace(replace(x, '''::text', ''), '''', '') ORDER BY 1)
  FROM unnest(string_to_array(
    regexp_replace(
      (SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conname = 'governance_documents_doc_type_check'),
      '.*ARRAY\[(.*)\].*', '\1'), ', ')) AS x;
$fn$;

REVOKE ALL ON FUNCTION public._audit_doc_type_check_values() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._audit_doc_type_check_values() TO authenticated, service_role;

COMMENT ON FUNCTION public._audit_doc_type_check_values() IS
  'Devolve os doc_type admitidos pelo governance_documents_doc_type_check. Existe para o guard da #2119 DERIVAR o denominador do proprio CHECK: guard que repete a lista de nomes nao cresce quando o CHECK cresce, e foi assim que 3 tipos ficaram admitidos e sem cadeia.';

-- 4. Pos-condicoes. A primeira e a que importa: os 11 ramos existentes NAO podem ter mudado, e a
--    verificacao nao confia na transcricao, compara o hash da cadeia RESOLVIDA contra o valor
--    medido imediatamente antes de aplicar (02/09/2026).
DO $mig$
DECLARE
  v_esperado CONSTANT jsonb := '{
    "cooperation_agreement":    "a5d2863a7bccb651829163d431d50dab",
    "cooperation_addendum":     "a5d2863a7bccb651829163d431d50dab",
    "volunteer_term_template":  "afc6c193ce7760100192bffc1a131a1f",
    "volunteer_addendum":       "afc6c193ce7760100192bffc1a131a1f",
    "policy":                   "49fd64356723b821506d5d53004ca417",
    "editorial_guide":          "dd21516b223ae5a0eea4e695c35fb447",
    "governance_guideline":     "dd21516b223ae5a0eea4e695c35fb447",
    "framework_reference":      "dd21516b223ae5a0eea4e695c35fb447",
    "manual":                   "55a619dcae7deff7c9a6dfdf38550ff8",
    "executive_summary":        "5c0d71741c9248e2210f28a25fbe0d07",
    "project_charter":          "900699241236a64a018ae601584096c7"
  }'::jsonb;
  r record; v_atual text; v_n int; v_tipos text[]; v_sem_nada text[];
BEGIN
  -- POS 1: nenhum dos 11 mudou de cadeia.
  FOR r IN SELECT key AS doc_type, value #>> '{}' AS hash FROM jsonb_each(v_esperado) LOOP
    v_atual := md5(public.resolve_default_gates(r.doc_type)::text);
    IF v_atual IS DISTINCT FROM r.hash THEN
      RAISE EXCEPTION 'ramo existente MUDOU: % passou de % para % (erro de transcricao)',
        r.doc_type, r.hash, v_atual;
    END IF;
  END LOOP;

  -- POS 2: os tres tipos novos resolvem, e o curator abre com "all" (invariante p35).
  FOREACH v_atual IN ARRAY ARRAY['accession_term','data_processing_agreement','assignment_term'] LOOP
    IF public.resolve_default_gates(v_atual) IS NULL THEN
      RAISE EXCEPTION '% continua sem cadeia', v_atual;
    END IF;
    IF (public.resolve_default_gates(v_atual) -> 0 ->> 'kind') <> 'curator'
       OR (public.resolve_default_gates(v_atual) -> 0 ->> 'threshold') <> 'all' THEN
      RAISE EXCEPTION '% nao abre com curator(all): invariante do p35 quebrada', v_atual;
    END IF;
  END LOOP;

  -- POS 3: o CHECK admite os 15, e assignment_term entre eles.
  SELECT array_agg(replace(replace(x, '''::text', ''), '''', '')) INTO v_tipos
  FROM unnest(string_to_array(
    regexp_replace((SELECT pg_get_constraintdef(oid) FROM pg_constraint
                     WHERE conname='governance_documents_doc_type_check'),
                   '.*ARRAY\[(.*)\].*', '\1'), ', ')) AS x;
  IF array_length(v_tipos,1) <> 15 THEN
    RAISE EXCEPTION 'o CHECK admite % tipos, esperava 15', array_length(v_tipos,1);
  END IF;
  IF NOT ('assignment_term' = ANY(v_tipos)) THEN
    RAISE EXCEPTION 'assignment_term nao entrou no CHECK';
  END IF;

  -- POS 4: A REGRA QUE ESTA ISSUE EXISTE PARA CRIAR. Todo tipo admitido pelo CHECK ou resolve
  -- cadeia, ou consta do mapa de fora-do-fluxo com motivo. Nenhum pode ficar em nenhum dos dois.
  SELECT array_agg(t) INTO v_sem_nada FROM unnest(v_tipos) AS t
   WHERE public.resolve_default_gates(t) IS NULL
     AND public.governance_doc_type_out_of_flow(t) IS NULL;
  IF v_sem_nada IS NOT NULL THEN
    RAISE EXCEPTION '% tipo(s) admitidos pelo CHECK sem cadeia E sem motivo de fora-do-fluxo: %',
      array_length(v_sem_nada,1), array_to_string(v_sem_nada, ', ');
  END IF;

  -- POS 5: e o fora-do-fluxo nao pode ser vago. Motivo curto e desculpa, nao razao.
  IF length(public.governance_doc_type_out_of_flow('declaration_template')) < 80 THEN
    RAISE EXCEPTION 'o motivo de fora-do-fluxo esta curto demais para ser auditavel';
  END IF;

  SELECT count(*) INTO v_n FROM unnest(v_tipos) AS t
   WHERE public.resolve_default_gates(t) IS NOT NULL;
  RAISE NOTICE 'CHECK com % tipos; % com cadeia; 1 fora do fluxo por desenho',
    array_length(v_tipos,1), v_n;
END $mig$;

NOTIFY pgrst, 'reload schema';
