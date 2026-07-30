-- #1537 item 3, FASE 1 — discriminador para a coluna polimórfica `gamification_points.ref_id`.
--
-- Problema: `ref_id` aponta para NOVE tabelas diferentes sem nenhuma coluna que diga qual. Medido em
-- 30/07/2026: attendance 1782 · events 224 · document_versions 73 · board_items 40 · event_showcases 31 ·
-- meeting_artifacts 12 · meeting_action_items 11 · event_agenda_blocks 8 · champions_awarded 3, mais 538
-- linhas em que a coluna é NULL por natureza da categoria (trail, badge, cert_*, course, ...) e 176 que
-- não resolvem em nenhuma delas.
--
-- Consequências já MEDIDAS desse buraco, e a razão desta migration:
--   * Auditoria que junta por um lado só devolve ZERO e parece "nada a fazer". Aconteceu no #1528: o
--     primeiro join deu 0 linhas de pontos e quase virou veredito de "a issue está errada".
--   * Nenhuma FK é possível, e por isso as 40 linhas órfãs do #1534 puderam existir por meses sem que nada
--     reclamasse.
--
-- ⚠️ A mesma `category` aponta para tabelas DIFERENTES (a categoria 'attendance' distribui entre
-- attendance.id, events.id e não-resolvido), então `ref_kind` NÃO pode ser derivado de `category` por
-- tabela-de-mapeamento. Tem de ser resolvido linha a linha, que é o que o backfill e o trigger fazem.
--
-- ESCOPO DA FASE 1: fechar a porta para linhas NOVAS e classificar as resolvíveis. As 176 não-resolvidas
-- ficam com `ref_kind IS NULL` de propósito e são a fase 2, junto do #1534 (é a mesma investigação).
--
-- SEMÂNTICA DOS VALORES, para o NULL não voltar a significar duas coisas:
--   'none'  = a categoria não referencia nada por natureza (ref_id IS NULL).
--   <tabela>= referência resolvida para aquela tabela.
--   NULL    = NÃO CLASSIFICADO (ref_id preenchido que não resolveu). É a dívida, e é mensurável.

ALTER TABLE public.gamification_points ADD COLUMN IF NOT EXISTS ref_kind text;

ALTER TABLE public.gamification_points DROP CONSTRAINT IF EXISTS gamification_points_ref_kind_check;
ALTER TABLE public.gamification_points ADD CONSTRAINT gamification_points_ref_kind_check
  CHECK (ref_kind IS NULL OR ref_kind IN (
    'none','attendance','event','document_version','board_item','event_showcase',
    'meeting_artifact','meeting_action_item','event_agenda_block','champion_award'));

COMMENT ON COLUMN public.gamification_points.ref_kind IS
  'Discriminador do ref_id polimórfico (#1537 fase 1). ''none'' = categoria sem referência por natureza; '
  'nome da tabela = referência resolvida; NULL = NÃO CLASSIFICADO (dívida da fase 2, ver #1534). '
  'Preenchido automaticamente pelo trigger trg_gamification_points_ref_kind — nenhum chamador precisa passar.';

