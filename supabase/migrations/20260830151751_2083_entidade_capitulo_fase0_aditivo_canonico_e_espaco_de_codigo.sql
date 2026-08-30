-- ADR-0127 passos 1 a 3 + ADR-0128 passos 1 e 2. TUDO ADITIVO.
-- Refs #2083, #2102, #2082. PR da doc: #2112.
--
-- INVARIANTE DESTE ARQUIVO: nenhuma coluna existente e reescrita, renomeada ou removida.
-- partner_chapters.chapter_code (forma de DISPLAY, PMI-XX) fica intocada: ela e lida por
-- members.chapter (juncao direta), por 4 funcoes do pipeline VEP e pelo _can_sign_gate.

-- ============ PASSO 1: colunas aditivas ============

-- ADR-0127 dec.5: cnpj vira identificador fiscal generico. A coluna antiga PERMANECE;
-- a retirada dela e passo posterior, depois que os leitores migrarem.
ALTER TABLE public.chapter_registry
  ADD COLUMN IF NOT EXISTS tax_id_type text,
  ADD COLUMN IF NOT EXISTS tax_id      text;

COMMENT ON COLUMN public.chapter_registry.tax_id_type IS
  'Tipo do identificador fiscal (CNPJ, CUIT, RUT, RFC, RUC, NIT, CIF). ADR-0127 dec.5.';
COMMENT ON COLUMN public.chapter_registry.tax_id IS
  'Identificador fiscal. Substitui cnpj, que permanece ate os leitores migrarem.';

-- Backfill dos 5 que ja tem cnpj. Nao inventa dado: so copia o que existe.
UPDATE public.chapter_registry
   SET tax_id_type = 'CNPJ', tax_id = cnpj
 WHERE cnpj IS NOT NULL AND tax_id IS NULL;

-- ADR-0127 dec.3: region migra de chapters para chapter_registry (significado SUBNACIONAL).
-- Fica nula aqui; o backfill e o passo 4, depois de provado o 3.
ALTER TABLE public.chapter_registry
  ADD COLUMN IF NOT EXISTS region text;
COMMENT ON COLUMN public.chapter_registry.region IS
  'Agrupamento SUBNACIONAL (Centro-Oeste, Nordeste...). NAO e o eixo do embaixador, que e
   entre paises e vira estrutura m2m propria (#2085). ADR-0127 dec.4.';

-- ADR-0128 dec.2: default_locale. E DEFAULT da jornada, nunca portao.
ALTER TABLE public.chapter_registry
  ADD COLUMN IF NOT EXISTS default_locale text NOT NULL DEFAULT 'pt-BR';
ALTER TABLE public.chapter_registry
  DROP CONSTRAINT IF EXISTS chapter_registry_default_locale_ck;
ALTER TABLE public.chapter_registry
  ADD CONSTRAINT chapter_registry_default_locale_ck
  CHECK (default_locale IN ('pt-BR','en-US','es-LATAM'));
COMMENT ON COLUMN public.chapter_registry.default_locale IS
  'Idioma inicial da jornada de quem entra por este capitulo. DEFAULT, nunca portao: o
   locale da pessoa e da pessoa. Travado nas 3 tags da plataforma. ADR-0128 dec.2.';

-- ADR-0128 dec.1: country deixa de ser inerte. Backfill gratuito (todas ja sao BR).
UPDATE public.chapter_registry SET country = 'BR' WHERE country IS NULL;
ALTER TABLE public.chapter_registry ALTER COLUMN country SET NOT NULL;

-- O espaco de codigo: capitulo nao brasileiro carrega o pais no codigo (AR-BUE, nunca BA).
ALTER TABLE public.chapter_registry
  DROP CONSTRAINT IF EXISTS chapter_registry_code_space_ck;
ALTER TABLE public.chapter_registry
  ADD CONSTRAINT chapter_registry_code_space_ck
  CHECK (country = 'BR' OR chapter_code LIKE country || '-%');
COMMENT ON CONSTRAINT chapter_registry_code_space_ck ON public.chapter_registry IS
  'ADR-0128 dec.1: BA e Bahia. Buenos Aires abrevia igual. Chave composta foi rejeitada
   (espalharia a ambiguidade para as 2 FKs); o pais restringe o ESPACO DE CODIGO.';

-- ADR-0127 dec.2: o tenant mora na PARTICIPACAO, nao no capitulo.
ALTER TABLE public.partner_chapters
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id);
COMMENT ON COLUMN public.partner_chapters.organization_id IS
  'O hub em que este capitulo participa. NAO vai em chapter_registry: dizer que o capitulo
   pertence ao hub e falso e nao sobrevive ao segundo hub. ADR-0127 dec.1 e dec.2.';

-- ============ PASSO 2: a coluna canonica, preenchida por JUNCAO ============

ALTER TABLE public.partner_chapters
  ADD COLUMN IF NOT EXISTS registry_chapter_code text;
COMMENT ON COLUMN public.partner_chapters.registry_chapter_code IS
  'Forma CANONICA do codigo (GO), alvo da FK. A coluna chapter_code guarda a forma de
   DISPLAY (PMI-GO) e fica intocada: members.chapter junta com ela, e 4 funcoes do
   pipeline VEP a leem. Renomear chapter_code para display_code e passo POSTERIOR.';

-- JUNCAO, nao substituicao. O valor gravado vem do REGISTRY, nao da string manipulada:
-- linha sem correspondencia fica NULL e a FK do passo 3 a denuncia, em vez de receber um
-- codigo fabricado que por acaso exista e grave o capitulo ERRADO em silencio.
-- O '^' ancora o prefixo no inicio (familia do DATA_ que contem ATA_).
UPDATE public.partner_chapters pc
   SET registry_chapter_code = cr.chapter_code
  FROM public.chapter_registry cr
 WHERE cr.chapter_code = regexp_replace(pc.chapter_code, '^PMI-', '')
   AND pc.registry_chapter_code IS DISTINCT FROM cr.chapter_code;

-- ============ PASSO 3: a FK, e ela so nasce se o passo 2 cobriu tudo ============
-- Se alguma linha ficou NULL, o NOT NULL abaixo FALHA a migration inteira. E o desejado:
-- melhor a migration reprovar alto do que a FK nascer sobre cobertura parcial.
ALTER TABLE public.partner_chapters ALTER COLUMN registry_chapter_code SET NOT NULL;
ALTER TABLE public.partner_chapters
  DROP CONSTRAINT IF EXISTS partner_chapters_registry_chapter_code_fkey;
ALTER TABLE public.partner_chapters
  ADD CONSTRAINT partner_chapters_registry_chapter_code_fkey
  FOREIGN KEY (registry_chapter_code) REFERENCES public.chapter_registry(chapter_code)
  ON DELETE RESTRICT;
