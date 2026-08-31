-- ADR-0127 passo 4 (parcial): preenche `region` dos 15 capitulos BRASILEIROS.
-- Refs #2083, #2085.
--
-- DECISAO DO PM (30/08): o Brasil e o pais-sede original do projeto e fica COM as regioes
-- preenchidas, porque ajuda agrupamento de dado. A subdivisao do PMI LATAM (Caribe, Norte
-- LATAM etc.) NAO entra aqui: e outra CAMADA, de regiao entre paises, e vive na estrutura
-- muitos-para-muitos da #2085. Esta coluna e, e continua sendo, agrupamento DENTRO de um pais
-- (ADR-0127 decisao 4).
--
-- POR ISSO o CHECK abaixo so restringe country='BR'. Capitulo nao brasileiro fica com region
-- NULL ate existir taxonomia do pais dele, e nao herda a taxonomia do IBGE por acidente.
--
-- O MAPEAMENTO NAO E AFIRMADO, E CONFERIDO: a tabela `chapters` ja carrega a regiao de 5
-- capitulos, e o bloco de assercao aborta a migration se o meu mapa discordar de qualquer um
-- deles. Os 5 cobrem 4 das 5 macrorregioes (Nordeste, Centro-Oeste, Sudeste, Sul), entao o
-- controle DISCRIMINA nessas quatro.
--
-- O QUE O CONTROLE NAO COBRIA, e como foi resolvido: `Norte` nao aparece nos 5 conhecidos, entao
-- AM -> Norte era a UNICA das 15 linhas sem corroboracao no dado. Foi levada ao PM e RATIFICADA
-- por ele em 30/08/2026. A fonte desta linha e decisao humana, nao inferencia a partir do nome do
-- estado. Registrado aqui porque `chapter_registry.state` do AM diz "Amazonia", que nao e nome de
-- unidade federativa, enquanto as outras 14 dizem o nome do estado: quem reler isso daqui a um ano
-- vai estranhar a linha, e a resposta e esta.

DO $mig$
DECLARE
  v_divergencias int;
  v_preenchidos  int;
BEGIN
  -- (1) ASSERCAO: o mapa proposto tem de concordar com os 5 que a tabela `chapters` ja conhece.
  SELECT count(*) INTO v_divergencias
    FROM chapters c
    JOIN (VALUES
      ('AM','Norte'),        ('BA','Nordeste'),     ('CE','Nordeste'),
      ('DF','Centro-Oeste'), ('ES','Sudeste'),      ('GO','Centro-Oeste'),
      ('MG','Sudeste'),      ('PB','Nordeste'),     ('PE','Nordeste'),
      ('PR','Sul'),          ('RJ','Sudeste'),      ('RS','Sul'),
      ('SC','Sul'),          ('SE','Nordeste'),     ('SP','Sudeste')
    ) AS m(code, region) ON m.code = c.code
   WHERE c.region IS NOT NULL AND c.region IS DISTINCT FROM m.region;

  IF v_divergencias > 0 THEN
    RAISE EXCEPTION 'o mapa proposto discorda de % linha(s) que a tabela chapters ja conhece', v_divergencias;
  END IF;

  -- (2) o backfill, so para BR e so onde ainda esta nulo
  UPDATE chapter_registry cr
     SET region = m.region
    FROM (VALUES
      ('AM','Norte'),        ('BA','Nordeste'),     ('CE','Nordeste'),
      ('DF','Centro-Oeste'), ('ES','Sudeste'),      ('GO','Centro-Oeste'),
      ('MG','Sudeste'),      ('PB','Nordeste'),     ('PE','Nordeste'),
      ('PR','Sul'),          ('RJ','Sudeste'),      ('RS','Sul'),
      ('SC','Sul'),          ('SE','Nordeste'),     ('SP','Sudeste')
    ) AS m(code, region)
   WHERE cr.chapter_code = m.code
     AND cr.country = 'BR'
     AND cr.region IS NULL;

  -- (3) POS-CONDICAO: os 15 brasileiros preenchidos, nenhum sobrando
  SELECT count(*) INTO v_preenchidos
    FROM chapter_registry WHERE country='BR' AND region IS NOT NULL;
  IF v_preenchidos <> (SELECT count(*) FROM chapter_registry WHERE country='BR') THEN
    RAISE EXCEPTION 'pos-condicao falhou: % de % brasileiros com region',
      v_preenchidos, (SELECT count(*) FROM chapter_registry WHERE country='BR');
  END IF;
END
$mig$;

-- (4) CHECK: so restringe o Brasil, pelo motivo do cabecalho.
ALTER TABLE public.chapter_registry DROP CONSTRAINT IF EXISTS chapter_registry_region_br_ck;
ALTER TABLE public.chapter_registry
  ADD CONSTRAINT chapter_registry_region_br_ck
  CHECK (country <> 'BR' OR region IS NULL
         OR region IN ('Norte','Nordeste','Centro-Oeste','Sudeste','Sul'));
COMMENT ON COLUMN public.chapter_registry.region IS
  'Agrupamento SUBNACIONAL. Para BR sao as 5 macrorregioes do IBGE. NAO e o eixo do
   embaixador nem regiao continental: agrupamento ENTRE paises (Caribe, Norte LATAM, Cone Sul)
   e OUTRA CAMADA e vive na estrutura m2m da #2085. ADR-0127 decisao 4.';
