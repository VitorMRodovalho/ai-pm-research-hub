// tests/contracts/1819-retencao-no-painel-lgpd.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C / #1109) — an unwired contract file is silently skipped.
/**
 * #1819 — a retencao do #1812 entra no painel de saude de LGPD.
 *
 * Medido em 16/08/2026: `get_lgpd_cron_health` reportava quatro jobs e nao via nada do que o
 * #1812 entregou -- nem a varredura `data-retention-sweep-daily` (ativa, 0 execucoes), nem a
 * cobertura das politicas (3 cobertas, 3 descobertas). E a descricao da tool MCP dizia
 * "3 monthly crons", ja desatualizada desde o #905.
 *
 * QUATRO CUIDADOS, todos deliberados e todos guardados aqui:
 *
 *   1. A varredura e DIARIA e ganha driver PROPRIO (2 dias). O limiar de 35 dias dos mensais
 *      esconderia semanas de silencio de um job que apaga linha todo dia.
 *   2. NUNCA-RODOU nao e vermelho. Sem a guarda `IS NOT NULL` o painel ficaria vermelho no
 *      minuto em que isto subisse -- a varredura nasce com zero execucoes.
 *   3. A cobertura e INFORMACIONAL. A base declarada tem descobertas POR DESENHO (#1814 e o
 *      portao legal do #905); pintar o painel de amarelo permanente treina todo mundo a
 *      ignora-lo. Quem cobra regressao e o ratchet do #1812 no CI.
 *   4. `max_days_since_any_job_ran` NAO muda de significado: segue sendo sobre os mensais.
 *
 * Provado em transacao abortada, impersonando quem tem view_internal_analytics:
 *   nunca-rodou            -> green   (a guarda funciona)
 *   silencio de 5 dias     -> red
 *   silencio de 1 dia      -> green   (o limiar vale nos dois sentidos)
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { loadLatestCaptures } from '../helpers/rpc-body-drift-parser.mjs';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations', '20260816201138_1819_retencao_no_painel_lgpd.sql'),
  'utf8',
);

// Prosa sai antes do assert: os comentarios EXPLICAM os limiares, e guard que le prosa acusa a
// propria documentacao (licao do #1801/#1805/#1809).
const SQL = MIG
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

test('#1819 mig: a varredura entra no snapshot de jobs, sem derrubar os quatro que ja estavam', () => {
  assert.match(SQL, /WHERE j\.jobname IN \('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly', 'lgpd-anonymize-premember-monthly', 'data-retention-sweep-daily'\)/);
});

test('#1819 mig: a varredura tem driver de saude PROPRIO, e nunca-rodou nao e vermelho', () => {
  // job diario ativo e silencioso ha mais de 2 dias e incidente
  assert.match(SQL, /WHEN v_sweep_active AND v_sweep_days_since IS NOT NULL AND v_sweep_days_since > 2 THEN 'red'/);
  // a guarda IS NOT NULL e o que impede o falso vermelho na estreia
  assert.match(SQL, /'never_ran',\s*v_sweep_days_since IS NULL/);
});

test('#1819 mig: max_days_since_any_job_ran NAO muda de significado', () => {
  // continua sendo sobre os TRES mensais originais — enfiar um job diario ali daria um segundo
  // sentido ao mesmo campo, que e como um painel deixa de significar alguma coisa
  assert.match(SQL, /WHERE j\.jobname IN \('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly'\)\n\s*GROUP BY j\.jobid/);
});

test('#1819 mig: a cobertura e INFORMACIONAL — nunca driver de saude', () => {
  // o bloco existe na SAIDA
  assert.match(SQL, /'data_retention', v_retention,/);
  assert.match(SQL, /'policies_uncovered', count\(\*\) FILTER \(WHERE NOT c\.coberta\)/);
  // e a variavel dele NAO aparece no CASE que decide o sinal
  const caseDaSaude = SQL.slice(SQL.indexOf('v_health := CASE'), SQL.indexOf('END;\n\n  RETURN'));
  assert.doesNotMatch(caseDaSaude, /v_retention|coberta|uncovered/,
    'cobertura entrando no sinal deixaria o painel amarelo permanente — e painel sempre amarelo ' +
    'treina todo mundo a ignorar o painel');
});

test('#1819 mig: com search_path vazio, toda referencia nova e qualificada', () => {
  assert.match(SQL, /SET search_path TO ''/);
  assert.match(SQL, /FROM public\._audit_retention_policy_coverage\(\) c;/);
  assert.match(SQL, /FROM public\.admin_audit_log l/);
  assert.match(SQL, /FROM cron\.job j WHERE j\.jobname = 'data-retention-sweep-daily';/);
});

test('#1819 EF: a descricao da tool deixa de dizer "3 monthly crons"', () => {
  const ef = readFileSync(resolve(process.cwd(), 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');
  const linha = ef.split('\n').find(l => l.includes('mcp.tool("get_lgpd_cron_health"'));
  assert.ok(linha, 'a tool get_lgpd_cron_health sumiu do registro');
  assert.doesNotMatch(linha, /3 monthly crons/, 'a descricao ja estava desatualizada desde o #905');
  assert.match(linha, /4 monthly crons/);
  assert.match(linha, /data-retention-sweep-daily/);
  assert.match(linha, /INFORMATIONAL/i, 'a descricao precisa dizer que a cobertura nao dirige o sinal');
  assert.match(linha, /never-ran is not red/i);
});

test('#1819 manifesto: foi regenerado com a descricao nova', () => {
  // o guard mcp-manifest-fresh pega a defasagem; aqui a asserção é sobre o CONTEUDO
  const manifest = JSON.parse(readFileSync(resolve(process.cwd(), 'src/lib/mcp-manifest.json'), 'utf8'));
  const tools = Array.isArray(manifest.tools) ? manifest.tools : Object.values(manifest.tools ?? {});
  const tool = tools.find(t => t?.name === 'get_lgpd_cron_health');
  assert.ok(tool, 'get_lgpd_cron_health nao esta no manifesto');
  assert.match(tool.description, /data-retention-sweep-daily/);
});

// ─── portao de DB ────────────────────────────────────────────────────────────────────────────────

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1819 DB: o corpo VIVO e o corpo desta migration, nao o anterior', { skip: dbGated ? false : skipMsg }, async () => {
  // get_lgpd_cron_health resolve o chamador por auth.uid() e devolve "Not authenticated" para
  // service_role, entao chama-la aqui mediria a falta de sessao. O que da para afirmar sem
  // impersonar e que o corpo aplicado E o revisado — por md5 normalizado, o mesmo criterio do
  // gate de drift, reusando o parser central.
  const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
  assert.ifError(error);

  const vivo = data.find(r => r.proname === 'get_lgpd_cron_health');
  assert.ok(vivo, 'get_lgpd_cron_health nao existe no banco');

  const { latest } = loadLatestCaptures(resolve(process.cwd(), 'supabase/migrations'));
  const chave = [...latest.keys()].find(k => k.startsWith('get_lgpd_cron_health@'));
  assert.ok(chave, 'nenhuma captura de get_lgpd_cron_health nas migrations');

  assert.equal(
    vivo.body_md5, latest.get(chave).bodyHash,
    'o corpo vivo divergiu da ultima captura — ou a migration nao foi aplicada, ou alguem rodou ' +
    'CREATE OR REPLACE por fora (o caminho que produziu os 92 orfaos do p50)',
  );
  // e a ultima captura tem de ser ESTA migration, nao a de 20260805000280
  assert.match(latest.get(chave).file, /1819_retencao_no_painel_lgpd/,
    `a captura mais recente veio de ${latest.get(chave).file}`);
});

test('#1819 DB: a fonte do bloco novo responde e cobre todas as politicas ativas', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_retention_policy_coverage');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0,
    'sem esta fonte o bloco data_retention sai vazio e o painel volta a nao ver a retencao');
  // toda politica ativa tem de trazer o par (coberta, motivo) que o painel exibe
  for (const r of data) {
    assert.equal(typeof r.coberta, 'boolean', `${r.politica} sem booleano de cobertura`);
    if (!r.coberta) assert.ok(r.motivo, `${r.politica} descoberta sem motivo — o painel mostraria lacuna muda`);
  }
});
