/**
 * Contract: #3063 (parte 2) — a triagem por IA escolhe a rubrica pelo perfil da vaga.
 *
 * Decisão do GP em 14/11/2026, que vale como o memorando da ADR-0076 para o ciclo 4: as vagas de apoio ganham
 * rubrica própria (aderência à vaga lida no prompt); a rubrica de pesquisa NÃO muda, para que as notas de pesquisa
 * continuem comparáveis.
 *
 * Camadas:
 *   S  migration: a coluna triage_profile, o CHECK e as 6 vagas de apoio escolhidas pelo GP.
 *   S  EF pmi-ai-triage:
 *      - a rubrica de pesquisa é byte a byte a de antes (sha256 do texto);
 *      - ehApoio sai do perfil da vaga, e decide a rubrica, o prompt e a versão no registro;
 *      - a rubrica escolhida é a que vai como system ao modelo e a que entra no hash do prompt;
 *      - na vaga de apoio, o bloco da vaga substitui a função; fora dela, a função segue como antes.
 *   L  viva: exatamente as 6 vagas estão em 'apoio'.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';
import { maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const EF = resolve(ROOT, 'supabase/functions/pmi-ai-triage/index.ts');
const APOIO = ['76624', '76628', '76629', '76630', '76661', '76664'];

// sha256 do texto da TRIAGE_RUBRIC (pesquisa) em origin/main antes do #3063 (1931252f).
const SHA_RUBRICA_PESQUISA = 'aada2ad755d31d2c18a26175e532b87f5b600adfe88ec800d6d8104fff088e25';

const fonte = readFileSync(EF, 'utf8');
const ef = maskJsComments(fonte).replace(/\s+/g, ' ');

function migration() {
  const f = readdirSync(MIGRATIONS).filter((n) => n.endsWith('_3063_triagem_por_perfil_da_vaga.sql'));
  assert.equal(f.length, 1, `esperava 1 migration _3063_triagem_por_perfil_da_vaga, achei ${f.length}`);
  return maskLineComments(readFileSync(join(MIGRATIONS, f[0]), 'utf8')).replace(/\s+/g, ' ');
}

test('#3063b S: a migration cria triage_profile com default research, CHECK e as 6 vagas de apoio', () => {
  const sql = migration();
  assert.match(sql, /ADD COLUMN IF NOT EXISTS triage_profile text NOT NULL DEFAULT 'research';/, 'a coluna não nasce NOT NULL com default research');
  assert.match(sql, /CHECK \(triage_profile IN \('research', 'apoio'\)\)/, 'o CHECK do perfil não está na forma esperada');
  const m = sql.match(/UPDATE public\.vep_opportunities SET triage_profile = 'apoio' WHERE opportunity_id IN \(([^)]*)\);/);
  assert.ok(m, 'o UPDATE das vagas de apoio sumiu ou mudou de forma');
  const ids = m[1].split(',').map((s) => s.trim().replace(/'/g, '')).sort();
  assert.deepEqual(ids, APOIO, 'as vagas de apoio não são as 6 escolhidas pelo GP');
});

test('#3063b S: a rubrica de pesquisa é byte a byte a de antes', () => {
  const m = fonte.match(/const TRIAGE_RUBRIC = `([\s\S]*?)`;/);
  assert.ok(m, 'TRIAGE_RUBRIC sumiu');
  assert.equal(createHash('sha256').update(m[1]).digest('hex'), SHA_RUBRICA_PESQUISA,
    'a rubrica de pesquisa mudou; as notas de pesquisa deixariam de ser comparáveis');
});

test('#3063b S: o perfil da vaga decide a rubrica, o prompt e a versão no registro', () => {
  assert.match(ef, /const vaga = await lerVaga\(sb, app\.vep_opportunity_id\); const ehApoio = vaga\?\.triage_profile === "apoio"; const rubric = ehApoio \? TRIAGE_RUBRIC_APOIO : TRIAGE_RUBRIC;/,
    'a rubrica não sai mais do perfil da vaga da candidatura');
  assert.match(ef, /const userPrompt = buildUserPrompt\(app, ehApoio \? vaga : null\); const promptCombined = rubric \+ "\\n---USER---\\n" \+ userPrompt;/,
    'o prompt ou o hash do prompt não usam a rubrica escolhida');
  assert.match(ef, /const promptVersion = ehApoio \? PROMPT_VERSION_APOIO : await resolvePromptVersion\(sb, app\.cycle_id\);/,
    'a versão no registro não separa a rubrica de apoio');
  assert.match(ef, /const response = await callAnthropicTriage\(userPrompt, rubric\);/, 'a chamada ao modelo não recebe a rubrica escolhida');
  assert.match(ef, /const res = await callAnthropicOnce\(userPrompt, rubric\);/, 'o retry não repassa a rubrica escolhida');
  assert.match(ef, /system: \[ \{ type: "text", text: rubric, cache_control: \{ type: "ephemeral" \}, \}, \]/,
    'o system enviado ao modelo não é a rubrica escolhida');
  assert.match(ef, /SELECT_COLS = "[^"]*, vep_opportunity_id";/, 'a candidatura não lê mais a vep_opportunity_id');
});

test('#3063b S: na vaga de apoio a vaga substitui a função; fora dela, a função segue', () => {
  assert.match(ef, /if \(vagaApoio\) parts\.push\(blocoDaVaga\(vagaApoio\)\); else parts\.push\(`# Função aplicada: \$\{app\.role_applied\}`\);/,
    'o prompt não troca a função pela vaga só na vaga de apoio');
  assert.match(ef, /\.from\("vep_opportunities"\) \.select\("title, time_commitment, essay_mapping, triage_profile"\) \.eq\("opportunity_id", opportunityId\)/,
    'lerVaga não lê a vaga pela opportunity_id da candidatura');
});

const URL_BASE = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

test('#3063b L: exatamente as 6 vagas escolhidas estão em apoio',
  { skip: URL_BASE && KEY ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(`${URL_BASE}/rest/v1/vep_opportunities?select=opportunity_id&triage_profile=eq.apoio`, {
      headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
    });
    assert.equal(r.status, 200, `a leitura devolveu ${r.status}`);
    const ids = (await r.json()).map((x) => x.opportunity_id).sort();
    assert.deepEqual(ids, APOIO, 'as vagas em apoio no banco não são as 6 escolhidas pelo GP');
  });
