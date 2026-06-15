-- #705 — fila de avaliação + linkage dual-track órfão (detectados na rodada cycle4-2026 via MCP).
--
-- Bug 1 — get_my_pending_evaluations devolvia applications TERMINAIS (rejected/
--   approved/withdrawn/...) na fila de pendentes: a query só filtrava por cycle_id
--   + "ainda não avaliei", SEM predicado de status. Ruído na fila do avaliador +
--   risco de avaliar candidato já decidido (ex.: Maria Araújo leader rejected).
-- Bug 3 — progress_pct podia passar de 100% (completed_count > total_count): o
--   completed_count fazia JOIN com selection_evaluations e contava LINHAS DE
--   AVALIAÇÃO (fan-out: 2 evals do mesmo avaliador no mesmo app contavam 2), vs
--   total_count que conta APPLICATIONS. Numerador e denominador com unidades
--   diferentes (live: completed=75 > total=50 -> 150%).
-- Fix (Bugs 1+3): universo "avaliável" = apps NÃO-terminais do ciclo. Aplica o
--   mesmo filtro de terminais em pending + completed + total, e usa
--   count(DISTINCT sa.id) no completed. Invariante: pending + completed = total e
--   progress_pct <= 100. Conjunto-terminal alinhado com SELECTION_TERMINAL_STATUSES
--   (worker db.ts) + recompute_application_status. PRESERVA os invariantes do #298
--   (picker determinístico ORDER BY created_at DESC + gate escopado ao comitê do
--   ciclo + short-circuit de ciclo vazio).
--
-- Bug 2 — pares dual-track ANTIGOS órfãos: as duas applications do mesmo candidato
--   (mesmo email + ciclo, roles distintos) não se enxergavam (linked_application_id
--   NULL, promotion_path NULL). Causa: o auto-link rodava em BEFORE INSERT e dava
--   FK violation no back-link (corrigido em #693 -> AFTER INSERT, mig 20260805000172);
--   pares NOVOS já linkam, mas os criados ANTES (ex.: Maria Araújo, apps de abril,
--   que escaparam do backfill único de 20260625000000) ficaram órfãos. Backfill
--   abaixo liga retroativamente os pares LIMPOS 1:1 (exatamente 1 leader + 1
--   researcher não-linkados por email+ciclo) — idempotente (NULL-guard). Blast
--   radius medido: 1 par (Maria). Distinto de #704 (identidade PMI duplicada =
--   2 contas/2 emails da mesma pessoa; aqui é 1 pessoa/1 email com 2 tracks).
--
-- ROLLBACK: re-aplicar o corpo anterior de get_my_pending_evaluations de
--   20260805000007 (sem o filtro de terminais / sem DISTINCT). O backfill é dado
--   (não revertível de forma significativa; os vínculos passam a refletir a verdade).

-- ── Bugs 1+3: get_my_pending_evaluations ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_pending_evaluations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_cycle record;
  v_pending jsonb;
  v_completed_count int;
  v_total_count int;
  -- #705 Bug 1/3 — terminais NÃO são avaliáveis: excluídos da fila, do numerador
  -- (completed) E do denominador (total) para o indicador fechar (pending +
  -- completed = total; progress_pct <= 100).
  v_terminal constant text[] := ARRAY['rejected','withdrawn','cancelled','approved','converted','waitlist','interview_noshow'];
