/**
 * public_members não carrega localização, e get_public_impact_data não nomeia liderança de linha.
 *
 * Por quê (04/10/2026):
 *   - public_members é legível por anon (SECURITY DEFINER aceito na ADR-0024). A /privacy diz que o
 *     estado de residência só aparece agregado (piso de 3, com consentimento) e que, sem opt-in,
 *     ninguém recebe pin individual de estado nem de país. Quem aplica essas regras são as RPCs do
 *     mapa. Toda coluna da view fica visível para anon, então a lista é FECHADA: coluna nova só entra
 *     acrescentada a COLUNAS_PERMITIDAS, com a base da D1 da #2553 (LIA por finalidade).
 *   - get_public_impact_data é chamável por anon. Até 24/10/2026 devolvia tribes_summary[].leader_name
 *     só enquanto a pessoa estava no papel (D1 da #2553, emenda 1). Pela decisão 4a do GP (24/10/2026,
 *     DB-4 da #2553) o /about mostra pessoas só em número: o nome da liderança saiu da resposta, e o
 *     guard 2553-about-sem-nome-de-pessoa cobre as outras chaves com nome.
 *
 * Camadas:
 *   1. estática: a migration mais nova que cria a view, e a captura mais nova da função, cada uma
 *      afirmada dentro do bloco que decide (a lista de colunas; o tribes_summary sem leader_name);
 *   2. viva, como ANON (a credencial de quem consome a vitrine; o papel da chave é conferido), com
 *      controle positivo na mesma medição e recusas calibradas pelo código (42703, 42501);
 *   3. viva, população inteira: nenhuma tribo do payload traz o nome da liderança, e o nome de nenhuma
 *      pessoa apontada como liderança de linha (no papel ou fora dele) aparece no payload.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const MIG_DIR = join(ROOT, 'supabase/migrations');

const BASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(BASE_URL && ANON_KEY && SERVICE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_ANON_KEY + SUPABASE_SERVICE_ROLE_KEY required';

// As colunas de 04/10/2026. "Contido em", nunca "igual a": a D1 pode enxugar sem mexer aqui.
const COLUNAS_PERMITIDAS = new Set([
  'id', 'name', 'photo_url', 'chapter', 'operational_role', 'designations', 'tribe_id',
  'initiative_id', 'current_cycle_active', 'is_active', 'linkedin_url', 'credly_badges',
  'credly_url', 'credly_verified_at', 'cpmai_certified', 'cpmai_certified_at', 'cycles',
  'created_at', 'share_whatsapp', 'member_status', 'is_founder',
]);
const LOCALIZACAO = ['state', 'country'];
const UUID_INEXISTENTE = '00000000-0000-0000-0000-000000000000';

/** Comentário de linha e de bloco viram espaço, preservando offsets. */
function semComentarios(sql) {
  return maskLineComments(sql).replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
}

