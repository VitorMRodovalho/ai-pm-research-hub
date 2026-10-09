/**
 * #2655 — get_selection_health le cron.job_run_details pela PK (runid), sem varrer a tabela.
 *
 * MEDIDO em 09/10/2026: 3 leituras x 4 crons = 12 varreduras sequenciais por chamada (a tabela so
 * tem indice em runid e pertence a supabase_admin). Uma chamada tocou ~426 mil paginas e levou
 * ~4,5 s; com o statement_timeout de 8 s do authenticated, 13 de 16 cargas de /admin/selection
 * voltaram 500.
 *
 * Estatico, sobre a captura mais nova da funcao, com comentarios mascarados: cada leitura do
 * historico tem de amarrar o filtro por job ao `ORDER BY <alias>.runid DESC LIMIT n` DENTRO da
 * mesma subconsulta, e nenhuma ordenacao ou agregado por start_time pode sobrar. O plano (Index
 * Scan Backward using job_run_details_pkey) foi conferido com EXPLAIN sem ANALYZE no preparo; o
 * efeito no tempo da tela so se mede depois de aplicada.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = latestFunctionCapture(ROOT, 'get_selection_health');
const corpo = maskLineComments(cap.body);
const arquivo = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', cap.file), 'utf8'));

test('#2655 toda leitura de cron.job_run_details filtra pelo job e anda a PK de tras para frente com LIMIT', () => {
  const ocorrencias = [...corpo.matchAll(/cron\.job_run_details/g)].map((m) => m.index);
  assert.equal(ocorrencias.length, 3, 'esperadas exatamente 3 leituras do historico (last_run_at, last_status, last_5_status)');
  for (const i of ocorrencias) {
    const resto = corpo.slice(i);
    const fim = resto.search(/LIMIT \d+/);
    assert.ok(fim > 0, 'leitura do historico sem LIMIT');
    const sub = resto.slice(0, fim + resto.slice(fim).match(/LIMIT \d+/)[0].length);
    // Sem parenteses entre o FROM e o LIMIT: o LIMIT pertence a ESTA subconsulta.
    assert.doesNotMatch(sub, /[()]/, `o LIMIT nao pertence a mesma subconsulta: ${sub}`);
    assert.match(
      sub,
      /^cron\.job_run_details (\w+)\s+WHERE \1\.jobid = j\.jobid\b[^;]*?\s+ORDER BY \1\.runid DESC LIMIT \d+$/,
      `leitura sem filtro por job amarrado ao ORDER BY runid DESC LIMIT: ${sub}`,
    );
  }
});

test('#2655 last_run_at: start_time da rodada mais nova que JA comecou (NULL segue ignorado, como no max)', () => {
  assert.match(
    corpo,
    /'last_run_at', \(\s*SELECT d\.start_time FROM cron\.job_run_details d\s+WHERE d\.jobid = j\.jobid AND d\.start_time IS NOT NULL\s+ORDER BY d\.runid DESC LIMIT 1\s*\)/,
  );
});

test('#2655 last_status: status da rodada de maior runid', () => {
  assert.match(
    corpo,
    /'last_status', \(\s*SELECT d\.status FROM cron\.job_run_details d\s+WHERE d\.jobid = j\.jobid\s+ORDER BY d\.runid DESC LIMIT 1\s*\)/,
  );
});

test('#2655 last_5_status: as 5 de maior runid, agregadas na mesma ordem e com as mesmas chaves', () => {
  assert.match(
    corpo,
    /'last_5_status', \(\s*SELECT jsonb_agg\(jsonb_build_object\('start', t\.start_time, 'status', t\.status, 'msg', t\.return_message\) ORDER BY t\.runid DESC\)\s+FROM \(\s*SELECT d2\.runid, d2\.start_time, d2\.status, d2\.return_message FROM cron\.job_run_details d2\s+WHERE d2\.jobid = j\.jobid\s+ORDER BY d2\.runid DESC LIMIT 5\s*\) t\s*\)/,
  );
});

test('#2655 nenhuma ordenacao nem agregado por start_time sobrou no corpo', () => {
  assert.doesNotMatch(corpo, /max\(\s*(?:\w+\.)?start_time\s*\)/i, 'max(start_time) varre a tabela');
  assert.doesNotMatch(corpo, /ORDER BY\s+(?:\w+\.)?start_time\b/i, 'ORDER BY start_time varre a tabela');
});

test('#2655 portoes, atributos e formato do retorno inalterados', () => {
  assert.match(cap.block, /RETURNS jsonb\s+LANGUAGE plpgsql\s+SECURITY DEFINER\s+SET search_path = public, pg_temp/);
  assert.match(corpo, /IF v_caller_id IS NULL THEN\s+RETURN jsonb_build_object\('error', 'Not authenticated'\);/);
  assert.match(corpo, /IF NOT public\.can_by_member\(v_caller_id, 'view_internal_analytics'\) THEN\s+RETURN jsonb_build_object\('error', 'Not authorized: requires view_internal_analytics'\);/);
  assert.match(corpo, /public\.selection_coi_recused\(v_caller_id, \(v_active_cycle->>'id'\)::uuid\) THEN\s+RETURN jsonb_build_object\('error', 'recused_conflict_of_interest'/);
  const ret = corpo.match(/RETURN jsonb_build_object\(\s*'active_cycle'([\s\S]*?)\);\s*END;\s*$/);
  assert.ok(ret, 'o RETURN final sumiu');
  for (const k of ['open_cycles', 'application_counts', 'decided_without_evaluation', 'stale_tokens_48h', 'welcome_backlog', 'crons', 'health_signal', 'fetched_at']) {
    assert.match(ret[1], new RegExp(`'${k}', `), `chave ${k} sumiu do retorno`);
  }
});

test('#2655 a migration confere SECURITY DEFINER, search_path e EXECUTE na pos-condicao', () => {
  const pos = arquivo.match(/DO \$\$([\s\S]*?)\$\$;/);
  assert.ok(pos, 'bloco de pos-condicao sumiu');
  const b = pos[1];
  assert.match(b, /IF NOT v_secdef THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF v_config IS DISTINCT FROM ARRAY\['search_path=public, pg_temp'\] THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF NOT has_function_privilege\('authenticated', v_oid, 'EXECUTE'\) THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF has_function_privilege\('anon', v_oid, 'EXECUTE'\) THEN\s+RAISE EXCEPTION/);
});
