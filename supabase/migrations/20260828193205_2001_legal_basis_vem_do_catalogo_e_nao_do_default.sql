-- #2001 — `engagements.legal_basis` passa a vir do CATALOGO, e o backfill segue a mesma regra.
--
-- A coluna e a base legal LGPD Art. 7 do vinculo. O catalogo `engagement_kinds.legal_basis` declara
-- a base canonica de cada kind, e nada comparava os dois. Medido em 28/08/2026: de 293 engajamentos,
-- **134 divergiam** do catalogo (106 deles ativos).
--
-- ── Tres pontas de escrita erravam, nao duas ─────────────────────────────────────────────────
--   1. o DEFAULT da coluna era `'consent'::text` — uma AFIRMACAO JURIDICA por omissao;
--   2. `seed_member_engagement_by_role` gravava o literal `'contract'` para qualquer kind;
--   3. `join_initiative` **nao nomeia a coluna**, entao herdava o default (esta terceira nao estava
--      na issue; apareceu ao contar quem insere: 8 funcoes inserem, 7 nomeiam `legal_basis`).
--
-- ── Por que gatilho, e nao remendo em cada chamador ──────────────────────────────────────────
-- Consertar os 8 chamadores deixa o defeito voltar no nono. A base legal e propriedade do KIND do
-- vinculo, nao da linha: divergencia por linha E o defeito. Entao o catalogo vira SSOT por gatilho,
-- e a divergencia deixa de ser possivel por construcao, em vez de ser proibida por convencao.
--
-- O DEFAULT sai junto: com ele, "nao informei" e "informei consent" sao indistinguiveis, e nao ha
-- como o gatilho respeitar um valor explicito. Sem default e com NOT NULL, omitir seria erro — mas
-- o gatilho preenche antes da checagem de NOT NULL (BEFORE trigger roda antes da constraint), entao
-- `join_initiative` segue funcionando sem alteracao.
--
-- ── A pergunta juridica que a issue deixou aberta, respondida por MEDICAO ────────────────────
-- A issue perguntava: trocar `consent` por `contract` nas linhas de `volunteer` afirma que existe
-- contrato — "essas pessoas assinaram o termo?". Medido em 28/08: das 46 linhas de `volunteer` que
-- divergiam, **46 de 46** sao de pessoas com termo de voluntariado CONTRA-ASSINADO. A afirmacao que
-- o backfill faz e verdadeira, e verificavel.
--
-- Para os kinds de `legitimate_interest`, nao ha termo envolvido: o `consent` gravado veio do
-- default e nunca foi coletado de ninguem. Registrar consentimento que nao existe e a afirmacao
-- errada — a correcao remove uma ficcao, nao um direito.
--
-- ── Antes -> depois (medido) ─────────────────────────────────────────────────────────────────
--   divergentes (todos os status) .... 134 -> 0
--   divergentes (ativos) ............. 106 -> 0
--   consent .......................... 150 -> 20   (os 20 sao kinds cujo catalogo DIZ consent)
--   contract ......................... 105 -> 163
--   legitimate_interest ...............  38 -> 110
--   CONTROLE: kinds fora do catalogo ...  0        (o RAISE do gatilho nao morde dado existente)

ALTER TABLE public.engagements ALTER COLUMN legal_basis DROP DEFAULT;

CREATE OR REPLACE FUNCTION public._trg_engagement_legal_basis_from_catalog()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_basis text;
BEGIN
  SELECT k.legal_basis INTO v_basis
  FROM public.engagement_kinds k WHERE k.slug = NEW.kind;

  -- Kind sem base legal declarada nao pode virar vinculo: seria uma linha sem fundamento, e o
  -- silencio aqui e o que produziu as 134 divergencias.
  IF v_basis IS NULL THEN
    RAISE EXCEPTION 'kind sem base legal no catalogo engagement_kinds: %', NEW.kind;
  END IF;

  NEW.legal_basis := v_basis;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public._trg_engagement_legal_basis_from_catalog() IS
  '#2001 — a base legal do vinculo vem do catalogo `engagement_kinds`, nunca do chamador nem de um '
  'default de coluna. Divergencia por linha e o defeito, entao ela deixa de ser possivel.';

DROP TRIGGER IF EXISTS trg_engagement_legal_basis_from_catalog ON public.engagements;
CREATE TRIGGER trg_engagement_legal_basis_from_catalog
  BEFORE INSERT OR UPDATE OF kind, legal_basis ON public.engagements
  FOR EACH ROW EXECUTE FUNCTION public._trg_engagement_legal_basis_from_catalog();

-- Backfill pela REGRA, nao por lista de ids: uma lista envelhece e nao cobre o que for criado entre
-- a medicao e o apply.
UPDATE public.engagements e
   SET legal_basis = k.legal_basis
  FROM public.engagement_kinds k
 WHERE k.slug = e.kind
   AND e.legal_basis IS DISTINCT FROM k.legal_basis;

-- Confirmar o EFEITO, nao a ausencia de erro.
DO $do$
DECLARE
  v_div  int;
  v_orfa int;
BEGIN
  SELECT count(*) INTO v_div
  FROM public.engagements e JOIN public.engagement_kinds k ON k.slug = e.kind
  WHERE e.legal_basis IS DISTINCT FROM k.legal_basis;

  SELECT count(*) INTO v_orfa
  FROM public.engagements e LEFT JOIN public.engagement_kinds k ON k.slug = e.kind
  WHERE k.slug IS NULL;

  IF v_div <> 0 THEN
    RAISE EXCEPTION '#2001: sobraram % engajamentos divergentes do catalogo', v_div;
  END IF;
  -- Controle positivo: se TODO kind estivesse fora do catalogo, o join acima nao veria nada e o
  -- zero acima seria vacuo. Este numero distingue "bateu" de "nao mediu".
  RAISE NOTICE '#2001: divergentes=0, engajamentos com kind fora do catalogo (controle)=%', v_orfa;
END $do$;

NOTIFY pgrst, 'reload schema';
