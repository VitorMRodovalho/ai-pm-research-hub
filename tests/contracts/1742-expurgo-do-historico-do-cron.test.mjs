/**
 * #1742 — expurgo do historico do pg_cron (cron.job_run_details).
 *
 * MEDIDO em 09/10/2026: 282 MB de um banco de 702 MB, 300.919 linhas desde 21/03, nenhum job que
 * limpasse, e o Supabase alertando falta de orcamento de IO de disco. Regra decidida pelo GP no
 * mesmo dia, refinada na revisao do data-architect:
 *   - sai rodada BEM-SUCEDIDA com mais de 14 dias;
 *   - rodada com FALHA fica 90 dias (as funcoes de saude contam falhas em janelas de 30 e 90 dias);
 *   - as 10 mais recentes de cada job ficam sempre (7 jobs mensais; limiar de 35 dias da LGPD).
 *
 * Estatico, sobre a captura mais nova da funcao: cada asserção amarra a condicao ao bloco que
 * decide (o DELETE, o conjunto protegido, os defaults, o REVOKE, o agendamento). Exercer a funcao
 * apagaria historico de producao, entao o efeito foi exercido em transacao desfeita na aplicacao.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const NOME = '_purge_cron_job_run_details';
const cap = latestFunctionCapture(ROOT, NOME);
const corpo = maskLineComments(cap.body);
const arquivo = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', cap.file), 'utf8'));

test('#1742 o DELETE so tira bem-sucedida antiga ou falha muito antiga, e nunca as protegidas', () => {
  const del = corpo.match(/DELETE FROM cron\.job_run_details d([\s\S]*?);/);
  assert.ok(del, 'o DELETE sumiu');
  const w = del[1];
  assert.match(w, /AND coalesce\(d\.start_time, '-infinity'::timestamptz\) < v_limite\s/,
    'a idade de 14 dias tem de ser conferida linha a linha');
  assert.match(w, /AND \(d\.status = 'succeeded'\s+OR coalesce\(d\.start_time, '-infinity'::timestamptz\) < v_limite_falha\)/,
    'falha so sai depois do limite de falha');
  assert.match(w, /AND NOT EXISTS \(SELECT 1 FROM pg_temp\._cron_keep k WHERE k\.runid = d\.runid\)/,
    'as protegidas por job nao podem sair');
  assert.match(w, /d\.runid < least\(v_de \+ p_batch, v_corte\)/, 'o lote anda pela PK abaixo do corte');
});

test('#1742 o conjunto protegido sao as N mais recentes POR JOB', () => {
  assert.match(corpo, /row_number\(\) OVER \(PARTITION BY d\.jobid ORDER BY d\.runid DESC\) AS rn[\s\S]*?\) x WHERE x\.rn <= p_keep_per_job;/);
});

test('#1742 defaults: 14 dias, falhas 90, 10 por job, teto 50.000 por noite', () => {
  const assinatura = cap.block.match(/\(([\s\S]*?)\)\s*RETURNS/)[1];
  assert.match(assinatura, /p_keep_days\s+integer DEFAULT 14\b/);
  assert.match(assinatura, /p_keep_failed_days\s+integer DEFAULT 90\b/);
  assert.match(assinatura, /p_keep_per_job\s+integer DEFAULT 10\b/);
  assert.match(assinatura, /p_max\s+integer DEFAULT 50000\b/);
  assert.match(cap.block, /SECURITY DEFINER\s+SET search_path TO ''/);
});

test('#1742 so o cron chama: EXECUTE sai de PUBLIC, anon, authenticated e service_role', () => {
  assert.match(arquivo, /REVOKE ALL ON FUNCTION public\._purge_cron_job_run_details\(integer, integer, integer, integer, integer\)\s+FROM PUBLIC, anon, authenticated, service_role;/);
});

test('#1742 agendado toda noite com nome fixo', () => {
  assert.match(arquivo, /cron\.schedule\(\s*'cron-history-purge-nightly',\s*'17 4 \* \* \*',\s*\$\$SELECT public\._purge_cron_job_run_details\(\)\$\$\s*\)/);
});
