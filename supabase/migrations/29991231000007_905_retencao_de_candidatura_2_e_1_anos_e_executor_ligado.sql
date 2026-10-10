-- #905 go-live (decisão do GP, 10/10/2026, cenário B) — retenção de candidatura de quem não virou membro:
-- 2 anos para rejeitada e 1 ano para desistência, contados da decisão do ciclo (ou da candidatura, quando a
-- decisão não está registrada), e o executor LIGADO.
--
-- Por quê: o cron lgpd-anonymize-premember-monthly nasceu dormente (20260805000280) com p_years := 5 como
-- valor provisório, atrás do checklist R1–R5, e o prazo sugerido para ligá-lo (30/09/2026) passou. A janela
-- registrada no SPEC #905 é 2 anos / 1 ano (R1). A ratificação do Encarregado fica para depois: nada vence
-- antes de 30/04/2027, então o número pode mudar até lá sem perda.
--
-- Medido em 10/10/2026 (leitura): 62 candidaturas terminais não anonimizadas (60 rejected, 2 withdrawn);
-- âncoras de 14/03/2026 (rejected) e 30/04/2026 (withdrawn) em diante; 0 com cycle_decision_date.
-- pmi_video_screenings: 225 linhas, 220 opted_out e 5 no Google Drive, todas de 1 candidatura approved.
-- Elegíveis hoje com 2/1: 0 (a pós-condição exige), então ligar não apaga nada agora.
--
-- (1) anonymize_premember_applications: mesmo corpo da captura 20260805000313 (md5 do corpo vivo
--     34572871bca566f276c46502d401c21c conferido), mais a trava R3: candidatura com vídeo externo ainda
--     apontado (drive_file_id/youtube_url) é pulada, contada em blocked_external_video e registrada em
--     admin_audit_log ('lgpd_premember_anonymization_blocked', sem dado pessoal). _erase_application_pii
--     apaga as linhas de pmi_video_screenings, e o arquivo no Drive ficaria sem ponteiro.
-- (2) cron: comando com p_years := 2, p_years_withdrawn := 1, e active := true.
-- (3) data_retention_policy de selection_applications: 730 dias (a #1812 exige retention_days = p_years × 365).
--
-- Rollback: cron.alter_job(<jobid>, command := <p_years := 5, p_years_withdrawn := NULL>, active := false);
--   retention_days = 1825; recriar anonymize_premember_applications pela captura 20260805000313.

CREATE OR REPLACE FUNCTION public.anonymize_premember_applications(
  p_dry_run boolean DEFAULT true,
  p_years integer DEFAULT 5,
  p_years_withdrawn integer DEFAULT NULL,
  p_limit integer DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_cand record;
  v_count int := 0;
  v_skipped int := 0;
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
  v_child jsonb;
  v_resume_deleted_total int := 0;
  v_video_deleted_total int := 0;
  v_children_deleted_total int := 0;
  v_calib_scrubbed_total int := 0;
  v_blocked int := 0;
  v_blocked_ids uuid[] := '{}';
BEGIN
  FOR v_cand IN
    SELECT * FROM public.list_premember_anonymization_candidates(p_years, p_years_withdrawn) LIMIT p_limit
  LOOP
    BEGIN
      -- #905 R3: o binário do vídeo mora fora do banco (Drive/YouTube). Apagar a linha antes de purgar o
      -- binário deixaria o arquivo sem ponteiro, e ninguém mais o acharia para apagar. A candidatura fica
      -- de fora, contada e registrada, até a purga externa limpar drive_file_id/youtube_url.
      IF EXISTS (SELECT 1 FROM public.pmi_video_screenings v
                 WHERE v.application_id = v_cand.application_id
                   AND (v.drive_file_id IS NOT NULL OR v.youtube_url IS NOT NULL)) THEN
        v_blocked := v_blocked + 1;
        v_blocked_ids := array_append(v_blocked_ids, v_cand.application_id);
        IF NOT p_dry_run THEN
          INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
          VALUES (NULL, 'lgpd_premember_anonymization_blocked', 'selection_application', v_cand.application_id,
            jsonb_build_object(
              'retention_anchor', v_cand.retention_anchor,
              'reason', 'external_video_binary_pending_purge',
              'issue', '905 R3',
              'source', 'cron:anonymize_premember_applications'
            ));
        END IF;
        CONTINUE;
      END IF;

      IF NOT p_dry_run THEN
        -- shared per-application erasure (resume binary + children + mother row + calibration name)
        v_child := public._erase_application_pii(v_cand.application_id);
        v_resume_deleted_total   := v_resume_deleted_total   + COALESCE((v_child->>'resume_objects_deleted')::int, 0);
        v_video_deleted_total    := v_video_deleted_total    + COALESCE((v_child->>'video_screenings_deleted')::int, 0);
        v_children_deleted_total := v_children_deleted_total  + COALESCE((v_child->>'child_rows_deleted')::int, 0);
        v_calib_scrubbed_total   := v_calib_scrubbed_total   + COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0);

        -- audit (NO PII in the audit row: ids, anchors, counts only)
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_premember_anonymization', 'selection_application', v_cand.application_id,
          jsonb_build_object(
            'anonymized_at', now(),
            'retention_anchor', v_cand.retention_anchor,
            'years_since_anchor', v_cand.years_since_anchor,
            'retention_years', p_years,
            'retention_years_withdrawn', p_years_withdrawn,
            'status_at_anonymization', v_cand.status,
            'legal_basis', 'LGPD Lei 13.709/2018 Art. 16 / Art. 6 III — pre-member candidate retention limit reached',
            'source', 'cron:anonymize_premember_applications',
            'resume_objects_deleted', COALESCE((v_child->>'resume_objects_deleted')::int, 0),
            'video_screenings_deleted', COALESCE((v_child->>'video_screenings_deleted')::int, 0),
            'child_rows_deleted', COALESCE((v_child->>'child_rows_deleted')::int, 0),
            'calibration_runs_scrubbed', COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0),
            'external_video_binaries', 'pending_manual_or_ef_purge'
          ));
      END IF;

      v_count := v_count + 1;
      v_ids := array_append(v_ids, v_cand.application_id);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('application_id', v_cand.application_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'retention_years', p_years,
    'retention_years_withdrawn', p_years_withdrawn,
    'processed', v_count,
    'skipped', v_skipped,
    'application_ids', to_jsonb(v_ids),
    'resume_objects_deleted_total', v_resume_deleted_total,
    'video_screenings_deleted_total', v_video_deleted_total,
    'child_rows_deleted_total', v_children_deleted_total,
    'calibration_runs_scrubbed_total', v_calib_scrubbed_total,
    'blocked_external_video', v_blocked,
    'blocked_application_ids', to_jsonb(v_blocked_ids),
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.anonymize_premember_applications(boolean, integer, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_premember_applications(boolean, integer, integer, integer) TO service_role;

-- ── (2) cron: janela 2 anos / 1 ano e job ligado ─────────────────────────────
DO $cronlive$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'lgpd-anonymize-premember-monthly';
  IF v_jobid IS NULL THEN
    RAISE EXCEPTION '#905: job lgpd-anonymize-premember-monthly não está registrado';
  END IF;
  PERFORM cron.alter_job(
    v_jobid,
    command := $cron$SELECT public.anonymize_premember_applications(p_dry_run := false, p_years := 2, p_years_withdrawn := 1, p_limit := 500)$cron$,
    active  := true
  );
END
$cronlive$;

-- ── (3) a tabela de retenção declara o que o job carrega ─────────────────────
UPDATE public.data_retention_policy
SET retention_days = 730,
    description = 'Candidaturas de pré-membro em estado terminal: 2 anos após a decisão (1 ano se desistiu), '
                  || 'depois anonimização (agregado pseudonimizado). Executor ligado em 10/10/2026 (SPEC #905, '
                  || 'decisão do GP); candidatura com vídeo externo ainda apontado espera a purga R3.'
WHERE table_name = 'selection_applications' AND cleanup_type = 'anonymize';

-- ── pós-condição ──────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_job record;
  v_cov record;
  v_dry jsonb;
BEGIN
  SELECT active, command INTO v_job FROM cron.job WHERE jobname = 'lgpd-anonymize-premember-monthly';
  IF NOT v_job.active THEN RAISE EXCEPTION '#905: o job continua inativo'; END IF;
  IF v_job.command !~ 'p_years\s*:=\s*2\M' OR v_job.command !~ 'p_years_withdrawn\s*:=\s*1\M'
     OR v_job.command !~ 'p_dry_run\s*:=\s*false' THEN
    RAISE EXCEPTION '#905: comando do job fora do esperado: %', v_job.command;
  END IF;

  SELECT * INTO v_cov FROM public._audit_retention_policy_coverage() c WHERE c.tabela = 'selection_applications';
  IF NOT FOUND OR v_cov.coberta IS NOT TRUE OR v_cov.horizonte_bate IS NOT TRUE THEN
    RAISE EXCEPTION '#905: a política de candidaturas não ficou coberta (%)', to_jsonb(v_cov);
  END IF;

  -- ligar não pode apagar nada hoje: o ensaio com a janela nova não acha ninguém
  v_dry := public.anonymize_premember_applications(true, 2, 1, 500);
  IF (v_dry->>'processed')::int <> 0 OR (v_dry->>'blocked_external_video')::int <> 0 THEN
    RAISE EXCEPTION '#905: o ensaio com 2/1 acharia linhas hoje: %', v_dry;
  END IF;
END
$postcondition$;
