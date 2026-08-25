/**
 * Contract: #1977 — o portão resourceless é EXPLÍCITO, e não depende de coluna legada.
 *
 * A classe. Seis RPCs de curadoria e comms perguntam pela capacidade sem passar recurso, e a
 * pergunta é legítima: "é alguém de curadoria / board / comms em ALGUM lugar?". Até a etapa 3 essa
 * pergunta era feita pela forma de 2 argumentos de `can_by_member`, que resolve o caso sem recurso
 * caindo num ramo de `can()` condicionado a `legacy_tribe_id IS NOT NULL`.
 *
 * `legacy_tribe_id` só é preenchida quando a iniciativa é uma TRIBO. Autoridade escopada a
 * iniciativa que não é tribo (comitê, congresso) portanto NÃO passava, mesmo com combo seedado e
 * vigente. Medido em 24-25/08/2026: 69 pessoas passavam, 72 têm a autoridade.
 *
 * ⚠️ `can_org_by_member` NÃO serve como substituto: aceita só `organization`/`global`, e trocar um
 * pelo outro ESTREITARIA o portão das seis de 69 para 15. O guard afirma o helper certo, de
 * propósito, e a camada C prova as duas direções no vivo.
 *
 * ⚠️ `can()` fica INTOCADA. A cláusula permissiva dela é a etapa 4 do procedimento e sai só depois
 * da Onda B. Este guard afirma que esta migration não a tocou.
 *
 * Camadas:
 *   A  estática sobre a captura DERIVADA, com a INVERSA de cada afirmação (a forma sem recurso não
 *      pode sobrar, senão um segundo ramo reabre o caminho antigo com este teste verde);
 *   A' md5 do corpo vivo contra a captura, para as 8 funções;
 *   C  o helper DISCRIMINA no vivo e é SUPERCONJUNTO do comportamento anterior — uma camada
 *      estática não percebe um helper que passou a devolver `true` para tudo, que é exatamente como
 *      o alcance indevido entraria sem tocar em nenhuma das seis.
 *
 * Migration: 20260825031531_1977_can_anywhere_portao_resourceless_explicito.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { normalizeBody, md5 } from '../helpers/rpc-body-drift-parser.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const HELPER = '_can_anywhere';
const HELPER_BY_MEMBER = '_can_anywhere_by_member';
const CHAMADA = /public\._can_anywhere_by_member\(\s*(\w+)\s*,\s*'write_board'\s*\)/g;
/** A forma que a etapa 3 remove: `can_by_member(x, 'write_board')` sem recurso. */
const RESOURCELESS = /public\.can_by_member\(\s*\w+\s*,\s*'write_board'(\s*::\s*text)?\s*\)/g;

/** As 6, e o ramo VIZINHO que precisa sobreviver intacto em cada uma. */
const ALVOS = [
  ['get_comms_pipeline',                "public.can_by_member(v_caller_id, 'manage_event')"],
  ['get_curation_dashboard',            "public.can_by_member(v_member_id, 'curate_content')"],
  ['get_curation_queue_state',          "public.can_by_member(v_member_id, 'curate_content')"],
  ['list_curation_board',               "public.can_by_member(v_member_id, 'curate_content')"],
  ['list_curation_pending_board_items', "public.can_by_member(v_member_id, 'curate_content')"],
  ['update_webinar_comms_assets',       "public.can_by_member(v_caller_id, 'manage_event')"],
];

// ─── A: estática sobre a captura ────────────────────────────────────────────────

test('#1977 controle positivo: as 8 funções têm captura em migration', () => {
  for (const n of [HELPER, HELPER_BY_MEMBER, ...ALVOS.map((a) => a[0])]) {
    const cap = latestFunctionCapture(ROOT, n);
    assert.ok(cap.body.length > 0, `${n} resolveu para captura vazia — toda asserção abaixo passaria por vácuo`);
  }
});