// Forma estrita, a única cuja lista de colunas sabemos recortar. Aceita aspas, schema opcional,
// lista de nomes e WITH (...) antes do AS.
const VIEW_ESTRITA = /\bCREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:"?public"?\s*\.\s*)?"?public_members"?\s*(?:\([^)]*\)\s*)?(?:WITH\s*\([^)]*\)\s*)?AS\s+SELECT\s+([\s\S]*?)\bFROM\b/gi;
// Forma frouxa: qualquer definição da view. Se casar mais vezes que a estrita, há uma forma que o
// recorte não entende, e o guard reprova em vez de continuar lendo a migration antiga.
const VIEW_FROUXA = /\bCREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:"?public"?\s*\.\s*)?"?public_members"?[\s(]/gi;

function listaDaView() {
  let ultimo = null;
  for (const f of readdirSync(MIG_DIR).filter((n) => n.endsWith('.sql')).sort()) {
    const sql = semComentarios(readFileSync(join(MIG_DIR, f), 'utf8'));
    const estritas = [...sql.matchAll(VIEW_ESTRITA)];
    const frouxas = [...sql.matchAll(VIEW_FROUXA)];
    if (frouxas.length !== estritas.length) {
      throw new Error(`${f}: ${frouxas.length} definição(ões) de public_members e só ${estritas.length} reconhecida(s). Ensine a forma nova a este guard.`);
    }
    if (estritas.length) ultimo = { file: f, lista: estritas[estritas.length - 1][1] };
  }
  if (!ultimo) throw new Error('nenhuma migration cria public.public_members');
  return ultimo;
}

test('view: toda coluna de public_members está na lista permitida, e nenhuma é localização', () => {
  const { file, lista } = listaDaView();
  const itens = lista.split(',').map((c) => c.trim());
  // Controle positivo no mesmo recorte: se ele voltasse vazio, as negativas abaixo ficariam verdes
  // sem ler nada.
  assert.ok(itens.includes('name'), `${file}: a lista recortada não tem name, o recorte está errado`);
  for (const item of itens) {
    assert.match(item, /^"?[a-z_][a-z0-9_]*"?$/i,
      `${file}: "${item}" não é coluna simples. Expressão, alias ou * na view decide o que anon lê sem passar por esta lista.`);
    const col = item.replace(/"/g, '').toLowerCase();
    assert.ok(!LOCALIZACAO.includes(col),
      `${file}: public_members seleciona ${col}. A view é legível por anon e a /privacy só permite localização agregada, pelas RPCs do mapa.`);
    assert.ok(COLUNAS_PERMITIDAS.has(col),
      `${file}: ${col} não está em COLUNAS_PERMITIDAS. Se é para ser pública, acrescente aqui com a base da D1 (#2553).`);
  }
});

test('função: tribes_summary não leva o nome da liderança nem lê o ponteiro dela', () => {
  const cap = latestFunctionCapture(ROOT, 'get_public_impact_data');
  const corpo = semComentarios(cap.body);
  const resumo = corpo.match(/'tribes_summary', COALESCE\(\([\s\S]*?\) ORDER BY t\.id\)\s+FROM tribes t\s+WHERE t\.is_active\s+\), '\[\]'::jsonb\)/);
  assert.ok(resumo, `${cap.file}: o bloco do tribes_summary não foi recortado`);
  assert.match(resumo[0], /'member_count', \(SELECT COUNT\(\*\) FROM members m WHERE m\.tribe_id = t\.id AND m\.is_active\)/,
    `${cap.file}: o controle (a contagem por linha) sumiu do recorte`);
  assert.equal((corpo.match(/'leader_name'/g) || []).length, 0, `${cap.file}: a chave leader_name voltou`);
  assert.equal((corpo.match(/\bleader_member_id\b/g) || []).length, 0,
    `${cap.file}: a função voltou a ler o ponteiro da liderança`);
});

const anonHeaders = () => ({ apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` });
const serviceHeaders = () => ({ apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` });

/** O teste diz "como anon": a chave tem de ser anon de fato, não outra que alguém pôs na variável. */
function assertChaveAnon() {
  const partes = ANON_KEY.split('.');
  if (partes.length === 3) {
    const payload = JSON.parse(Buffer.from(partes[1], 'base64url').toString('utf8'));
    assert.equal(payload.role, 'anon', `a chave usada como anon tem papel ${payload.role}`);
  } else {
    assert.match(ANON_KEY, /^sb_publishable_/, 'a chave usada como anon não é JWT anon nem chave publicável');
  }
}

