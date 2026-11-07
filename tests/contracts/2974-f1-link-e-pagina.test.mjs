/**
 * #2974 (F1): link e página de cada rota de `ADMIN_ROUTE_ACCESS` respondem pela mesma entrada, e a entrada é a
 * pergunta que as RPCs da tela fazem ao servidor.
 *
 * O que este arquivo prende:
 *   1. `canForUnscoped` espelha can(pessoa, ação) sem recurso: a exceção de tribo legada é a do corpo de can() na
 *      última captura das migrations.
 *   2. Para cada rota declarada e cada forma sintética, o menu, a sidebar e a página dizem a mesma coisa.
 *   3. Quem abre a rota é exatamente a declaração: cada ação sozinha, cada designação sozinha, o próprio capítulo.
 *   4. A declaração é igual à pergunta das RPCs listadas (ações sem recurso, designações lidas no portão e a cláusula
 *      do próprio capítulo do chamador dentro do bloco que nega), e a tela chama essas RPCs.
 *   5. A página decide pelo `gateAdminPage` com `canEnterAdminRoute` da própria rota, passa `onLoadFailed` e não
 *      espera por laço próprio.
 *   6. A rota declarada não carrega eixo V3 que ninguém lê.
 * As funções rodam no Node com capacidades simuladas; o servidor é lido nas migrations, não no banco.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { latestFunctionCapture, maskJsComments, maskLineComments, buildNewestDefinitions } from '../helpers/guard-pin-staleness.mjs';
import {
  ADMIN_ROUTE_ACCESS, canEnterAdminRoute, NAV_ITEMS, getItemAccessibility, ADMIN_SIDEBAR_SECTIONS, isAdminSidebarItemVisible,
} from '../../src/lib/navigation.config.ts';
import { resolveTierFromMember } from '../../src/lib/admin/route-access.ts';
import { setCapabilities, clearCapabilities, canForUnscoped, ADMIN_TIER_ACTIONS } from '../../src/lib/permissions.ts';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '../..');
const ROTAS = Object.entries(ADMIN_ROUTE_ACCESS);

const SEM = { is_superadmin: false, org_actions: [], initiative_actions: {}, tribe_actions: {} };
const P = { operational_role: 'researcher', designations: [], is_superadmin: false };
const PAPEIS = ['manager', 'deputy_manager', 'tribe_leader', 'researcher', 'chapter_liaison', 'sponsor', 'observer', 'guest'];
const DESIGNACOES = ['sponsor', 'chapter_liaison', 'curator', 'comms_team', 'comms_leader', 'comms_member', 'co_gp',
  'deputy_manager', 'chapter_board', 'certificacao_director', 'filiacao_director', 'voluntariado_director'];
const ACOES = [...new Set([...ADMIN_TIER_ACTIONS, ...ROTAS.flatMap(([, a]) => a.actions), 'curate_content'])].sort();
const FORMAS = [
  ...PAPEIS.map((p) => [`papel:${p}`, { ...P, operational_role: p }, SEM]),
  ...DESIGNACOES.map((d) => [`designacao:${d}`, { ...P, designations: [d] }, SEM]),
  ['superadmin', { ...P, is_superadmin: true }, { ...SEM, is_superadmin: true }],
  ['capitulo', { ...P, chapter: 'CAPITULO-SINTETICO' }, SEM],
  ['capitulo-vazio', { ...P, chapter: '' }, SEM],
  ...ACOES.map((a) => [`acao:${a}`, P, { ...SEM, org_actions: [a] }]),
  ...ACOES.map((a) => [`tribo:${a}`, P, { ...SEM, tribe_actions: { 1: [a] } }]),
  ...ACOES.map((a) => [`iniciativa:${a}`, P, { ...SEM, initiative_actions: { x: [a] } }]),
  ['sem-membro', null, null],
];
// Escape completo para interpolar texto num RegExp (inclui a barra invertida), como nos guards 963/991/1021.
const escRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const comCaps = (caps, fn) => { if (caps) setCapabilities(caps); else clearCapabilities(); try { return fn(); } finally { clearCapabilities(); } };

// A exceção de tribo legada no corpo de can(): `p_action NOT IN ('view_pii', 'manage_member')`.
function excecaoDoServidor() {
  const can = latestFunctionCapture(ROOT, 'can');
  assert.ok(can, 'can() não foi capturada por nenhuma migration');
  const b = can.body.replace(/--[^\n]*/g, '');
  assert.match(b, /ekp\.scope\s+IN\s*\(\s*'organization'\s*,\s*'global'\s*\)/, 'can(): o escopo de organização e global mudou');
  const m = b.match(/p_resource_id\s+IS\s+NULL\s+AND\s+ae\.legacy_tribe_id\s+IS\s+NOT\s+NULL\s+AND\s+p_action\s+NOT\s+IN\s*\(([^)]*)\)/);
  assert.ok(m, 'can(): o ramo de tribo legada sem recurso mudou de forma');
  return [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();
}