BEGIN
  -- Authenticate caller
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Pick newest evaluating cycle deterministically (fix #298 A+ part 1)
  SELECT * INTO v_cycle FROM public.selection_cycles
  WHERE phase = 'evaluating'
  ORDER BY created_at DESC
  LIMIT 1;

  -- No evaluating cycle -> return empty consistently (no info leak)
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('cycle', null, 'pending', '[]'::jsonb, 'completed_count', 0, 'total_count', 0);
  END IF;

  -- Gate scoped to picked cycle's committee OR admin manage_member bypass (fix #298 A+ part 2)
  IF NOT EXISTS (
    SELECT 1 FROM public.selection_committee sc
    WHERE sc.member_id = v_caller_member_id AND sc.cycle_id = v_cycle.id
  ) AND NOT public.can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Pending = EVALUÁVEIS (não-terminais) do ciclo onde o avaliador ainda não submeteu.
  -- #705 Bug 1: faltava o filtro de status -> terminais poluíam a fila.
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', sa.id,
    'applicant_name', sa.applicant_name,
    'role_applied', sa.role_applied,
    'promotion_path', sa.promotion_path,
    'created_at', sa.created_at,
    'has_my_evaluation_in_progress',
      EXISTS (SELECT 1 FROM public.selection_evaluations se
              WHERE se.application_id = sa.id AND se.evaluator_id = v_caller_member_id
                AND se.submitted_at IS NULL)
  ) ORDER BY sa.created_at)
  INTO v_pending
  FROM public.selection_applications sa
  WHERE sa.cycle_id = v_cycle.id
    AND sa.status <> ALL (v_terminal)
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations se
      WHERE se.application_id = sa.id
        AND se.evaluator_id = v_caller_member_id
        AND se.submitted_at IS NOT NULL
    );

  -- Completed = apps avaliáveis DISTINTOS que o avaliador já submeteu.
  -- #705 Bug 3: era count(*) sobre o JOIN de evals -> fan-out fazia completed > total.
  SELECT count(DISTINCT sa.id)
  INTO v_completed_count
  FROM public.selection_applications sa
  JOIN public.selection_evaluations se ON se.application_id = sa.id
  WHERE sa.cycle_id = v_cycle.id
    AND sa.status <> ALL (v_terminal)
    AND se.evaluator_id = v_caller_member_id
    AND se.submitted_at IS NOT NULL;

  -- Total = apps avaliáveis do ciclo (denominador alinhado com a fila).
  SELECT count(*) INTO v_total_count
  FROM public.selection_applications
  WHERE cycle_id = v_cycle.id
    AND status <> ALL (v_terminal);

  RETURN jsonb_build_object(
    'cycle_code', v_cycle.cycle_code,
    'cycle_phase', v_cycle.phase,
    'pending', COALESCE(v_pending, '[]'::jsonb),
    'pending_count', COALESCE(jsonb_array_length(v_pending), 0),
    'completed_count', v_completed_count,
    'total_count', v_total_count,
    'progress_pct', CASE WHEN v_total_count > 0 THEN round((v_completed_count::numeric / v_total_count) * 100, 1) ELSE 0 END
  );
END;
$function$;

-- ── Bug 2: backfill dos pares dual-track LIMPOS (1 leader + 1 researcher) órfãos ──
-- Só liga quando há EXATAMENTE 1 leader e 1 researcher não-linkados para o mesmo
-- (lower(email), cycle_id) — evita ambiguidade em quem tem 3+ apps. Bidirecional +
-- promotion_path='dual_track'. Idempotente: rows já linkadas não entram (guard NULL).
WITH unlinked AS (
  SELECT lower(email) AS em, cycle_id, role_applied,
         count(*) AS n, (array_agg(id))[1] AS the_id
  FROM public.selection_applications
  WHERE linked_application_id IS NULL
    AND email IS NOT NULL AND cycle_id IS NOT NULL
    AND role_applied IN ('leader','researcher')
  GROUP BY lower(email), cycle_id, role_applied
),
clean_pairs AS (
  SELECT l.the_id AS leader_id, r.the_id AS researcher_id
  FROM unlinked l
  JOIN unlinked r ON r.em = l.em AND r.cycle_id = l.cycle_id
  WHERE l.role_applied = 'leader'     AND l.n = 1
    AND r.role_applied = 'researcher' AND r.n = 1
)
UPDATE public.selection_applications sa
SET linked_application_id = CASE WHEN sa.id = cp.leader_id THEN cp.researcher_id ELSE cp.leader_id END,
    promotion_path        = 'dual_track',
    updated_at            = now()
FROM clean_pairs cp
WHERE sa.id IN (cp.leader_id, cp.researcher_id);

-- docstring atualizado (CREATE OR REPLACE preserva o COMMENT antigo, que só citava #298)
COMMENT ON FUNCTION public.get_my_pending_evaluations() IS
  'Fila de avaliações pendentes do avaliador no ciclo evaluating. #298: picker '
  'determinístico (ORDER BY created_at DESC) + gate escopado ao comitê do ciclo + '
  'short-circuit de ciclo vazio. #705: universo "avaliável" = apps NÃO-terminais '
  '(filtro status <> ALL terminais em pending + completed + total) e '
  'count(DISTINCT sa.id) no completed -> invariante pending+completed=total, '
  'progress_pct <= 100.';

-- body-only change não muda a superfície PostgREST, mas mantém o ritual (parity).
NOTIFY pgrst, 'reload schema';
