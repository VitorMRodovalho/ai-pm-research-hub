/**
 * Contract: #2864 (G19) — os 2 gatilhos de `board_items` que existiam só no banco agora estão em
 * migration, com a definição viva, e a cobertura de migrations olha gatilho.
 *
 * `trg_auto_comms_on_publish` (cria o card "Divulgar" quando o card é publicado) e
 * `trg_notify_leader_review` (avisa o líder) rodavam em produção sem nenhum `CREATE TRIGGER` no
 * repositório. As funções batiam com migration; os gatilhos não. A captura copia
 * `pg_get_triggerdef` lido no banco em 31/10/2026, trocando só CREATE por CREATE OR REPLACE.
 *
 * Camadas:
 *   S  estática: a última captura de cada gatilho amarra momento, evento, coluna, tabela e função;
 *      a função de auditoria é SECURITY DEFINER com search_path vazio, só para service_role, e lê
 *      só gatilho não interno de public;
 *   L  viva: a definição viva de cada um é a da migration; anon é recusado na função de auditoria.
 * A cobertura (gatilho vivo sem migration reprova) mora em `rpc-migration-coverage`.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');

const GATILHOS = {
  trg_auto_comms_on_publish:
    'AFTER UPDATE OF curation_status ON public.board_items FOR EACH ROW EXECUTE FUNCTION auto_comms_card_on_publish()',
  trg_notify_leader_review:
    'AFTER UPDATE OF curation_status ON public.board_items FOR EACH ROW EXECUTE FUNCTION notify_leader_on_review()',
};

/** A ÚLTIMA instrução CREATE [OR REPLACE] TRIGGER <nome> das migrations, sem comentário, com espaço colapsado. */
function ultimaCaptura(nome) {
  let achou = null;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8'));
    const re = new RegExp(`\\bCREATE\\s+(?:OR\\s+REPLACE\\s+)?TRIGGER\\s+${nome}\\s[^;]*;`, 'gi');
    for (const m of sql.matchAll(re)) achou = { file: f, stmt: m[0].replace(/\s+/g, ' ') };
  }
  return achou;
}

const semEsquema = (s) => s.replace(/\bpublic\./g, '').replace(/\s+/g, ' ').trim();

test('#2864 S: cada gatilho tem captura com o momento, o evento, a tabela e a função dele', () => {
  for (const [nome, corpo] of Object.entries(GATILHOS)) {
    const cap = ultimaCaptura(nome);
    assert.ok(cap, `${nome}: nenhuma migration cria este gatilho`);
    assert.equal(cap.stmt, `CREATE OR REPLACE TRIGGER ${nome} ${corpo};`,
      `${nome}: a captura em ${cap.file} não é a definição viva lida em 31/10/2026`);
  }
});

test('#2864 S: _audit_list_public_triggers é SECURITY DEFINER, search_path vazio, só gatilho não interno de public', () => {
  const cap = latestFunctionCapture(ROOT, '_audit_list_public_triggers');
  const bloco = maskLineComments(cap.block).replace(/\s+/g, ' ');
  assert.match(bloco, /\bSECURITY DEFINER SET search_path = ''/, 'perdeu SECURITY DEFINER com search_path vazio');
  assert.match(bloco, /WHERE NOT t\.tgisinternal AND c\.relnamespace = 'public'::regnamespace/,
    'o filtro deixou de ser gatilho não interno de tabela de public');
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, cap.file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._audit_list_public_triggers\(\) FROM PUBLIC, anon, authenticated;/,
    'a migration da função não revoga PUBLIC, anon e authenticated');
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\._audit_list_public_triggers\(\) TO service_role;/,
    'a migration da função não concede a service_role');
});

// ─── L: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY;
const temCredencial = Boolean(URL_BASE && KEY);
const chamar = (chave) => dbFetch(`${URL_BASE}/rest/v1/rpc/_audit_list_public_triggers`, {
  method: 'POST',
  headers: { apikey: chave, Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json' },
  body: '{}',
});

test('#2864 L: a definição viva dos 2 é a da migration, e eles estão ligados',
  { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
    const r = await chamar(KEY);
    assert.equal(r.status, 200, `_audit_list_public_triggers respondeu ${r.status} a service_role`);
    const linhas = await r.json();
    assert.ok(linhas.length > 0, 'nenhum gatilho devolvido: as asserções abaixo passariam por vácuo');
    for (const nome of Object.keys(GATILHOS)) {
      const vivo = linhas.find((l) => l.table_name === 'board_items' && l.trigger_name === nome);
      assert.ok(vivo, `${nome} não existe no banco`);
      assert.equal(vivo.enabled, 'O', `${nome} não está ligado (tgenabled = ${vivo.enabled})`);
      const cap = ultimaCaptura(nome);
      assert.equal(semEsquema(vivo.definition), semEsquema(cap.stmt.replace(/^CREATE OR REPLACE/, 'CREATE').replace(/;$/, '')),
        `${nome}: a definição viva diverge da captura em ${cap.file}`);
    }
  });

test('#2864 L: anon é recusado na função de auditoria',
  { skip: temCredencial && ANON ? false : 'sem credencial de banco' }, async () => {
    const r = await chamar(ANON);
    assert.notEqual(r.status, 200, 'anon executou _audit_list_public_triggers');
  });
