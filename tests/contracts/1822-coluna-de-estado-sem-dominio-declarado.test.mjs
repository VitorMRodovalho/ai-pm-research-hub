// tests/contracts/1822-coluna-de-estado-sem-dominio-declarado.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C / #1109) — an unwired contract file is silently skipped.
/**
 * #1822 — a coluna de estado SEM DOMINIO DECLARADO, a terceira face da classe do #1805/#1809.
 *
 * O #1805 (dono unico) e o #1809 (nome compartilhado) provam que o literal escrito por uma funcao
 * casa com o dominio DECLARADO da coluna. Onde nao ha dominio declarado nao ha contra o que comparar,
 * e o par nao chega a produzir linha: nenhum dos dois alcanca, e um literal errado ali e silencioso
 * para sempre.
 *
 * Como apareceu: medindo o ponto cego declarado do #1809 (funcao que referencia duas ou mais relacoes
 * com a mesma coluna sai da cobertura). Medido em 16/08/2026, o ponto cego tem 377 pares em 294
 * funcoes; 91 sem nenhuma relacao com dominio, 48 com exatamente uma, 238 com duas ou mais. Os 48
 * pareciam recuperaveis contando so relacoes com dominio — ensaiado, deu 51 violacoes e ZERO defeitos,
 * todas misatribuicao: `type = 'selection_approved'` debitado de `certificates` e `kind = 'volunteer'`
 * de `member_emails`, porque `notifications.type` e `engagements.kind` nao tem CHECK nenhum e sobrava
 * so o homonimo com dominio para levar a culpa. O `count(DISTINCT reloid) = 1` do #1809 e o que
 * protege contra isso; o resto daquela classe so sai por resolucao por STATEMENT.
 *
 * Este ratchet nao olha para funcao nenhuma. Olha para o catalogo.
 *
 * DUAS DECISOES DE PREDICADO, ambas medidas:
 *   (a) Dominio conta em DUAS formas, porque o Postgres imprime as duas: `= ANY (ARRAY[...])` e a
 *       igualdade simples a um literal, que e dominio de tamanho 1. `event_guest_certificates.type`
 *       e `CHECK ((type = 'event_participation'))` e saia da base indevidamente.
 *   (b) O trigger de tabela e DEVOLVIDO mas nao entra no predicado. Trigger e de tabela, nao de
 *       coluna, e nao prova que aquela coluna e validada. Se contasse, a base cairia quando a tabela
 *       ganhasse um trigger nao relacionado — progresso aparente sem nada guardado.
 *
 * Linha de base: 56, medida em 16/08/2026. So encolhe. Declarar dominio sobre dado vivo e mudanca de
 * schema com risco proprio (o ensaio deste ratchet bateu em `pilots.status` na primeira tentativa),
 * entao a triagem de quais das 56 merecem dominio e decisao de produto, nao deste teste.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations', '20260816225830_1822_ratchet_de_dominio_nao_declarado.sql'),
  'utf8',
);

/**
 * So o SQL EXECUTAVEL. O COMMENT ON explica o predicado e por isso CITA as formas de CHECK que o
 * auditor aceita e recusa — guard que le prosa acusa a propria documentacao (licao do #1801/#1805),
 * e o filtro de `--` nao pega bloco COMMENT ON.
 */
const SQL = MIG
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

test('#1822 mig: o universo vem do CATALOGO, nao de lista de nomes', () => {
  // a lista da issue nunca e a classe (licao repetida em #1805, #1809 e #1801): o nome entra por
  // carregar dominio em alguma tabela, nao por estar num array escrito a mao
  assert.match(SQL, /nomes AS MATERIALIZED \(SELECT DISTINCT col FROM dominio\)/);
  assert.match(SQL, /JOIN nomes k ON k\.col = t\.col/);
  assert.doesNotMatch(SQL, /IN \('status', 'state', 'kind'/, 'lista de nomes a mao nao e catalogo');
});

test('#1822 mig: dominio conta nas DUAS formas que o Postgres imprime', () => {
  assert.match(SQL, /pg_get_constraintdef\(ct\.oid\) ~ '= ANY \\\(ARRAY\\\['/);
  // igualdade simples = dominio de tamanho 1 (event_guest_certificates.type)
  assert.match(SQL, /'\^CHECK \\\(\\\(' \|\| t\.col \|\| ' = ''\[\^''\]\+''::text\\\)\\\)\$'/);
});

test('#1822 mig: o trigger de tabela e devolvido mas NAO entra no predicado', () => {
  // devolvido como coluna informacional
  assert.match(SQL, /EXISTS \(SELECT 1 FROM pg_trigger tg WHERE tg\.tgrelid = t\.reloid AND NOT tg\.tgisinternal\)/);
  // o predicado da base usa apenas dominio e FK, ambos especificos da coluna
  const predicado = SQL.match(/NOT EXISTS \(SELECT 1 FROM dominio d[\s\S]*?FROM fk f WHERE f\.reloid = t\.reloid AND f\.col = t\.col\)/);
  assert.ok(predicado, 'predicado da base nao encontrado');
  assert.doesNotMatch(predicado[0], /tgisinternal/,
    'trigger e sinal de TABELA: no predicado, a base cairia quando a tabela ganhasse trigger nao relacionado');
});

test('#1822 mig: a auditoria nasce fechada (CREATE FUNCTION concede a PUBLIC)', () => {
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\._audit_undeclared_state_domain\(\) FROM PUBLIC, anon, authenticated/i);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\._audit_undeclared_state_domain\(\) TO service_role/i);
});

