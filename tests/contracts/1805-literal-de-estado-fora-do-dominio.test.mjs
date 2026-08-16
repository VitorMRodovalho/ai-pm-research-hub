// tests/contracts/1805-literal-de-estado-fora-do-dominio.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C / #1109) — an unwired contract file is silently skipped.
/**
 * #1805 — literal de estado fora do dominio do CHECK: o ramo nao erra, ele nunca casa.
 *
 * Classe irma da #1801 e distinta dela: la o defeito era ORDENAR por `created_at`; aqui e
 * COMPARAR contra um literal que o CHECK da coluna nao admite. O predicado fica calado — nao
 * levanta erro, nao aparece em log, so deixa de alcancar linhas.
 *
 * Medido em 16/08/2026 por ensaio em transacao abortada (o GP avanca o ciclo), nao por inspecao:
 *
 *   | cenario                                     | antes | depois |
 *   |---------------------------------------------|------:|-------:|
 *   | PERT, ciclo em `applications_open`          |     0 |      1 |  ciclos
 *   | calibracao semanal, ciclo em `evaluation`   |     2 |      3 |  ciclos
 *   | consistencia diaria, ciclo em `evaluation`  |     0 |     81 |  candidaturas
 *
 * A varredura saiu do CATALOGO, nao da lista da issue: a issue nomeava 3 funcoes e o catalogo
 * tinha 4 — `approve_selection_application` nao estava na lista de ninguem.
 *
 * ALCANCE DO RATCHET, declarado de proposito: `_audit_state_literal_domain` cobre apenas colunas
 * cujo NOME pertence a UMA UNICA tabela em public. A ambiguidade de alias e sobre a TABELA, e o
 * nome da coluna esta no texto; quando o nome tem dono unico, alias nenhum muda a resposta.
 * `status` (~50 tabelas, dominios proprios) fica FORA: varrer por regex ali deu 58 candidatos,
 * quase todos com o literal pertencendo a uma tabela vizinha. Os dois casos de `status` desta
 * issue entraram por LEITURA do corpo, e por isso tem asserts de texto aqui em vez de ratchet.
 *
 * Linha de base do ratchet: ZERO. Nao ha excecao a manter.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ler = f => readFileSync(resolve(process.cwd(), 'supabase/migrations', f), 'utf8');
const MIG_A = ler('20260816040023_1805_literal_de_estado_fora_do_dominio.sql');
const MIG_B = ler('20260816040153_1805_approve_selection_application_ramo_morto.sql');

/**
 * So o SQL EXECUTAVEL. O cabecalho e os comentarios de corpo CITAM os literais que estao sendo
 * removidos — e obrigatorio que citem, senao a migration nao explica o que corrigiu. Guard que le
 * prosa acusa a propria documentacao (licao do #1801), entao prosa sai antes do assert.
 */
const soSql = m => m
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

const SQL_A = soSql(MIG_A);
const SQL_B = soSql(MIG_B);

test('#1805 mig: o cron de PERT alcanca o ciclo com inscricoes abertas', () => {
  assert.match(
    SQL_A,
    /WHERE phase IN \('evaluating', 'interviews', 'applications_open'\)/,
    'o literal precisa ser applications_open, o valor real do dominio de phase',
  );
  assert.doesNotMatch(SQL_A, /'open_apps'/, 'open_apps nao existe no dominio de phase');
});

test('#1805 mig: a calibracao semanal exprime a intencao (tudo menos rascunho), nao a lista de hoje', () => {
  assert.match(SQL_A, /WHERE status <> 'draft'/, 'o predicado precisa excluir apenas o rascunho');
  // os dois literais que eram vocabulario de outra coluna nao podem voltar
  assert.doesNotMatch(SQL_A, /status IN \('open', 'evaluating', 'decided', 'closed'\)/);
});

test('#1805 mig: a consistencia enxerga o ciclo em avaliacao, em TODAS as ocorrencias', () => {
  // seis no relatorio + uma no cron; uma delas tinha indentacao diferente e escapou da 1a passada.
  const novas = SQL_A.match(/c\.status NOT IN \('draft','closed'\)/g) || [];
  assert.equal(novas.length, 7, `esperava 7 ocorrencias do predicado novo, achei ${novas.length}`);
  assert.doesNotMatch(SQL_A, /status IN \('open','active'\)/, "'active' nao existe no dominio de status de selection_cycles");
  assert.match(SQL_A, /'all running cycles \(not draft\/closed\)'/, 'o escopo relatado precisa dizer a verdade');
});

