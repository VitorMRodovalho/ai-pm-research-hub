/**
 * board_items: escrita de card so pelas RPCs da plataforma.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a migration mais nova que mexe na escrita de board_items a revoga da borda (authenticated, anon,
 *      PUBLIC) para INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES e TRIGGER, na tabela e no que restar
 *      por coluna, com pos-condicao pelo efeito (has_table_privilege) que falha a migration, e nenhuma
 *      posterior a concede de volta;
 *   B. nenhum codigo de tela ou Edge Function escreve em board_items direto (toda escrita vai por RPC).
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
const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
const TOUCH = /\b(GRANT|REVOKE)\s+[A-Za-z_, ()]*\b(ALL|INSERT|UPDATE|DELETE)\b[A-Za-z_, ()]*\s+ON\s+(TABLE\s+)?(public\.)?board_items\b/i;

test('A. a escrita direta em board_items esta revogada da borda e nao volta', () => {
  let last = null;
  for (const f of files) {
    const sql = maskLineComments(readFileSync(join(DIR, f), 'utf8'));
    if (TOUCH.test(sql)) last = { f, sql };
  }
  assert.ok(last, 'nenhuma migration mexe na escrita de board_items');
  assert.match(last.sql, /REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public\.board_items FROM PUBLIC, anon, authenticated;/,
    `a mais nova (${last.f}) revoga INSERT, UPDATE e DELETE da tabela`);
  assert.match(last.sql,
    /FROM pg_attribute a\s+CROSS JOIN LATERAL aclexplode\(a\.attacl\) x\s+WHERE a\.attrelid = 'public\.board_items'::regclass[\s\S]*?AND x\.privilege_type IN \('INSERT', 'UPDATE', 'REFERENCES'\)\s+AND \(x\.grantee = 0 OR x\.grantee IN \('anon'::regrole, 'authenticated'::regrole\)\)\s+LOOP\s+[\s\S]*?EXECUTE format\('REVOKE %s \(%I\) ON public\.board_items FROM PUBLIC', c\.priv, c\.col\);\s+ELSE\s+EXECUTE format\('REVOKE %s \(%I\) ON public\.board_items FROM %s', c\.priv, c\.col, c\.who\);/,
    'e o que restar por coluna, lido do catalogo');
  assert.match(last.sql,
    /IF EXISTS \(SELECT 1\s+FROM unnest\(ARRAY\['public', 'anon', 'authenticated'\]\) r\(rol\)\s+CROSS JOIN unnest\(ARRAY\['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'\]\) p\(priv\)\s+WHERE has_table_privilege\(r\.rol, 'public\.board_items', p\.priv\)\s+OR \(p\.priv IN \('INSERT', 'UPDATE'\)\s+AND has_any_column_privilege\(r\.rol, 'public\.board_items', p\.priv\)\)\) THEN\s+RAISE EXCEPTION 'board_items: escrita ainda concedida/,
    'a migration falha se sobrar escrita para a borda (pos-condicao)');
  assert.doesNotMatch(last.sql, /GRANT\s+[^;]*\b(ALL|INSERT|UPDATE|DELETE)\b[^;]*ON\s+(TABLE\s+)?(public\.)?board_items[^;]*\bTO\b[^;]*\b(authenticated|anon|PUBLIC)\b/i,
    'sem GRANT de volta na mesma migration');
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

test('B. nenhum codigo de tela ou Edge Function escreve em board_items direto', () => {
  const offenders = [];
  for (const base of ['src', 'supabase/functions']) {
    for (const f of walk(resolve(ROOT, base))) {
      const src = maskJsComments(readFileSync(f, 'utf8'));
      if (/\.from\(\s*['"`]board_items['"`]\s*\)\s*\.\s*(insert|update|upsert|delete)\s*\(/.test(src)) offenders.push(f.replace(ROOT + '/', ''));
    }
  }
  assert.deepEqual(offenders, []);
});
