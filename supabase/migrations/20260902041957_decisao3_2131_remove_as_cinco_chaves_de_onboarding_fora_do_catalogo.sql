-- WHAT: remove de `onboarding_progress` as cinco chaves de etapa que nao existem no catalogo
--       `onboarding_steps`: accept_terms, join_whatsapp, kick_off, platform_access, profile_complete.
-- WHY:  decisao 3 da #2131, tomada pelo dono em 02/09/2026. As 145 linhas dessas cinco chaves tem
--       ZERO conclusoes em toda a historia, desde 26/06. Nao sao etapas que as pessoas deixam de
--       fazer: nunca tiveram caminho de escrita. Como estao fora do catalogo, nao aparecem na
--       trilha e nao cobram nada de ninguem. O unico efeito mensuravel e fazer quem ja cumpriu
--       parecer incompleto, que e o sintoma do "6 de 12" da #1875.
-- A CONDICAO QUE O DONO POS foi "o importante e que ao eles fazerem, o gate ficar verde", e ela ja
--       esta satisfeita pela chave viva, e nao so para o perfil. Cobertura das 29 pessoas:
--         profile_complete -> complete_profile   29/29 tem, 26 concluiram
--         accept_terms     -> volunteer_term     29/29 tem, 27 concluiram
--         kick_off         -> first_meeting      29/29 tem, 21 concluiram
--         platform_access  -> sem contraparte, e nao precisa (a pessoa esta na plataforma)
--         join_whatsapp    -> sem contraparte hoje; o gancho do grupo e a decisao 4, nao esta chave
-- POR QUE APAGAR E SEGURO, MEDIDO EM 02/09/2026 ANTES DE APLICAR:
--         FKs apontando para onboarding_progress ......... nenhuma
--         triggers que disparam em DELETE ................ nenhum (os 3 sao INSERT/UPDATE)
--         linhas com evidence_url, notes ou metadata ..... 0  (nao se perde dado)
--         conclusoes em toda a historia .................. 0
--       E o trigger de marco (_trg_record_onboarding_complete_milestone) so avalia etapas do
--       CATALOGO, entao estas cinco ja eram invisiveis para ele: apagar nao cria nem destroi marco.
--       A pos-condicao abaixo verifica isso em vez de confiar na leitura.
-- ACAO RESIDUAL, QUE E COBRANCA E NAO ESQUEMA: das 29, tres ainda nao concluiram `complete_profile`.
--       Essas sao as pessoas que de fato precisam atualizar o perfil.
-- SE VOLTAR: `join_whatsapp` volta pelo CATALOGO, com label_pt e step_order, como etapa de verdade.
-- ESTADO ANTES (medido 02/09/2026, imediatamente antes de aplicar):
--         chaves fora do catalogo .... 5        linhas dessas chaves ..... 145
--         onboarding_progress ........ 935      pessoas afetadas ......... 29
--         marcos onboarding_complete . 15       destas 29, com marco ..... 1
-- ESTADO DEPOIS (o que este arquivo torna verdadeiro):
--         chaves fora do catalogo .... 0        onboarding_progress ...... 790
--         marcos onboarding_complete . 15 (INALTERADO, e a pos-condicao afirma isso)
-- LEITOR FUTURO: as duas linhas acima sao DATADAS. Cabecalho de migration descreve o mundo de ANTES
--       dela, e quem le meses depois le como se fosse o de agora.
-- ROLLBACK: nao ha. As linhas nao carregam dado (evidence/notes/metadata vazios) e nunca foram
--       concluidas, entao recria-las seria recriar o defeito. Se alguma chave precisar existir,
--       ela entra pelo catalogo.
-- NOTA DE SINTAXE: o bloco usa um delimitador NOMEADO em vez do generico de dois cifroes. Dentro de
--       texto dollar-quoted nao existe comentario: `--` e so texto, e o lexer procura o delimitador
--       de fechamento inclusive dentro dele. Um comentario que CITA o delimitador ao descrever um
--       bloco termina o bloco. Custou uma reprovacao em 02/09, e esta propria nota foi reescrita
--       para nao citar o delimitador que ela recomenda.
-- CROSS-REF: #2131 (decisao 3) · #1875 (o "6 de 12") · #2136

DO $mig$
DECLARE
  v_esperadas text[] := ARRAY['accept_terms','join_whatsapp','kick_off','platform_access','profile_complete'];
  v_chaves int; v_linhas int; v_concl int; v_dado int; v_total_antes int; v_marcos_antes int;
  v_total_depois int; v_marcos_depois int; v_apagadas int;
