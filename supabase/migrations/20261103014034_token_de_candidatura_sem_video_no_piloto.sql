-- #2393, fatia 3 (ADR-0134, decisão D4 do GP em 02/11/2026): token de candidatura de vaga piloto sem o
-- escopo de vídeo geral.
--
-- O token do portal do candidato é emitido em 4 lugares, todos com 'video_screening' fixo: o worker na
-- importação (INSERT direto nesta tabela), dispatch_pending_welcomes, dispatch_consent_nudge e
-- reissue_onboarding_link. Mexer só num deles deixaria os outros emitindo o escopo. Este trigger é o ponto
-- único: todo INSERT (e toda troca de scopes ou de origem) de token de candidatura cuja vaga é 'line_pilot'
-- sai sem 'video_screening'. Os outros escopos ficam.
--
-- Sem o escopo, o servidor já recusa a gravação e a recusa dos vídeos (register_video_screening,
-- opt_out_all_pillars, revert_interview_optout e a Edge Function pmi-video-init-upload), e o modo entrevista do
-- portal só liga pela recusa dos 5 vídeos. A avaliação do piloto é outra (ADR-0134 §3): o vídeo da linha ainda
-- não existe, e o convite da entrevista geral já recusa a vaga piloto.
--
-- Limite: o trigger age na emissão. Um token emitido antes de a vaga virar 'line_pilot' fica como está; a ordem
-- da ativação marca a vaga antes de importar.

CREATE OR REPLACE FUNCTION public._token_de_candidatura_sem_video_no_piloto()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.source_type = 'pmi_application'
     AND 'video_screening' = ANY (NEW.scopes)
     AND NOT public._na_avaliacao_geral(NEW.source_id) THEN
    NEW.scopes := array_remove(NEW.scopes, 'video_screening');
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._token_de_candidatura_sem_video_no_piloto() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._token_de_candidatura_sem_video_no_piloto() IS
  'ADR-0134 (#2393, D4): tira video_screening do token de candidatura de vaga line_pilot, em todo INSERT e em toda troca de scopes ou de origem.';

DROP TRIGGER IF EXISTS trg_token_de_candidatura_sem_video_no_piloto ON public.onboarding_tokens;

CREATE TRIGGER trg_token_de_candidatura_sem_video_no_piloto
  BEFORE INSERT OR UPDATE OF scopes, source_id, source_type ON public.onboarding_tokens
  FOR EACH ROW
  EXECUTE FUNCTION public._token_de_candidatura_sem_video_no_piloto();

NOTIFY pgrst, 'reload schema';
