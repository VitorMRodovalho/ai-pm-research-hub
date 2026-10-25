// PR3: decisões do GP de 25/10/2026 para o site público.
//
// O QUE ESTE GUARD AFIRMA
//   A1. /about, "Capítulos participantes": a lista é a dos capítulos engajados (os mesmos status de
//       get_chapter_metrics 'engaged'), sem status jurídico na saída; a contagem vem da base do cabeçalho
//       (v_operational_members) e só sai a partir do k do mapa da home, lido da função do mapa, não escrito aqui;
//       a página mostra o número só quando ele vem, e a seção se chama "capítulos participantes" nas 3 línguas.
//   A4. A linha do Summit entrou na timeline depois de 2026.2, sem o painel do dia 22.
//   A3. A meta "Entidades Parceiras" conta só os tipos que o CRM oferece para governo, academia e empresa, e só
//       com termo assinado no registro que link_attachment_to_governance grava.
//   C2. "Quem faz": a curadoria soma o Comitê de Curadoria (_wiki_committee_ids) aos curadores engajados, sem
//       repetir pessoa; a gestão continua igual. Nenhum termo de portão do #965 entrou nos corpos.
//   A5. Nenhum nome longo em inglês sobra em src/, o nome curto está nos lugares nomeados pela decisão e os nomes
//       em português e espanhol ficaram como estavam.
//   (banco) Como anon, o efeito das três funções bate com as fontes lidas pela service role na mesma rodada.
//
// Asserções amarram a CONDIÇÃO ao RESULTADO dentro do bloco que decide, sobre a captura vigente de cada função
// (latestFunctionCapture) com comentários mascarados.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const cap = (name) => latestFunctionCapture(ROOT, name);
const IMPACT_CAP = cap('get_public_impact_data');
const HEALTH_CAP = cap('exec_portfolio_health');
const TEAM_CAP = cap('get_public_home_team');
const IMPACT = maskLineComments(IMPACT_CAP.body);
const HEALTH = maskLineComments(HEALTH_CAP.body);
const TEAM = maskLineComments(TEAM_CAP.body);
const REACH = maskLineComments(cap('get_public_country_reach').body);
const METRICS = maskLineComments(cap('get_chapter_metrics').body);
const ISLAND = maskJsComments(readFileSync('src/components/islands/ImpactPageIsland.tsx', 'utf8'));
const CRM = maskJsComments(readFileSync('src/pages/admin/partnerships.astro', 'utf8'));
const ABOUT = maskJsComments(readFileSync('src/pages/about.astro', 'utf8'));
const LANGS = ['pt-BR', 'en-US', 'es-LATAM'];
const DICT = Object.fromEntries(LANGS.map((l) => [l, readFileSync(`src/i18n/${l}.ts`, 'utf8')]));
const dictValue = (lang, key) => {
  const m = DICT[lang].match(new RegExp(`^  '${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}': '([^']*)',$`, 'm'));
  return m ? m[1] : null;
};

/** O trecho de `src` entre `from` e `to` (exclusivo), com falha clara se algum marco sumir. */
function cut(src, from, to) {
  const a = src.indexOf(from);
  assert.ok(a >= 0, `marco não encontrado: ${from}`);
  const b = src.indexOf(to, a + from.length);
  assert.ok(b > a, `marco final não encontrado: ${to}`);
  return src.slice(a, b);
}
const literals = (list) => [...list.matchAll(/'([^']*)'/g)].map((m) => m[1]).sort();

