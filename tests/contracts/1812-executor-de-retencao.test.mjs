// tests/contracts/1812-executor-de-retencao.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C / #1109) — an unwired contract file is silently skipped.
/**
 * #1812 — data_retention_policy declarava 6 politicas ativas e nao tinha executor nenhum.
 *
 * Medido em 16/08/2026: ZERO funcoes em public referenciavam a tabela. A unica que a lia,
 * admin_run_retention_cleanup, foi aposentada em 16/08 (#1809) por citar tres colunas
 * inexistentes -- e nunca teve chamador nem cron, entao nunca chegou a executar. Uma tabela
 * que declara politica que ninguem executa e pior que tabela vazia: parece controle.
 *
 * O prazo nao e "0 linhas hoje". As seis alcancam 0 linhas porque a plataforma tem 155 dias;
 * a primeira passa a morder em 2026-09-09 (notifications lidas, 180d).
 *
 * DESENHO: a tabela vira REGISTRO. `executor` nomeia o job que executa cada linha, a varredura
 * generica executa so as linhas do job dela, e o predicado de cada ramo sai da DESCRICAO da
 * propria linha -- foi inventando qualificador ("status = 'resolved'" sobre uma tabela sem
 * status) que a funcao aposentada derivou.
 *
 * selection_applications NAO e executada pela varredura: ja tem caminho dedicado e revisado
 * (SPEC #905), dormante de proposito por portao de parecer legal R1-R5.
 *
 * BASE DECLARADA DO RATCHET: 3 politicas descobertas.
 *   attendance/archive e board_lifecycle_events/archive — sem destino de arquivamento (#1814)
 *   selection_applications/anonymize — job dedicado registrado porem INATIVO (portao legal)
 * Uma quarta derruba o CI.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations', '20260816184810_1812_executor_de_retencao_e_ratchet_de_cobertura.sql'),
  'utf8',
);

/**
 * So o SQL EXECUTAVEL. Os comentarios CITAM as colunas erradas da funcao aposentada -- e
 * obrigatorio que citem, senao a migration nao explica o que corrigiu. Guard que le prosa
 * acusa a propria documentacao (licao do #1801/#1805/#1809): prosa sai antes do assert.
 */
const SQL = MIG
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

const conta = (s, sub) => (s.split(sub).length - 1);

