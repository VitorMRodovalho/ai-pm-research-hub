/**
 * Contract: #2565 (i) e #2865 — a meta de artigos conta o que a curadoria aprova e diz isso, e a
 * submissão de publicação fixa o search_path.
 *
 * G6. `exec_portfolio_health` contava `curation_status = 'approved'` na meta `articles_published`, e
 * o CHECK de `board_items.curation_status` não tem esse valor: a meta ficava sempre em 0. Passa a
 * contar `published`. Como a aprovação da curadoria grava `published` mesmo para artigo só
 * submetido, o GP decidiu em 31/10/2026 (opção c) que o rótulo diga o que o número mede, sem
 * prometer publicação externa.
 *
 * G14. `create_publication_submission` é SECURITY DEFINER e não fixava `search_path`. Passa a fixar
 * `public, pg_temp` por ALTER FUNCTION, sem mudar o corpo. ⚠️ Um CREATE OR REPLACE posterior sem a
 * cláusula SET apagaria a configuração: por isso o guard exige o ALTER DEPOIS da captura vigente.
 *
 * Camadas:
 *   K  estática: o ramo articles_published conta 'published', e 'approved' não sobrou nele;
 *   R  estática: a troca do rótulo exige o rótulo antigo, para se não achar 1 linha e registra auditoria;
 *   S  estática: o ALTER do search_path vem depois da última captura da função;
 *   V  viva: corpo de exec_portfolio_health igual à captura; o rótulo vivo é o novo.
 * O proconfig vivo de create_publication_submission foi conferido no pacote de banco, antes e depois.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { normalizeBody, md5 } from '../helpers/rpc-body-drift-parser.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const ROTULO_NOVO = { pt: 'Artigos aprovados pela curadoria', en: 'Articles approved by curation', es: 'Artículos aprobados por la curaduría' };

/** O ramo `WHEN 'articles_published'` do CASE, até o WHEN seguinte. */
function ramoArtigos() {
  const c = maskLineComments(latestFunctionCapture(ROOT, 'exec_portfolio_health').body).replace(/\s+/g, ' ');
  const i = c.indexOf("WHEN 'articles_published' THEN");
  assert.ok(i >= 0, "exec_portfolio_health não tem o ramo WHEN 'articles_published'");
  const j = c.indexOf(' WHEN ', i + 10);
  return c.slice(i, j < 0 ? undefined : j);
}

test('#2565 K: a meta de artigos conta curation_status = published', () => {
  const ramo = ramoArtigos();
  assert.match(ramo, /SELECT COUNT\(\*\)::numeric INTO v_current FROM public\.board_items bi [^;]*AND bi\.curation_status = 'published' [^;]*;/,
    `o ramo articles_published não conta curation_status = 'published': ${ramo.slice(0, 300)}`);
});

test("#2565 K (INVERSA): 'approved' não sobrou no ramo de artigos", () => {
  assert.doesNotMatch(ramoArtigos(), /'approved'/, "o ramo articles_published voltou a contar um valor que o CHECK não aceita");
});

/** A última migration que troca o metric_label de articles_published, sem comentário, com espaço colapsado. */
function trocaDoRotulo() {
  let achou = null;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')).replace(/\s+/g, ' ');
    if (/UPDATE public\.portfolio_kpi_targets SET metric_label = v_new WHERE cycle_code = 'cycle3-2026' AND metric_key = 'articles_published'/.test(sql)) achou = { file: f, sql };
  }
  assert.ok(achou, 'nenhuma migration troca o rótulo de articles_published');
  return achou;
}

test('#2565 R: o rótulo novo diz "aprovados pela curadoria" nas 3 línguas, e não promete publicação', () => {
  const { sql } = trocaDoRotulo();
  assert.match(sql, new RegExp(`v_new jsonb := jsonb_build_object\\( 'pt', '${ROTULO_NOVO.pt}', 'en', '${ROTULO_NOVO.en}', 'es', '${ROTULO_NOVO.es}'\\);`),
    'o rótulo novo não é o decidido nas 3 línguas');
});

test('#2565 R: a troca exige o rótulo de hoje, para sem 1 linha e deixa auditoria', () => {
  const { sql } = trocaDoRotulo();
  assert.match(sql, /AND metric_key = 'articles_published' AND metric_label->>'pt' = 'Artigos Publicados'; GET DIAGNOSTICS v_rows = ROW_COUNT; IF v_rows <> 1 THEN RAISE EXCEPTION/,
    'a troca não confere o rótulo antigo, ou não para quando não acha exatamente 1 linha');
  assert.match(sql, /INSERT INTO public\.admin_audit_log \(actor_id, action, target_type, changes, metadata\) VALUES \(NULL, 'kpi\.label_set', 'portfolio_kpi_targets', jsonb_build_object\('articles_published', jsonb_build_object\('before', v_old, 'after', v_new\)\)/,
    'a troca não registra antes e depois em admin_audit_log');
});

test('#2865 S: o ALTER do search_path vem depois da última captura de create_publication_submission', () => {
  const cap = latestFunctionCapture(ROOT, 'create_publication_submission');
  let alter = null;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')).replace(/\s+/g, ' ');
    if (/ALTER FUNCTION public\.create_publication_submission\([^)]*\) SET search_path = public, pg_temp;/.test(sql)) alter = f;
  }
  assert.ok(alter, 'nenhuma migration fixa o search_path de create_publication_submission');
  assert.ok(alter > cap.file,
    `o ALTER (${alter}) não vem depois da captura vigente (${cap.file}): um CREATE OR REPLACE sem SET apagou a configuração`);
});

// ─── V: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const temCredencial = Boolean(URL_BASE && KEY);
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };

test('#2565 V: o corpo VIVO de exec_portfolio_health é igual à captura', { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
  const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/_audit_function_source`, { method: 'POST', headers: H, body: JSON.stringify({ p_proname: 'exec_portfolio_health' }) });
  assert.equal(r.status, 200, '_audit_function_source falhou');
  const linhas = await r.json();
  assert.equal(linhas.length, 1, `esperava 1 assinatura viva, vieram ${linhas.length}`);
  const cap = latestFunctionCapture(ROOT, 'exec_portfolio_health');
  assert.equal(md5(normalizeBody(linhas[0].prosrc)), md5(normalizeBody(cap.body)), `corpo vivo diverge da captura ${cap.version}`);
});

test('#2565 V: a meta viva de artigos sai com o rótulo novo', { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
  const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/exec_portfolio_health`, { method: 'POST', headers: H, body: '{}' });
  assert.equal(r.status, 200, 'exec_portfolio_health falhou');
  const meta = (await r.json()).find((m) => m.metric_key === 'articles_published');
  assert.ok(meta, 'exec_portfolio_health não devolveu articles_published');
  assert.deepEqual({ pt: meta.label?.pt, en: meta.label?.en, es: meta.label?.es }, ROTULO_NOVO, 'o rótulo vivo não é o decidido');
});
