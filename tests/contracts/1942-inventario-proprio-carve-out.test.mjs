/**
 * Contract: #1942 — o responsavel le o PROPRIO inventario, e so o proprio.
 *
 * O defeito. `get_member_responsibility_inventory(p_member_id)` consolida 7 superficies de
 * responsabilidade, mas `p_member_id` e o ALVO e o portao era `manage_platform` OU `service_role`.
 * Medido por contraste em 23/08/2026: um responsavel real pedindo o PROPRIO inventario recebia
 * `Unauthorized: requires manage_platform permission`. Ela e ferramenta de GP para offboarding e
 * handoff, nao superficie de autoatendimento — e por isso as 57 acoes de reuniao abertas e nao
 * convertidas em card ficavam invisiveis para quem responde por elas.
 *
 * A correcao e um carve-out "si mesmo" no portao, mais `get_my_responsibilities()` sem parametro,
 * que por construcao nao pode ser apontada para outra pessoa. NAO toca
 * `engagement_kind_permissions`, logo nao aciona o procedimento de 4 etapas do V4_AUTHORITY_MODEL.
 *
 * Camadas: A estatica sobre a captura DERIVADA, com a INVERSA (o portao antigo, puro, nao pode
 * coexistir: um segundo ramo com ele deixaria este guard verde e o carve-out inerte); A' md5 do
 * corpo vivo contra a captura, para as DUAS funcoes; C o ACL no vivo, porque uma camada estatica
 * nao percebe `EXECUTE` para `anon`, que e como `CREATE FUNCTION` nasce.
 *
 * O que este guard NAO cobre, declarado: ele nao exerce o contraste com sessao de usuario real
 * (proprio abre / alheio barra). Isso foi medido a mao na sessao que escreveu a migration, mas a
 * suite roda com `service_role`, para quem o portao devolve `true` por desenho — o mesmo motivo
 * pelo qual `_can_manage_event` precisa de controle NEGATIVO no #1728. Exercer o contraste pediria
 * fixture de sessao autenticada, que a suite ainda nao tem.
 *
 * Migration: 20260823164317_1942_carve_out_si_mesmo_e_get_my_responsibilities.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody, md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

const INVENTARIO = 'get_member_responsibility_inventory@p_member_id uuid';
const WRAPPER = 'get_my_responsibilities@';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function capturaMaisRecente(chave) {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(chave);
  assert.ok(cap, `sem captura de migration para ${chave}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === chave);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${chave}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b). */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

async function rpc(nome, corpo) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    body: JSON.stringify(corpo ?? {}),
  });
  assert.ok(res.ok, `${nome} devia responder 2xx (veio ${res.status})`);
  return res.json();
}

// ── A ────────────────────────────────────────────────────────────────────────────────────

test('#1942 A: o portao do inventario tem o carve-out "si mesmo"', () => {
  const { body, file } = capturaMaisRecente(INVENTARIO);
  const codigo = achatado(body);

  assert.match(
    codigo,
    /v_caller\s*<>\s*p_member_id\s+AND\s+NOT\s+public\.can_by_member\(\s*v_caller\s*,\s*'manage_platform'\s*\)/i,
    `${file}: sem o carve-out — quem pede o proprio inventario volta a depender de manage_platform`,
  );

  // A INVERSA. Nao basta a forma nova ESTAR la: a forma antiga, pura, nao pode sobrar. Um segundo
  // ramo com ela recusa antes de o carve-out ser avaliado, e este guard fica verde assim mesmo.
  assert.doesNotMatch(
    codigo,
    /v_caller\s+IS\s+NULL\s+OR\s+NOT\s+public\.can_by_member\(\s*v_caller\s*,\s*'manage_platform'\s*\)\s*\)\s*THEN/i,
    `${file}: o portao puro (sem carve-out) reapareceu no corpo`,
  );
});