test('DB como anon: public_members recusa localização e escrita, e serve o resto', { skip: dbGated ? false : skipMsg }, async () => {
  assertChaveAnon();
  const ok = await dbFetch(`${BASE_URL}/rest/v1/public_members?select=name&limit=1`, { headers: anonHeaders() });
  assert.equal(ok.status, 200, `controle positivo: anon não leu name (${ok.status})`);
  assert.equal((await ok.json()).length, 1, 'controle positivo: name voltou sem linha');

  for (const col of LOCALIZACAO) {
    const res = await dbFetch(`${BASE_URL}/rest/v1/public_members?select=${col}&limit=1`, { headers: anonHeaders() });
    const corpo = await res.text();
    assert.equal(res.status, 400, `anon pediu ${col} e recebeu ${res.status}`);
    assert.match(corpo, /"code":"42703"/, `a recusa de ${col} não foi "coluna inexistente" (42703)`);
  }

  const tudo = await dbFetch(`${BASE_URL}/rest/v1/public_members?select=*&limit=1`, { headers: anonHeaders() });
  assert.equal(tudo.status, 200, `select=* como anon voltou ${tudo.status}`);
  const [linha] = await tudo.json();
  assert.ok(linha && 'name' in linha, 'select=* sem name: o controle positivo falhou');
  const fora = Object.keys(linha).filter((c) => !COLUNAS_PERMITIDAS.has(c));
  assert.deepEqual(fora, [], `select=* como anon devolve coluna fora da lista: ${fora.join(', ')}`);

  // DROP + CREATE de view sobre members herda ALL do default privilege; só o REVOKE fecha. O id não
  // existe, então nada muda mesmo se o ACL regredir.
  for (const metodo of ['PATCH', 'DELETE']) {
    const res = await dbFetch(`${BASE_URL}/rest/v1/public_members?id=eq.${UUID_INEXISTENTE}`, {
      method: metodo,
      headers: { ...anonHeaders(), 'Content-Type': 'application/json' },
      body: metodo === 'PATCH' ? JSON.stringify({ name: 'x' }) : undefined,
    });
    const corpo = await res.text();
    assert.equal(res.status, 401, `${metodo} como anon voltou ${res.status}`);
    assert.match(corpo, /"code":"42501"/, `${metodo} como anon não foi recusado por permissão (42501)`);
  }
});

test('DB: nenhuma tribo do payload público traz o nome da liderança, no papel ou fora dele (população inteira)', { skip: dbGated ? false : skipMsg }, async () => {
  assertChaveAnon();
  const r = await dbFetch(`${BASE_URL}/rest/v1/rpc/get_public_impact_data`, {
    method: 'POST',
    headers: { ...anonHeaders(), 'Content-Type': 'application/json' },
    body: '{}',
  });
  assert.equal(r.status, 200, `get_public_impact_data como anon voltou ${r.status}`);
  const payload = await r.json();
  const resumo = payload.tribes_summary;

  const rt = await dbFetch(`${BASE_URL}/rest/v1/tribes?select=id,is_active,leader_member_id`, { headers: serviceHeaders() });
  assert.equal(rt.status, 200, `leitura de tribes voltou ${rt.status}`);
  const tribos = await rt.json();

  // #2365: tribes_summary lista só as tribos ativas, como o contador `tribes`.
  const ativas = tribos.filter((tr) => tr.is_active);
  assert.equal(resumo.length, ativas.length, 'tribes_summary não cobre exatamente as tribos ativas');
  const comNome = resumo.filter((linha) => 'leader_name' in linha).map((linha) => linha.id);
  assert.deepEqual(comNome, [], `tribos com a chave leader_name: ${comNome.join(', ')}`);

  // Nenhum nome de quem é ou foi apontado como liderança de linha aparece no payload, sob chave nenhuma.
  const ids = [...new Set(tribos.map((tr) => tr.leader_member_id).filter(Boolean))];
  assert.ok(ids.length > 0, 'nenhum ponteiro de liderança: a varredura não tem o que procurar');
  const rp = await dbFetch(`${BASE_URL}/rest/v1/members?select=id,name&id=in.(${ids.join(',')})`, { headers: serviceHeaders() });
  assert.equal(rp.status, 200, `leitura de members voltou ${rp.status}`);
  const nomes = (await rp.json()).map((p) => p.name).filter(Boolean);
  assert.ok(nomes.length > 0, 'nenhum nome de liderança lido: a varredura não discrimina');
  const texto = JSON.stringify(payload);
  // Só a contagem na mensagem: o nome é justamente o dado que este guard protege.
  const achados = nomes.filter((nome) => texto.includes(JSON.stringify(nome).slice(1, -1))).length;
  assert.equal(achados, 0, `${achados} nome(s) de liderança de linha no payload público`);
});