// ─── portao de DB ────────────────────────────────────────────────────────────────────────────────

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const BASE = 56; // medida em 16/08/2026 — so encolhe

test('#1822 DB: RATCHET — a base de coluna sem dominio declarado nao cresce', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_undeclared_state_domain');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, 'o auditor precisa devolver linhas (senao o guard esta cego)');

  const semDominio = data.filter(r => r.sem_dominio_declarado);
  assert.ok(
    semDominio.length <= BASE,
    `a base subiu de ${BASE} para ${semDominio.length}. Coluna de estado nova nasceu sem dominio ` +
    'declarado: nenhum ratchet do #1805/#1809 alcanca literal escrito nela, e um literal errado ali ' +
    'e silencioso para sempre. Declare CHECK (= ANY (ARRAY[...])) ou FK na coluna. Entraram: ' +
    semDominio.map(r => `${r.tabela}.${r.coluna}`).join(', '),
  );
});

test('#1822 DB: o ratchet devolve TODAS as examinadas, nao so as que violam', { skip: dbGated ? false : skipMsg }, async () => {
  // lista vazia tem de ser distinguivel de guard cego (licao do #1801/#1805/#1809)
  const { data, error } = await sb().rpc('_audit_undeclared_state_domain');
  assert.ifError(error);

  const comDominio = data.filter(r => r.tem_dominio_declarado);
  const nomes = new Set(data.map(r => r.coluna));
  // medido em 16/08/2026: 270 examinadas, 208 com dominio, 6 sem dominio mas com FK, 123 nomes. Piso folgado.
  assert.ok(data.length >= 240, `cobertura caiu para ${data.length} colunas examinadas (esperado >= 240)`);
  assert.ok(comDominio.length >= 180, `so ${comDominio.length} colunas com dominio (esperado >= 180)`);
  assert.ok(nomes.size >= 100, `cobertura caiu para ${nomes.size} nomes de estado (esperado >= 100)`);
  assert.ok(nomes.has('status') && nomes.has('state') && nomes.has('kind'),
    'status/state/kind precisam estar no universo examinado');
});

test('#1822 DB: FK conta como dominio declarado por outro caminho', { skip: dbGated ? false : skipMsg }, async () => {
  // engagements.kind nao tem CHECK que limite o conjunto (so duas condicionais que citam kinds), mas
  // tem FK — e foi essa falta de CHECK que fez o ensaio do ponto cego do #1809 debitar
  // `kind = 'volunteer'` de member_emails. Sem o ramo de FK, a base contaria colunas ja declaradas.
  const { data, error } = await sb().rpc('_audit_undeclared_state_domain');
  assert.ifError(error);

  const kind = data.find(r => r.tabela === 'engagements' && r.coluna === 'kind');
  assert.ok(kind, 'engagements.kind precisa estar entre as examinadas');
  assert.equal(kind.tem_fk, true, 'engagements.kind e declarada por FK');
  assert.equal(kind.sem_dominio_declarado, false, 'declarada por FK nao entra na base');
});

test('#1822 DB: as colunas mais escritas da base seguem sob vigilancia', { skip: dbGated ? false : skipMsg }, async () => {
  // se uma destas sair da base, foi porque ganhou dominio — e o ratchet acima aceita a queda.
  // O que este teste impede e ela sumir do UNIVERSO examinado (nome deixando de carregar dominio
  // em qualquer tabela apagaria a coluna da cobertura sem nada ter sido declarado).
  const { data, error } = await sb().rpc('_audit_undeclared_state_domain');
  assert.ifError(error);

  const examinadas = new Set(data.map(r => `${r.tabela}.${r.coluna}`));
  for (const alvo of ['notifications.type', 'persons.state', 'members.state', 'user_profiles.role']) {
    assert.ok(examinadas.has(alvo), `${alvo} saiu do universo examinado sem ter ganhado dominio`);
  }
});
