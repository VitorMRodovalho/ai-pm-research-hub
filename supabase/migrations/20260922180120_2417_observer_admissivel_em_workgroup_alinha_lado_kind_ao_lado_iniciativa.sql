-- ============================================================================
-- #2417 — `observer` passa a ser admissivel em iniciativa `kind='workgroup'`
-- ============================================================================
--
-- POR QUE: o par `observer x participant -> write_board` (#2400, PR #2416) foi seedado para um
-- workgroup concreto, o Hackathon de Impacto Social, e ficou INALCANCAVEL. Existem dois portoes
-- em serie e o checklist de 4 etapas do V4_AUTHORITY_MODEL.md so audita o segundo:
--
--   portao 1 — `engagement_kinds.initiative_kinds_allowed`: este kind pode ser ATADO a esta
--              especie de iniciativa? E o que `manage_initiative_engagement` valida, antes de tudo.
--   portao 2 — `engagement_kind_permissions`: o par (kind, role) concede a action?
--
-- Medido em 22/09/2026, com dois controles positivos:
--   observer x workgroup .................. a RPC deixa passar: FALSE  <- o caso do Hackathon
--   CONTROLE + workgroup_member x workgroup ...................... TRUE
--   CONTROLE + observer x research_tribe ......................... TRUE
--
-- E A CAUSA RAIZ SAO DUAS FONTES DA VERDADE QUE DISCORDAM:
--   `initiative_kinds.allowed_engagement_kinds` — lado-INICIATIVA, o que o dropdown do admin MOSTRA
--   `engagement_kinds.initiative_kinds_allowed` — lado-KIND, o que a RPC VALIDA
-- Para `workgroup`, o lado-INICIATIVA **ja lista `observer`**. O lado-KIND nao listava. Esta
-- migration alinha o lado-KIND a uma intencao que o lado-INICIATIVA ja declarava — nao cria
-- autoridade nova, destrava um caminho que a propria plataforma ja prometia na tela.
--
-- Precedente identico: `20260729000000_p205_issue_169_congress_engagement_kinds_align.sql`, que
-- documentou esta mesma classe para `congress` e escolheu a mesma forma de conserto.
--
-- ESCOPO: SO a celula do caso, por decisao do dono em 22/09. A varredura completa achou 33 pares,
-- 19 concordando, 10 em que a UI oferece e a RPC recusa e 4 no sentido inverso. As outras 9 celulas
-- ficam na #2417, congeladas pela catraca de
-- `tests/contracts/2417-catalogo-de-vinculo-admite-o-que-a-ui-promete.test.mjs`, que so as deixa
-- diminuir.
--
-- O QUE ISTO NAO MUDA: nada do que `observer` CONCEDE. As permissoes continuam vindo do par, e
-- `observer x observer` segue concedendo nada, por desenho. Criar um vinculo `observer` tambem
-- continua exigindo `manage_member` na iniciativa: `observer.created_by_role` e
-- {manager, deputy_manager, leader}, e o ramo nao-admin de `manage_initiative_engagement` so aceita
-- quem tem 'owner' ou 'coordinator' nessa lista. Coordenador de iniciativa NAO passa a poder
-- convidar externo.
--
-- Raio: 10 iniciativas `workgroup`, todas `active`, 0 confidenciais (medido 22/09).
-- ============================================================================

UPDATE public.engagement_kinds
   SET initiative_kinds_allowed = initiative_kinds_allowed || ARRAY['workgroup']::text[],
       updated_at = now()
 WHERE slug = 'observer'
   AND NOT ('workgroup' = ANY(initiative_kinds_allowed));

-- Pos-condicao afirmada na propria transacao: o portao 1 tem de deixar passar, e o lado-INICIATIVA
-- tem de continuar prometendo. Afirmar so um dos dois lados deixaria a migration "verde" num mundo
-- em que a promessa sumiu e o alinhamento passou a ser com o nada.
DO $$
DECLARE
  v_lado_kind boolean;
  v_lado_iniciativa boolean;
BEGIN
  SELECT 'workgroup' = ANY(initiative_kinds_allowed) INTO v_lado_kind
    FROM public.engagement_kinds WHERE slug = 'observer';
  SELECT 'observer' = ANY(allowed_engagement_kinds) INTO v_lado_iniciativa
    FROM public.initiative_kinds WHERE slug = 'workgroup';

  IF NOT COALESCE(v_lado_kind, false) THEN
    RAISE EXCEPTION '#2417: observer continua inadmissivel em workgroup — manage_initiative_engagement segue recusando';
  END IF;
  IF NOT COALESCE(v_lado_iniciativa, false) THEN
    RAISE EXCEPTION '#2417: o lado-INICIATIVA nao promete observer em workgroup — este alinhamento perdeu a contraparte';
  END IF;
END $$;

COMMENT ON COLUMN public.engagement_kinds.initiative_kinds_allowed IS
  'Especies de iniciativa em que este kind pode ser ATADO. Validado por manage_initiative_engagement '
  'ANTES de qualquer checagem de permissao — e o portao 1, e o checklist de 4 etapas do '
  'V4_AUTHORITY_MODEL.md audita o portao 2. Tem de concordar com initiative_kinds.allowed_engagement_kinds, '
  'que e a lista que o dropdown do admin mostra; quando divergem, a UI oferece o que a RPC recusa (#2417, #169).';
