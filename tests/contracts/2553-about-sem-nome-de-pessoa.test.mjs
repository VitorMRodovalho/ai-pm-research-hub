// #2553 D7, DB-4 (GP 24/10/2026): get_public_impact_data, lida por anon no /about, pelo MCP do Núcleo e por
// consumidores externos, não devolve nome de pessoa. Pessoas aparecem só em número (decisão 4a), e o prêmio
// individual saiu da RPC e da página (decisão 5).
//
// O QUE ESTE GUARD AFIRMA
//   A. Na captura mais nova da função: nenhuma das chaves que saíram (leader_name, sponsor, authors, partners,
//      recognitions), nenhuma leitura de nome ou designação de members, a publicação sem autoria, e a entrada 2024 da
//      timeline no texto sem o nome do patrocinador. partner_count e tribes_summary continuam.
//   B. A página não lê nem mostra nenhuma dessas chaves.
//   C. Os dois instrumentos do item D sabem dizer não: a lista fechada de caminhos reprova uma chave que saiu, e a
//      busca de nomes acha um nome plantado numa frase (exercidos aqui, sem banco).
//   D. (banco) Como anon, a credencial de quem lê a vitrine: todo caminho da resposta está na lista fechada, e nenhum
//      nome do cadastro de membros aparece em texto nenhum da resposta.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const SAIRAM = ['leader_name', 'sponsor', 'authors', 'partners', 'recognitions'];

// Os caminhos da resposta em 24/10/2026, depois do DB-4. Caminho novo só entra acrescentado aqui, de propósito:
// a função é lida por anon, e uma chave nova é exposição nova.
const CAMINHOS = new Set([
  'active_members', 'articles_approved', 'articles_published', 'chapters', 'chapters_engaged', 'chapters_signed',
  'chapters_summary[].chapter', 'chapters_summary[].member_count', 'courses_count', 'ia_pilots', 'impact_hours',
  'impact_hours_since', 'partner_count', 'recent_publications[].external_url', 'recent_publications[].platform',
  'recent_publications[].publication_date', 'recent_publications[].title', 'timeline[].description', 'timeline[].title',
  'timeline[].year', 'timeline_is_narrative', 'total_attendance_hours', 'total_events', 'tribes', 'tribes_summary[].id',
  'tribes_summary[].member_count', 'tribes_summary[].name', 'tribes_summary[].quadrant_name', 'webinars',
]);

/** Cada folha da resposta: caminho com índice de lista apagado, e o valor. */
function folhas(v, p = '', out = []) {
  if (Array.isArray(v)) { for (const x of v) folhas(x, `${p}[]`, out); return out; }
  if (v && typeof v === 'object') { for (const [k, x] of Object.entries(v)) folhas(x, p ? `${p}.${k}` : k, out); return out; }
  out.push({ caminho: p, valor: v });
  return out;
}
const foraDaLista = (payload) => [...new Set(folhas(payload).map((f) => f.caminho))].filter((c) => !CAMINHOS.has(c));
/**
 * Caminhos da resposta cujo texto contém um nome do cadastro (duas palavras ou mais). Devolve o caminho, nunca o
 * nome: o log do CI deste repositório é público.
 */
function nomesNaResposta(payload, nomes) {
  const alvos = nomes
    .map((n) => String(n ?? '').trim().replace(/\s+/g, ' ').toLocaleLowerCase('pt-BR'))
    .filter((n) => n.split(' ').length >= 2);
  const textos = folhas(payload).filter((f) => typeof f.valor === 'string');
  return [...new Set(textos.filter((f) => alvos.some((n) => f.valor.toLocaleLowerCase('pt-BR').includes(n))).map((f) => f.caminho))];
}

const cap = latestFunctionCapture(ROOT, 'get_public_impact_data');
const CORPO = cap ? maskLineComments(cap.body) : '';
const ISLAND = maskJsComments(readFileSync('src/components/islands/ImpactPageIsland.tsx', 'utf8'));

