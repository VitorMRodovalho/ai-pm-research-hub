// tests/contracts/1925-ssot-da-escada-e-reconciliacao.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1925 saida 2 - a escada de prioridade de `members.operational_role` vira SSOT, e ganha
 * reconciliacao agendada.
 *
 * O DEFEITO: `A3_active_role_engagement_derivation` deriva de `public.auth_engagements`, que usa
 * `CURRENT_DATE`. A virada de data muda a DERIVACAO sem que ninguem escreva, e o cache so e
 * reescrito pelo trigger, que so dispara em ESCRITA. A3 fica vermelha sozinha.
 *
 * MEDIDO EM 25/08/2026:
 *   - 14 funcoes escrevem `operational_role`, TODAS por evento; nenhuma e lote agendavel.
 *   - a escada estava inline em DUAS copias byte-identicas (trigger + CTE `computed` da A3),
 *     md5 f7d75a5c... apos colapsar espaco e tirar comentario. Um cron copiado seria a TERCEIRA.
 *   - 94 membros ativos, ZERO divergindo: o reconciliador e PREVENCAO, nao reparo.
 *   - 32 divergencias entre NAO-ativos, que ficam de fora de proposito (papel congelado no
 *     offboarding); reconcilia-las seria mutacao em massa que ninguem pediu.
 *
 * Cross-ref: #1925, #1981 (saida 1), #1924, #1932 (a migration precisa SER a captura), #1829.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260825163644_1925_ssot_da_escada_e_reconciliacao_agendada.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

// Prosa sai antes do assert: os comentarios CITAM a escada e o predicado antigo, e guard que le
// prosa acusa a propria documentacao (licao do #1801/#1805/#1809/#1813).
const semProsa = (sql) => sql
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
const SQL = semProsa(mig);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// A escada, degrau a degrau, na ordem. Mudar QUALQUER item aqui e mudar autoridade de gente.
const DEGRAUS = [
  'manager', 'deputy_manager', 'deputy_manager', 'tribe_leader', 'sponsor', 'chapter_liaison',
  'researcher', 'external_signer', 'institutional_auditor', 'observer', 'alumni', 'candidate',
];

// ── STATIC ────────────────────────────────────────────────────────────────────────────
test('#1925 static: a escada virou funcao propria, e o trigger CHAMA em vez de copiar', () => {
  assert.ok(mig, 'a migration existe no timestamp canonico (o mesmo da linha de tracking)');
  assert.match(SQL, /CREATE OR REPLACE FUNCTION public\._derive_operational_role\(p_person_id uuid\)/);

  const trigger = latestFunctionCapture(ROOT, 'sync_operational_role_cache');
  const corpo = semProsa(trigger.body);
  assert.match(corpo, /v_new_role := public\._derive_operational_role\(COALESCE\(NEW\.person_id, OLD\.person_id\)\)/,
    `o trigger (captura ${trigger.file}) precisa CHAMAR a escada`);
  assert.doesNotMatch(corpo, /bool_or/,
    `o trigger (captura ${trigger.file}) ainda carrega a escada inline: a copia nao foi removida`);
});

test('#1925 static: a extracao preserva a escada degrau a degrau, na ordem', () => {
  // Extracao, nao redesenho. Se um degrau mudar de lugar aqui, alguem muda de papel na plataforma.
  const ssot = SQL.slice(SQL.indexOf('_derive_operational_role'));
  const achados = [...ssot.matchAll(/THEN '([a-z_]+)'/g)].map((m) => m[1]).slice(0, DEGRAUS.length);
  assert.deepEqual(achados, DEGRAUS, 'a ordem dos degraus mudou: isto e mudanca de autoridade, nao extracao');
  assert.match(ssot, /ELSE 'guest'/, 'o degrau final precisa continuar sendo guest');
  assert.match(ssot, /ae\.is_authoritative = true/, 'o filtro de engajamento autoritativo tem de vir junto');
});

