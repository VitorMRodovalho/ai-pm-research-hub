/**
 * Contract: #1990 — `manage_event` sem recurso é EXPLÍCITO, e o helper recebe o id CERTO.
 *
 * Continuação do #1977, que fez a mesma troca em `write_board`. Dez RPCs cujo portão pergunta
 * "tem `manage_event` em algum lugar?" passam a dizer isso com `_can_anywhere*`.
 *
 * ⚠️ A ASSERÇÃO QUE JUSTIFICA ESTE ARQUIVO EXISTIR SOZINHO É A DA CAMADA D.
 *
 * `can_by_member` recebe **member id**; `_can_anywhere` recebe **person id**. Os dois são `uuid`,
 * então `_can_anywhere(m.id, ...)` COMPILA, não dá erro de tipo, e devolve **0 de 94** — porque
 * `members.person_id = members.id` em **0 de 94** linhas. Uma troca ingênua esvaziaria a audiência
 * em silêncio, que é exatamente o defeito do #1978. Nenhuma camada estática de "usa o helper novo"
 * pega isso: o helper novo ESTÁ lá, só recebeu o id errado.
 *
 * As duas formas corretas também não são equivalentes: `_by_member` resolve por
 * `persons.legacy_member_id`, que alcança 92 dos 94. Hoje empatam em 16 porque os 2 não alcançados
 * não têm a capacidade — **empate por coincidência**, do tipo que vira bomba-relógio.
 *
 * Camadas: A estática sobre a captura, com a INVERSA; A' md5 do vivo contra a captura;
 *          D a armadilha de argumento, estática sobre TODAS as migrations;
 *          C o vivo discrimina e ninguém perde.
 *
 * Migration: 20260825193745_1990_manage_event_portao_resourceless_explicito.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { normalizeBody, md5 } from '../helpers/rpc-body-drift-parser.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGR = resolve(ROOT, 'supabase/migrations');
const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const temCred = Boolean(URL_BASE && KEY);

/** [função, variável passada ao helper, helper esperado]. A 3ª coluna é a decisão do #1990. */
const ALVOS = [
  ['create_governance_document_intake',  'v_caller_member_id',  '_can_anywhere_by_member'],
  ['create_next_geral_meeting',          'v_caller_id',         '_can_anywhere_by_member'],
  ['get_comms_pipeline',                 'v_caller_id',         '_can_anywhere_by_member'],
  ['get_dropout_risk_members',           'v_caller_id',         '_can_anywhere_by_member'],
  ['get_gamification_category_activity', 'v_caller_id',         '_can_anywhere_by_member'],
  ['get_geral_agenda_viva',              'v_caller',            '_can_anywhere_by_member'],
  ['get_recurrence_stockout',            'v_caller_id',         '_can_anywhere_by_member'],
  ['list_webinar_proposals',             'v_caller_id',         '_can_anywhere_by_member'],
  ['get_member_comms_card',              'v_caller_person_id',  '_can_anywhere'],
  ['detect_agenda_blocks_pending_cron',  'm.person_id',         '_can_anywhere'],
];

/** As formas resourceless que a etapa 3 remove. */
const RESOURCELESS = [
  /public\.can_by_member\(\s*[\w.]+\s*,\s*'manage_event'(\s*::\s*text)?\s*\)/g,
  /public\.can\(\s*[\w.]+\s*,\s*'manage_event'(\s*::\s*text)?\s*,\s*NULL\s*,\s*NULL\s*\)/g,
];

const corpo = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);

// ─── A: estática ────────────────────────────────────────────────────────────────

test('#1990 controle positivo: as 10 têm captura em migration', () => {
  for (const [n] of ALVOS) {
    assert.ok(latestFunctionCapture(ROOT, n).body.length > 0,
      `${n} resolveu para captura vazia — tudo abaixo passaria por vácuo`);
  }
});

test('#1990 A: cada uma usa o helper DECIDIDO, com a variável decidida, uma vez', () => {
  for (const [n, variavel, helper] of ALVOS) {
    const esperado = new RegExp(
      `public\\.${helper}\\(\\s*${variavel.replace('.', '\\.')}\\s*,\\s*'manage_event'\\s*\\)`, 'g');
    const achou = (corpo(n).match(esperado) || []).length;
    assert.equal(achou, 1,
      `${n}: esperava exatamente 1 chamada \`${helper}(${variavel}, 'manage_event')\`, achei ${achou}. ` +
      'A escolha do helper e da variável é POR CALL SITE — ver camada D.');
  }
});