test('#1977 A: `_can_anywhere` não pergunta por recurso NEM pela coluna legada', () => {
  // Mascara comentário: o corpo EXPLICA por que não usa `legacy_tribe_id`, e uma asserção negativa
  // sobre o texto cru reprovaria pela própria justificativa. O que importa é o CÓDIGO.
  const body = maskLineComments(latestFunctionCapture(ROOT, HELPER).body);
  // O ponto inteiro da issue: a coluna legada não pode participar da decisão.
  assert.doesNotMatch(body, /legacy_tribe_id/i,
    '`_can_anywhere` voltou a depender de `legacy_tribe_id` — é exatamente o defeito que #1977 fecha');
  assert.doesNotMatch(body, /p_resource_id|p_resource_type/i,
    '`_can_anywhere` ganhou parâmetro de recurso — então não é mais a pergunta "em algum lugar"');
  // ...e o escopo de iniciativa PRECISA valer, senão o helper virou `can_org` disfarçado.
  assert.match(body, /ekp\.scope\s*=\s*'initiative'\s*AND\s*ae\.initiative_id\s+IS\s+NOT\s+NULL/i,
    '`_can_anywhere` deixou de aceitar escopo `initiative` — estreitaria o portão das 6 para só organization');
  assert.match(body, /ekp\.scope\s+IN\s*\(\s*'organization',\s*'global'\s*\)/i,
    '`_can_anywhere` deixou de aceitar organization/global');
  // Carve-out p195, que `can()` e `can_org()` têm: omiti-lo NEGARIA governança.
  assert.match(body, /participate_in_governance_review/i,
    '`_can_anywhere` perdeu o carve-out p195 — negaria comentário em governança a quem tem contra-assinatura pendente');
  assert.match(body, /ae\.is_authoritative\s*=\s*true/i,
    '`_can_anywhere` parou de exigir engajamento vigente');
});

test('#1977 A: o helper é SECURITY DEFINER com search_path fixo', () => {
  for (const n of [HELPER, HELPER_BY_MEMBER]) {
    const { block } = latestFunctionCapture(ROOT, n);
    assert.match(block, /SECURITY\s+DEFINER/i, `${n} deixou de ser SECURITY DEFINER`);
    assert.match(block, /SET\s+search_path\s+TO\s+'public',\s*'pg_temp'/i, `${n} perdeu o search_path fixo`);
  }
});