-- ── Derivação automática ────────────────────────────────────────────────────────────────────────────
-- Trigger em vez de exigir a coluna dos chamadores: DEZ funções inserem em gamification_points hoje
-- (_grant_agenda_block_xp, _grant_auto_xp, auto_detect_onboarding_completions, award_champion,
-- remove_event_showcase, revoke_agenda_block_xp, revoke_champion, submit_cpmai_mock_score,
-- sync_attendance_points, update_cpmai_progress). Um NOT NULL quebraria as dez de uma vez; derivar fecha
-- a porta sem tocar em nenhuma. Custo: no máximo 9 lookups por chave primária, e só quando não veio valor.
CREATE OR REPLACE FUNCTION public.derive_gamification_ref_kind()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Só (re)deriva quando falta valor ou quando o alvo mudou; um UPDATE de pontos não paga o custo.
  IF TG_OP = 'UPDATE' AND NEW.ref_id IS NOT DISTINCT FROM OLD.ref_id AND NEW.ref_kind IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.ref_kind IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.ref_id IS NULL THEN
    NEW.ref_kind := 'none';
  ELSIF EXISTS (SELECT 1 FROM public.attendance t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'attendance';
  ELSIF EXISTS (SELECT 1 FROM public.events t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'event';
  ELSIF EXISTS (SELECT 1 FROM public.document_versions t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'document_version';
  ELSIF EXISTS (SELECT 1 FROM public.board_items t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'board_item';
  ELSIF EXISTS (SELECT 1 FROM public.event_showcases t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'event_showcase';
  ELSIF EXISTS (SELECT 1 FROM public.meeting_artifacts t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'meeting_artifact';
  ELSIF EXISTS (SELECT 1 FROM public.meeting_action_items t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'meeting_action_item';
  ELSIF EXISTS (SELECT 1 FROM public.event_agenda_blocks t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'event_agenda_block';
  ELSIF EXISTS (SELECT 1 FROM public.champions_awarded t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'champion_award';
  ELSE
    -- Não resolveu: um ponto novo nascendo órfão é exatamente a classe do #1534. NÃO levanta exceção
    -- (isso derrubaria concessão de ponto em produção por um alvo que pode ser criado logo depois), mas
    -- deixa NULL e avisa, para o guard de CI detectar em vez de o problema envelhecer em silêncio.
    NEW.ref_kind := NULL;
    RAISE WARNING 'gamification_points: ref_id % nao resolve em nenhuma tabela conhecida (category=%)',
      NEW.ref_id, NEW.category;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.derive_gamification_ref_kind() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_gamification_points_ref_kind ON public.gamification_points;
CREATE TRIGGER trg_gamification_points_ref_kind
  BEFORE INSERT OR UPDATE OF ref_id, ref_kind ON public.gamification_points
  FOR EACH ROW EXECUTE FUNCTION public.derive_gamification_ref_kind();

-- ── Backfill do histórico ───────────────────────────────────────────────────────────────────────────
-- Ordem idêntica à do trigger, para que histórico e linhas novas sejam classificados pela mesma regra.
UPDATE public.gamification_points gp SET ref_kind =
  CASE
    WHEN gp.ref_id IS NULL THEN 'none'
    WHEN EXISTS (SELECT 1 FROM public.attendance t WHERE t.id = gp.ref_id) THEN 'attendance'
    WHEN EXISTS (SELECT 1 FROM public.events t WHERE t.id = gp.ref_id) THEN 'event'
    WHEN EXISTS (SELECT 1 FROM public.document_versions t WHERE t.id = gp.ref_id) THEN 'document_version'
    WHEN EXISTS (SELECT 1 FROM public.board_items t WHERE t.id = gp.ref_id) THEN 'board_item'
    WHEN EXISTS (SELECT 1 FROM public.event_showcases t WHERE t.id = gp.ref_id) THEN 'event_showcase'
    WHEN EXISTS (SELECT 1 FROM public.meeting_artifacts t WHERE t.id = gp.ref_id) THEN 'meeting_artifact'
    WHEN EXISTS (SELECT 1 FROM public.meeting_action_items t WHERE t.id = gp.ref_id) THEN 'meeting_action_item'
    WHEN EXISTS (SELECT 1 FROM public.event_agenda_blocks t WHERE t.id = gp.ref_id) THEN 'event_agenda_block'
    WHEN EXISTS (SELECT 1 FROM public.champions_awarded t WHERE t.id = gp.ref_id) THEN 'champion_award'
    ELSE NULL
  END
WHERE gp.ref_kind IS NULL;

-- Índice parcial: a consulta que importa para governança é "quais linhas seguem não classificadas",
-- e ela deve continuar barata conforme a tabela cresce.
CREATE INDEX IF NOT EXISTS idx_gamification_points_ref_kind_unclassified
  ON public.gamification_points (category, created_at)
  WHERE ref_kind IS NULL;
