/**
 * Contract #2495 — o wiki é lido só por membro ativo (decisão do GP, 2026-09-27).
 *
 * `wiki_pages_read` decidia por `rls_is_member()`, que só pergunta se existe cadastro com aquele
 * login: medido em 27/09, 116 contas liam o wiki, 25 delas sem cadastro ativo. A política passa ao
 * portão canônico da fase 2 de RLS, `rls_is_authoritative_member()`.
 *
 * O guard lê a ÚLTIMA migration que define a política (derivada do diretório, nunca fixada), para
 * que uma migration futura que volte a `rls_is_member()` reprove aqui. Comentários mascarados.
 *
 * A camada VIVA foi provada por impersonação na PR (antes/depois por grupo, com controle negativo);
 * mutar este arquivo não exercita o banco.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const POLICY_STMT = /\b(?:CREATE|ALTER)\s+POLICY\s+"?wiki_pages_read"?\s+ON\s+(?:public\.)?wiki_pages\b[^;]*;/gi;

/** A última instrução (em ordem de migration) que cria ou altera wiki_pages_read. */
function latestPolicyStatement() {
  let hit = null;
  for (const file of readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(DIR, file), 'utf8'));
    for (const m of sql.matchAll(POLICY_STMT)) hit = { file, stmt: m[0] };
  }
  assert.ok(hit, 'nenhuma migration define wiki_pages_read');
  return hit;
}

test('#2495: a definição vigente de wiki_pages_read usa o portão canônico de membro ativo', () => {
  const { file, stmt } = latestPolicyStatement();
  assert.match(stmt,
    /USING\s*\(\s*\(\s*SELECT\s+public\.rls_is_authoritative_member\(\)\s*\)\s*\)\s*;$/i,
    `${file}: a leitura do wiki decide por rls_is_authoritative_member()`);
  assert.doesNotMatch(stmt, /[^_]rls_is_member\s*\(/i,
    `${file}: não pode voltar ao rls_is_member() que aceitava cadastro inativo`);
});