describe('#2553 DB-4: o /about sem nome de pessoa', () => {
  it('A: a função não devolve nem lê nome de pessoa, e a timeline não nomeia o patrocinador', () => {
    assert.ok(cap, 'get_public_impact_data não foi capturada');
    for (const k of SAIRAM) assert.doesNotMatch(CORPO, new RegExp(`'${k}'\\s*,`), `${cap.file}: a chave ${k} voltou`);
    // PR3 A1 (GP 25/10/2026): a contagem dos capítulos passou de members para v_operational_members (a base do
    // cabeçalho). A view também é de pessoas, então o alias dela entra na mesma verificação de .name/.designations,
    // e o piso de 2 contagens continua (linha em members, capítulo na view).
    const aliases = [...CORPO.matchAll(/\b(?:FROM|JOIN)\s+(?:public\.)?(?:v_operational_)?members\s+(?:AS\s+)?(\w+)/gi)].map((m) => m[1]);
    assert.ok(aliases.length >= 2, `${cap.file}: as contagens de pessoas não foram achadas (${aliases.length})`);
    for (const a of new Set(aliases)) {
      assert.doesNotMatch(CORPO, new RegExp(`\\b${a}\\.(name|designations)\\b`), `${cap.file}: lê ${a}.name ou ${a}.designations`);
    }
    assert.match(CORPO, /FROM \(SELECT title, external_platform AS platform, publication_date, external_url\s+FROM public_publications WHERE is_published = true/);
    assert.match(CORPO, /'partner_count', \(SELECT COUNT\(\*\) FROM partner_entities WHERE status = 'active'\),/);
    assert.match(CORPO, /jsonb_build_object\('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO\. Experimentação e lições aprendidas\.'\),/);
    assert.doesNotMatch(CORPO, /Patroc[ií]nio/);
  });

  it('B: a página não lê nem mostra as chaves que saíram', () => {
    for (const k of SAIRAM) assert.doesNotMatch(ISLAND, new RegExp(`\\b${k}\\b`), `ImpactPageIsland lê ${k}`);
    assert.doesNotMatch(ISLAND, /\brecipient\b|recognitionsSection|partnersSection/);
  });

  it('C: os instrumentos do item D reprovam o que devem reprovar', () => {
    const limpo = { tribes: 1, tribes_summary: [{ id: 1, name: 'Linha', quadrant_name: 'Q', member_count: 2 }] };
    assert.deepEqual(foraDaLista(limpo), []);
    assert.deepEqual(foraDaLista({ ...limpo, recognitions: [{ recipient: 'x' }] }), ['recognitions[].recipient']);
    assert.deepEqual(foraDaLista({ ...limpo, tribes_summary: [{ ...limpo.tribes_summary[0], leader_name: 'x' }] }), ['tribes_summary[].leader_name']);
    const nomes = ['Fulana de Tal Exemplo', 'Ciclano', null];
    assert.deepEqual(nomesNaResposta(limpo, nomes), []);
    const plantado = { ...limpo, timeline: [{ year: '2024', title: 'T', description: 'Concepção. Patrocínio fulana de tal exemplo.' }] };
    assert.deepEqual(nomesNaResposta(plantado, nomes), ['timeline[].description']);
  });

  const BASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
  const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
  const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const dbGated = !!(BASE_URL && ANON_KEY && SERVICE_KEY);

  it('D: (banco) como anon, só caminhos da lista e nenhum nome do cadastro', { skip: dbGated ? false : 'SUPABASE_URL + anon + service role required' }, async () => {
    // a chave usada como anon tem de ser anon de fato
    const partes = ANON_KEY.split('.');
    if (partes.length === 3) assert.equal(JSON.parse(Buffer.from(partes[1], 'base64url').toString('utf8')).role, 'anon');
    else assert.match(ANON_KEY, /^sb_publishable_/);

    const r = await dbFetch(`${BASE_URL}/rest/v1/rpc/get_public_impact_data`, {
      method: 'POST',
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    assert.equal(r.status, 200, `get_public_impact_data como anon voltou ${r.status}`);
    const payload = await r.json();
    // controle positivo: a descida alcança as listas
    assert.ok(Array.isArray(payload.tribes_summary) && payload.tribes_summary.length > 0, 'tribes_summary vazio: o controle não discrimina');
    assert.ok(folhas(payload).some((f) => f.caminho === 'tribes_summary[].name'), 'a descida não chegou às folhas das listas');
    assert.deepEqual(foraDaLista(payload), [], 'caminho fora da lista fechada');

    const m = await dbFetch(`${BASE_URL}/rest/v1/members?select=name`, {
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    });
    assert.equal(m.status, 200, `leitura de members voltou ${m.status}`);
    const nomes = (await m.json()).map((x) => x.name);
    assert.ok(nomes.length > 0, 'cadastro de membros vazio: a busca de nomes não discrimina');
    assert.deepEqual(nomesNaResposta(payload, nomes), [], 'caminho da resposta pública com nome do cadastro');
  });
});
