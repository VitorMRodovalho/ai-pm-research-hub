/**
 * Contract: #1961 — a suíte DB-aware escreve em produção e não pode ter dois escritores.
 *
 * O que a medição de 24/08/2026 mostrou, e que enquadra este arquivo:
 *
 *  • Duas sessões locais + a CI escrevendo ao mesmo tempo produzem TIMEOUT, e timeout se lê
 *    como defeito. O mesmo teste (`ADR-0012 B10: schema invariants report`) foi de
 *    **234.009 ms**, reprovando com Postgres `57014`, para **232,6 ms** só por rodar isolado.
 *    Numa PR que alterava UMA linha de `.gitignore`.
 *  • A defesa que já existia (`concurrency` do #1505 no `ci.yml`) é chaveada por `github.ref`,
 *    então serializa apenas o MESMO ref: nos últimos 30 runs, 7 de 9 sobreposições eram de
 *    refs diferentes. E YAML nenhum alcança duas sessões locais na mesma máquina.
 *
 * ⚠️ Por que WRAPPER e não preload (`--import`): `node --test` cria um processo filho POR
 * ARQUIVO, e o `--import` roda dentro de cada filho — nem `globalThis` atravessa. Com 324
 * arquivos, um lease no preload seria adquirido 324 vezes e não seguraria a rodada.
 *
 * ⚠️ Por que tabela e não `pg_advisory_lock`: lock de sessão morre com a conexão, e sobre
 * PostgREST cada request pega uma do pool. Seria solto na hora.
 *
 * Cross-ref: #1961, #1505 (a issue fechada cuja mitigação não cobria refs diferentes),
 * #1963 (a contenção que sobra DENTRO de uma rodada só, causa ainda em aberto).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260824213839_1961_lease_de_rodada_da_suite_db_aware.sql');
const WRAPPER = resolve(ROOT, 'scripts/with-db-lease.mjs');

const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const wrapper = existsSync(WRAPPER) ? readFileSync(WRAPPER, 'utf8') : '';
const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8'));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const PROBE = 'probe_1961_contract';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
async function purge(sb) {
  // filtro por COLUNA de chave, nunca sem WHERE.
  await sb.from('test_suite_leases').delete().eq('source', PROBE);
}

// ── STATIC: a migration ───────────────────────────────────────────────────────────────
test('#1961 static: a aquisição é ATÔMICA — o predicado vive no ON CONFLICT, não num SELECT antes', () => {
  assert.ok(mig, 'migration existe no timestamp canônico');
  assert.match(mig, /ON CONFLICT \(source\) DO UPDATE/);
  // o ponto todo: ler "expirado" e depois escrever é janela para dois entrarem.
  assert.match(mig, /WHERE public\.test_suite_leases\.expires_at <= now\(\)\s*\n?\s*OR public\.test_suite_leases\.holder = EXCLUDED\.holder/);
  assert.doesNotMatch(
    mig,
    /SELECT[\s\S]{0,200}FROM public\.test_suite_leases[\s\S]{0,200}IF[\s\S]{0,80}expires_at[\s\S]{0,40}THEN[\s\S]{0,200}INSERT/,
    'a decisão não pode ser um SELECT seguido de INSERT — isso reabre a corrida',
  );
});

test('#1961 static: release casa o HOLDER — uma rodada nunca solta o lease de outra', () => {
  assert.match(mig, /DELETE FROM public\.test_suite_leases WHERE source = p_source AND holder = p_holder/);
});

test('#1961 static: as duas RPCs nascem NEGADAS (CREATE FUNCTION abre para PUBLIC)', () => {
  for (const fn of ['acquire_test_suite_lease', 'release_test_suite_lease']) {
    // `\s+` e não ` `: as linhas são alinhadas com espaços, e uma regex de espaço único
    // reprova por formatação em vez de por ausência do REVOKE.
    assert.match(mig, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([^)]*\\)\\s+FROM PUBLIC, anon, authenticated`));
    assert.match(mig, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\([^)]*\\)\\s+TO service_role`));
  }
});

test('#1961 static: a tabela tem RLS ligada', () => {
  assert.match(mig, /ALTER TABLE public\.test_suite_leases ENABLE ROW LEVEL SECURITY/);
});

// ── STATIC: o wrapper e o wiring ──────────────────────────────────────────────────────
test('#1961 static: `test:behavioural` passa pelo wrapper, e a lista de arquivos sobrevive', () => {
  const s = pkg.scripts['test:behavioural'];
  assert.ok(s.startsWith('node scripts/with-db-lease.mjs -- '), 'o balde comportamental é embrulhado');
  assert.ok((s.match(/\.test\.mjs/g) || []).length > 300, 'a lista de arquivos continua inteira');
});

test('#1961 static: falta de lease NÃO reprova — contenção não pode virar vermelho', () => {
  assert.ok(wrapper, 'wrapper existe');
  // A decisão: sem lease a rodada segue, com aviso que NOMEIA quem está no banco.
  assert.match(wrapper, /RODANDO SEM LEASE/);
  assert.doesNotMatch(
    wrapper,
    /if \(!adquirido\)[\s\S]{0,120}process\.exit\([1-9]/,
    'não sair com erro por não conseguir o lease',
  );
});

test('#1961 static: o wrapper propaga o código de saída do comando', () => {
  // `npm test | tail` já devolveu exit 0 com falhas dentro neste repo. O wrapper não repete.
  assert.match(wrapper, /child\.on\('exit'/);
  assert.match(wrapper, /process\.exit\(code\)/);
});

// ── DB: o comportamento, exercido ─────────────────────────────────────────────────────
test('#1961 db: dois donos não coexistem, e o segundo aprende QUEM está no banco',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    await purge(sb);
    try {
      const { data: a } = await sb.rpc('acquire_test_suite_lease', { p_source: PROBE, p_holder: 'A', p_ttl_minutes: 5 });
      assert.equal(a.acquired, true, 'A pega o lease livre');

      const { data: b } = await sb.rpc('acquire_test_suite_lease', { p_source: PROBE, p_holder: 'B', p_ttl_minutes: 5 });
      assert.equal(b.acquired, false, 'B é recusado enquanto A segura');
      assert.equal(b.holder, 'A', 'a recusa NOMEIA o detentor — sem isso a espera é cega');

      const { data: renova } = await sb.rpc('acquire_test_suite_lease', { p_source: PROBE, p_holder: 'A', p_ttl_minutes: 5 });
      assert.equal(renova.acquired, true, 'o mesmo dono renova em vez de se bloquear');

      const { data: roubo } = await sb.rpc('release_test_suite_lease', { p_source: PROBE, p_holder: 'B' });
      assert.equal(roubo.released, false, 'B não solta o lease de A');

      const { data: solta } = await sb.rpc('release_test_suite_lease', { p_source: PROBE, p_holder: 'A' });
      assert.equal(solta.released, true);

      const { data: c } = await sb.rpc('acquire_test_suite_lease', { p_source: PROBE, p_holder: 'B', p_ttl_minutes: 5 });
      assert.equal(c.acquired, true, 'liberado, o próximo entra');
    } finally {
      await purge(sb);
    }
  });

test('#1961 db: lease EXPIRADO é tomado — rodada morta não trava a fila para sempre',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    await purge(sb);
    try {
      await sb.rpc('acquire_test_suite_lease', { p_source: PROBE, p_holder: 'morta', p_ttl_minutes: 1 });
      // envelhece a linha em vez de esperar o TTL
      const passado = new Date(Date.now() - 60_000).toISOString();
      const { error } = await sb.from('test_suite_leases').update({ expires_at: passado }).eq('source', PROBE);
      assert.ifError(error);

      const { data } = await sb.rpc('acquire_test_suite_lease', { p_source: PROBE, p_holder: 'nova', p_ttl_minutes: 5 });
      assert.equal(data.acquired, true, 'expirado é tomado');
      assert.equal(data.holder, 'nova');

      const { data: linha } = await sb.from('test_suite_leases').select('holder').eq('source', PROBE).single();
      assert.equal(linha.holder, 'nova', 'a linha reflete o novo dono (ler em statement separado, não no mesmo snapshot)');
    } finally {
      await purge(sb);
    }
  });

const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const anonGated = !!(SUPABASE_URL && ANON_KEY);

test('#1961 db: anon é RECUSADO nas duas RPCs — exercido, não lido do catálogo',
  { skip: anonGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_ANON_KEY required' }, async () => {
    const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });

    // CONTROLE POSITIVO: o client anon funciona para algo que ele PODE fazer. Sem isto,
    // uma chave inválida faria as duas asserções abaixo passarem por motivo errado.
    const { error: vivo } = await anon.rpc('get_public_platform_stats');
    assert.equal(vivo, null, `o client anon precisa estar vivo (controle positivo): ${vivo?.message}`);

    for (const fn of ['acquire_test_suite_lease', 'release_test_suite_lease']) {
      const { error } = await anon.rpc(fn, { p_source: PROBE, p_holder: 'anon', p_ttl_minutes: 1 });
      assert.ok(error, `${fn} deve recusar anon`);
      assert.match(
        `${error.code ?? ''} ${error.message ?? ''}`,
        /42501|PGRST202|permission denied|Could not find the function/i,
        `${fn}: recusa esperada por permissão, veio "${error.code}: ${error.message}"`,
      );
    }
  });
