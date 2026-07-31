-- #1537 fase 2a — as três tabelas que faltavam no vocabulário do discriminador `ref_kind`.
--
-- A fase 1 (migration ...495) listou NOVE tabelas no trigger derivador e classificou 2722 de 2898
-- linhas, deixando 176 com `ref_kind IS NULL`. A leitura de então foi que as 176 eram dívida de DADO
-- (referência órfã, mesma família do #1534). Uma varredura de TODO o schema público — toda tabela com
-- coluna `id` do tipo uuid, não um subconjunto adivinhado — mostrou que a maioria não é dívida de dado
-- nenhuma: são referências perfeitamente resolvíveis para tabelas que simplesmente não estavam na
-- lista. Medido em 30/07/2026, em produção:
--
--   approval_signoffs   98 linhas (curation_ratification)      — resolve 98/98
--   document_comments   29 linhas (curation_comment_resolved)  — resolve 29/29
--   initiatives          7 linhas (showcase_talk)              — resolve  7/7, em 2 iniciativas
--   ── não resolve em NENHUMA tabela do schema ─────────────────────────────────────────────────────
--   attendance          40 linhas — as órfãs do #1534
--   curation_doc_authored 2 linhas — órfãs equivalentes, que o #1534 não cobre (document_versions
--                                    apagadas). Registradas no #1534 para não se perderem.
--
-- Confirmado pelo CÓDIGO, não por inferência sobre o dado: `trg_approval_signoff_xp` chama
-- `_grant_auto_xp('curation_ratification', NEW.signer_id, NEW.id, ...)` a partir de um trigger em
-- `approval_signoffs`; `trg_doc_comment_resolved_xp` faz o mesmo a partir de `document_comments`; e os
-- dois `ref_id` de `showcase_talk` são iniciativas reais (`kind = 'congress'`) cujos títulos batem com
-- o `reason` da linha de ponto.
--
-- ⚠️ POR QUE ISSO É URGENTE, e não cosmético: o guard da fase 1 fixou o ratchet das não-classificadas
-- em 176. Como `approval_signoffs` e `document_comments` seguem em uso, CADA ratificação assinada e
-- CADA comentário resolvido nasce com `ref_kind` NULL (e com RAISE WARNING). O ratchet seria então
-- rompido pela OPERAÇÃO NORMAL da plataforma, não por regressão — um guard que acusa o inocente. Esta
-- migration fecha essa porta antes que isso aconteça.
--
-- A semântica da fase 1 permanece intacta e é o que torna a medição possível:
--   'none'   = a categoria não referencia nada por natureza (ref_id IS NULL)
--   <tabela> = referência resolvida
--   NULL     = NÃO CLASSIFICADO (é a dívida, e continua mensurável — agora 42, não 176)

ALTER TABLE public.gamification_points DROP CONSTRAINT IF EXISTS gamification_points_ref_kind_check;
ALTER TABLE public.gamification_points ADD CONSTRAINT gamification_points_ref_kind_check
  CHECK (ref_kind IS NULL OR ref_kind IN (
    'none','attendance','event','document_version','board_item','event_showcase',
    'meeting_artifact','meeting_action_item','event_agenda_block','champion_award',
    'approval_signoff','document_comment','initiative'));

-- Os três ramos novos entram no FIM da cascata, de propósito: assim nenhuma linha já classificada pela
-- fase 1 pode mudar de valor por efeito colateral desta migration. A ordem só importaria se dois ids
-- colidissem entre tabelas, o que uuid v4 não produz.
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
  ELSIF EXISTS (SELECT 1 FROM public.approval_signoffs t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'approval_signoff';
  ELSIF EXISTS (SELECT 1 FROM public.document_comments t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'document_comment';
  ELSIF EXISTS (SELECT 1 FROM public.initiatives t WHERE t.id = NEW.ref_id) THEN
    NEW.ref_kind := 'initiative';
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

-- Backfill restrito ao que a fase 1 deixou NULL. Nenhuma linha já classificada é tocada.
UPDATE public.gamification_points gp SET ref_kind =
  CASE
    WHEN EXISTS (SELECT 1 FROM public.approval_signoffs t WHERE t.id = gp.ref_id) THEN 'approval_signoff'
    WHEN EXISTS (SELECT 1 FROM public.document_comments t WHERE t.id = gp.ref_id) THEN 'document_comment'
    WHEN EXISTS (SELECT 1 FROM public.initiatives t WHERE t.id = gp.ref_id) THEN 'initiative'
    ELSE NULL
  END
WHERE gp.ref_kind IS NULL AND gp.ref_id IS NOT NULL;