describe('PR3, estático', () => {
  it('A1: a lista é a dos engajados, sem status na saída, e a contagem só sai a partir do k do mapa', () => {
    const bloco = cut(IMPACT, "'chapters_summary', COALESCE((", "'timeline_is_narrative'");
    // a população: os mesmos status do 'engaged' de get_chapter_metrics, nacionais
    const engaged = METRICS.match(/'engaged', \(SELECT count\(\*\)::int FROM public\.partner_entities WHERE entity_type = 'pmi_chapter' AND status IN \(([^)]*)\) AND NOT COALESCE\(is_international, false\)\)/);
    assert.ok(engaged, "o 'engaged' de get_chapter_metrics mudou de forma");
    const pop = bloco.match(/FROM partner_entities pe\s+CROSS JOIN LATERAL \([\s\S]*?\) n\s+WHERE pe\.entity_type = 'pmi_chapter' AND pe\.status IN \(([^)]*)\)\s+AND NOT COALESCE\(pe\.is_international, false\)/);
    assert.ok(pop, `${IMPACT_CAP.file}: a população dos cards não é a dos capítulos engajados nacionais`);
    assert.deepEqual(literals(pop[1]), literals(engaged[1]), 'os status dos cards não são os do engaged');

    // a contagem: base do cabeçalho, casando o nome do CRM ou 'PMI-' || código, que é o que o membro guarda
    assert.match(bloco, /CROSS JOIN LATERAL \(\s*SELECT COUNT\(\*\) AS people FROM public\.v_operational_members om\s+WHERE om\.chapter = pe\.name OR om\.chapter = 'PMI-' \|\| pe\.chapter\s*\) n/);
    assert.match(IMPACT, /'active_members', \(SELECT COUNT\(\*\) FROM public\.v_operational_members\),/, 'o cabeçalho mudou de base');
    assert.doesNotMatch(bloco, /\bFROM\s+(?:public\.)?members\b/, 'os cards voltaram a contar members');

    // condição e resultado: o k decide se o número sai, e o k é o do mapa da home
    const k = bloco.match(/CASE WHEN n\.people >= (\d+) THEN n\.people END AS member_count/);
    const kMapa = REACH.match(/CASE WHEN n >= (\d+) AND code <> 'XX' THEN code ELSE 'ZZ' END AS country_code/);
    assert.ok(k && kMapa, 'o k dos cards ou o do mapa não foi achado');
    assert.equal(Number(k[1]), Number(kMapa[1]), 'o k dos cards não é o do mapa da home');

    // a saída: só capítulo e contagem, nada que diga assinado ou em negociação
    const saida = bloco.match(/jsonb_build_object\(([^)]*)\)\s+ORDER BY c\.member_count DESC NULLS LAST, c\.chapter/);
    assert.ok(saida, 'a linha ou a ordem dos cards mudou');
    assert.equal(saida[1], "'chapter', c.chapter, 'member_count', c.member_count");
    assert.doesNotMatch(bloco, /mou_stage|is_signed|'status'\s*,|'signed'\s*,/, 'os cards voltaram a ler ou devolver status');
  });

  it('A4: a linha do Summit vem depois de 2026.2, sem o painel do dia 22 e sem ano repetido', () => {
    const entradas = [...IMPACT.matchAll(/jsonb_build_object\('year', '([^']+)', 'title', '([^']*)', 'description', '([^']*)'\)/g)]
      .map((m) => ({ year: m[1], title: m[2], description: m[3] }));
    const i = entradas.findIndex((e) => e.title === 'PMI Global Summit 2026');
    assert.ok(i >= 0, `${IMPACT_CAP.file}: a linha do Summit não está na timeline`);
    assert.equal(i, entradas.findIndex((e) => e.year === '2026.2') + 1, 'a linha do Summit não vem logo depois de 2026.2');
    const s = entradas[i];
    assert.match(s.description, /Volunteer Live!/);
    assert.match(s.description, /Detroit/);
    assert.match(s.description, /21\/10\/2026/);
    assert.doesNotMatch(`${s.title} ${s.description}`, /22\/10|painel|panel|mesa/i, 'o painel do dia 22 entrou');
    const anos = entradas.map((e) => e.year);
    assert.deepEqual(anos.filter((a, j) => anos.indexOf(a) !== j), [], 'ano repetido (a página usa o ano como chave)');
  });

  it('A1: a página mostra o número só quando ele vem, e a seção é "capítulos participantes" nas 3 línguas', () => {
    assert.match(ISLAND, /chapters_summary: Array<\{ chapter: string; member_count: number \| null \}>;/);
    const cards = cut(ISLAND, 'data.chapters_summary.map(', '))}');
    assert.match(cards, /\{typeof ch\.member_count === 'number' && \(\s*<>\s*<div [^>]*>\{ch\.member_count\}<\/div>\s*<div [^>]*>\{membersLabel\(ch\.member_count\)\}<\/div>\s*<\/>\s*\)\}/,
      'o número do card não depende de ele vir');
    const esperado = { 'pt-BR': 'Capítulos participantes', 'en-US': 'Participating chapters', 'es-LATAM': 'Capítulos participantes' };
    for (const lang of LANGS) {
      const bloco = cut(ISLAND, `'${lang}': {`, 'leadConsentRequired');
      assert.match(bloco, new RegExp(`chaptersSection: '${esperado[lang]}',`), `${lang}: título da seção`);
    }
    assert.doesNotMatch(ISLAND, /Patrocinador|Sponsoring/, 'o título antigo sobrou');
  });

  it('A3: a meta conta os tipos que o CRM oferece para governo, academia e empresa, e só com termo assinado', () => {
    const ramo = cut(HEALTH, "WHEN 'partner_entities' THEN", "WHEN 'certification_trail' THEN");
    // condição e resultado no mesmo comando: tipos, ativo, ano e o termo assinado decidem a contagem
    const m = ramo.match(/SELECT COUNT\(\*\)::numeric INTO v_current\s+FROM public\.partner_entities pe\s+WHERE pe\.entity_type IN \(([^)]*)\)\s+AND pe\.status = 'active'\s+AND pe\.partnership_date >= v_year_start\s+AND EXISTS \(\s*SELECT 1 FROM public\.governance_documents gd\s+WHERE gd\.partner_entity_id = pe\.id\s+AND gd\.doc_type = 'cooperation_agreement'\s+AND gd\.status = 'active'\s+AND gd\.signed_at IS NOT NULL\s*\);/);
    assert.ok(m, `${HEALTH_CAP.file}: o ramo partner_entities não conta só parceria com termo assinado`);
    const tipos = literals(m[1]);
    assert.deepEqual(tipos, ['academia', 'academic', 'empresa', 'governo'], 'os tipos da meta mudaram');
    // nenhum tipo fantasma: todo tipo da meta é uma opção do cadastro do CRM (o defeito era filtrar 'academia'
    // enquanto o CRM gravava 'academic')
    const select = cut(CRM, '<select id="modal-type"', '</select>');
    const opcoes = [...select.matchAll(/<option value="([^"]+)"/g)].map((o) => o[1]);
    assert.ok(opcoes.length >= 5, 'as opções de tipo do CRM não foram lidas');
    for (const t of tipos) assert.ok(opcoes.includes(t), `o tipo ${t} não é oferecido pelo CRM`);
    // o registro que a meta lê é o que o caminho de termo assinado grava
    const link = maskLineComments(cap('link_attachment_to_governance').body);
    assert.match(link, /INSERT INTO governance_documents \(title, doc_type, status, pdf_url, partner_entity_id, signed_at,/);
    assert.match(link, /VALUES \(p_title, 'cooperation_agreement', 'active', v_attachment\.file_url,\s+v_attachment\.partner_entity_id, p_signed_at,/);
  });

  it('C2: a curadoria soma o comitê aos curadores engajados, sem repetir pessoa, e a gestão segue igual', () => {
    const cur = cut(TEAM, "'curators', (", "'hub_members', (");
    assert.match(cur, /SELECT count\(DISTINCT c\.who\) FROM \(\s*SELECT le\.person_id AS who FROM live_engagements le WHERE le\.role = 'curator'\s+UNION ALL\s+SELECT coalesce\(m\.person_id, m\.id\) FROM public\.members m WHERE m\.id IN \(SELECT public\._wiki_committee_ids\(\)\)\s*\) c/);
    const gest = cut(TEAM, "'management', (", "'line_leaders', (");
    assert.match(gest, /SELECT count\(\*\) FROM active_members a\s+WHERE a\.operational_role IN \('manager', 'deputy_manager'\) OR 'co_gp' = ANY \(a\.designations\)\s*\),\s*$/);
    // o comitê é o mesmo do wiki: ativo, com login e com curate_content
    const cmt = maskLineComments(cap('_wiki_committee_ids').body);
    assert.match(cmt, /WHERE m\.is_active AND m\.member_status = 'active' AND m\.auth_id IS NOT NULL\s+AND public\.can_by_member\(m\.id, 'curate_content'\)/);
    assert.doesNotMatch(TEAM, /\.name\b|photo_url|linkedin_url|email/, 'a contagem passou a ler dado de pessoa');
  });

  it('#965: nenhum dos três corpos ganhou termo de portão (a varredura continua os enxergando como antes)', () => {
    for (const c of [IMPACT_CAP, HEALTH_CAP, TEAM_CAP]) {
      for (const tok of ['auth.uid()', 'can_by_member', 'public.can(', 'auth.role', 'current_setting']) {
        assert.ok(!c.body.includes(tok), `${c.file}: o corpo cita ${tok}`);
      }
    }
  });
});

