/**
 * #2542 (etapa 0 da ADR-0134, item 1): o detector de divergencia entre avaliadores roda por
 * candidatura e por tipo de avaliacao, e nao mais na troca de fase do ciclo. Emenda a ADR-0059.
 *
 * O detector antigo nunca disparou (dependia de uma troca de fase que o ciclo de entrada continua
 * nao faz), tinha limiar de outra escala, misturava objetiva com entrevista e nunca gravava o
 * evaluator_id que a calibragem le. Este guard amarra cada CONDICAO ao RESULTADO dentro do bloco
 * que decide, e liga o campo que o detector grava ao campo que a calibragem le.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const corpo = (fn) => maskLineComments(latestFunctionCapture(ROOT, fn).body);
const migracoes = () => readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => ({ f, sql: maskLineComments(readFileSync(join(MIG_DIR, f), 'utf8')) }));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#2542 detector: compara so notas submetidas do MESMO tipo, na mesma candidatura', () => {
  assert.match(corpo('_trg_evaluation_divergence'),
    /WHERE e\.application_id = NEW\.application_id\s+AND e\.evaluation_type = NEW\.evaluation_type\s+AND e\.submitted_at IS NOT NULL/);
});

test('#2542 detector: a condicao relativa (30% da media, 2+ notas) produz o alerta com evaluator_id', () => {
  const b = corpo('_trg_evaluation_divergence');
  assert.match(b, /c_limiar constant numeric := 0\.30;/);
  assert.match(b,
    /IF v_n >= 2 AND v_mean > 0 AND \(v_max - v_min\) > c_limiar \* v_mean THEN\s+INSERT INTO public\.selection_evaluation_anomalies \(application_id, cycle_id, alert_type, payload\)\s+SELECT NEW\.application_id, v_cycle, 'high_variance',\s+jsonb_build_object\(\s+'evaluation_type', NEW\.evaluation_type,\s+'evaluator_id', ev,/);
});

test('#2542 detector: reavaliar refaz so o alerta ABERTO do mesmo tipo, antes de decidir', () => {
  const b = corpo('_trg_evaluation_divergence');
  const apaga = b.search(/DELETE FROM public\.selection_evaluation_anomalies an\s+WHERE an\.application_id = NEW\.application_id\s+AND an\.alert_type = 'high_variance'\s+AND an\.resolved_at IS NULL\s+AND an\.payload->>'evaluation_type' = NEW\.evaluation_type;/);
  const decide = b.search(/IF v_n >= 2 AND v_mean > 0/);
  assert.ok(apaga > 0 && decide > apaga, 'o alerta aberto e apagado antes da decisao; o resolvido fica');
});

test('#2542 detector: o gatilho esta na avaliacao, e o gatilho de fase nao volta', () => {
  const todas = migracoes();
  const cria = todas.filter((m) => /CREATE TRIGGER trg_evaluation_divergence\s+AFTER INSERT OR UPDATE OF weighted_subtotal, submitted_at ON public\.selection_evaluations\s+FOR EACH ROW EXECUTE FUNCTION public\._trg_evaluation_divergence\(\);/.test(m.sql));
  assert.ok(cria.length >= 1, 'alguma migration cria o gatilho na tabela de avaliacoes');
  const fase = todas.filter((m) => /trg_compute_evaluation_anomalies_on_phase_change/.test(m.sql));
  const ultima = fase[fase.length - 1];
  assert.ok(ultima, 'o gatilho de fase aparece no historico');
  assert.match(ultima.sql, /DROP TRIGGER IF EXISTS trg_compute_evaluation_anomalies_on_phase_change ON public\.selection_cycles;/,
    `a ultima migration que cita o gatilho de fase (${ultima.f}) tem de ser a que o derruba`);
  assert.doesNotMatch(ultima.sql.slice(ultima.sql.search(/DROP TRIGGER IF EXISTS trg_compute_evaluation_anomalies_on_phase_change/)),
    /CREATE TRIGGER trg_compute_evaluation_anomalies_on_phase_change/);
});

test('#2542 detector: o campo que o detector grava e o que a calibragem le', () => {
  assert.match(corpo('get_evaluator_calibration_stats'),
    /\(payload->>'evaluator_id'\)::uuid AS evaluator_id,\s+COUNT\(\*\) AS cnt\s+FROM public\.selection_evaluation_anomalies[\s\S]{0,120}payload \? 'evaluator_id'/);
  assert.match(corpo('_trg_evaluation_divergence'), /'evaluator_id', ev,/);
});

test('#2542 detector db: todo alerta de divergencia tem tipo de avaliacao e avaliador',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.from('selection_evaluation_anomalies')
      .select('payload').eq('alert_type', 'high_variance');
    assert.ifError(error);
    assert.ok((data ?? []).length > 0, 'ha alertas de divergencia: o detector rodou no preenchimento');
    const sem = (data ?? []).filter((r) => !r.payload?.evaluation_type || !r.payload?.evaluator_id);
    assert.equal(sem.length, 0, `${sem.length} alerta(s) sem tipo de avaliacao ou sem avaliador`);
  });
