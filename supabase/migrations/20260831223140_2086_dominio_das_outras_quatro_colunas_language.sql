-- =====================================================================
-- #2086 continuacao — declarar dominio nas outras 4 colunas `language`
--
-- POR QUE ISTO EXISTE, e o motivo e mais interessante que o conserto.
--
-- A migration anterior (20260831220149) declarou CHECK em
-- `campaign_recipients.language`. Isso fez o ratchet do #1822 subir de 56 para 60,
-- e a causa NAO foi lacuna nova: foi o auditor passar a ENXERGAR lacuna antiga.
--
-- `_audit_undeclared_state_domain()` escolhe a populacao assim:
--
--     nomes AS (SELECT DISTINCT col FROM dominio)   -- nomes que tem dominio EM ALGUM LUGAR
--     ...
--     JOIN nomes k ON k.col = t.col                 -- e o join final e por NOME
--
-- Ou seja, ele so examina colunas cujo NOME ja tem dominio declarado em alguma
-- tabela. Ate ontem NENHUMA coluna `language` do schema tinha dominio, entao as 5
-- eram invisiveis ao guard. Declarar a primeira colocou o nome na lista e trouxe as
-- outras 4 para dentro da populacao de uma vez.
--
-- Nada piorou. O guard ficou mais sensivel, e o que ele revelou e real:
--
--   certificates.language ............ 173 linhas, todas 'pt-BR'   -- ja conforme
--   event_guest_certificates.language    1 linha,  'pt-BR'         -- ja conforme
--   knowledge_assets.language .......... 1 linha,  'pt-BR'         -- ja conforme
--   public_publications.language ....... 7 linhas, todas 'en'      -- SUBTAG NUA
--
-- A quarta carrega exatamente o defeito que a migration anterior consertou, num
-- quinto lugar. Fechar as quatro (decisao do PM, 31/08) resolve o ratchet e a
-- lacuna, em vez de subir a linha de base e congelar as duas.
--
-- MEDIDO IMEDIATAMENTE ANTES:
--   as 4 ja tem DEFAULT 'pt-BR'::text
--   event_guest_certificates e knowledge_assets ja sao NOT NULL
--   certificates e public_publications sao anulaveis, com 0 nulos
--   nulos nas 4 ............... 0 / 0 / 0 / 0
--   ancora das 7 linhas 'en' .. md5 dos ids = 89d82bd464e132b4d4ae439b1f9ec967
--
-- LEITORES CONFERIDOS antes de mexer no dado: 3 funcoes citam
-- `public_publications` e `language` (`admin_manage_publication`,
-- `get_public_publications`, `get_publication_detail`) e NENHUMA compara com o
-- literal 'en'. Nada em `src/` ou nas Edge Functions ramifica por essa coluna.
-- A troca e de rotulo, nao de comportamento.
--
-- Refs #2086, #1822.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. o dado: pelo MESMO helper canonico, nao por replace() de string.
--    O lado canonico PRODUZ o valor; a coluna so diz qual linha atualizar.
-- ---------------------------------------------------------------------
UPDATE public.public_publications
   SET language = public.normalize_platform_language(language)
 WHERE language IS DISTINCT FROM public.normalize_platform_language(language);

-- ---------------------------------------------------------------------
-- 2. NOT NULL nas duas anulaveis. As duas ja tem DEFAULT 'pt-BR' e 0 nulos.
--    Sem isto o CHECK ADMITE NULL, porque `NULL IN (...)` e NULL e CHECK so
--    reprova FALSE — o mesmo buraco que a migration anterior fechou.
-- ---------------------------------------------------------------------
ALTER TABLE public.certificates        ALTER COLUMN language SET NOT NULL;
ALTER TABLE public.public_publications ALTER COLUMN language SET NOT NULL;

-- ---------------------------------------------------------------------
-- 3. o dominio. Nome explicito no constraint: nome auto-gerado e engolido
--    pelo handler e nao da para derrubar depois.
--    A forma `IN (...)` e a que o auditor reconhece (`= ANY (ARRAY[`).
-- ---------------------------------------------------------------------
ALTER TABLE public.certificates
  DROP CONSTRAINT IF EXISTS certificates_language_platform_tag_check;
ALTER TABLE public.certificates
  ADD CONSTRAINT certificates_language_platform_tag_check
  CHECK (language IN ('pt-BR','en-US','es-LATAM'));

ALTER TABLE public.event_guest_certificates
  DROP CONSTRAINT IF EXISTS event_guest_certificates_language_platform_tag_check;
ALTER TABLE public.event_guest_certificates
  ADD CONSTRAINT event_guest_certificates_language_platform_tag_check
  CHECK (language IN ('pt-BR','en-US','es-LATAM'));

ALTER TABLE public.knowledge_assets
  DROP CONSTRAINT IF EXISTS knowledge_assets_language_platform_tag_check;
ALTER TABLE public.knowledge_assets
  ADD CONSTRAINT knowledge_assets_language_platform_tag_check
  CHECK (language IN ('pt-BR','en-US','es-LATAM'));

ALTER TABLE public.public_publications
  DROP CONSTRAINT IF EXISTS public_publications_language_platform_tag_check;
ALTER TABLE public.public_publications
  ADD CONSTRAINT public_publications_language_platform_tag_check
  CHECK (language IN ('pt-BR','en-US','es-LATAM'));

-- ---------------------------------------------------------------------
-- 4. POS-CONDICAO: o ratchet do #1822 tem de VOLTAR a 56.
--    Falhar alto aqui e melhor que descobrir no CI 13 minutos depois.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM public._audit_undeclared_state_domain()
   WHERE sem_dominio_declarado;
  IF v_n <> 56 THEN
    RAISE EXCEPTION 'pos-condicao falhou: ratchet #1822 esperava 56, veio %', v_n;
  END IF;

  -- e as 5 colunas `language` tem de estar TODAS declaradas agora
  SELECT count(*) INTO v_n
    FROM public._audit_undeclared_state_domain()
   WHERE coluna = 'language' AND sem_dominio_declarado;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'pos-condicao falhou: ainda ha % coluna(s) language sem dominio', v_n;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