test('canForUnscoped espelha can() sem recurso, com a exceção de tribo do corpo de can()', () => {
  const doServidor = excecaoDoServidor();
  const fonte = maskJsComments(readFileSync(resolve(ROOT, 'src/lib/permissions.ts'), 'utf8'));
  const m = fonte.match(/const SEM_RECURSO_SEM_TRIBO\s*=\s*\[([^\]]*)\]/);
  assert.ok(m, 'SEM_RECURSO_SEM_TRIBO não encontrada em permissions.ts');
  assert.deepEqual([...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort(), doServidor,
    'a exceção do front não é a do servidor');
  assert.ok(doServidor.length > 0, 'controle: a exceção do servidor veio vazia');
  for (const a of doServidor) {
    assert.equal(comCaps({ ...SEM, tribe_actions: { 1: [a] } }, () => canForUnscoped(a)), false, `${a} na tribo abriu sem recurso`);
    assert.equal(comCaps({ ...SEM, org_actions: [a] }, () => canForUnscoped(a)), true, `${a} de organização não abriu`);
  }
  assert.equal(comCaps({ ...SEM, tribe_actions: { 1: ['write'] } }, () => canForUnscoped('write')), true, 'controle: write na tribo legada abre sem recurso');
  assert.equal(comCaps({ ...SEM, initiative_actions: { x: ['write'] } }, () => canForUnscoped('write')), false, 'iniciativa sem tribo legada não conta sem recurso');
  assert.equal(comCaps({ ...SEM, is_superadmin: true }, () => canForUnscoped('manage_platform')), true, 'superadmin passa');
  assert.equal(comCaps(null, () => canForUnscoped('manage_platform')), false, 'sem capacidades não passa');
});

test('no navegador, a capacidade lida é a que o Nav pôs por último na janela', () => {
  const antes = globalThis.window;
  globalThis.window = {};
  try {
    window.__nucleoCapabilities = { ...SEM };
    assert.equal(canForUnscoped('view_partner'), false, 'controle: sem a ação, não passa');
    window.__nucleoCapabilities = { ...SEM, org_actions: ['view_partner'] };
    assert.equal(canForUnscoped('view_partner'), true, 'a capacidade nova não foi vista');
    window.__nucleoCapabilities = null;
    assert.equal(canForUnscoped('view_partner'), false, 'depois do logout a capacidade antiga continuou valendo');
  } finally {
    if (antes === undefined) delete globalThis.window; else globalThis.window = antes;
  }
});

// Item de menu sintético na mesma rota, com tier mínimo visitor: o menu é exercido mesmo quando a rota declarada não
// tem entrada no menu, e pelo eixo V3 ele abriria para qualquer membro.
const menuSintetico = (href) => ({ key: 'menu-sintetico', labelKey: 'x', href, minTier: 'visitor', requiresAuth: true, section: 'main', group: 'admin-sub' });

function links(href, m) {
  const tier = resolveTierFromMember(m);
  const menu = [...NAV_ITEMS.filter((i) => i.href === href), menuSintetico(href)]
    .map((i) => getItemAccessibility(i, tier, m?.designations || [], !!m, m?.operational_role, m?.selection_committee_role ?? null, m?.chapter ?? null).enabled);
  const sidebar = ADMIN_SIDEBAR_SECTIONS.flatMap((s) => s.items).filter((i) => i.href === href).map((i) => isAdminSidebarItemVisible(m, i));
  return [...menu, ...sidebar];
}