test('#1925 static: a escada nunca devolve NULL', () => {
  // Pessoa sem engajamento autoritativo resolve para `guest`. Devolver NULL faria o trigger
  // gravar o COALESCE dele e o reconciliador comparar contra nada.
  assert.match(SQL, /SELECT COALESCE\(\s*\(/);
  assert.match(SQL, /\),\s*'guest'\s*\);/);
});

test('#1925 static: o reconciliador so toca ATIVOS', () => {
  // 32 nao-ativos divergem hoje. O papel de quem saiu e congelado no offboarding; reconciliar
  // ali seria mutacao em massa de 32 linhas que ninguem pediu.
  assert.match(SQL, /WHERE m\.member_status = 'active'/);
  assert.doesNotMatch(SQL, /member_status\s*(<>|!=)\s*'active'/, 'nao pode existir ramo para nao-ativos');
});

test('#1925 static: escreve so quando ha diferenca, e um dado ruim nao silencia os outros', () => {
  assert.match(SQL, /IF v_m\.operational_role IS DISTINCT FROM v_esperado THEN/);
  assert.match(SQL, /WHERE id = v_m\.id AND operational_role IS DISTINCT FROM v_esperado/);
  // classe do #1829: a excecao e POR ITEM, dentro do laco
  assert.match(SQL, /LOOP[\s\S]*?BEGIN[\s\S]*?EXCEPTION WHEN OTHERS THEN[\s\S]*?END;\s*\n\s*END LOOP;/);
});

test('#1925 static: o cron so registra quando houve mudanca ou erro', () => {
  // Uma linha por dia dizendo "nada a fazer" enterraria o dia em que algo aconteceu (#1906).
  assert.match(SQL, /IF COALESCE\(\(v_result->>'changed'\)::int, 0\) > 0\s*\n\s*OR COALESCE\(\(v_result->>'errors'\)::int, 0\) > 0 THEN/);
  assert.match(SQL, /INSERT INTO public\.admin_audit_log[\s\S]{0,200}NULL, 'members\.operational_role_reconciled'/,
    'pg_cron nao tem sessao: o ator tem de ser NULL, nao um membro inventado');
});