test('#1812 mig: a tabela vira registro — cada linha nomeia quem a executa', () => {
  assert.match(SQL, /ALTER TABLE public\.data_retention_policy\s*\n?\s*ADD COLUMN IF NOT EXISTS executor text;/);
  // as tres de delete apontam para a varredura generica
  assert.match(SQL, /SET executor = 'data-retention-sweep-daily'\s*\n\s*WHERE cleanup_type = 'delete' AND table_name IN \('notifications', 'data_anomaly_log', 'visitor_leads'\)/);
  // resolvido por (tabela, tipo), NUNCA por id gerado
  assert.doesNotMatch(SQL, /WHERE id = '[0-9a-f]{8}-/, 'data migration nao pode fixar id gerado');
});

test('#1812 mig: a anonimizacao aponta para o caminho dedicado e NAO e reimplementada aqui', () => {
  // um executor generico rodando essa linha passaria por cima do portao legal do SPEC #905
  assert.match(SQL, /SET executor = 'lgpd-anonymize-premember-monthly'/);
  // e a varredura nao tem ramo para ela
  assert.doesNotMatch(SQL, /v_policy\.table_name = 'selection_applications'/);
  // horizonte declarado passa a ser o que o job REALMENTE carrega (p_years := 5 -> 1825)
  assert.match(SQL, /retention_days = 1825/);
});

test('#1812 mig: o predicado de cada ramo sai da DESCRICAO da linha, sem qualificador inventado', () => {
  // "Notificacoes lidas com mais de 6 meses" -> o qualificador declarado e "lidas"
  assert.equal(conta(SQL, 'is_read = true AND created_at < v_cutoff'), 2, 'contagem seca + delete');
  // "Logs de anomalia com mais de 1 ano" -> SEM qualificador de resolucao
  assert.equal(conta(SQL, 'data_anomaly_log WHERE detected_at < v_cutoff'), 2);
  // "unconverted visitor leads" -> sem promocao a candidatura
  assert.equal(conta(SQL, 'promoted_at IS NULL AND created_at < v_cutoff'), 2);
});

test('#1812 mig: as colunas que mataram a funcao aposentada nao voltam', () => {
  // citava notifications.read (a coluna e is_read), data_anomaly_log.status (a tabela nao tem)
  // e selection_applications.applied_at (a coluna e application_date)
  assert.doesNotMatch(SQL, /WHERE read = true/);
  assert.doesNotMatch(SQL, /data_anomaly_log[\s\S]{0,120}status = 'resolved'/);
  assert.doesNotMatch(SQL, /applied_at/);
});

test('#1812 mig: a chamada nua CONTA, nao apaga', () => {
  assert.match(SQL, /_data_retention_sweep\(p_dry_run boolean DEFAULT true\)/);
  // e o cron e quem assume o risco, explicitamente
  assert.match(SQL, /_data_retention_sweep\(p_dry_run := false\)/);
});

test('#1812 mig: a varredura percorre TODAS as ativas, para nao confundir "nada a apagar" com "ninguem executa"', () => {
  assert.match(SQL, /FROM public\.data_retention_policy WHERE is_active = true ORDER BY table_name/);
  // politica de outro executor sai com handled=false e o motivo, nao com affected=0
  assert.match(SQL, /'handled',\s*v_handled/);
  assert.match(SQL, /'affected', CASE WHEN v_handled THEN v_affected ELSE NULL END/);
  assert.match(SQL, /v_reason := 'politica ativa sem executor declarado'/);
});

test('#1812 mig: o ratchet deriva o ramo do CATALOGO, nao de lista de nomes', () => {
  assert.match(SQL, /CREATE OR REPLACE FUNCTION public\._audit_retention_policy_coverage\(\)/);
  // procura a propria condicao de ramo no corpo VIVO da varredura — casar so o nome da tabela
  // daria falso positivo com qualquer mencao em comentario
  assert.match(SQL, /s\.prosrc ~ \('v_policy\\\.table_name = '''/);
  // dormencia do job conta como NAO coberta: e a verdade sobre a politica
  assert.match(SQL, /\(a\.job_registrado AND a\.job_ativo AND a\.ramo_implementado AND a\.horizonte_bate\)/);
  // \b no ARE do Postgres e BACKSPACE (licao do #1801)
  assert.doesNotMatch(SQL, /~ \([^)]*\\b/, 'no ARE do Postgres \\b e BACKSPACE, nao fronteira de palavra');
});

test('#1812 mig: as tres funcoes nascem fechadas (CREATE FUNCTION concede a PUBLIC)', () => {
  for (const fn of ['_data_retention_sweep\\(boolean\\)', '_data_retention_sweep_cron\\(\\)', '_audit_retention_policy_coverage\\(\\)']) {
    assert.match(SQL, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC, anon, authenticated`, 'i'), fn);
    assert.match(SQL, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn} TO service_role`, 'i'), fn);
  }
});

test('#1812 mig: a corrida inteira fica auditavel depois do fato', () => {
  assert.match(SQL, /'data_retention\.sweep', 'system'/);
  assert.match(SQL, /SELECT cron\.schedule\(\s*\n?\s*'data-retention-sweep-daily'/);
});

// ─── portao de DB ────────────────────────────────────────────────────────────────────────────────

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

/** Base declarada em 16/08/2026 — o ratchet so anda para BAIXO. */
const DESCOBERTAS_DECLARADAS = [
  'attendance/archive',
  'board_lifecycle_events/archive',
  'selection_applications/anonymize',
];

test('#1812 DB: RATCHET — as politicas descobertas sao exatamente a base declarada', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_retention_policy_coverage');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, 'o auditor precisa devolver TODAS as ativas (senao o guard esta cego)');

  assert.deepEqual(
    data.filter(r => !r.coberta).map(r => r.politica).sort(), DESCOBERTAS_DECLARADAS,
    'politica ativa sem executor exercivel. Uma tabela que declara politica que ninguem executa ' +
    'parece controle e nao e. Ou a politica ganha executor, ou sai da tabela — e se uma das tres ' +
    'da base foi resolvida, esta lista encolhe junto (o ratchet nao sobe).',
  );
});

test('#1812 DB: as tres politicas de delete estao cobertas de ponta a ponta', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_retention_policy_coverage');
  assert.ifError(error);

  const cobertas = data.filter(r => r.coberta);
  assert.deepEqual(
    cobertas.map(r => r.politica).sort(),
    ['data_anomaly_log/delete', 'notifications/delete', 'visitor_leads/delete'],
  );
  // coberta exige as quatro condicoes, nao so job registrado
  for (const r of cobertas) {
    assert.ok(r.job_registrado && r.job_ativo && r.ramo_implementado && r.horizonte_bate,
      `${r.politica} conta como coberta sem satisfazer as quatro condicoes`);
    assert.equal(r.motivo, null);
  }
});