test('cada rota declarada: menu, sidebar e página dizem a mesma coisa em todas as formas', () => {
  assert.ok(ROTAS.length > 0, 'nenhuma rota declarada');
  for (const [href] of ROTAS) {
    assert.ok(existsSync(resolve(ROOT, `src/pages${href}.astro`)), `${href}: a página não existe`);
    let abre = 0, fecha = 0;
    for (const [id, m, caps] of FORMAS) {
      comCaps(caps, () => {
        const pagina = canEnterAdminRoute(href, m);
        const ls = links(href, m);
        assert.ok(ls.length > 0, `${href}: nenhum link no menu nem na sidebar`);
        for (const l of ls) assert.equal(l, pagina, `${href} em ${id}: o link diz ${l} e a página diz ${pagina}`);
        if (pagina) abre++; else fecha++;
      });
    }
    assert.ok(abre > 0 && fecha > 0, `controle: ${href} abriu para ${abre} e fechou para ${fecha} formas`);
  }
});

test('quem abre cada rota é exatamente a declaração: cada ação e cada designação sozinhas', () => {
  const excecao = excecaoDoServidor();
  for (const [href, acc] of ROTAS) {
    for (const d of acc.designations || []) assert.ok(DESIGNACOES.includes(d), `${href}: ${d} fora das formas do teste`);
    for (const [id, m, caps] of FORMAS) {
      const [tipo, nome] = id.split(':');
      const esperado = id === 'superadmin'
        || (tipo === 'acao' && acc.actions.includes(nome))
        || (tipo === 'tribo' && acc.actions.includes(nome) && !excecao.includes(nome))
        || (tipo === 'designacao' && (acc.designations || []).includes(nome))
        || (id === 'capitulo' && acc.ownChapter === true);
      assert.equal(comCaps(caps, () => canEnterAdminRoute(href, m)), esperado, `${href} em ${id}`);
    }
  }
});

// Argumentos de nível zero de uma chamada que começa em `abre` (o índice do parêntese); conta (), [] e {}.
function argumentos(src, abre) {
  let nivel = 0, atual = '', out = [];
  for (let i = abre + 1; i < src.length; i++) {
    const c = src[i];
    if ('([{'.includes(c)) nivel++;
    if (')]}'.includes(c)) { if (nivel === 0) { out.push(atual.trim()); return out; } nivel--; }
    if (c === ',' && nivel === 0) { out.push(atual.trim()); atual = ''; continue; }
    atual += c;
  }
  return null;
}

// Propriedades de nível zero de um objeto literal `{ a: x, b: (m) => f(m, 1) }`.
function propriedades(obj) {
  const corpo = obj.trim().replace(/^\{/, '').replace(/\}$/, '');
  let nivel = 0, atual = '';
  const out = [];
  for (const c of corpo) {
    if ('([{'.includes(c)) nivel++;
    if (')]}'.includes(c)) nivel--;
    if (c === ',' && nivel === 0) { out.push(atual.trim()); atual = ''; continue; }
    atual += c;
  }
  if (atual.trim()) out.push(atual.trim());
  return out;
}

// Índice do parêntese que fecha o que abre em `abre`.
function fecha(src, abre) {
  let nivel = 0;
  for (let i = abre; i < src.length; i++) {
    if (src[i] === '(') nivel++;
    if (src[i] === ')' && --nivel === 0) return i;
  }
  return -1;
}

/**
 * O corpo da última versão de uma função. Quando uma migration antiga tem duas assinaturas, o helper recusa; vale então
 * a migration mais nova que a define, se nela houver um CREATE só, precedido do DROP de uma assinatura.
 */
function captura(nome) {
  try {
    return latestFunctionCapture(ROOT, nome);
  } catch (e) {
    if (!/assinaturas/.test(e.message)) throw e;
    const dir = resolve(ROOT, 'supabase/migrations');
    const f = buildNewestDefinitions(dir).newest.get(nome);
    assert.ok(f, `${nome}: sem migration que a defina`);
    const original = readFileSync(resolve(dir, f.file), 'utf8');
    const sql = maskLineComments(original);
    const creates = [...sql.matchAll(new RegExp(`\\bCREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?${nome}\\s*\\(`, 'gi'))];
    assert.equal(creates.length, 1, `${nome}: ${f.file} tem ${creates.length} CREATE; a sobrecarga não foi resolvida`);
    const drop = sql.search(new RegExp(`\\bDROP\\s+FUNCTION\\s+(?:IF\\s+EXISTS\\s+)?(?:public\\.)?${nome}\\s*\\(`, 'i'));
    assert.ok(drop >= 0 && drop < creates[0].index, `${nome}: ${f.file} não remove a outra assinatura antes de criar`);
    const after = original.slice(creates[0].index);
    const as = maskLineComments(after).match(/\bAS\s+(\$[a-zA-Z_]*\$)/);
    assert.ok(as, `${nome}: corpo não encontrado em ${f.file}`);
    const abre = as.index + as[0].length;
    return { file: f.file, body: after.slice(abre, after.indexOf(as[1], abre)) };
  }
}