// ── A5: o nome curto em inglês ────────────────────────────────────────────────────────────────────────────────
const LONGO = /\b(?:Stud(?:y|ies)\s+(?:and|&|&amp;)\s+Research\s+(?:Hub|Group|Center|Centre)|(?:AI|Artificial Intelligence)\s+(?:&|&amp;|and)\s+Project\s+Management\s+(?:Stud(?:y|ies)\s+(?:and|&|&amp;)\s+)?Research\s+Hub)\b/i;

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(astro|tsx?|mjs|js|json|md)$/.test(name) && name !== 'database.gen.ts') out.push(p);
  }
  return out;
}

describe('PR3 A5, estático', () => {
  it('o detector reprova o nome longo e aprova o curto (controle)', () => {
    for (const s of ['the AI & PM Study and Research Hub', 'AI &amp; PM Study and Research Hub',
      'AI & Project Management Study and Research Hub', 'About the AI & Project Management Research Hub',
      'the AI & PM Study and Research Group', 'Study and Research Hub in']) {
      assert.match(s, LONGO, `o detector não reprova: ${s}`);
    }
    for (const s of ['AI & PM Research Hub', 'Research Hub in', 'Núcleo de Estudos e Pesquisa em IA e GP']) {
      assert.doesNotMatch(s, LONGO, `o detector reprova o nome curto: ${s}`);
    }
  });

  it('nenhum nome longo em inglês sobra em src/', () => {
    const files = walk(join(ROOT, 'src'));
    assert.ok(files.length > 100, `a varredura leu só ${files.length} arquivos`);
    const hits = [];
    for (const f of files) {
      readFileSync(f, 'utf8').split('\n').forEach((line, i) => {
        if (LONGO.test(line)) hits.push(`${relative(ROOT, f)}:${i + 1}`);
      });
    }
    assert.deepEqual(hits, [], 'nome longo em inglês');
  });

  it('o nome curto nos lugares que a decisão nomeia; português e espanhol como estavam', () => {
    assert.equal(dictValue('en-US', 'cycleReport.printOrgName'), 'AI & PM Research Hub');
    assert.match(dictValue('en-US', 'nav.brand'), /^AI & PM Research Hub\b/);
    assert.match(dictValue('en-US', 'footer.line1'), /^AI & PM Research Hub · /);
    assert.match(dictValue('en-US', 'meta.description'), /^AI & PM Research Hub: /);
    assert.match(dictValue('en-US', 'meta.ogImageAlt'), /^AI & PM Research Hub: Research on Artificial Intelligence and Project Management\./);
    assert.match(ABOUT, /"name": lang === 'en-US' \? 'AI & PM Research Hub' : "Núcleo de Estudos e Pesquisa em IA & Gerenciamento de Projetos",/);
    assert.equal(dictValue('pt-BR', 'footer.line1'), 'Núcleo de Estudos e Pesquisa em IA e GP · The AI & PM Research Hub');
    assert.equal(dictValue('es-LATAM', 'footer.line1'), 'Núcleo de Estudios e Investigación en IA y GP · The AI & PM Research Hub');
    assert.equal(dictValue('pt-BR', 'cycleReport.printOrgName'), 'Núcleo de Estudos e Pesquisa em IA & Gerenciamento de Projetos');
    assert.equal(dictValue('es-LATAM', 'cycleReport.printOrgName'), 'Núcleo de Estudios e Investigación en IA & Gestión de Proyectos');
    assert.match(dictValue('pt-BR', 'nav.brand'), /^Núcleo IA & GP\b/);
    assert.match(dictValue('es-LATAM', 'nav.brand'), /^Núcleo IA & GP\b/);
  });
});

