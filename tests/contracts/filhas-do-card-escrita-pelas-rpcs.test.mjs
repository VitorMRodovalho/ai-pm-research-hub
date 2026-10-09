/**
 * Tabelas do card: escrita somente pelas RPCs da plataforma.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a migration mais nova que mexe na escrita de cada tabela a revoga de PUBLIC, anon e
 *      authenticated (INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER), inclui a tabela no laco
 *      por coluna e na pos-condicao pelo efeito, e nenhuma posterior devolve a escrita (nem por
 *      GRANT da tabela nem por GRANT amplo do schema);
 *   B. nenhum codigo de tela, Edge Function ou script escreve nessas tabelas direto.
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
const TABLES = ['board_item_assignments', 'board_item_checklists', 'board_item_tag_assignments',
  'board_item_event_links', 'board_lifecycle_events', 'curation_review_log'];
const sqls = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => ({ f, sql: maskLineComments(readFileSync(join(DIR, f), 'utf8')) }));
const SCHEMA_WIDE = /\b(GRANT\s+[^;]*\bON\s+ALL\s+TABLES\s+IN\s+SCHEMA\s+public\b[^;]*\bTO\b[^;]*\b(authenticated|anon|PUBLIC)\b|ALTER\s+DEFAULT\s+PRIVILEGES[^;]*\bGRANT\b[^;]*\bTO\b[^;]*\b(authenticated|anon|PUBLIC)\b)/i;

for (const t of TABLES) {
  test(`A. ${t}: escrita revogada da borda, no laco e na pos-condicao, sem volta`, () => {
    const touch = new RegExp(`\\b(GRANT|REVOKE)\\s+[A-Za-z_, ()]*\\b(ALL|INSERT|UPDATE|DELETE)\\b[A-Za-z_, ()]*\\s+ON\\s+(TABLE\\s+)?[^;]*\\b(public\\.)?${t}\\b`, 'i');
    let lastIdx = -1;
    sqls.forEach((m, i) => { if (touch.test(m.sql)) lastIdx = i; });
    assert.ok(lastIdx >= 0, `nenhuma migration mexe na escrita de ${t}`);
    const { f, sql } = sqls[lastIdx];
    const revoke = sql.match(/REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE([^;]*)\s+FROM PUBLIC, anon, authenticated;/);
    assert.ok(revoke && new RegExp(`\\bpublic\\.${t}\\b`).test(revoke[1]), `a mais nova (${f}) revoga ${t} da borda`);
    const arr = sql.match(/v_tables regclass\[\] := ARRAY\[([\s\S]*?)\];/);
    assert.ok(arr && arr[1].includes(`'public.${t}'::regclass`), `${t} no array usado pelo laco e pela pos-condicao`);
    assert.match(sql, /WHERE a\.attrelid = ANY \(v_tables\)[\s\S]*?LOOP\s+[\s\S]*?EXECUTE format\('REVOKE %s \(%I\) ON %s FROM PUBLIC', c\.priv, c\.col, c\.tbl\);\s+ELSE\s+EXECUTE format\('REVOKE %s \(%I\) ON %s FROM %s', c\.priv, c\.col, c\.tbl, c\.who\);/,
      'laco por coluna sobre o array');
    assert.match(sql, /FROM unnest\(v_tables\) t\(tbl\)\s+CROSS JOIN unnest\(ARRAY\['public', 'anon', 'authenticated'\]\) r\(rol\)\s+CROSS JOIN unnest\(ARRAY\['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'\]\) p\(priv\)\s+WHERE has_table_privilege\(r\.rol, t\.tbl, p\.priv\)\s+OR \(p\.priv IN \('INSERT', 'UPDATE'\) AND has_any_column_privilege\(r\.rol, t\.tbl, p\.priv\)\)\s+\) THEN\s+RAISE EXCEPTION/,
      'pos-condicao pelo efeito, sobre o array');
    assert.doesNotMatch(sql, new RegExp(`GRANT\\s+[^;]*\\b(ALL|INSERT|UPDATE|DELETE)\\b[^;]*ON\\s+[^;]*\\b${t}\\b[^;]*\\bTO\\b[^;]*\\b(authenticated|anon|PUBLIC)\\b`, 'i'));
    for (const later of sqls.slice(lastIdx + 1)) {
      assert.doesNotMatch(later.sql, SCHEMA_WIDE, `${later.f} devolve escrita ampla no schema`);
    }
  });
}

function walk(dir, out = []) {
  for (const e of readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|astro|mjs|js)$/.test(e)) out.push(p);
  }
  return out;
}

test('B. nenhum codigo de tela, Edge Function ou script escreve nessas tabelas direto', () => {
  const re = new RegExp(`\\.from\\(\\s*['"\`](${TABLES.join('|')})['"\`]\\s*\\)\\s*\\.\\s*(insert|update|upsert|delete)\\s*\\(`);
  const offenders = [];
  for (const base of ['src', 'supabase/functions', 'scripts']) {
    for (const f of walk(resolve(ROOT, base))) if (re.test(maskJsComments(readFileSync(f, 'utf8')))) offenders.push(f.replace(ROOT + '/', ''));
  }
  assert.deepEqual(offenders, []);
});