/**
 * A cláusula do próprio capítulo: dentro de um `IF NOT (...) THEN` que nega, `OR <v> = p_chapter`, com <v> lido do
 * capítulo do chamador (`SELECT ... chapter ... INTO ... <v> ... auth_id = auth.uid()`).
 */
function aceitaProprioCapitulo(b) {
  for (const m of b.matchAll(/\bIF\s+NOT\s*\(/gi)) {
    const abre = m.index + m[0].length - 1;
    const fim = fecha(b, abre);
    if (fim < 0 || !/^\s*THEN\s+(RETURN|RAISE)\b/i.test(b.slice(fim + 1))) continue;
    for (const c of b.slice(abre + 1, fim).matchAll(/\bOR\s+(\w+)\s*=\s*p_chapter\b/gi)) {
      const lido = new RegExp(`SELECT[^;]*\\bchapter\\b[^;]*\\bINTO\\b[^;]*\\b${c[1]}\\b[^;]*auth_id\\s*=\\s*auth\\.uid\\(\\)`, 'i');
      if (lido.test(b)) return true;
    }
  }
  return false;
}

/**
 * A pergunta do portão de uma função: ações perguntadas SEM recurso, designações lidas e a cláusula do próprio
 * capítulo. Expande um nível de helper.
 */
function pergunta(nome, nivel = 0) {
  const cap = captura(nome);
  assert.ok(cap, `${nome} não foi capturada por nenhuma migration`);
  return perguntaDoCorpo(cap.body.replace(/--[^\n]*/g, ''), nivel);
}

// A mesma leitura sobre um corpo já sem comentário: o de uma função ou a expressão de uma policy.
function perguntaDoCorpo(b, nivel = 0) {
  const acoes = new Set(), desig = new Set();
  let capitulo = aceitaProprioCapitulo(b);
  for (const m of b.matchAll(/\b(can_by_member|can|rls_can)\s*\(/g)) {
    const args = argumentos(b, m.index + m[0].length - 1);
    if (!args) continue;
    const semRecurso = m[1] === 'rls_can' ? args.length === 1 : args.length === 2;
    const lit = (m[1] === 'rls_can' ? args[0] : args[1])?.match(/^'([a-z_]+)'$/);
    if (semRecurso && lit) acoes.add(lit[1]);
  }
  for (const m of b.matchAll(/'([a-z_]+)'\s*=\s*ANY\s*\(\s*(?:COALESCE\s*\(\s*)?\w*designations/gi)) desig.add(m[1]);
  for (const m of b.matchAll(/designations\s*&&\s*ARRAY\s*\[([^\]]*)\]/gi)) for (const x of m[1].matchAll(/'([a-z_]+)'/g)) desig.add(x[1]);
  if (nivel === 0) {
    for (const m of b.matchAll(/public\.([a-z_]+)\s*\(\s*\)/g)) {
      const helper = latestFunctionCapture(ROOT, m[1]);
      if (helper && /can_by_member|rls_can/.test(helper.body)) {
        const h = pergunta(m[1], 1);
        h.acoes.forEach((a) => acoes.add(a)); h.desig.forEach((d) => desig.add(d));
        capitulo = capitulo || h.capitulo;
      }
    }
  }
  return { acoes, desig, capitulo };
}

// SQL sem comentário: o `--` de linha primeiro (um `/*` dentro dele não abre bloco), depois o bloco `/* */`, como o
// bloco de rollback da migration de 15/04, que repete CREATE POLICY antigos.
const semComentarioSql = (s) => maskLineComments(s).replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));

// A expressão de `USING (...)` ou `WITH CHECK (...)` no nível zero do comando, ou null.
function clausula(st, kw) {
  for (const m of st.matchAll(new RegExp(`\\b${kw}\\s*\\(`, 'gi'))) {
    const antes = st.slice(0, m.index);
    if ((antes.match(/\(/g) || []).length !== (antes.match(/\)/g) || []).length) continue;
    const abre = m.index + m[0].length - 1;
    const fim = fecha(st, abre);
    assert.ok(fim > abre, `${kw} sem o parêntese que fecha`);
    return st.slice(abre + 1, fim);
  }
  return null;
}

// Um identificador do SQL, como o Postgres o lê: entre aspas vale como está (com `""` virando `"`), sem aspas vira
// minúsculo. As migrations usam as duas formas para o nome da policy, às vezes na mesma policy.
const IDENT = '(?:"(?:[^"]|"")+"|[A-Za-z_][\\w$]*)';
const ident = (s) => (s.startsWith('"') ? s.slice(1, -1).replace(/""/g, '"') : s.toLowerCase());
const RE_POLICY = new RegExp(`\\b(CREATE|ALTER|DROP)\\s+POLICY\\s+(?:IF\\s+EXISTS\\s+)?(${IDENT})\\s+ON\\s+(?:(${IDENT})\\s*\\.\\s*)?(${IDENT})`, 'gi');

/**
 * A definição vigente de uma policy, lendo as migrations em ordem de arquivo: o CREATE POLICY a define, cada ALTER
 * POLICY depois dele troca o USING e o WITH CHECK que trouxer, e o DROP POLICY a remove (devolve null).
 */
function politica(tabela, nome) {
  const dir = resolve(ROOT, 'supabase/migrations');
  const fontes = readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()
    .map((f) => ({ f, sql: semComentarioSql(readFileSync(resolve(dir, f), 'utf8')) }));
  return politicaEm(fontes, tabela, nome);
}

/** O mesmo, sobre fontes dadas ({ f, sql } já sem comentário, em ordem), para os controles com SQL escrito no teste. */
function politicaEm(fontes, tabela, nome) {
  let atual = null;
  for (const { f, sql } of fontes) {
    for (const m of sql.matchAll(RE_POLICY)) {
      if (ident(m[2]) !== nome || ident(m[4]) !== tabela || (m[3] !== undefined && ident(m[3]) !== 'public')) continue;
      const fim = sql.indexOf(';', m.index);
      const st = sql.slice(m.index + m[0].length, fim < 0 ? sql.length : fim);
      const verbo = m[1].toUpperCase();
      if (verbo === 'DROP') { atual = null; continue; }
      const using = clausula(st, 'USING'), check = clausula(st, 'WITH\\s+CHECK');
      if (verbo === 'CREATE') {
        const cmd = st.match(/\bFOR\s+(ALL|SELECT|INSERT|UPDATE|DELETE)\b/i)?.[1]?.toUpperCase() || 'ALL';
        atual = { file: f, cmd, restritiva: /\bAS\s+RESTRICTIVE\b/i.test(st), using, check };
      } else {
        assert.ok(atual, `${tabela}.${nome}: ALTER POLICY em ${f} sem policy viva antes`);
        assert.doesNotMatch(st, /\bRENAME\b/i, `${tabela}.${nome}: ${f} renomeia a policy, e o extrator não segue o nome novo`);
        atual = { ...atual, file: f, using: using ?? atual.using, check: check ?? atual.check };
      }
    }
  }
  return atual;
}

/**
 * A pergunta de uma policy: a do USING. Sem WITH CHECK, o USING vale também para a linha nova; com WITH CHECK, ele tem
 * de perguntar o mesmo, porque a declaração da rota não separa ler de gravar.
 */
function perguntaDaPolitica(tabela, nome) {
  const pol = politica(tabela, nome);
  assert.ok(pol, `${tabela}.${nome}: a policy não existe nas migrations`);
  assert.equal(pol.restritiva, false, `${tabela}.${nome}: policy RESTRICTIVE não concede acesso`);
  assert.ok(pol.using, `${tabela}.${nome}: sem USING`);
  const p = perguntaDoCorpo(pol.using);
  if (pol.check) {
    const c = perguntaDoCorpo(pol.check);
    assert.deepEqual([[...c.acoes].sort(), [...c.desig].sort()], [[...p.acoes].sort(), [...p.desig].sort()],
      `${tabela}.${nome}: o WITH CHECK pergunta outra coisa que o USING`);
  }
  return { ...p, cmd: pol.cmd };
}

// As operações da tela sobre a tabela: `.from('t').select(`, `.insert(`, `.update(`, `.delete(` ou `.upsert(`.
const operacoes = (fonte, t) => [...fonte.matchAll(new RegExp(`\\.from\\(\\s*['"]${escRe(t)}['"]\\s*\\)\\s*\\.(select|insert|update|delete|upsert)\\(`, 'g'))]
  .map((x) => x[1].toUpperCase());
const cobre = (cmd, op) => cmd === 'ALL' || cmd === op;

const resolveImport = (from, spec) => {
  if (!spec.startsWith('.')) return null;
  const base = resolve(dirname(from), spec);
  return [base, `${base}.tsx`, `${base}.ts`, `${base}.astro`].find((c) => existsSync(c) && /\.(tsx|ts|astro)$/.test(c)) || null;
};
function arquivosDaTela(pagina) {
  const vistos = new Set();
  const visita = (f, prof) => {
    if (vistos.has(f)) return; vistos.add(f);
    if (prof === 0) return;
    for (const m of readFileSync(f, 'utf8').matchAll(/(?:import|from)\s*['"]([^'"]+)['"]/g)) {
      const r = resolveImport(f, m[1]);
      if (r && r.includes('/src/components/')) visita(r, prof - 1);
    }
  };
  visita(pagina, 3);
  return [...vistos];
}

// A tela chama a RPC: `.rpc('nome'`, ou um embrulho local `function f(nome) { ... .rpc(nome ... }` chamado como f('nome').
function chamaRpc(fonte, r) {
  if (new RegExp(`\\.rpc\\(\\s*['"]${r}['"]`).test(fonte)) return true;
  for (const m of fonte.matchAll(/(?:async\s+)?function\s+(\w+)\s*\(\s*(\w+)/g)) {
    const corpo = fonte.slice(m.index, fonte.indexOf('\n  }', m.index));
    if (new RegExp(`\\.rpc\\(\\s*${m[2]}\\b`).test(corpo) && new RegExp(`\\b${m[1]}\\(\\s*['"]${r}['"]`).test(fonte)) return true;
  }
  return false;
}

test('o extrator de policy lê o nome com e sem aspas, como o Postgres', () => {
  // Migrations reais em que a leitura só com aspas erra: um ALTER sem aspas depois de um CREATE com aspas (ela ficava
  // com o USING do CREATE), um DROP sem aspas no fim (ela via a policy viva) e CREATE e ALTER sem aspas (ela não via).
  assert.equal(politica('attendance', 'attendance_read_members')?.file, '20260805000246_rls_phase2_authoritative_member.sql',
    'controle: o ALTER POLICY sem aspas depois de um CREATE com aspas não foi lido');
  assert.equal(politica('cycles', 'cycles_admin_write'), null, 'controle: o DROP POLICY sem aspas não removeu a policy');
  assert.equal(politica('cr_approvals', 'cr_approvals_read_authenticated')?.file, '20260805000463_1408_governance_write_surface_hardening.sql',
    'controle: a policy criada e alterada sem aspas não foi lida');
  // Formas que nenhuma migration usa hoje, escritas aqui: sem aspas dobra para minúsculo, com aspas não dobra, a tabela
  // entre aspas vale, e outro schema não é public.
  const fontes = (...sqls) => sqls.map((sql, i) => ({ f: `${i}.sql`, sql }));
  assert.equal(politicaEm(fontes('CREATE POLICY Leitura ON public.t USING (a);'), 't', 'leitura')?.using, 'a',
    'controle: o nome sem aspas não dobrou para minúsculo');
  assert.equal(politicaEm(fontes('CREATE POLICY "Leitura" ON public.t USING (a);'), 't', 'leitura'), null,
    'controle: o nome entre aspas dobrou para minúsculo');
  assert.equal(politicaEm(fontes('CREATE POLICY p ON t USING (a);', 'ALTER POLICY "p" ON "public"."t" USING (b);'), 't', 'p')?.using, 'b',
    'controle: o ALTER com a tabela entre aspas não foi lido');
  assert.equal(politicaEm(fontes('CREATE POLICY p ON outro.t USING (a);'), 't', 'p'), null, 'controle: a policy de outro schema contou');
});

test('a declaração é a pergunta das RPCs e das policies da tela, e a tela as usa', () => {
  // controle do extrator de policy: o bloco de rollback de 15/04 (comentado) não ressuscita a policy removida
  assert.equal(politica('blog_posts', 'Admin manages posts'), null, 'controle: a policy removida voltou pelo bloco comentado');
  assert.deepEqual([...perguntaDaPolitica('campaign_templates', 'campaign_templates_manage_v4').acoes], ['write'],
    'controle: campaign_templates_manage_v4 pergunta write');
  const restritiva = politica('blog_posts', 'blog_posts_v4_org_scope_insert');
  assert.equal(restritiva?.restritiva, true, 'controle: a policy RESTRICTIVE não foi vista como tal');
  assert.equal(restritiva?.cmd, 'INSERT', 'controle: o comando da policy não foi lido');
  assert.throws(() => perguntaDaPolitica('blog_posts', 'blog_posts_v4_org_scope_insert'), /RESTRICTIVE/, 'controle: policy RESTRICTIVE aceita como origem');
  // controle do embrulho: o nome passado a safeRpc conta; um nome que a tela não chama, não
  const analytics = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/analytics.astro'), 'utf8'));
  assert.equal(chamaRpc(analytics, 'exec_role_transitions'), true, 'controle: o embrulho safeRpc não foi visto');
  assert.equal(chamaRpc(analytics, 'exec_funnel_summary'), false, 'controle: o extrator viu chamada que não existe');
  // controle do extrator: com recurso não conta, sem recurso conta
  assert.deepEqual([...pergunta('update_initiative').acoes], [], 'controle: update_initiative pergunta COM recurso');
  assert.deepEqual([...pergunta('create_initiative').acoes], ['manage_platform'], 'controle: create_initiative pergunta manage_platform');
  // controle do capítulo: o filtro `chapter = p_chapter` do funil não é portão; o retrato aceita o próprio capítulo
  assert.equal(pergunta('get_selection_pipeline_metrics').capitulo, false, 'controle: filtro por capítulo contou como portão');
  assert.equal(pergunta('exec_chapter_dashboard').capitulo, true, 'controle: a cláusula do próprio capítulo não foi vista');
  // controle da sobrecarga: set_site_config tem duas assinaturas numa migration antiga e uma só na mais nova
  assert.throws(() => latestFunctionCapture(ROOT, 'set_site_config'), /assinaturas/, 'controle: a sobrecarga antiga sumiu; o desvio de captura() ficou morto');
  assert.deepEqual([...pergunta('set_site_config').acoes], ['manage_platform'], 'controle: set_site_config pergunta manage_platform');
  for (const [href, acc] of ROTAS) {
    const policies = acc.policies || [];
    assert.ok(acc.rpcs.length + policies.length > 0, `${href}: sem RPC nem policy de origem`);
    const acoes = new Set(), desig = new Set();
    let capitulo = false;
    for (const p of [...acc.rpcs.map((r) => pergunta(r)), ...policies.map((x) => perguntaDaPolitica(x.table, x.name))]) {
      p.acoes.forEach((a) => acoes.add(a)); p.desig.forEach((d) => desig.add(d)); capitulo = capitulo || p.capitulo;
    }
    assert.deepEqual([...acoes].sort(), [...acc.actions].sort(), `${href}: as ações declaradas não são as que as RPCs e as policies perguntam`);
    assert.deepEqual([...desig].sort(), [...(acc.designations || [])].sort(), `${href}: as designações declaradas não são as que as RPCs e as policies leem`);
    assert.equal(acc.ownChapter === true, capitulo, `${href}: o próprio capítulo declarado não é o que as RPCs e as policies aceitam`);
    const fonte = arquivosDaTela(resolve(ROOT, `src/pages${href}.astro`)).map((f) => maskJsComments(readFileSync(f, 'utf8'))).join('\n');
    for (const r of acc.rpcs) assert.ok(chamaRpc(fonte, r), `${href}: a tela não chama ${r}`);
    for (const x of policies) {
      const ops = operacoes(fonte, x.table);
      assert.ok(ops.length > 0, `${href}: a tela não usa ${x.table}`);
      const { cmd } = perguntaDaPolitica(x.table, x.name);
      for (const op of ops) {
        const precisa = op === 'UPSERT' ? ['INSERT', 'UPDATE'] : [op];
        for (const o of precisa) assert.ok(cobre(cmd, o), `${href}: a tela faz ${o} em ${x.table}, e ${x.name} é FOR ${cmd}`);
      }
    }
  }
});

test('a página decide pelo gateAdminPage com canEnterAdminRoute da própria rota, e trata a falha das capacidades', () => {
  for (const [href] of ROTAS) {
    const src = maskJsComments(readFileSync(resolve(ROOT, `src/pages${href}.astro`), 'utf8'));
    const at = src.indexOf('gateAdminPage({');
    assert.ok(at >= 0, `${href}: a página não passa pelo gateAdminPage`);
    const args = argumentos(src, at + 'gateAdminPage'.length)?.[0] || '';
    const allow = propriedades(args).find((x) => x.startsWith('allow:'))?.slice('allow:'.length).trim() || '';
    assert.ok(allow, `${href}: gateAdminPage sem allow`);
    let corpo = allow;
    if (/^\w+$/.test(allow)) {
      const f = src.indexOf(`function ${allow}(`);
      assert.ok(f >= 0, `${href}: ${allow} não definida na página`);
      corpo = src.slice(f, src.indexOf('\n  }', f));
    }
    assert.match(corpo, new RegExp(`canEnterAdminRoute\\(\\s*'${escRe(href)}'\\s*,`), `${href}: o allow não pergunta a entrada da própria rota`);
    assert.doesNotMatch(corpo, /hasPermission|canAccessAdminRoute|canReadInternalAnalytics|canFor\w*\(|operational_role|designations|is_superadmin/,
      `${href}: o allow decide também por outro eixo`);
    assert.match(args, /onLoadFailed:/, `${href}: falha das capacidades viraria "sem acesso"`);
    // a espera é do primitivo: uma função que se reagenda (`function f() { ... setTimeout(f, n) }`) espera sem limite
    // e fora do gateAdminPage, qualquer que seja a condição
    for (const f of src.matchAll(/function\s+(\w+)\s*\(/g)) {
      const corpo = src.slice(f.index, src.indexOf('\n  }', f.index));
      assert.doesNotMatch(corpo, new RegExp(`setTimeout\\(\\s*${f[1]}\\s*,`), `${href}: ${f[1]} espera por laço próprio`);
    }
  }
});

test('rota declarada não carrega eixo V3 que ninguém lê', () => {
  for (const [href] of ROTAS) {
    for (const i of NAV_ITEMS.filter((x) => x.href === href)) {
      for (const eixo of ['allowedDesignations', 'allowedOperationalRoles', 'allowedSelectionCommittee']) {
        assert.equal(i[eixo], undefined, `${href}: o menu ainda declara ${eixo}`);
      }
    }
    for (const i of ADMIN_SIDEBAR_SECTIONS.flatMap((s) => s.items).filter((x) => x.href === href)) {
      assert.equal(i.permission, undefined, `${href}: a sidebar ainda declara permission`);
      assert.equal(i.routeKey, undefined, `${href}: a sidebar ainda declara routeKey`);
    }
  }
});

test('o menu do cliente passa o capítulo do membro a getItemAccessibility', () => {
  const nav = maskJsComments(readFileSync(resolve(ROOT, 'src/components/nav/Nav.astro'), 'utf8'));
  const at = nav.indexOf('getItemAccessibility(', nav.indexOf('function getItemAccessClient('));
  assert.ok(at >= 0, 'getItemAccessClient não chama getItemAccessibility');
  const args = argumentos(nav, at + 'getItemAccessibility'.length);
  assert.equal(args?.[6], '_member?.chapter ?? null', 'o 7º argumento não é o capítulo do membro');
});

test('o texto de falha ao carregar existe nos 3 idiomas e o AdminLayout o põe na página', () => {
  for (const l of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.match(readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8'), /'admin\.capabilitiesLoadFailed':\s*'[^']+'/, `${l} sem a chave`);
  }
  assert.match(readFileSync(resolve(ROOT, 'src/layouts/AdminLayout.astro'), 'utf8'),
    /<span id="admin-load-failed" class="hidden">\{t\('admin\.capabilitiesLoadFailed', lang\)\}<\/span>/);
  assert.match(maskJsComments(readFileSync(resolve(ROOT, 'src/lib/member-ready.ts'), 'utf8')), /getElementById\('admin-load-failed'\)/);
});
