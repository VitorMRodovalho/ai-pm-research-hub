/**
 * #2974 (F1): link e página de cada rota de `ADMIN_ROUTE_ACCESS` respondem pela mesma entrada, e a entrada é a
 * pergunta que as RPCs da tela fazem ao servidor.
 *
 * O que este arquivo prende:
 *   1. `canForUnscoped` espelha can(pessoa, ação) sem recurso: a exceção de tribo legada é a do corpo de can() na
 *      última captura das migrations.
 *   2. Para cada rota declarada e cada forma sintética, o menu, a sidebar e a página dizem a mesma coisa.
 *   3. Quem abre a rota é exatamente a declaração: cada ação sozinha, cada designação sozinha.
 *   4. A declaração é igual à pergunta das RPCs listadas (ações sem recurso e designações lidas no portão), e a tela
 *      chama essas RPCs.
 *   5. A página decide pelo `gateAdminPage` com `canEnterAdminRoute` da própria rota, passa `onLoadFailed` e não
 *      espera por laço próprio.
 *   6. A rota declarada não carrega eixo V3 que ninguém lê.
 * As funções rodam no Node com capacidades simuladas; o servidor é lido nas migrations, não no banco.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { latestFunctionCapture, maskJsComments } from '../helpers/guard-pin-staleness.mjs';
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
    .map((i) => getItemAccessibility(i, tier, m?.designations || [], !!m, m?.operational_role, m?.selection_committee_role ?? null).enabled);
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
        || (tipo === 'designacao' && (acc.designations || []).includes(nome));
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

/** A pergunta do portão de uma função: ações perguntadas SEM recurso e designações lidas. Expande um nível de helper. */
function pergunta(nome, nivel = 0) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome} não foi capturada por nenhuma migration`);
  const b = cap.body.replace(/--[^\n]*/g, '');
  const acoes = new Set(), desig = new Set();
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
      }
    }
  }
  return { acoes, desig };
}

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

test('a declaração é a pergunta das RPCs da tela, e a tela chama essas RPCs', () => {
  // controle do extrator: com recurso não conta, sem recurso conta
  assert.deepEqual([...pergunta('update_initiative').acoes], [], 'controle: update_initiative pergunta COM recurso');
  assert.deepEqual([...pergunta('create_initiative').acoes], ['manage_platform'], 'controle: create_initiative pergunta manage_platform');
  for (const [href, acc] of ROTAS) {
    assert.ok(acc.rpcs.length > 0, `${href}: sem RPC de origem`);
    const acoes = new Set(), desig = new Set();
    for (const r of acc.rpcs) { const p = pergunta(r); p.acoes.forEach((a) => acoes.add(a)); p.desig.forEach((d) => desig.add(d)); }
    assert.deepEqual([...acoes].sort(), [...acc.actions].sort(), `${href}: as ações declaradas não são as que as RPCs perguntam`);
    assert.deepEqual([...desig].sort(), [...(acc.designations || [])].sort(), `${href}: as designações declaradas não são as que as RPCs leem`);
    const fonte = arquivosDaTela(resolve(ROOT, `src/pages${href}.astro`)).map((f) => maskJsComments(readFileSync(f, 'utf8'))).join('\n');
    for (const r of acc.rpcs) assert.match(fonte, new RegExp(`\\.rpc\\(\\s*['"]${r}['"]`), `${href}: a tela não chama ${r}`);
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

test('o texto de falha ao carregar existe nos 3 idiomas e o AdminLayout o põe na página', () => {
  for (const l of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.match(readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8'), /'admin\.capabilitiesLoadFailed':\s*'[^']+'/, `${l} sem a chave`);
  }
  assert.match(readFileSync(resolve(ROOT, 'src/layouts/AdminLayout.astro'), 'utf8'),
    /<span id="admin-load-failed" class="hidden">\{t\('admin\.capabilitiesLoadFailed', lang\)\}<\/span>/);
  assert.match(maskJsComments(readFileSync(resolve(ROOT, 'src/lib/member-ready.ts'), 'utf8')), /getElementById\('admin-load-failed'\)/);
});
