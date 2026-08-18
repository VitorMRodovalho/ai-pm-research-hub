-- #1834 -- o status da candidatura ganha historico proprio, no nivel da TABELA.
--
-- Motivo, medido em 17/08/2026: `selection_applications.status` nao tinha carimbo proprio
-- nem historico. `updated_at` era o unico relogio, e qualquer escrita na linha o move. Foi
-- assim que uma sincronizacao de 152 linhas PRE-EXISTENTES (13:03:46 a 13:05:50 UTC) foi
-- lida como decisoes tomadas naquele minuto: das 89 linhas hoje `approved` tocadas na
-- janela, as 30 que carregam carimbo de oferta se espalham por CINCO meses (15/04 a 17/08).
--
-- Por que o gate vai na tabela e nao nas funcoes: vinte funcoes de `public` escrevem
-- `status` e apenas seis auditam a mudanca. Pior, o evento de 17/08 nao passou por funcao
-- nenhuma -- nenhuma escreve `imported_at` por UPDATE, e 152 linhas o receberam --, entao
-- veio de SQL direto com `service_role`. Auditoria por funcao nao alcanca esse caminho.
-- Um trigger alcanca as vinte E o SQL direto.
--
-- O que este historico NAO faz: reconstruir o passado. As linhas semeadas para as
-- candidaturas que ja existem carregam `changed_at` NULO de proposito, porque a data da
-- decisao nao existe em lugar nenhum. `source` separa "medido pelo trigger" de "estado
-- observado na estreia" -- a mesma distincao que a coluna `instrumented` faz no #1590.

CREATE TABLE public.selection_application_status_history (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id    uuid NOT NULL
                      REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  action            text NOT NULL,
  from_status       text,
  to_status         text NOT NULL,
  -- quando a transicao aconteceu. NULO SO na linha de base semeada, onde e desconhecida.
  changed_at        timestamptz,
  -- quando esta linha de historico foi escrita. Sempre presente, sempre confiavel.
  observed_at       timestamptz NOT NULL DEFAULT now(),
  actor_member_id   uuid REFERENCES public.members(id) ON DELETE SET NULL,
  -- sinais do chamador. `auth.uid()` nulo com `session_user` de servico e a assinatura de
  -- escrita direta, que era invisivel antes deste trigger.
  caller_context    jsonb NOT NULL DEFAULT '{}'::jsonb,
  source            text NOT NULL DEFAULT 'trigger',

  CONSTRAINT sash_action_check
    CHECK (action = ANY (ARRAY['insert'::text, 'update'::text, 'seed'::text])),
  CONSTRAINT sash_source_check
    CHECK (source = ANY (ARRAY['trigger'::text, 'baseline_seed'::text])),
  -- os dois dominios de status espelham `selection_applications_status_check`, para que a
  -- coluna de estado nasca com dominio declarado (#1822) em vez de virar a 57a sem guarda.
  CONSTRAINT sash_to_status_check
    CHECK (to_status = ANY (ARRAY['submitted'::text, 'screening'::text, 'objective_eval'::text,
      'objective_cutoff'::text, 'interview_pending'::text, 'interview_scheduled'::text,
      'interview_done'::text, 'interview_noshow'::text, 'final_eval'::text, 'approved'::text,
      'rejected'::text, 'waitlist'::text, 'converted'::text, 'withdrawn'::text,
      'cancelled'::text])),
  CONSTRAINT sash_from_status_check
    CHECK (from_status IS NULL OR from_status = ANY (ARRAY['submitted'::text, 'screening'::text,
      'objective_eval'::text, 'objective_cutoff'::text, 'interview_pending'::text,
      'interview_scheduled'::text, 'interview_done'::text, 'interview_noshow'::text,
      'final_eval'::text, 'approved'::text, 'rejected'::text, 'waitlist'::text,
      'converted'::text, 'withdrawn'::text, 'cancelled'::text])),
  -- a honestidade do carimbo, imposta pelo banco: linha de trigger SEMPRE sabe quando;
  -- linha semeada NUNCA finge saber.
  CONSTRAINT sash_changed_at_matches_source_check
    CHECK ((source = 'trigger'       AND changed_at IS NOT NULL)
        OR (source = 'baseline_seed' AND changed_at IS NULL))
);

CREATE INDEX idx_sash_application_observed
  ON public.selection_application_status_history (application_id, observed_at DESC);
CREATE INDEX idx_sash_to_status_changed
  ON public.selection_application_status_history (to_status, changed_at DESC)
  WHERE source = 'trigger';

COMMENT ON TABLE public.selection_application_status_history IS
  '#1834 -- toda transicao de selection_applications.status, escrita por trigger de tabela e '
  'nao por cada funcao. Existe porque status nao tinha carimbo proprio: updated_at e o relogio '
  'da LINHA, move com qualquer escrita, e por isso uma sincronizacao de 152 linhas foi lida '
  'como 83 decisoes do mesmo minuto (17/08/2026). Alcanca as 20 funcoes que escrevem status E '
  'o SQL direto por service_role, que foi o caminho daquele evento e que nenhuma auditoria '
  'por funcao pega.';
COMMENT ON COLUMN public.selection_application_status_history.changed_at IS
  'Quando a transicao ocorreu. NULO apenas em source=baseline_seed, onde a data da decisao nao '
  'existe em fonte nenhuma. NUNCA preencher com updated_at: e o carimbo da linha, nao do fato.';
COMMENT ON COLUMN public.selection_application_status_history.source IS
  'trigger = transicao medida no ato. baseline_seed = estado que ja existia na estreia do '
  'historico, sem data conhecida. Separa "nao mediu" de "nao aconteceu".';
COMMENT ON COLUMN public.selection_application_status_history.caller_context IS
  'Sinais do chamador: auth_uid, session_user, jwt_role. auth_uid nulo com session_user de '
  'servico e a assinatura de escrita direta, invisivel antes deste trigger.';

ALTER TABLE public.selection_application_status_history ENABLE ROW LEVEL SECURITY;

-- Leitura de historico de decisao e funcao de governanca: manage_platform, como o resto da
-- superficie de decisao. Ampliar depois e decisao deliberada, nao efeito colateral.
CREATE POLICY sash_select_gp ON public.selection_application_status_history
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.members m
     WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform')
  ));

