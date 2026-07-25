-- #1468 (follow-up do audit A3 / Onda 2 PR #1467): escopar o corte objetivo por mediana em
-- recompute_application_status a role_applied = 'researcher'.
--
-- A Onda 2 (mig 20260805000479) estabeleceu que o corte objetivo/research e researcher-only
-- (_compute_pert_cutoff_core, get_cutoff_dispatch_health, _selection_cutoff_pending_cron todos
-- filtram researcher; as linhas de lider tiveram o corte objetivo nulificado). Ficou de fora
-- recompute_application_status: seu cyc_median calcula median(objective_score_avg)*0.75 agrupado
-- SO por cycle_id (sem role_applied), poolando researchers + leaders. Era o unico caminho
-- remanescente onde um corte objetivo pooled cross-role poderia setar status='objective_cutoff'
-- num lider. Materialidade baixa (nao wired a nenhum cron; self-heal manual; in_cutoff=0 hoje),
-- registrado para as duas mecanicas de corte nao divergirem em contradicao.
--
-- FIX (ratificado): cyc_median ganha AND role_applied = 'researcher', alinhando a semantica
-- researcher-only da A3. Unica mudanca; resto do corpo identico ao vivo.

CREATE OR REPLACE FUNCTION public.recompute_application_status(p_application_id uuid DEFAULT NULL::uuid, p_cycle_id uuid DEFAULT NULL::uuid, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_changes jsonb := '[]'::jsonb;
  v_changed int := 0;
  v_evaluated int := 0;
  v_rec record;
  -- pipeline-stage rank used for the forward-only guard
  v_ladder text[] := ARRAY['submitted','screening','objective_eval','objective_cutoff',
                           'interview_pending','interview_scheduled','interview_done','final_eval'];
BEGIN
  -- Auth: authenticated callers need manage_platform. A no-JWT context
  -- (pg_cron / service_role) is the self-healing path and is allowed; anon is
  -- blocked by the GRANT ladder below, not by reaching here.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: manage_platform required';
    END IF;
  END IF;

  FOR v_rec IN
    WITH ev AS (
      SELECT application_id,
             count(*) FILTER (WHERE evaluation_type = 'objective' AND submitted_at IS NOT NULL) AS obj_n
      FROM public.selection_evaluations
      GROUP BY application_id
    ),
    iv AS (
      SELECT application_id,
             bool_or(conducted_at IS NOT NULL OR status = 'completed') AS conducted,
             bool_or(status IN ('scheduled','rescheduled'))            AS sched_active,
             bool_or(status NOT IN ('cancelled','noshow'))             AS has_live_row
      FROM public.selection_interviews
      GROUP BY application_id
    ),
    fully AS (
      -- precise: a CONDUCTED interview row whose EVERY assigned interviewer
      -- submitted an interview eval (mirrors submit_interview_scores' completion
      -- gate; avoids advancing a partial 2-interviewer interview to final_eval).
      SELECT DISTINCT a.id
      FROM public.selection_applications a
      JOIN public.selection_interviews si ON si.application_id = a.id
        AND (si.conducted_at IS NOT NULL OR si.status = 'completed')
        AND si.status NOT IN ('cancelled','noshow')
      WHERE COALESCE(array_length(si.interviewer_ids, 1), 0) >= 1
        AND NOT EXISTS (
          SELECT 1 FROM unnest(si.interviewer_ids) AS iid
          WHERE NOT EXISTS (
            SELECT 1 FROM public.selection_evaluations se
            WHERE se.application_id = a.id
              AND se.evaluator_id = iid
              AND se.evaluation_type = 'interview'
              AND se.submitted_at IS NOT NULL
          )
        )
    ),
    cyc_median AS (
      -- #1468: corte objetivo por mediana e researcher-only (alinha a A3/mig 479).
      SELECT cycle_id,
             ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY objective_score_avg))::numeric * 0.75, 2) AS cutoff
      FROM public.selection_applications
      WHERE objective_score_avg IS NOT NULL
        AND role_applied = 'researcher'
      GROUP BY cycle_id
    ),
    base AS (
      SELECT a.id, a.applicant_name, a.cycle_id, a.status AS cur,
             c.min_evaluators, cm.cutoff, a.objective_score_avg, a.interview_score,
             COALESCE(ev.obj_n, 0)        AS obj_n,
             COALESCE(iv.conducted, false) AS conducted,
             COALESCE(iv.sched_active, false) AS sched_active,
             COALESCE(iv.has_live_row, false) AS has_live_row,
             (f.id IS NOT NULL)            AS fully_scored
      FROM public.selection_applications a
      JOIN public.selection_cycles c ON c.id = a.cycle_id
      LEFT JOIN ev ON ev.application_id = a.id
      LEFT JOIN iv ON iv.application_id = a.id
      LEFT JOIN cyc_median cm ON cm.cycle_id = a.cycle_id
      LEFT JOIN fully f ON f.id = a.id
      WHERE (p_application_id IS NULL OR a.id = p_application_id)
        AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
    ),
    canon AS (
      SELECT *,
        CASE
          WHEN fully_scored OR (interview_score IS NOT NULL AND NOT has_live_row) THEN 'final_eval'
          WHEN conducted    THEN 'interview_done'
          WHEN sched_active THEN 'interview_scheduled'
          WHEN obj_n >= min_evaluators AND objective_score_avg IS NOT NULL THEN
            CASE WHEN cutoff > 0 AND objective_score_avg < cutoff THEN 'objective_cutoff'
                 ELSE 'interview_pending' END
          ELSE NULL
        END AS canonical
      FROM base
    ),
    ranked AS (
      SELECT *,
             array_position(v_ladder, cur)       AS cur_r,
             array_position(v_ladder, canonical) AS can_r
      FROM canon
    )
    SELECT id, applicant_name, cycle_id, cur, canonical, obj_n, objective_score_avg,
           interview_score, conducted, sched_active, fully_scored, cutoff
    FROM ranked
    WHERE cur NOT IN ('approved','rejected','converted','withdrawn','cancelled','waitlist','interview_noshow')
      AND canonical IS NOT NULL
      AND canonical <> cur
      AND ( can_r > cur_r
            OR (can_r = cur_r AND cur IN ('objective_cutoff','interview_pending')) )
  LOOP
    v_changed := v_changed + 1;
    v_changes := v_changes || jsonb_build_object(
      'application_id', v_rec.id,
      'applicant_name', v_rec.applicant_name,
      'cycle_id',       v_rec.cycle_id,
      'from',           v_rec.cur,
      'to',             v_rec.canonical
    );

    IF NOT p_dry_run THEN
      UPDATE public.selection_applications
         SET status = v_rec.canonical, updated_at = now()
       WHERE id = v_rec.id
         AND status = v_rec.cur;   -- snapshot guard: skip if changed concurrently

      IF FOUND THEN
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id,
          'selection.status_recomputed',
          'selection_application',
          v_rec.id,
          jsonb_build_object('status', jsonb_build_object('from', v_rec.cur, 'to', v_rec.canonical)),
          jsonb_build_object(
            'source',   'recompute_application_status',
            'cycle_id', v_rec.cycle_id,
            'facts', jsonb_build_object(
              'objective_evals',        v_rec.obj_n,
              'objective_score_avg',    v_rec.objective_score_avg,
              'interview_score',        v_rec.interview_score,
              'interview_conducted',    v_rec.conducted,
              'interview_scheduled',    v_rec.sched_active,
              'interview_fully_scored', v_rec.fully_scored,
              'objective_cutoff',       v_rec.cutoff
            )
          )
        );
      END IF;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_evaluated
  FROM public.selection_applications a
  WHERE (p_application_id IS NULL OR a.id = p_application_id)
    AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id);

  RETURN jsonb_build_object(
    'success',   true,
    'dry_run',   p_dry_run,
    'evaluated', v_evaluated,
    'changed',   v_changed,
    'changes',   v_changes
  );
END;
$function$;

-- PostgREST schema reload (RPC surface changed)
NOTIFY pgrst, 'reload schema';