test('#1977 A: `_can_anywhere_by_member` DELEGA, não reimplementa a regra', () => {
  const body = maskLineComments(latestFunctionCapture(ROOT, HELPER_BY_MEMBER).body);
  assert.match(body, /public\._can_anywhere\(/,
    'o irmão por member parou de delegar — a regra passaria a viver em dois lugares');
  assert.doesNotMatch(body, /engagement_kind_permissions/i,
    'o irmão por member reimplementou a consulta em vez de delegar');
});

test('#1977 A: as 6 usam `_can_anywhere_by_member`, uma vez cada', () => {
  for (const [nome] of ALVOS) {
    const block = maskLineComments(latestFunctionCapture(ROOT, nome).block);
    const n = (block.match(new RegExp(CHAMADA.source, 'g')) || []).length;
    assert.equal(n, 1, `${nome} tem ${n} chamadas a _can_anywhere_by_member para write_board, esperado 1`);
  }
});

test('#1977 A (INVERSA): a forma sem recurso não sobrou em nenhuma das 6', () => {
  for (const [nome] of ALVOS) {
    const block = maskLineComments(latestFunctionCapture(ROOT, nome).block);
    const sobrou = block.match(new RegExp(RESOURCELESS.source, 'g')) || [];
    assert.equal(sobrou.length, 0,
      `${nome} ainda tem ${sobrou.length} chamada(s) resourceless de write_board: ${sobrou.join(', ')} ` +
      '— um segundo ramo reabriria o caminho antigo com este teste verde');
  }
});

test('#1977 A (INVERSA): o ramo vizinho de cada uma sobreviveu intacto', () => {
  for (const [nome, vizinho] of ALVOS) {
    const { block } = latestFunctionCapture(ROOT, nome);
    assert.ok(block.includes(vizinho),
      `${nome} perdeu o ramo vizinho \`${vizinho}\` — a troca do ramo de write_board ESTREITOU o portão, ` +
      'que não é o que #1977 propõe');
  }
});

test('#1977 A: a migration de #1977 NÃO tocou `can()`', () => {
  const cap = latestFunctionCapture(ROOT, HELPER);
  const sql = readFileSync(resolve(ROOT, 'supabase/migrations', cap.file), 'utf8');
  assert.doesNotMatch(sql, /CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+public\.can\s*\(/i,
    'a migration de #1977 redefiniu `can()`. A cláusula permissiva dela é a ETAPA 4 e sai só depois da Onda B');
});

// ─── A' + C: vivo ───────────────────────────────────────────────────────────────

const temCredencial = Boolean(URL_BASE && KEY);
const rest = (caminho) => dbFetch(`${URL_BASE}/rest/v1/${caminho}`, {
  headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
});
const rpc = (nome, corpo) => dbFetch(`${URL_BASE}/rest/v1/rpc/${nome}`, {
  method: 'POST',
  headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(corpo),
});

test("#1977 A': o corpo VIVO das 8 é igual à captura", { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
  for (const n of [HELPER, HELPER_BY_MEMBER, ...ALVOS.map((a) => a[0])]) {
    const r = await rpc('_audit_function_source', { p_proname: n });
    assert.equal(r.status, 200, `_audit_function_source falhou para ${n}`);
    const j = await r.json();
    const vivo = (Array.isArray(j) ? j[0] : j);
    assert.ok(vivo?.prosrc, `${n} não existe no banco`);
    const cap = latestFunctionCapture(ROOT, n);
    assert.equal(md5(normalizeBody(cap.body)), md5(normalizeBody(vivo.prosrc)),
      `${n}: corpo vivo diverge da captura ${cap.version} — produção e migration contam histórias diferentes`);
  }
});

test('#1977 C: no vivo, `_can_anywhere` DISCRIMINA e é SUPERCONJUNTO de `can()` sem recurso',
  { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
    // Deriva os conjuntos do DADO, sem fixar nenhum id: hardcode viraria mentira na próxima seed.
    const [rCombos, rEng] = await Promise.all([
      rest('engagement_kind_permissions?action=eq.write_board&select=kind,role,scope'),
      rest('auth_engagements?is_authoritative=eq.true&select=person_id,kind,role,initiative_id,legacy_tribe_id'),
    ]);
    assert.equal(rCombos.status, 200, 'leitura de engagement_kind_permissions falhou');
    assert.equal(rEng.status, 200, 'leitura de auth_engagements falhou');
    const combos = new Map((await rCombos.json()).map((c) => [`${c.kind}|${c.role}`, c.scope]));
    const engs = await rEng.json();
    assert.ok(combos.size > 0, 'nenhum combo de write_board — o teste passaria por vácuo');

    const org = new Set(); const hoje = new Set(); const anywhere = new Set(); const todos = new Set();
    for (const e of engs) {
      todos.add(e.person_id);
      const escopo = combos.get(`${e.kind}|${e.role}`);
      if (!escopo) continue;
      if (escopo === 'organization' || escopo === 'global') { org.add(e.person_id); hoje.add(e.person_id); anywhere.add(e.person_id); }
      else if (escopo === 'initiative' && e.initiative_id) {
        anywhere.add(e.person_id);
        if (e.legacy_tribe_id !== null && e.legacy_tribe_id !== undefined) hoje.add(e.person_id);
      }
    }

    // Superconjunto, na direção que importa: ninguém que passava pode ter deixado de passar.
    for (const p of hoje) {
      assert.ok(anywhere.has(p), `pessoa ${p} passava por can() e não passa por _can_anywhere — ESTREITOU`);
    }

    const forade = [...todos].find((p) => !anywhere.has(p));
    assert.ok(forade, 'ninguém sem autoridade de write_board — a asserção de discriminação passaria por vácuo');

    // DISCRIMINA: quem não tem combo nenhum não pode passar. É isto que pega um helper degenerado.
    const rNao = await rpc(HELPER, { p_person_id: forade, p_action: 'write_board' });
    assert.equal(await rNao.json(), false,
      `_can_anywhere devolveu true para ${forade}, que não tem combo de write_board — helper degenerado`);

    // ...e quem tem, passa.
    const dentro = [...hoje][0];
    assert.ok(dentro, 'ninguém com write_board — o par de asserções passaria por vácuo');
    const rSim = await rpc(HELPER, { p_person_id: dentro, p_action: 'write_board' });
    assert.equal(await rSim.json(), true, `_can_anywhere negou ${dentro}, que tem write_board vigente`);

    // O caso QUE MOTIVA a issue: escopo de iniciativa sem tribo legada. Pode ser vazio num dia em
    // que só existam tribos, e aí a afirmação é honestamente inaplicável em vez de falsa.
    const soAnywhere = [...anywhere].filter((p) => !hoje.has(p));
    if (soAnywhere.length > 0) {
      const alvo = soAnywhere[0];
      const [ra, rc] = await Promise.all([
        rpc(HELPER, { p_person_id: alvo, p_action: 'write_board' }),
        rpc('can', { p_person_id: alvo, p_action: 'write_board' }),
      ]);
      assert.equal(await ra.json(), true, `_can_anywhere negou ${alvo}, que tem write_board escopado a iniciativa sem tribo legada`);
      assert.equal(await rc.json(), false, `can() sem recurso passou a aceitar ${alvo} — a cláusula permissiva mudou, e a etapa 4 não foi executada`);
    }
  });