// ── (banco) o efeito, como anon ────────────────────────────────────────────────────────────────────────────────
const BASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const skip = BASE_URL && ANON_KEY && SERVICE_KEY ? false : 'SUPABASE_URL + anon + service role required';

const anonRpc = async (fn) => {
  const r = await dbFetch(`${BASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
  assert.equal(r.status, 200, `${fn} como anon voltou ${r.status}`);
  return r.json();
};
const svc = async (path, init = {}) => {
  const r = await dbFetch(`${BASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
  });
  assert.equal(r.status, 200, `${path} voltou ${r.status}`);
  return r.json();
};

describe('PR3, efeito no banco', { skip }, () => {
  it('A1: como anon, os cards são os engajados, sem número abaixo de 3, e somam a base filtrada pelo k', async () => {
    const partes = ANON_KEY.split('.');
    if (partes.length === 3) assert.equal(JSON.parse(Buffer.from(partes[1], 'base64url').toString('utf8')).role, 'anon');
    const imp = await anonRpc('get_public_impact_data');
    const pe = await svc('partner_entities?select=name,chapter&entity_type=eq.pmi_chapter&status=in.(active,negotiation)&is_international=eq.false');
    const om = await svc('v_operational_members?select=chapter');
    const cards = imp.chapters_summary;
    assert.deepEqual(cards.map((c) => c.chapter).sort(), pe.map((p) => p.name).sort(), 'os cards não são os capítulos engajados');
    const esperado = new Map(pe.map((p) => [p.name, om.filter((o) => o.chapter === p.name || (p.chapter && o.chapter === `PMI-${p.chapter}`)).length]));
    for (const c of cards) {
      assert.deepEqual(Object.keys(c).sort(), ['chapter', 'member_count'], `${c.chapter}: chave além de chapter e member_count`);
      const n = esperado.get(c.chapter);
      assert.equal(c.member_count, n >= 3 ? n : null, `${c.chapter}: contagem ${c.member_count}, base ${n}`);
    }
    // controle positivo: a leitura chegou aos números (o null abaixo de 3 já é cobrado card a card acima)
    assert.ok(cards.some((c) => Number.isInteger(c.member_count) && c.member_count >= 3), 'controle: nenhum card com número');
    const soma = cards.reduce((s, c) => s + (c.member_count ?? 0), 0);
    assert.ok(soma <= imp.active_members, `os cards somam ${soma}, acima do cabeçalho ${imp.active_members}`);
  });

  it('A3: como anon, a meta Entidades Parceiras é a contagem de parcerias com termo assinado', async () => {
    const health = await anonRpc('exec_portfolio_health');
    const meta = health.find((x) => x.metric_key === 'partner_entities');
    assert.ok(meta, 'a meta partner_entities não voltou');
    const inicio = `${new Date().getUTCFullYear()}-01-01`;
    const pe = await svc(`partner_entities?select=id,entity_type&status=eq.active&partnership_date=gte.${inicio}&entity_type=in.(academia,academic,governo,empresa)`);
    const gd = await svc('governance_documents?select=partner_entity_id&doc_type=eq.cooperation_agreement&status=eq.active&signed_at=not.is.null&partner_entity_id=not.is.null');
    const assinados = new Set(gd.map((g) => g.partner_entity_id));
    assert.equal(Number(meta.current), pe.filter((p) => assinados.has(p.id)).length, 'a meta não é a contagem com termo assinado');
    // controle: a lista de tipos alcança um cadastro ativo que a lista antiga ('academia','governo','empresa') não via.
    // Sem o recorte do ano, para o controle não vencer na virada de ano.
    const ativos = await svc('partner_entities?select=entity_type&status=eq.active');
    assert.ok(ativos.some((p) => ['academia', 'academic', 'governo', 'empresa'].includes(p.entity_type) && !['academia', 'governo', 'empresa'].includes(p.entity_type)),
      'controle: nenhum cadastro ativo de tipo que só a lista nova vê; o teste dos tipos não discrimina');
  });

  it('C2: como anon, a curadoria inclui o comitê; a gestão não mudou de regra', async () => {
    const team = await anonRpc('get_public_home_team');
    const comite = await svc('rpc/_wiki_committee_ids', { method: 'POST', body: '{}' });
    assert.ok(Array.isArray(comite) && comite.length > 0, 'controle: comitê vazio, a asserção não discrimina');
    assert.ok(team.curators >= comite.length, `curadoria ${team.curators} abaixo do comitê ${comite.length}`);
    const gestao = await svc('members?select=id,operational_role,designations&is_active=eq.true&current_cycle_active=eq.true');
    const n = gestao.filter((m) => ['manager', 'deputy_manager'].includes(m.operational_role) || (m.designations || []).includes('co_gp')).length;
    assert.equal(team.management, n, 'a gestão mudou');
  });
});