test('#1805 mig: o ramo morto de role_applied saiu, e `both` segue como estava', () => {
  assert.match(SQL_B, /WHEN v_app\.role_applied IN \('leader', 'researcher', 'manager'\) THEN v_app\.role_applied/);
  assert.doesNotMatch(SQL_B, /'coordinator'/, 'coordinator nao existe no dominio de role_applied');
  // a correcao e de literal morto; mudar o destino de 'both' seria decisao de produto.
  assert.match(SQL_B, /ELSE 'researcher'\s*\n\s*END;/, "o ELSE preexistente nao pode ter mudado junto");
});

test('#1805 mig: o ratchet e derivado do catalogo, nao de lista de nomes', () => {
  assert.match(SQL_A, /CREATE OR REPLACE FUNCTION public\._audit_state_literal_domain\(\)/);
  // a cobertura sai de pg_class/pg_attribute/pg_constraint, e a condicao de solidez e o dono unico
  assert.match(SQL_A, /FROM pg_class c\s*\n\s*JOIN pg_namespace n/);
  assert.match(SQL_A, /GROUP BY col\s*\n\s*HAVING count\(\*\) = 1/, 'a solidez vem de "o nome da coluna tem dono unico"');
  // \y (fronteira de palavra), nunca \b, que no ARE do Postgres e BACKSPACE (licao do #1801)
  assert.doesNotMatch(SQL_A, /regexp_matches\([^)]*\\b/, 'no ARE do Postgres \\b e BACKSPACE; fronteira de palavra e \\y');
  assert.match(SQL_A, /\\y\(\[a-z_\]\[a-z0-9_\]\{0,62\}\)/, 'a varredura precisa usar \\y e quantificador limitado');
});

test('#1805 mig: a auditoria nasce fechada (CREATE FUNCTION concede a PUBLIC)', () => {
  assert.match(SQL_A, /REVOKE ALL ON FUNCTION public\._audit_state_literal_domain\(\) FROM PUBLIC, anon, authenticated/i);
  assert.match(SQL_A, /GRANT EXECUTE ON FUNCTION public\._audit_state_literal_domain\(\) TO service_role/i);
});

// ─── portao de DB ────────────────────────────────────────────────────────────────────────────────

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1805 DB: RATCHET — nenhum literal de estado fora do dominio (linha de base ZERO)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_state_literal_domain');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, 'o auditor precisa devolver linhas (senao o guard esta cego)');

  const violam = data.filter(r => r.fora_do_dominio);
  assert.deepEqual(
    violam.map(r => `${r.funcao}(${r.args}): ${r.tabela_dona}.${r.coluna} = '${r.literal}'`), [],
    'literal comparado contra uma coluna cujo CHECK nao o admite. O ramo nunca casa, e nao levanta ' +
    'erro: confira o dominio com pg_get_constraintdef antes de escrever o literal.',
  );
});

test('#1805 DB: o ratchet tem alcance real (nao esta olhando para meia duzia de linhas)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_state_literal_domain');
  assert.ifError(error);
  const colunas = new Set(data.map(r => r.coluna));
  const funcoes = new Set(data.map(r => r.funcao));
  // medido em 16/08/2026: 262 pares, 38 colunas, 151 funcoes. Piso folgado — o catalogo cresce.
  assert.ok(colunas.size >= 20, `cobertura caiu para ${colunas.size} colunas (esperado >= 20)`);
  assert.ok(funcoes.size >= 80, `cobertura caiu para ${funcoes.size} funcoes (esperado >= 80)`);
  // e `phase` precisa estar coberta: e a coluna do defeito que abriu a issue.
  assert.ok(colunas.has('phase'), 'phase saiu da cobertura do ratchet');
});

test('#1805 DB: o relatorio de consistencia declara o escopo novo pelo caminho real', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('selection_consistency_report', { p_cycle_id: null });
  assert.ifError(error);
  assert.equal(
    data.scope, 'all running cycles (not draft/closed)',
    'o escopo relatado tem de acompanhar o predicado; era "all open/active cycles" com active morto',
  );
});
