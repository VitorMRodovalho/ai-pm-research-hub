-- #693 defeito 2 — dual-track auto-link FK violation (candidatura múltipla descartada).
--
-- ROOT CAUSE (aterrado 2026-06-14 via cron_run_log da pmi-vep-sync-ingest):
-- `_trg_auto_link_dual_track` rodava em **BEFORE INSERT** e fazia o back-link
-- recíproco `UPDATE sibling SET linked_application_id = NEW.id` — mas em BEFORE
-- INSERT a row NEW ainda NÃO existe na tabela. A FK
-- `selection_applications_linked_application_id_fkey` é NÃO-deferrable, então o
-- back-link referencia um id inexistente e viola a FK → o INSERT inteiro da 2ª
-- candidatura (dual-track) aborta → a app é dropada em TODA sync.
--
-- O par dual-track existente (William Junio) foi linkado pelo BACKFILL único da
-- migração 20260625000000 (ids já válidos), NÃO pelo trigger — por isso o bug
-- ficou mascarado até o 1º caso NOVO (Ana Sofia Pires Pacheco, app researcher
-- 296896 ↔ leader 296862): falhando em todo ingest desde >= 2026-06-10.
--
-- FIX: converter o trigger para **AFTER INSERT**. Aí NEW.id já é uma row real, e
-- ambos os UPDATEs recíprocos (forward em NEW, back no sibling) satisfazem a FK.
-- Como AFTER não pode mutar NEW.*, o forward-link também vira UPDATE na própria
-- row de NEW. Guard `linked_application_id IS NULL` em ambos os UPDATEs preserva
-- a semântica original (não re-linka rows já em triaged_to_leader/direct_*).
-- Idempotente em re-import: o worker faz UPDATE (não INSERT) em re-sync, então o
-- trigger AFTER INSERT só dispara na 1ª materialização da row.
--
-- ROLLBACK (não recomendado — reintroduz o drop de candidaturas dual-track):
-- recriar o trigger como BEFORE INSERT a partir do CORPO DA FUNÇÃO nas linhas
-- 67-113 de 20260625000000_p158_f1_dual_track_link_backfill_and_trigger.sql.
-- NÃO re-rodar aquela migração inteira (ela também contém o backfill DML único e
-- ALTER TABLE que não devem ser reexecutados).

CREATE OR REPLACE FUNCTION public._trg_auto_link_dual_track()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_sibling_id uuid;
BEGIN
  -- link já fornecido no payload → nada a auto-derivar
  IF NEW.linked_application_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_sibling_id
  FROM public.selection_applications
  WHERE lower(email)        = lower(NEW.email)
    AND cycle_id            = NEW.cycle_id
    AND role_applied       <> NEW.role_applied
    AND linked_application_id IS NULL
    AND id                 <> NEW.id
  ORDER BY created_at
  LIMIT 1;

  IF v_sibling_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- AFTER INSERT: NEW.id já é uma row materializada → ambos os lados da FK resolvem.
  -- forward link (NEW → sibling)
  UPDATE public.selection_applications
  SET    linked_application_id = v_sibling_id,
         promotion_path        = 'dual_track',
         updated_at            = now()
  WHERE  id = NEW.id
    AND  linked_application_id IS NULL;

  -- back link (sibling → NEW)
  UPDATE public.selection_applications
  SET    linked_application_id = NEW.id,
         promotion_path        = 'dual_track',
         updated_at            = now()
  WHERE  id = v_sibling_id
    AND  linked_application_id IS NULL;

  RETURN NULL;
END;
$function$;

COMMENT ON FUNCTION public._trg_auto_link_dual_track() IS
  'AFTER INSERT auto-link (#693 defeito 2): quando a 2ª candidatura VEP de um candidato chega no mesmo ciclo com role_applied diferente e sem link, estabelece linked_application_id mútuo + promotion_path=dual_track nas duas rows. Roda em AFTER INSERT (não BEFORE) para que NEW.id já exista e o back-link recíproco não viole a FK não-deferrable selection_applications_linked_application_id_fkey. Guard NULL-linked evita re-linkar triaged_to_leader/direct_*. Era BEFORE INSERT em p158 F1 (20260625000000) e dropava silenciosamente toda 2ª app dual-track.';

DROP TRIGGER IF EXISTS trg_auto_link_dual_track ON public.selection_applications;
CREATE TRIGGER trg_auto_link_dual_track
AFTER INSERT ON public.selection_applications
FOR EACH ROW
EXECUTE FUNCTION public._trg_auto_link_dual_track();

COMMENT ON TRIGGER trg_auto_link_dual_track ON public.selection_applications IS
  '#693 defeito 2: AFTER INSERT (era BEFORE) — corrige FK violation no back-link recíproco que dropava a 2ª candidatura dual-track em toda sync.';

-- parity com 20260625000000 (trigger não muda a superfície PostgREST, mas mantém o ritual)
NOTIFY pgrst, 'reload schema';
