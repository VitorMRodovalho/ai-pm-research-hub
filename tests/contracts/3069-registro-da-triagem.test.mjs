/**
 * Contract: #3069 — a triagem por IA não roda sem deixar registro em ai_processing_log.
 *
 * De 22/06 a 14/11/2026 a EF pmi-ai-triage gravou prompt_version numa coluna que não existia: o INSERT do log
 * falhava, a EF só avisava, e a nota saía sem rastro da versão do prompt (ADR-0076).
 *
 * Camadas:
 *   S  EF: a falha do INSERT do log interrompe a triagem antes da chamada ao modelo.
 *   S  migration: a coluna prompt_version existe, sem default inventado.
 *   L  viva: cada campo que a EF grava em ai_processing_log é uma coluna real da tabela. É isto que teria
 *      derrubado o CI em junho, e vale para qualquer campo novo.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const EF = resolve(ROOT, 'supabase/functions/pmi-ai-triage/index.ts');
const fonte = readFileSync(EF, 'utf8');
const ef = maskJsComments(fonte).replace(/\s+/g, ' ');

function camposDoInsert() {
  // maskJsComments só apaga comentário em linha própria; aqui o INSERT tem comentário no fim da linha.
  const semComentario = maskJsComments(fonte).replace(/\s\/\/[^\n]*/g, '').replace(/\s+/g, ' ');
  const m = semComentario.match(/\.from\("ai_processing_log"\) \.insert\(\{ (.*?) \}\) \.select\("id"\)/);
  assert.ok(m, 'o INSERT em ai_processing_log não foi encontrado na EF');
  const campos = m[1].split(',').map((s) => s.trim()).filter(Boolean).map((s) => s.split(':')[0].trim());
  assert.ok(campos.includes('prompt_version'), `o INSERT não grava prompt_version: ${campos.join(', ')}`);
  return campos;
}

test('#3069 S: falhou o registro, a triagem para antes de chamar o modelo', () => {
  assert.match(ef,
    /if \(logErr\) throw new Error\(`ai_processing_log_insert_failed: \$\{logErr\.message\}`\); logId = logRow\?\.id \?\? null; const response = await callAnthropicTriage\(/,
    'a falha do INSERT do log não interrompe a triagem antes da chamada ao modelo');
  camposDoInsert();
});

test('#3069 S: a migration cria prompt_version sem default', () => {
  const f = readdirSync(MIGRATIONS).filter((n) => n.endsWith('_3069_prompt_version_no_log.sql'));
  assert.equal(f.length, 1, `esperava 1 migration _3069_prompt_version_no_log, achei ${f.length}`);
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, f[0]), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /ALTER TABLE public\.ai_processing_log ADD COLUMN IF NOT EXISTS prompt_version text;/, 'a coluna não é criada');
  assert.doesNotMatch(sql, /prompt_version text[^;]*DEFAULT/i, 'a coluna ganhou default, que inventaria a versão das linhas antigas');
});

const URL_BASE = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

test('#3069 L: cada campo que a EF grava em ai_processing_log existe na tabela',
  { skip: URL_BASE && KEY ? false : 'sem credencial de banco' }, async () => {
    const campos = camposDoInsert();
    const r = await dbFetch(`${URL_BASE}/rest/v1/ai_processing_log?select=${campos.join(',')}&limit=0`, {
      headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
    });
    const texto = await r.text();
    assert.equal(r.status, 200, `a tabela não tem algum destes campos (${campos.join(', ')}): ${texto.slice(0, 200)}`);
  });