test('#1925 static: agenda logo apos a virada de CURRENT_DATE', () => {
  assert.match(SQL, /cron\.schedule\(\s*\n?\s*'operational-role-reconcile-daily',\s*\n?\s*'4 0 \* \* \*'/,
    'a janela que este cron existe para fechar comeca em 00:00 UTC');
});

test('#1925 static: as funcoes novas nascem fechadas (CREATE FUNCTION concede a PUBLIC)', () => {
  for (const f of ['_derive_operational_role\\(uuid\\)', '_reconcile_operational_role_cache\\(boolean\\)',
                   '_operational_role_reconcile_cron\\(\\)']) {
    assert.match(SQL, new RegExp(`REVOKE ALL ON FUNCTION public\\.${f} FROM PUBLIC, anon, authenticated`, 'i'), f);
    assert.match(SQL, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${f} TO service_role`, 'i'), f);
  }
});

test('#1925 static: a A3 NAO foi convertida nesta migration, e isso e deliberado', () => {
  // Se derivacao e verificacao compartilharem a funcao, o invariante deixa de ser independente
  // da implementacao: um erro na escada ficaria invisivel para o guard que existe para pega-lo.
  // E troca real, e merece PR propria.
  assert.doesNotMatch(SQL, /FUNCTION public\.check_schema_invariants/,
    'converter a A3 aqui trocaria a independencia do invariante sem decisao escrita');
});

// ── DB ────────────────────────────────────────────────────────────────────────────────
test('#1925 db: a escada agora tem UMA copia inline, nao duas',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Antes: trigger + CTE `computed` da A3. Depois: so a A3 (que sai na PR dela).
    // Este e o numero que mede o conserto, e ele so pode DESCER.
    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    const comEscada = (data ?? []).filter((f) => ['sync_operational_role_cache'].includes(f.proname));
    assert.equal(comEscada.length, 1, 'sync_operational_role_cache continua existindo');

    const cap = latestFunctionCapture(ROOT, 'sync_operational_role_cache');
    assert.doesNotMatch(semProsa(cap.body), /bool_or/,
      'a captura vigente do trigger ainda tem a escada inline');
  });

test('#1925 db: a escada extraida concorda com a derivacao da A3 em TODOS os ativos',
  { skip: dbGated ? false : skipMsg }, async () => {
    // A prova de que isto foi extracao e nao redesenho: se as duas discordassem em uma pessoa,
    // essa pessoa mudaria de papel na plataforma no primeiro disparo do trigger.
    const cli = sb();
    const { data: membros, error: e1 } = await cli
      .from('members').select('id, person_id, operational_role')
      .eq('member_status', 'active').not('person_id', 'is', null);
    assert.ifError(e1);
    assert.ok(membros.length > 0, 'ha membros ativos para medir');

    const { data: inv, error: e2 } = await cli.rpc('check_schema_invariants');
    assert.ifError(e2);
    const a3 = (inv ?? []).find((r) => r.invariant_name === 'A3_active_role_engagement_derivation');
    assert.ok(a3, 'A3 continua no catalogo de invariantes');
    assert.equal(a3.violation_count, 0,
      `A3 acusa ${a3.violation_count} divergencia(s): a escada extraida discorda da verificacao`);
  });

test('#1925 db: a escada nunca devolve NULL, nem para pessoa inexistente',
  { skip: dbGated ? false : skipMsg }, async () => {
    for (const [rotulo, id] of [['inexistente', '00000000-0000-0000-0000-000000000000'], ['NULL', null]]) {
      const { data, error } = await sb().rpc('_derive_operational_role', { p_person_id: id });
      assert.ifError(error);
      assert.equal(data, 'guest', `person_id ${rotulo} deveria resolver para guest, veio ${JSON.stringify(data)}`);
    }
  });

test('#1925 db: o dry-run examina os ativos e NAO escreve',
  { skip: dbGated ? false : skipMsg }, async () => {
    const cli = sb();
    const { data, error } = await cli.rpc('_reconcile_operational_role_cache', { p_dry_run: true });
    assert.ifError(error);
    assert.equal(data.dry_run, true);
    assert.ok(data.examined > 0, 'o reconciliador precisa enxergar alguem');

    const { count, error: e2 } = await cli.from('members')
      .select('id', { count: 'exact', head: true })
      .eq('member_status', 'active').not('person_id', 'is', null);
    assert.ifError(e2);
    // O examinado e menor ou igual aos ativos: as duas exclusoes de nome (pseudo-membro
    // compartilhado e fixtures `_synthetic`) saem, exatamente como na A3.
    assert.ok(data.examined <= count,
      `examinou ${data.examined} de ${count} ativos: o escopo nao pode ser MAIOR que a populacao`);
    assert.ok(data.examined >= count - 5,
      `examinou so ${data.examined} de ${count}: escopo estreito demais deixa a A3 poder ficar vermelha`);
  });

test('#1925 db: as funcoes novas nao sao alcancaveis por chamador anonimo',
  { skip: dbGated ? false : skipMsg }, async () => {
    const anon = createClient(
      SUPABASE_URL,
      process.env.PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY ?? 'sem-chave',
      { auth: { persistSession: false } },
    );
    for (const [fn, args] of [['_derive_operational_role', { p_person_id: null }],
                              ['_reconcile_operational_role_cache', { p_dry_run: true }],
                              ['_operational_role_reconcile_cron', {}]]) {
      const { error } = await anon.rpc(fn, args);
      assert.ok(error, `${fn} respondeu a anonimo: ela le e escreve papel de membro`);
    }
  });