-- Ninguem escreve por fora do trigger: sem policy de INSERT/UPDATE/DELETE, e sem grant.
REVOKE ALL ON public.selection_application_status_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.selection_application_status_history TO authenticated;

CREATE OR REPLACE FUNCTION public._trg_record_application_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_auth_uid  uuid;
  v_member_id uuid;
  v_jwt_role  text;
BEGIN
  -- UPDATE que nao mexeu no status nao e transicao e nao entra no historico.
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  v_auth_uid := auth.uid();
  IF v_auth_uid IS NOT NULL THEN
    SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = v_auth_uid;
  END IF;

  -- A claim pode nao existir (cron, SQL direto). Ausencia e sinal, nao erro.
  BEGIN
    v_jwt_role := current_setting('request.jwt.claims', true)::jsonb->>'role';
  EXCEPTION WHEN OTHERS THEN
    v_jwt_role := NULL;
  END;

  INSERT INTO public.selection_application_status_history (
    application_id, action, from_status, to_status,
    changed_at, actor_member_id, caller_context, source
  ) VALUES (
    NEW.id,
    CASE WHEN TG_OP = 'INSERT' THEN 'insert' ELSE 'update' END,
    CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
    NEW.status,
    now(),
    v_member_id,
    jsonb_build_object(
      'auth_uid',     v_auth_uid,
      'session_user', session_user,
      'jwt_role',     v_jwt_role
    ),
    'trigger'
  );

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public._trg_record_application_status_change() IS
  '#1834 -- grava cada transicao de status em selection_application_status_history. '
  'SECURITY DEFINER de proposito: precisa gravar mesmo quando quem escreve na candidatura '
  'nao tem grant no historico, que e o caso de todo caminho hoje. Nao ha gate de leitura '
  'aqui porque a funcao nao devolve dado: a RLS do historico e que decide quem le.';

-- CREATE FUNCTION concede EXECUTE a PUBLIC; trigger nao precisa de grant para disparar.
REVOKE ALL ON FUNCTION public._trg_record_application_status_change() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_record_application_status_change
  AFTER INSERT OR UPDATE ON public.selection_applications
  FOR EACH ROW EXECUTE FUNCTION public._trg_record_application_status_change();

-- Linha de base: o estado observado na estreia, com changed_at NULO porque a data da decisao
-- nao existe. Idempotente: so semeia candidatura que ainda nao tem linha de historico.
INSERT INTO public.selection_application_status_history (
  application_id, action, from_status, to_status, changed_at, actor_member_id, caller_context, source
)
SELECT a.id, 'seed', NULL, a.status, NULL, NULL,
       jsonb_build_object('note', 'estado observado na estreia do historico'), 'baseline_seed'
  FROM public.selection_applications a
 WHERE a.status IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.selection_application_status_history h
      WHERE h.application_id = a.id
   );
