/**
 * Tabelas de financas: leitura direta exige a capacidade de financas (view_finance).
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a policy de leitura mais nova de cada tabela exige rls_can('view_finance') junto do escopo da
 *      organizacao (ou superadmin), e nenhuma policy permissiva de leitura sem a capacidade sobra;
 *   B. a escrita e revogada da borda, com pos-condicao pelo efeito e sobre as policies;
 *   C. nenhum codigo de tela, Edge Function ou script le ou escreve nessas tabelas direto.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const TABLES = ['cost_entries', 'revenue_entries', 'sustainability_kpi_targets'];
const sqls = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => ({ f, sql: maskLineComments(readFileSync(join(DIR, f), 'utf8')) }));

for (const t of TABLES) {
  test(`A. ${t}: a policy de leitura vigente exige view_finance`, () => {
    // estado vigente das policies da tabela, aplicando CREATE/DROP na ordem das migrations
    const live = new Map();
    const re = new RegExp(`(CREATE POLICY\\s+("?[A-Za-z_ ]+"?)\\s+ON\\s+(public\\.)?${t}\\b([^;]*);|DROP POLICY IF EXISTS\\s+("?[A-Za-z_ ]+"?)\\s+ON\\s+(public\\.)?${t}\\b)`, 'gi');
    for (const { sql } of sqls) {
      for (const m of sql.matchAll(re)) {
        if (m[2]) live.set(m[2].replace(/"/g, ''), m[4]);
        else live.delete(m[5].replace(/"/g, ''));
      }
    }
    const reads = [...live.entries()].filter(([, body]) => /FOR\s+(SELECT|ALL)\b/i.test(body) && !/AS\s+RESTRICTIVE/i.test(body));
    assert.ok(reads.length >= 1, `${t}: nenhuma policy de leitura vigente`);
    for (const [name, body] of reads) {
      assert.match(body,
        /USING\s*\(\s*public\.rls_is_superadmin\(\)\s+OR\s*\(\s*organization_id = public\.auth_org\(\) AND public\.rls_can\('view_finance'\)\s*\)\s*\)/,
        `${t}.${name}: leitura exige view_finance na organizacao`);
    }
  });
}

test('B. escrita revogada da borda, com pos-condicoes que falham a migration', () => {
  const touch = /REVOKE[^;]*\bON TABLE[^;]*\bcost_entries\b/i;
  let last = null;
  for (const m of sqls) if (touch.test(m.sql)) last = m;
  assert.ok(last, 'nenhuma migration revoga a escrita das tabelas de financas');
  const revoke = last.sql.match(/REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE([^;]*)\s+FROM PUBLIC, anon, authenticated;/);
  assert.ok(revoke, 'REVOKE da escrita');
  for (const t of TABLES) assert.match(revoke[1], new RegExp(`\\bpublic\\.${t}\\b`), `${t} no REVOKE`);
  assert.match(last.sql, /WHERE has_table_privilege\(r\.rol, t\.tbl, p\.priv\)[\s\S]*?\) THEN\s+RAISE EXCEPTION 'financas: escrita da borda/, 'pos-condicao pelo efeito');
  assert.match(last.sql, /AND coalesce\(p\.qual, ''\) NOT LIKE '%view_finance%'\)[\s\S]*?<> 3 THEN\s+RAISE EXCEPTION 'financas: policy de leitura sem a capacidade/, 'pos-condicao sobre as policies');
});

function walk(dir, out = []) {
  for (const e of readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|astro|mjs|js)$/.test(e)) out.push(p);
  }
  return out;
}

test('C. nenhum codigo le ou escreve nas tabelas de financas direto (so pelas RPCs)', () => {
  const re = new RegExp(`\\.from\\(\\s*['"\`](${TABLES.join('|')})['"\`]\\s*\\)`);
  const offenders = [];
  for (const base of ['src', 'supabase/functions', 'scripts']) {
    for (const f of walk(resolve(ROOT, base))) if (re.test(maskJsComments(readFileSync(f, 'utf8')))) offenders.push(f.replace(ROOT + '/', ''));
  }
  assert.deepEqual(offenders, []);
});
