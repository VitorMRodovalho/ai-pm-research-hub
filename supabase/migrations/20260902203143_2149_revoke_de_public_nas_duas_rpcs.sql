-- WHAT: `get_comms_to_adoption_funnel(integer)` e `resolve_default_gates(text)` deixam de conceder
--       EXECUTE a PUBLIC e a anon. Nenhum corpo muda: so a ACL.
--
-- WHY:  medido em 02/09/2026, com controle positivo na mesma consulta:
--
--         funcao                                anon_exec ANTES
--         get_comms_to_adoption_funnel(int) ...  TRUE
--         resolve_default_gates(text) .........  TRUE
--         controle: das 1312 funcoes de public, 687 tem anon_exec = FALSE
--
--       O controle importa porque sem ele "TRUE" nao se distingue de uma consulta que devolve TRUE
--       para tudo. 687 negativos provam que a coluna discrimina.
--
-- O DEFEITO DE ORIGEM, E POR QUE ELE SOBREVIVEU UM MES: a migration 20260805000331 (#883 Onda A)
--       escreveu `REVOKE EXECUTE ... FROM anon` e o guard afirmava que ESSA LINHA EXISTIA NO
--       ARQUIVO. Existia. E era inutil: a ACL viva e `=X/postgres`, ou seja PUBLIC mantem EXECUTE,
--       e anon herda de PUBLIC. Revogar de anon nao tira o que PUBLIC concede. O guard media a
--       PRESENCA DE UMA LINHA, nao o EFEITO dela, e um guard assim fica verde sobre uma falsidade.
--
-- AS DUAS PEDEM REMEDIOS DIFERENTES, e e por isso que isto nao e um one-liner:
--       - get_comms_to_adoption_funnel so herda de PUBLIC  -> REVOKE FROM PUBLIC basta.
--       - resolve_default_gates tem GRANT EXPLICITO a anon (`anon=X/postgres`) ALEM do PUBLIC
--         -> REVOKE FROM PUBLIC sozinho NAO FECHARIA NADA. Precisa nomear anon tambem.
--       Aplicar so `FROM PUBLIC` nas duas teria fechado uma e deixado a outra aberta, com a
--       migration parecendo simetrica. A assimetria e do estado, nao do texto.
--
-- NAO HA VAZAMENTO HOJE, e o aperto nao e correcao de incidente: get_comms_to_adoption_funnel e
--       fail-closed no corpo (auth.uid() NULL -> Unauthorized ANTES de tocar em dado) e
--       resolve_default_gates devolve template de portao, sem PII. O que se conserta e a
--       SUPERFICIE: permissao contradizendo intencao declarada, com guard verde por cima.
--
-- QUEM CHAMA, medido antes de apertar:
--       - tela: src/pages/admin/comms.astro:937 e
--         src/components/governance/DocumentVersionEditor.tsx:115, ambas como authenticated.
--       - SQL: preview_gate_eligibles, _refresh_preview_gate_eligibles_for_member e
--         _audit_preview_gate_eligibles_drift chamam resolve_default_gates, e as tres sao
--         SECURITY DEFINER: rodam com privilegio do owner, entao a ACL do chamador nao as alcanca.
--       - testes: chamam por REST com SUPABASE_SERVICE_ROLE_KEY, e service_role segue com grant
--         explicito abaixo.
--       Nenhum caminho legitimo depende do privilegio que sai.
--
-- SCOPE LOCK: nenhuma funcao e recriada. Corpo, assinatura, volatilidade, SECURITY DEFINER e
--       search_path ficam intocados, porque REVOKE/GRANT nao os alcanca.
--
-- ROLLBACK: GRANT EXECUTE ON FUNCTION <fn> TO PUBLIC;  (e a anon, para resolve_default_gates)
--
-- CROSS-REF: #2149 · #883 (a Onda A que escreveu o REVOKE inocuo) · #2142 (o guard que parou de
--       mentir e registrou que faltava esta mudanca) · #2119 (resolve_default_gates ganhou os tres
--       ramos que faltavam, e ali ficou registrado que apertar ACL de carona seria errado)

-- 1. A que so herda de PUBLIC.
REVOKE ALL ON FUNCTION public.get_comms_to_adoption_funnel(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_comms_to_adoption_funnel(integer) TO authenticated, service_role;

-- 2. A que tem grant explicito a anon. Nomear anon aqui e o ponto todo da migration.
REVOKE ALL ON FUNCTION public.resolve_default_gates(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_default_gates(text) TO authenticated, service_role;

-- 3. POS-CONDICOES. Falham a migration inteira, e a ultima e um controle que TEM COMO reprovar.
DO $$
DECLARE
  v_funil_anon   boolean;
  v_gates_anon   boolean;
  v_funil_auth   boolean;
  v_gates_auth   boolean;
  v_funil_svc    boolean;
  v_gates_svc    boolean;
  v_controle     boolean;
BEGIN
  SELECT has_function_privilege('anon',          'public.get_comms_to_adoption_funnel(integer)', 'EXECUTE'),
         has_function_privilege('anon',          'public.resolve_default_gates(text)',           'EXECUTE'),
         has_function_privilege('authenticated', 'public.get_comms_to_adoption_funnel(integer)', 'EXECUTE'),
         has_function_privilege('authenticated', 'public.resolve_default_gates(text)',           'EXECUTE'),
         has_function_privilege('service_role',  'public.get_comms_to_adoption_funnel(integer)', 'EXECUTE'),
         has_function_privilege('service_role',  'public.resolve_default_gates(text)',           'EXECUTE')
    INTO v_funil_anon, v_gates_anon, v_funil_auth, v_gates_auth, v_funil_svc, v_gates_svc;

  -- 3a. O efeito pretendido: anon perdeu as duas.
  IF v_funil_anon THEN
    RAISE EXCEPTION 'POS-CONDICAO: anon ainda executa get_comms_to_adoption_funnel';
  END IF;
  IF v_gates_anon THEN
    RAISE EXCEPTION 'POS-CONDICAO: anon ainda executa resolve_default_gates (o grant explicito sobreviveu?)';
  END IF;

  -- 3b. E o que NAO podia sair continua entrando. Um REVOKE que fecha demais quebra a tela de
  --     admin e o CI, e o modo de falha seria "nada aparece", que demora a ser lido como permissao.
  IF NOT (v_funil_auth AND v_gates_auth) THEN
    RAISE EXCEPTION 'POS-CONDICAO: authenticated perdeu EXECUTE (funil=%, gates=%)', v_funil_auth, v_gates_auth;
  END IF;
  IF NOT (v_funil_svc AND v_gates_svc) THEN
    RAISE EXCEPTION 'POS-CONDICAO: service_role perdeu EXECUTE (funil=%, gates=%)', v_funil_svc, v_gates_svc;
  END IF;

  -- 3c. CONTROLE POSITIVO. Se has_function_privilege devolvesse FALSE para tudo, os testes 3a
  --     passariam por vacuidade e esta migration se declararia vitoriosa sem ter feito nada.
  --     _audit_list_public_function_bodies() e sabidamente ABERTA a anon (medido em 02/09), e tem
  --     de continuar assim: ela nao esta no escopo desta mudanca.
  SELECT has_function_privilege('anon', 'public._audit_list_public_function_bodies()', 'EXECUTE')
    INTO v_controle;
  IF NOT v_controle THEN
    RAISE EXCEPTION 'CONTROLE: a sonda nao discrimina (ou esta migration revogou fora do escopo)';
  END IF;
END $$;