test('#1942 A: o wrapper nao aceita parametro e delega, em vez de duplicar', () => {
  const { body, file, } = capturaMaisRecente(WRAPPER);
  const codigo = achatado(body);

  assert.match(
    codigo,
    /RETURN\s+public\.get_member_responsibility_inventory\(\s*v_caller\s*\)/i,
    `${file}: o wrapper parou de delegar — corpo duplicado diverge do original com o tempo`,
  );

  // As 7 superficies vivem num corpo so. Se qualquer uma aparecer aqui, houve duplicacao.
  for (const tabela of ['board_items', 'board_item_checklists', 'drive_curation_grants', 'meeting_action_items']) {
    assert.doesNotMatch(
      codigo,
      new RegExp(`\\bFROM\\s+public\\.${tabela}\\b`, 'i'),
      `${file}: o wrapper passou a consultar ${tabela} por conta propria (SSOT quebrado)`,
    );
  }
});

test('#1942 A: o wrapper resolve o chamador por auth.uid(), nao por argumento', () => {
  const { body, file } = capturaMaisRecente(WRAPPER);
  const codigo = achatado(body);
  assert.match(
    codigo,
    /WHERE\s+auth_id\s*=\s*auth\.uid\(\)/i,
    `${file}: o wrapper deixou de resolver o chamador por auth.uid()`,
  );
});

// ── A' ───────────────────────────────────────────────────────────────────────────────────

for (const [rotulo, chave, proname] of [
  ['inventario', INVENTARIO, 'get_member_responsibility_inventory'],
  ['wrapper', WRAPPER, 'get_my_responsibilities'],
]) {
  test(`#1942 A': o corpo VIVO do ${rotulo} == a captura mais recente`, {
    skip: dbGated ? false : skipMsg,
  }, async () => {
    const { bodyHash, file } = capturaMaisRecente(chave);
    const linhas = await rpc('_audit_function_source', { p_proname: proname });
    assert.equal(linhas.length, 1, `esperado exatamente 1 ${proname} em pg_proc`);
    assert.equal(md5(normalizeBody(linhas[0].prosrc)), bodyHash,
      `corpo vivo de ${proname} divergente de ${file}: a mudanca esta so num dos dois lados`);
  });
}

// ── C ────────────────────────────────────────────────────────────────────────────────────

test('#1942 C: nenhuma das duas executa como anon, e ambas executam como authenticated', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // `CREATE FUNCTION` nasce com EXECUTE para PUBLIC, logo para `anon`. A migration revoga; sem esta
  // camada, uma recriacao futura devolve a funcao ao anonimo e as camadas estaticas ficam verdes.
  const linhas = await rpc('_audit_function_execute_acl', {
    p_names: ['get_my_responsibilities', 'get_member_responsibility_inventory'],
  });
  assert.equal(linhas.length, 2, 'esperadas as duas funcoes no audit de ACL');

  for (const l of linhas) {
    assert.equal(l.anon_exec, false, `${l.proname}: EXECUTE para anon — inventario de responsabilidade e dado de pessoa`);
    assert.equal(l.authenticated_exec, true, `${l.proname}: sem EXECUTE para authenticated — a tela nao consegue chamar`);
  }
});

test('#1942 C: o wrapper existe no vivo, sem argumento, e responde', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  const linhas = await rpc('_audit_function_execute_acl', { p_names: ['get_my_responsibilities'] });
  assert.equal(linhas[0].identity_args, '',
    'get_my_responsibilities ganhou parametro — deixa de ser inapontavel para outra pessoa por construcao');

  // Chamada como service_role: nao ha auth.uid(), entao o wrapper tem de devolver o erro de sessao,
  // e NAO um inventario. Controle negativo: um wrapper que devolvesse dado aqui estaria resolvendo
  // o chamador por outro caminho que nao a sessao.
  const r = await rpc('get_my_responsibilities');
  assert.equal(r?.error, 'Not authenticated',
    'sem sessao o wrapper tem de recusar; devolver inventario aqui significa que ele nao depende de auth.uid()');
});
