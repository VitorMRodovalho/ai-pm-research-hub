/**
 * public_members não carrega localização, e get_public_impact_data nomeia só o líder atual.
 *
 * Por quê (04/10/2026):
 *   - public_members é legível por anon (SECURITY DEFINER aceito na ADR-0024). A /privacy diz que o
 *     estado de residência só aparece agregado (piso de 3, com consentimento) e que, sem opt-in,
 *     ninguém recebe pin individual de estado nem de país. Quem aplica essas regras são as RPCs do
 *     mapa. Toda coluna da view fica visível para anon, então a lista é FECHADA: coluna nova só entra
 *     acrescentada a COLUNAS_PERMITIDAS, com a base da D1 da #2553 (LIA por finalidade).
 *   - get_public_impact_data é chamável por anon e devolve tribes_summary[].leader_name. Pela D1 da
 *     #2553 (emenda 1), o nome de quem ocupa papel institucional sai só enquanto a pessoa está no
 *     papel: tribo ativa e pessoa ativa no ciclo corrente.
 *
 * Camadas:
 *   1. estática: a migration mais nova que cria a view, e a captura mais nova da função, cada uma
 *      afirmada dentro do bloco que decide (a lista de colunas; o subselect do leader_name);
 *   2. viva, como ANON (a credencial de quem consome a vitrine; o papel da chave é conferido), com
 *      controle positivo na mesma medição e recusas calibradas pelo código (42703, 42501);
 *   3. viva, população inteira: cada tribo do payload contra o estado de tribo e pessoa no banco, nos
 *      dois sentidos, com braço negativo obrigatório.
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

/** Fatia do parêntese em `inicio` até o que o fecha, pulando literais entre aspas simples. */
function parenteseBalanceado(s, inicio) {
  assert.equal(s[inicio], '(', 'esperava um parêntese de abertura');
  let nivel = 0;
  let aspas = false;
  for (let i = inicio; i < s.length; i++) {
    const c = s[i];
    if (c === "'") aspas = !aspas;
    if (aspas) continue;
    if (c === '(') nivel++;
    if (c === ')' && --nivel === 0) return s.slice(inicio, i + 1);
  }
  throw new Error('parêntese sem fechamento');
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

test('função: leader_name só sai com tribo ativa e pessoa ativa no ciclo', () => {
  const cap = latestFunctionCapture(ROOT, 'get_public_impact_data');
  const corpo = semComentarios(cap.body);
  const chaves = corpo.match(/'leader_name'/g) || [];
  assert.equal(chaves.length, 1, `${cap.file}: esperava exatamente 1 'leader_name', achei ${chaves.length}`);
  const ponteiros = corpo.match(/\bleader_member_id\b/g) || [];
  assert.equal(ponteiros.length, 1,
    `${cap.file}: leader_member_id aparece ${ponteiros.length} vezes. Outra chave que leia o ponteiro precisa do mesmo filtro; ensine este guard.`);
  const sub = parenteseBalanceado(corpo, corpo.indexOf('(', corpo.indexOf("'leader_name'")));
  assert.match(sub, /\bFROM\s+members\s+(?:AS\s+)?m\b[\s\S]*\bm\.id\s*=\s*t\.leader_member_id\b/i,
    `${cap.file}: o subselect do leader_name não lê a pessoa referenciada pela tribo`);
  // Predicado nu, ancorado no AND seguinte ou no fecha-parêntese: `IS NOT NULL`, `= false` e afins não passam.
  const fim = String.raw`(?=\s+AND\b|\s*\))`;
  assert.match(sub, new RegExp(String.raw`\bAND\s+m\.is_active${fim}`, 'i'), `${cap.file}: leader_name sem a condição de pessoa ativa`);
  assert.match(sub, new RegExp(String.raw`\bAND\s+m\.current_cycle_active${fim}`, 'i'), `${cap.file}: leader_name sem a condição de ciclo corrente`);
  assert.match(sub, new RegExp(String.raw`\bAND\s+m\.member_status\s*=\s*'active'${fim}`, 'i'), `${cap.file}: leader_name sem a condição de status ativo`);
  assert.match(sub, new RegExp(String.raw`\bAND\s+t\.is_active${fim}`, 'i'), `${cap.file}: leader_name sem a condição de tribo ativa`);
  assert.doesNotMatch(sub, /\bOR\b/i, `${cap.file}: um OR no subselect do leader_name reabre o nome de quem saiu`);
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

test('DB: cada tribo do payload público nomeia só líder ativo de tribo ativa (população inteira)', { skip: dbGated ? false : skipMsg }, async (t) => {
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
  const ids = [...new Set(tribos.map((tr) => tr.leader_member_id).filter(Boolean))];
  let pessoas = [];
  if (ids.length) {
    const rp = await dbFetch(`${BASE_URL}/rest/v1/members?select=id,name,is_active,current_cycle_active,member_status&id=in.(${ids.join(',')})`, { headers: serviceHeaders() });
    assert.equal(rp.status, 200, `leitura de members voltou ${rp.status}`);
    pessoas = await rp.json();
  }
  const porId = new Map(pessoas.map((p) => [p.id, p]));
  const esperado = new Map(tribos.map((tr) => {
    const p = porId.get(tr.leader_member_id);
    const atual = !!(tr.is_active && p && p.is_active && p.current_cycle_active && p.member_status === 'active');
    return [tr.id, atual ? p.name : null];
  }));

  assert.equal(resumo.length, tribos.length, 'tribes_summary não cobre todas as tribos');
  // Só ids na mensagem: o nome é justamente o dado que este guard protege.
  const divergentes = resumo
    .filter((linha) => (linha.leader_name ?? null) !== esperado.get(linha.id))
    .map((linha) => `tribo ${linha.id}: nome ${linha.leader_name != null ? 'presente' : 'ausente'}, esperado ${esperado.get(linha.id) != null ? 'o líder atual' : 'ausente'}`);
  assert.deepEqual(divergentes, [], divergentes.join('; '));
  assert.ok([...esperado.values()].some((v) => v != null), 'nenhuma tribo com líder atual: o braço positivo não disparou');

  // Braço negativo: precisa existir quem saiu, senão a regra removida passaria aqui.
  const excluidos = tribos
    .filter((tr) => tr.leader_member_id && esperado.get(tr.id) == null)
    .map((tr) => porId.get(tr.leader_member_id)?.name)
    .filter(Boolean);
  if (excluidos.length === 0) return t.skip('nenhum ponteiro de líder aponta para quem saiu hoje: o braço negativo não tem caso');
  // O nome de quem saiu não pode aparecer em lugar nenhum do payload, sob outra chave inclusive.
  // Autoria de obra publicada fica fora da varredura: pela D1 ela permanece depois da saída.
  const { recent_publications: _autoria, ...semAutoria } = payload;
  const texto = JSON.stringify(semAutoria);
  const achados = excluidos.filter((nome) => texto.includes(JSON.stringify(nome).slice(1, -1))).length;
  assert.equal(achados, 0, `${achados} nome(s) de quem saiu do papel ainda aparece(m) no payload público`);
});