test('#1812 DB: o motivo de cada descoberta e o motivo REAL, nao um rotulo generico', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_retention_policy_coverage');
  assert.ifError(error);
  const por = Object.fromEntries(data.map(r => [r.politica, r]));

  // as duas de archive: nao ha destino de arquivamento na plataforma (#1814)
  for (const p of ['attendance/archive', 'board_lifecycle_events/archive']) {
    assert.equal(por[p].executor, null);
    assert.match(por[p].motivo, /sem executor declarado/);
  }
  // a anonimizacao: o job existe e esta dormante por portao legal (SPEC #905 R1-R5)
  const anon = por['selection_applications/anonymize'];
  assert.equal(anon.executor, 'lgpd-anonymize-premember-monthly');
  assert.equal(anon.job_registrado, true);
  assert.equal(anon.job_ativo, false);
  assert.match(anon.motivo, /registrado porem INATIVO/);
  // e o horizonte declarado bate com o argumento do job (1825 = p_years := 5)
  assert.equal(anon.dias, 1825);
  assert.equal(anon.horizonte_bate, true);
});

test('#1812 DB: a varredura seca conta sem apagar, e nao finge executar o que nao e dela', { skip: dbGated ? false : skipMsg }, async () => {
  const antes = await sb().from('notifications').select('*', { count: 'exact', head: true });
  assert.ifError(antes.error);

  const { data, error } = await sb().rpc('_data_retention_sweep', { p_dry_run: true });
  assert.ifError(error);
  assert.equal(data.dry_run, true);

  const politicas = Object.fromEntries(data.policies.map(p => [`${p.table}/${p.type}`, p]));
  // as tres da varredura executam e reportam numero
  for (const p of ['notifications/delete', 'data_anomaly_log/delete', 'visitor_leads/delete']) {
    assert.equal(politicas[p].handled, true, p);
    assert.equal(typeof politicas[p].affected, 'number', p);
  }
  // as outras tres saem com handled=false e motivo — nunca com affected=0, que leria como cumprida
  for (const p of ['attendance/archive', 'board_lifecycle_events/archive', 'selection_applications/anonymize']) {
    assert.equal(politicas[p].handled, false, p);
    assert.equal(politicas[p].affected, null, `${p}: affected=0 leria como politica cumprida`);
    assert.ok(politicas[p].reason, `${p} precisa dizer POR QUE nao foi executada`);
  }

  const depois = await sb().from('notifications').select('*', { count: 'exact', head: true });
  assert.ifError(depois.error);
  assert.equal(depois.count, antes.count, 'modo seco nao pode apagar linha');
});

test('#1812 DB: a varredura e o ratchet nao sao alcancaveis por chamador anonimo', { skip: dbGated ? false : skipMsg }, async () => {
  const anon = createClient(process.env.SUPABASE_URL, process.env.PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY ?? 'sem-chave', { auth: { persistSession: false } });
  for (const fn of ['_data_retention_sweep', '_data_retention_sweep_cron', '_audit_retention_policy_coverage']) {
    const { error } = await anon.rpc(fn);
    assert.ok(error, `${fn} respondeu a chamador anonimo — a varredura APAGA linhas`);
  }
});