BEGIN
  -- PRE 1: as chaves fora do catalogo sao EXATAMENTE as cinco esperadas. Se aparecer uma sexta,
  -- alguem introduziu outra chave orfa e isto merece decisao humana, nao um DELETE silencioso.
  SELECT count(DISTINCT p.step_key) INTO v_chaves
    FROM public.onboarding_progress p
    LEFT JOIN public.onboarding_steps s ON s.id = p.step_key
   WHERE s.id IS NULL AND NOT (p.step_key = ANY(v_esperadas));
  IF v_chaves <> 0 THEN
    RAISE EXCEPTION 'ha % chave(s) fora do catalogo alem das cinco decididas: pare e decida', v_chaves;
  END IF;

  -- PRE 2: nenhuma delas foi concluida alguma vez. E o fato que sustenta a decisao inteira.
  SELECT count(*) INTO v_concl
    FROM public.onboarding_progress p
    LEFT JOIN public.onboarding_steps s ON s.id = p.step_key
   WHERE s.id IS NULL AND (p.status = 'completed' OR p.completed_at IS NOT NULL);
  IF v_concl <> 0 THEN
    RAISE EXCEPTION '% linha(s) fantasma constam como concluidas: a premissa mudou', v_concl;
  END IF;

  -- PRE 3: nao ha dado que se perca.
  SELECT count(*) INTO v_dado
    FROM public.onboarding_progress p
    LEFT JOIN public.onboarding_steps s ON s.id = p.step_key
   WHERE s.id IS NULL
     AND (p.evidence_url IS NOT NULL OR p.notes IS NOT NULL
          OR (p.metadata IS NOT NULL AND p.metadata::text NOT IN ('{}','null')));
  IF v_dado <> 0 THEN
    RAISE EXCEPTION '% linha(s) fantasma carregam evidencia, nota ou metadata: nao apagar as cegas', v_dado;
  END IF;

  SELECT count(*) INTO v_linhas
    FROM public.onboarding_progress p
    LEFT JOIN public.onboarding_steps s ON s.id = p.step_key WHERE s.id IS NULL;
  SELECT count(*) INTO v_total_antes FROM public.onboarding_progress;
  SELECT count(*) INTO v_marcos_antes FROM public.member_milestones WHERE milestone_key = 'onboarding_complete';

  -- IDEMPOTENCIA: se nao ha linha fantasma, esta migration ja rodou.
  IF v_linhas = 0 THEN
    RAISE NOTICE 'nenhuma chave fantasma: nada a fazer (total=%)', v_total_antes;
    RETURN;
  END IF;

  DELETE FROM public.onboarding_progress p
   USING (SELECT p2.id FROM public.onboarding_progress p2
            LEFT JOIN public.onboarding_steps s ON s.id = p2.step_key
           WHERE s.id IS NULL) alvo
   WHERE p.id = alvo.id;
  GET DIAGNOSTICS v_apagadas = ROW_COUNT;
  IF v_apagadas <> v_linhas THEN
    RAISE EXCEPTION 'apaguei % linhas, esperava %', v_apagadas, v_linhas;
  END IF;

  -- POS 1: nao sobrou chave fora do catalogo.
  SELECT count(*) INTO v_chaves
    FROM public.onboarding_progress p
    LEFT JOIN public.onboarding_steps s ON s.id = p.step_key WHERE s.id IS NULL;
  IF v_chaves <> 0 THEN RAISE EXCEPTION 'sobraram % linhas fora do catalogo', v_chaves; END IF;

  -- POS 2: a aritmetica fecha. Protege contra apagar mais do que o alvo.
  SELECT count(*) INTO v_total_depois FROM public.onboarding_progress;
  IF v_total_depois <> v_total_antes - v_linhas THEN
    RAISE EXCEPTION 'total foi de % para %, esperava %', v_total_antes, v_total_depois, v_total_antes - v_linhas;
  END IF;

  -- POS 3: nenhum marco foi criado nem destruido. O trigger de marco so avalia etapas do catalogo,
  -- entao estas cinco ja eram invisiveis para ele. Esta linha VERIFICA a leitura em vez de confiar.
  SELECT count(*) INTO v_marcos_depois FROM public.member_milestones WHERE milestone_key = 'onboarding_complete';
  IF v_marcos_depois <> v_marcos_antes THEN
    RAISE EXCEPTION 'marcos onboarding_complete mudaram de % para %: efeito colateral nao previsto',
      v_marcos_antes, v_marcos_depois;
  END IF;

  RAISE NOTICE 'apagadas % linhas de % chaves. total % -> %. marcos inalterados em %.',
    v_apagadas, array_length(v_esperadas,1), v_total_antes, v_total_depois, v_marcos_depois;
END $mig$;