test('#1990 A (INVERSA): nenhuma forma resourceless sobrou nas 10', () => {
  for (const [n] of ALVOS) {
    const b = corpo(n);
    for (const re of RESOURCELESS) {
      const sobrou = b.match(new RegExp(re.source, 'g')) || [];
      assert.equal(sobrou.length, 0,
        `${n} ainda tem ${sobrou.length} chamada(s) resourceless de manage_event: ${sobrou.join(', ')}`);
    }
  }
});

test('#1990 A (INVERSA): os ramos VIZINHOS sobreviveram', () => {
  // Trocar só o ramo de manage_event não pode ter estreitado o portão composto.
  for (const n of ['get_comms_pipeline', 'list_webinar_proposals', 'get_member_comms_card']) {
    assert.match(corpo(n), /'manage_member'/,
      `${n} perdeu o ramo de manage_member — a troca ESTREITOU o portão, que não é o proposto`);
  }
  assert.match(corpo('get_comms_pipeline'), /'write_board'/,
    'get_comms_pipeline perdeu o ramo de write_board (#1977)');
});

// ─── D: a armadilha de argumento, sobre TODAS as migrations ─────────────────────

test('#1990 D: `_can_anywhere` NUNCA recebe um id de MEMBRO (a troca que devolve 0)', () => {
  // `members.person_id = members.id` em 0 de 94 linhas: passar member id aqui esvazia em silêncio.
  const suspeitos = /public\._can_anywhere\(\s*((?:\w+\.)?(?:m|member|caller)?_?(?:member_)?id|m\.id|v_member_id|v_caller_id)\s*,/g;
  const achados = [];
  for (const f of readdirSync(MIGR).filter((x) => x.endsWith('.sql'))) {
    const sql = maskLineComments(readFileSync(join(MIGR, f), 'utf8'));
    for (const m of sql.matchAll(suspeitos)) achados.push(`${f}: _can_anywhere(${m[1]}, ...)`);
  }
  assert.deepEqual(achados, [],
    'chamada de `_can_anywhere` com o que parece id de MEMBRO. `_can_anywhere` recebe PERSON id; ' +
    'member id devolve false para todo mundo, sem erro de tipo. Use `_can_anywhere_by_member`, ' +
    `ou passe \`.person_id\`. Achados:\n  ${achados.join('\n  ')}`);
});

test('#1990 D: `_can_anywhere_by_member` NUNCA recebe um id de PESSOA', () => {
  const suspeitos = /public\._can_anywhere_by_member\(\s*([\w.]*person_id)\s*,/g;
  const achados = [];
  for (const f of readdirSync(MIGR).filter((x) => x.endsWith('.sql'))) {
    const sql = maskLineComments(readFileSync(join(MIGR, f), 'utf8'));
    for (const m of sql.matchAll(suspeitos)) achados.push(`${f}: _can_anywhere_by_member(${m[1]}, ...)`);
  }
  assert.deepEqual(achados, [],
    '`_can_anywhere_by_member` recebe MEMBER id e resolve por `persons.legacy_member_id`. ' +
    `Passar person id ali não resolve nada. Achados:\n  ${achados.join('\n  ')}`);
});

// ─── A' + C: vivo ───────────────────────────────────────────────────────────────

const rpc = (n, corpoJson) => dbFetch(`${URL_BASE}/rest/v1/rpc/${n}`, {
  method: 'POST',
  headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(corpoJson),
});
const rest = (c) => dbFetch(`${URL_BASE}/rest/v1/${c}`, { headers: { apikey: KEY, Authorization: `Bearer ${KEY}` } });

test("#1990 A': o corpo VIVO das 10 é igual à captura",
  { skip: temCred ? false : 'sem credencial de banco' }, async () => {
    for (const [n] of ALVOS) {
      const r = await rpc('_audit_function_source', { p_proname: n });
      assert.equal(r.status, 200, `_audit_function_source falhou para ${n}`);
      const j = await r.json();
      const vivo = Array.isArray(j) ? j[0] : j;
      assert.ok(vivo?.prosrc, `${n} não existe no banco`);
      const cap = latestFunctionCapture(ROOT, n);
      assert.equal(md5(normalizeBody(cap.body)), md5(normalizeBody(vivo.prosrc)),
        `${n}: vivo diverge da captura ${cap.version}`);
    }
  });

test('#1990 C: no vivo, a forma escolhida DISCRIMINA e a ingênua devolve zero',
  { skip: temCred ? false : 'sem credencial de banco' }, async () => {
    // Os conjuntos são DERIVADOS de 3 leituras de tabela; as chamadas de RPC são poucas e
    // dirigidas. Uma versão anterior deste teste chamava a RPC por membro (282 requisições) e
    // estourava o tempo — um guard que a CI não consegue rodar não guarda nada.
    const [rM, rE, rP] = await Promise.all([
      rest('members?is_active=eq.true&select=id,person_id'),
      rest('auth_engagements?is_authoritative=eq.true&select=person_id,kind,role,initiative_id'),
      rest("engagement_kind_permissions?action=eq.manage_event&select=kind,role,scope"),
    ]);
    for (const [nome, r] of [['members', rM], ['auth_engagements', rE], ['permissions', rP]]) {
      assert.equal(r.status, 200, `leitura de ${nome} falhou`);
    }
    const ativos = await rM.json();
    const engs = await rE.json();
    const combos = new Map((await rP.json()).map((c) => [`${c.kind}|${c.role}`, c.scope]));
    assert.ok(ativos.length > 0 && combos.size > 0, 'base vazia — o teste passaria por vácuo');

    // A coincidência que torna a armadilha invisível: os dois ids são uuid e NUNCA iguais.
    assert.equal(ativos.filter((m) => m.person_id === m.id).length, 0,
      'algum membro tem person_id = id. Se isso mudar, a troca ingênua passa a "funcionar" por '
      + 'acidente em parte da base e o defeito vira intermitente — releia a camada D.');

    const comAutoridade = new Set();
    for (const e of engs) {
      const escopo = combos.get(`${e.kind}|${e.role}`);
      if (!escopo) continue;
      if (escopo === 'organization' || escopo === 'global' || e.initiative_id) comAutoridade.add(e.person_id);
    }
    const dentro = ativos.find((m) => comAutoridade.has(m.person_id));
    const fora = ativos.find((m) => !comAutoridade.has(m.person_id));
    assert.ok(dentro && fora, 'sem um caso de cada lado, a discriminação não é afirmável');

    const chamar = async (fn, corpoJson) => (await (await rpc(fn, corpoJson)).json());

    // 1. Quem tem, passa pela forma direta.
    assert.equal(await chamar('_can_anywhere', { p_person_id: dentro.person_id, p_action: 'manage_event' }), true,
      'a forma direta negou quem tem manage_event vigente');
    // 2. Quem não tem, não passa (helper não degenerou para true).
    assert.equal(await chamar('_can_anywhere', { p_person_id: fora.person_id, p_action: 'manage_event' }), false,
      'a forma direta aceitou quem não tem combo — helper degenerado');
    // 3. A ARMADILHA: o mesmo caso, com member id, devolve false SEM erro. É por isso que a
    //    camada D é estática e proíbe a forma — no vivo ela é indistinguível de "não tem".
    assert.equal(await chamar('_can_anywhere', { p_person_id: dentro.id, p_action: 'manage_event' }), false,
      `\`_can_anywhere(member_id)\` devolveu true para ${dentro.id}. Se deixou de devolver false, `
      + 'a premissa da camada D mudou e o guard precisa ser relido, não silenciado.');
    // 4. E a forma _by_member alcança o mesmo caso a partir do member id.
    assert.equal(await chamar('_can_anywhere_by_member', { p_member_id: dentro.id, p_action: 'manage_event' }), true,
      '`_can_anywhere_by_member` não alcançou quem a forma direta alcança. É ESPERADO que divirjam '
      + 'para quem não tem back-reference em `persons.legacy_member_id` — mas não para este caso.');
  });
