-- #2004 — escolher entrevista ao vivo deixa de saltar a fase objetiva.
--
-- SINTOMA (PM, 26/08): um candidato aparecia em "Aguardando Entrevista" com ZERO avaliacao
-- objetiva, `objective_score_avg`/`research_score`/`final_score` todos NULL, nenhuma linha em
-- `selection_interviews`, sem bypass de admin e sem resgate.
--
-- MECANISMO: `opt_out_all_pillars` roda como `anon` (e intencional — o candidato abre o link do
-- token) e promovia para `interview_pending` a partir de QUATRO status, sem olhar avaliacao nenhuma.
-- O portao do #1613 (`_trg_gate_interview_stage_entry`) existe e esta correto, mas guarda a entrada
-- em `interview_scheduled`; `interview_pending` e o estado ambiguo (pre-entrada E pos-cancelamento),
-- e o opt-out escrevia exatamente ali, passando por baixo.
--
-- ── Decisao do PM (28/08): opcao C, portao primeiro ──────────────────────────────────────────
-- A origem passa a ser SO `submitted`. Sair de `objective_eval` ou `objective_cutoff` significa que
-- a avaliacao ja comecou, e saltar dali pula a regua de quem esta sendo medido.
--
-- ── Por que `submitted` apenas nao quebra o fluxo legitimo, MEDIDO ───────────────────────────
-- Historico completo das transicoes para `interview_pending` em 28/08/2026:
--
--   from_status          transicoes   ja_tinham_avaliacao
--   (null)                        8                    8   <- fase objetiva, caminho legitimo
--   interview_scheduled           1                    1   <- retorno de cancelamento
--   submitted                     1                    0   <- o opt-out, o caso da issue
--
-- Ninguem NUNCA optou por entrevista a partir de `screening`, `objective_eval` ou
-- `objective_cutoff`. A restricao remove superficie nao usada; o unico caminho que a pratica
-- exerceu continua aberto.
--
-- ── A recusa deixa rastro ────────────────────────────────────────────────────────────────────
-- Antes, um status nao elegivel simplesmente nao promovia, em silencio. Agora a tentativa fica
-- registrada: sem isso, "alguem tentou saltar" seria invisivel, e a mesma licao do #2012 (recusa de
-- autoridade que nao commita nao existe) se repetiria aqui.

CREATE OR REPLACE FUNCTION public.opt_out_all_pillars(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_organization_id uuid;
  v_app_status text;
  v_pillars text[] := ARRAY['background','communication','proactivity','teamwork','culture_alignment'];
  v_question_indices int[] := ARRAY[1,2,3,4,5];
  v_promoted boolean := false;
  i int;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'video_screening' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing video_screening scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type does not support video screening (got %)', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;
  v_organization_id := v_token_row.organization_id;

  SELECT status INTO v_app_status FROM selection_applications WHERE id = v_application_id;

  FOR i IN 1..5 LOOP
    INSERT INTO pmi_video_screenings (
      application_id, pillar, question_index, question_text,
      storage_provider, status, organization_id
    ) VALUES (
      v_application_id, v_pillars[i], v_question_indices[i],
      'Optou por entrevista ao vivo (cobre os 5 pilares)',
      'opted_out', 'opted_out', v_organization_id
    )
    ON CONFLICT (application_id, pillar, question_index) DO UPDATE SET
      storage_provider = 'opted_out',
      status = 'opted_out',
      drive_file_id = NULL,
      drive_folder_id = NULL,
      drive_file_name = NULL,
      youtube_url = NULL,
      uploaded_at = NULL,
      failure_reason = NULL,
      retry_count = 0,
      updated_at = now();
  END LOOP;

  -- #2004: SO `submitted`. O opt-out registra a escolha do candidato em qualquer status — isso e
  -- direito dele e continua acontecendo acima —, mas PROMOVER de um estado onde a avaliacao ja
  -- comecou seria pular a regua.
  IF v_app_status = 'submitted' THEN
    UPDATE selection_applications
    SET status = 'interview_pending', updated_at = now()
    WHERE id = v_application_id;
    v_promoted := true;
  ELSIF v_app_status IN ('screening','objective_eval','objective_cutoff') THEN
    -- Recusa COM rastro: antes isto era silencio, e silencio nao se distingue de "nao aconteceu".
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (NULL, 'selection.opt_out_promotion_refused', 'selection_application', v_application_id,
      jsonb_build_object(
        'reason', 'avaliacao ja iniciada: promover daqui pularia a fase objetiva (#2004)',
        'app_status', v_app_status,
        'refused_at', now()
      ));
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'pillars_opted_out', 5,
    'app_status_before', v_app_status,
    'promoted', v_promoted,
    'app_status_after', CASE WHEN v_promoted THEN 'interview_pending' ELSE v_app_status END
  );
END;
$function$;

COMMENT ON FUNCTION public.opt_out_all_pillars(text) IS
  '#2004 — registra a opcao por entrevista ao vivo em qualquer status, mas so PROMOVE a partir de '
  '`submitted`. Promover de um estado onde a avaliacao ja comecou pularia a fase objetiva. A recusa '
  'e registrada em admin_audit_log.';

NOTIFY pgrst, 'reload schema';
