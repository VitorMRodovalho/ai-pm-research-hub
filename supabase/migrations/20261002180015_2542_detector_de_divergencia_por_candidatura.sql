-- #2542 (etapa 0 da ADR-0134, item 1): detector de divergencia entre avaliadores, por candidatura.
-- Emenda a ADR-0059 (decisao B6 do GP em 01/10/2026).
--
-- O detector antigo (_trg_compute_evaluation_anomalies_on_phase_change) tinha tres defeitos, medidos
-- em 01/10/2026 no cycle4-2026:
--   1. so disparava na passagem de fase evaluating -> evaluations_closed, que o ciclo de entrada
--      continua nunca faz: 0 linhas em selection_evaluation_anomalies;
--   2. o limiar era stddev > 1.5, de outra escala: a nota objetiva vai de 23 a 245;
--   3. misturava objetiva com entrevista no mesmo calculo. Simulado como estava: 91 de 93 marcadas.
-- E nunca gravava payload.evaluator_id, que e a chave pela qual get_evaluator_calibration_stats
-- conta anomalias por avaliador: essa contagem era zero por construcao.
--
-- Agora: o gatilho roda na propria avaliacao, por tipo de avaliacao, quando ha 2 ou mais notas
-- submetidas do mesmo tipo na candidatura. Marca quando (maior - menor) > 30% da media daquele
-- tipo. Grava uma linha por avaliador envolvido, com evaluator_id, para a calibragem contar.
-- Reavaliar recalcula: o alerta ABERTO do mesmo tipo e refeito; o resolvido fica.

CREATE OR REPLACE FUNCTION public._trg_evaluation_divergence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_limiar constant numeric := 0.30;
  v_n int;
  v_mean numeric;
  v_min numeric;
  v_max numeric;
  v_ids uuid[];
  v_cycle uuid;
BEGIN
  IF NEW.submitted_at IS NULL OR NEW.weighted_subtotal IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*), avg(e.weighted_subtotal), min(e.weighted_subtotal), max(e.weighted_subtotal),
         array_agg(e.evaluator_id ORDER BY e.evaluator_id)
    INTO v_n, v_mean, v_min, v_max, v_ids
    FROM public.selection_evaluations e
   WHERE e.application_id = NEW.application_id
     AND e.evaluation_type = NEW.evaluation_type
     AND e.submitted_at IS NOT NULL
     AND e.weighted_subtotal IS NOT NULL;

  SELECT a.cycle_id INTO v_cycle FROM public.selection_applications a WHERE a.id = NEW.application_id;

  DELETE FROM public.selection_evaluation_anomalies an
   WHERE an.application_id = NEW.application_id
     AND an.alert_type = 'high_variance'
     AND an.resolved_at IS NULL
     AND an.payload->>'evaluation_type' = NEW.evaluation_type;

  IF v_n >= 2 AND v_mean > 0 AND (v_max - v_min) > c_limiar * v_mean THEN
    INSERT INTO public.selection_evaluation_anomalies (application_id, cycle_id, alert_type, payload)
    SELECT NEW.application_id, v_cycle, 'high_variance',
           jsonb_build_object(
             'evaluation_type', NEW.evaluation_type,
             'evaluator_id', ev,
             'evaluator_ids', to_jsonb(v_ids),
             'evaluator_count', v_n,
             'mean', round(v_mean, 2),
             'min', v_min,
             'max', v_max,
             'diff', v_max - v_min,
             'rel_diff', round((v_max - v_min) / v_mean, 4),
             'threshold_rel', c_limiar,
             'rule', 'maior - menor > 30% da media, por tipo de avaliacao (#2542, ADR-0134 B6)')
      FROM unnest(v_ids) AS ev;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._trg_evaluation_divergence() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_evaluation_divergence ON public.selection_evaluations;
CREATE TRIGGER trg_evaluation_divergence
  AFTER INSERT OR UPDATE OF weighted_subtotal, submitted_at ON public.selection_evaluations
  FOR EACH ROW EXECUTE FUNCTION public._trg_evaluation_divergence();

-- O detector antigo sai: o disparo por fase era o defeito 1, e mudar a fase do ciclo agora nao
-- produz mais a enxurrada de 91 alertas.
DROP TRIGGER IF EXISTS trg_compute_evaluation_anomalies_on_phase_change ON public.selection_cycles;
DROP FUNCTION IF EXISTS public._trg_compute_evaluation_anomalies_on_phase_change();

-- Preenchimento: o estado atual de todas as candidaturas, pela mesma regra. Em 01/10/2026 a
-- tabela tinha 0 linhas, entao nada se perde.
WITH grupos AS (
  SELECT e.application_id, e.evaluation_type,
         count(*) AS n, avg(e.weighted_subtotal) AS media,
         min(e.weighted_subtotal) AS menor, max(e.weighted_subtotal) AS maior,
         array_agg(e.evaluator_id ORDER BY e.evaluator_id) AS ids
    FROM public.selection_evaluations e
   WHERE e.submitted_at IS NOT NULL AND e.weighted_subtotal IS NOT NULL
   GROUP BY e.application_id, e.evaluation_type
  HAVING count(*) >= 2
)
INSERT INTO public.selection_evaluation_anomalies (application_id, cycle_id, alert_type, payload)
SELECT g.application_id, a.cycle_id, 'high_variance',
       jsonb_build_object(
         'evaluation_type', g.evaluation_type,
         'evaluator_id', ev,
         'evaluator_ids', to_jsonb(g.ids),
         'evaluator_count', g.n,
         'mean', round(g.media, 2),
         'min', g.menor,
         'max', g.maior,
         'diff', g.maior - g.menor,
         'rel_diff', round((g.maior - g.menor) / g.media, 4),
         'threshold_rel', 0.30,
         'rule', 'maior - menor > 30% da media, por tipo de avaliacao (#2542, ADR-0134 B6)',
         'backfill', true)
  FROM grupos g
  JOIN public.selection_applications a ON a.id = g.application_id
  CROSS JOIN LATERAL unnest(g.ids) AS ev
 WHERE g.media > 0 AND (g.maior - g.menor) > 0.30 * g.media;
