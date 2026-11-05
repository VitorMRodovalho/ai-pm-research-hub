// tests/contracts/2973-acesso-decidido-quando-o-membro-chega.test.mjs
/**
 * #2973: as telas do admin decidem o acesso quando o Nav resolve o membro, e não quando um contador de tentativas
 * acaba.
 *
 * O caso: /admin/portfolio consultava navGetMember() 20 vezes a cada 150 ms e, sem resposta em ~3 s, mostrava
 * "acesso restrito". Quem tinha admin.portfolio e um get_member_by_auth lento via a tela negada. pilots,
 * partnerships e cycle-report faziam o mesmo com 60 tentativas, governance-v2 e selection com 20, e as duas ilhas
 * da governance-v2 escondiam os controles do GP depois de ~9 s.
 *
 * O guard afirma:
 *   1. o portão (src/lib/member-ready.ts), exercido com uma janela falsa: nada se decide enquanto a sessão não foi
 *      lida, por mais eventos que cheguem; sem sessão, onNoSession; com sessão, onDenied só quando allow(membro) é
 *      falso ou não há cadastro, e onAllowed uma vez quando é verdadeiro;
 *   2. o Nav marca o estado da sessão em cada transição e avisa a falta de sessão (nav:no-session);
 *   3. cada tela liga o caminho de negado à função de permissão dela (hasPermission), e o caminho sem sessão ao
 *      texto "entre para ver";
 *   4. censo: nenhum arquivo de src/pages/admin ou src/components/admin espera o membro com contador, salvo as
 *      isenções declaradas abaixo, cada uma com o motivo;
 *   5. #2974 (E1): o estado 'member' diz se as capacidades falharam. O Nav marca a falha no catch de
 *      loadCapabilities e limpa no sucesso e no logout; o portão chama onLoadFailed, e não onDenied, só quando
 *      allow é falso e as capacidades falharam, e só se a tela passar onLoadFailed.
 * O censo das ilhas que chamam RPC sem esperar o membro foi para a catraca de 2974-catraca-de-espera.test.mjs.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { gateAdminPage, onMemberResolved, readMemberResolution } from '../../src/lib/member-ready.ts';

const ROOT = process.cwd();
const ler = (p) => maskJsComments(readFileSync(join(ROOT, p), 'utf8'));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function janela(state = 'pending', member = null, capFailed = false) {
  const ouvintes = new Map();
  const w = {
    state, member, capFailed,
    navAuthState: () => w.state,
    navGetMember: () => w.member,
    navCapabilitiesFailed: () => w.capFailed,
    addEventListener: (t, fn) => { if (!ouvintes.has(t)) ouvintes.set(t, new Set()); ouvintes.get(t).add(fn); },
    removeEventListener: (t, fn) => { ouvintes.get(t)?.delete(fn); },
    disparar: (t) => { for (const fn of [...(ouvintes.get(t) || [])]) fn(); },
    ouvindo: () => [...ouvintes.values()].reduce((n, s) => n + s.size, 0),
  };
  return w;
}

function portao(w, allow, comFalha = false) {
  const log = [];
  const chamadasAllow = [];
  gateAdminPage({
    allow: (m) => { chamadasAllow.push(m); return allow(m); },
    onAllowed: (m) => log.push(['allowed', m?.id]),
    onDenied: () => log.push(['denied']),
    onNoSession: () => log.push(['no-session']),
    ...(comFalha ? { onLoadFailed: () => log.push(['load-failed']) } : {}),
  }, w);
  return { log, chamadasAllow };
}

// ── 1. o portão, exercido ──

test('portão: enquanto a sessão não foi lida, nada se decide, por mais eventos que cheguem', () => {
  const w = janela('pending');
  const { log } = portao(w, () => true);
  for (let i = 0; i < 100; i++) w.disparar('nav:member');
  assert.deepEqual(log, [], 'decidiu antes de o Nav ler a sessão: é o prazo de tentativas de volta');
  assert.equal(readMemberResolution(w), null);
});

test('portão: sem sessão, onNoSession; e quando a sessão chega com permissão, libera uma vez e para de ouvir', () => {
  const w = janela('pending');
  const { log } = portao(w, (m) => m.ok === true);
  w.state = 'no-session'; w.disparar('nav:no-session');
  assert.deepEqual(log, [['no-session']]);
  w.state = 'resolved'; w.member = { id: 'm1', ok: true }; w.disparar('nav:member');
  assert.deepEqual(log, [['no-session'], ['allowed', 'm1']]);
  assert.equal(w.ouvindo(), 0, 'depois de liberar, o portão para de ouvir');
  w.disparar('nav:member');
  assert.equal(log.length, 2, 'liberou duas vezes');
});

test('portão: com sessão, negado só pelo resultado de allow, e nunca liberado se allow for falso', () => {
  const w = janela('pending');
  const { log, chamadasAllow } = portao(w, () => false);
  w.state = 'resolved'; w.member = { id: 'm2' };
  for (let i = 0; i < 5; i++) w.disparar('nav:member');
  assert.ok(log.length > 0 && log.every(([k]) => k === 'denied'), `esperado só denied, veio ${JSON.stringify(log)}`);
  assert.ok(chamadasAllow.every((m) => m?.id === 'm2'), 'allow precisa receber o membro');
});

test('portão: sessão sem cadastro de membro é negada sem chamar allow', () => {
  const w = janela('resolved', null);
  const { log, chamadasAllow } = portao(w, () => true);
  assert.deepEqual(log, [['denied']]);
  assert.equal(chamadasAllow.length, 0, 'allow foi chamado com membro nulo');
});

test('portão: membro já resolvido na hora da inscrição decide na hora', () => {
  const w = janela('resolved', { id: 'm3' });
  const { log } = portao(w, () => true);
  assert.deepEqual(log, [['allowed', 'm3']]);
  assert.equal(w.ouvindo(), 0);
});

test('onMemberResolved: segue as trocas e para quando desinscrito', () => {
  const w = janela('pending');
  const vistos = [];
  const parar = onMemberResolved((r) => vistos.push(r.kind), w);
  w.state = 'resolved'; w.member = { id: 'a' }; w.disparar('nav:member');
  w.state = 'no-session'; w.member = null; w.disparar('nav:member');
  parar();
  w.state = 'resolved'; w.member = { id: 'b' }; w.disparar('nav:member');
  assert.deepEqual(vistos, ['member', 'no-session']);
  assert.equal(w.ouvindo(), 0);
});

test('estado: capabilitiesFailed vem do Nav e só no estado member', () => {
  assert.deepEqual(readMemberResolution(janela('resolved', { id: 'a' }, true)), { kind: 'member', member: { id: 'a' }, capabilitiesFailed: true });
  assert.deepEqual(readMemberResolution(janela('resolved', { id: 'a' }, false)), { kind: 'member', member: { id: 'a' }, capabilitiesFailed: false });
  const semMarca = janela('resolved', { id: 'a' });
  delete semMarca.navCapabilitiesFailed;
  assert.equal(readMemberResolution(semMarca).capabilitiesFailed, false, 'sem a marca do Nav, falha não pode ser presumida');
  assert.deepEqual(readMemberResolution(janela('resolved', null, true)), { kind: 'no-member' });
  assert.deepEqual(readMemberResolution(janela('no-session', null, true)), { kind: 'no-session' });
});

test('portão: capacidades falharam e allow falso: onLoadFailed, quando a tela o passa', () => {
  const { log } = portao(janela('resolved', { id: 'f1' }, true), () => false, true);
  assert.deepEqual(log, [['load-failed']]);
});

test('portão: capacidades falharam e a tela não passa onLoadFailed: onDenied, como antes', () => {
  const { log } = portao(janela('resolved', { id: 'f2' }, true), () => false, false);
  assert.deepEqual(log, [['denied']]);
});

test('portão: capacidades falharam e allow verdadeiro: libera (a permissão V3 não depende delas)', () => {
  const { log } = portao(janela('resolved', { id: 'f3' }, true), () => true, true);
  assert.deepEqual(log, [['allowed', 'f3']]);
});

test('portão: capacidades carregadas e allow falso: onDenied, nunca onLoadFailed', () => {
  const { log } = portao(janela('resolved', { id: 'f4' }, false), () => false, true);
  assert.deepEqual(log, [['denied']]);
});

test('portão: sem cadastro de membro com capacidades falhadas: onDenied, não onLoadFailed', () => {
  const { log } = portao(janela('resolved', null, true), () => false, true);
  assert.deepEqual(log, [['denied']]);
});

// ── 2. o Nav ──

test('Nav: marca o estado da sessão em cada transição e avisa a falta de sessão', () => {
  const nav = ler('src/components/nav/Nav.astro').replace(/\s+/g, ' ');
  assert.match(nav, /\(window as any\)\.navAuthState = \(\) => _authState;/, 'navAuthState não exposto');
  assert.match(nav, /if \(!session\) \{ _authState = 'no-session'; window\.dispatchEvent\(new CustomEvent\('nav:no-session'\)\); \}/,
    'sem sessão o Nav precisa marcar no-session e disparar nav:no-session');
  const resolvido = nav.match(/_member = data; _authState = 'resolved'; renderAuth\(\); window\.dispatchEvent\(new CustomEvent\('nav:member', \{ detail: _member \}\)\);/g) || [];
  assert.equal(resolvido.length, 2, "boot e SIGNED_IN precisam marcar 'resolved' antes do nav:member");
  assert.match(nav, /if \(event === 'SIGNED_OUT'\) \{ _member = null; _user = null;[\s\S]*?_authState = 'no-session'; renderLoggedOut\(\); window\.dispatchEvent\(new CustomEvent\('nav:member', \{ detail: null \}\)\);/,
    "SIGNED_OUT precisa marcar 'no-session' antes do nav:member nulo");
});

test('Nav: marca a falha das capacidades no catch, limpa no sucesso e no logout, e expõe a marca', () => {
  const nav = ler('src/components/nav/Nav.astro').replace(/\s+/g, ' ');
  assert.match(nav, /\(window as any\)\.navCapabilitiesFailed = \(\) => _capFailed;/, 'navCapabilitiesFailed não exposto');
  const ini = nav.indexOf('async function loadCapabilities() {');
  const fim = nav.indexOf('async function bootNav()', ini);
  assert.ok(ini !== -1 && fim !== -1, 'loadCapabilities não encontrada');
  const corpo = nav.slice(ini, fim);
  assert.match(corpo, /try \{ const \{ data, error \} = await sb\.rpc\('get_caller_capabilities'\); if \(error\) throw error; _capFailed = false; \(window as any\)\.__nucleoCapabilities = data \|\| null;/,
    'no sucesso, a marca precisa ser limpa antes de gravar as capacidades');
  assert.match(corpo, /\} catch \(e\) \{ \(window as any\)\.__nucleoCapabilities = null; _capFailed = true;/,
    'no catch, a marca precisa ser posta junto com as capacidades nulas');
  assert.match(nav, /if \(event === 'SIGNED_OUT'\) \{ _member = null; _user = null;[\s\S]*?_capFailed = false; _authState = 'no-session';/,
    'no logout, a marca precisa ser limpa');
});

// ── 3. as telas ──

// #2974 (F1): partnerships e governance-v2 decidem pela entrada da rota em ADMIN_ROUTE_ACCESS (`rota`), e não mais por
// hasPermission; o 2974-f1-link-e-pagina prende o resto. A forma do portão é a mesma, com onLoadFailed.
const PORTOES = [
  { arq: 'src/pages/admin/portfolio.astro', fn: 'hasPortfolioAccess', perm: 'admin.portfolio' },
  { arq: 'src/pages/admin/partnerships.astro', fn: 'hasPartnershipsAccess', rota: '/admin/partnerships' },
  { arq: 'src/pages/admin/cycle-report.astro', fn: 'hasAccess', perm: 'admin.analytics' },
  { arq: 'src/pages/admin/governance-v2.astro', fn: 'hasBoardGovAccess', rota: '/admin/governance-v2' },
];

/** O portão da tela, ligado: allow é a função de permissão, negado e sem sessão mostram textos diferentes. */
export function portaoDaTela(src, fn, perm, rota) {
  const c = src.replace(/\s+/g, ' ');
  const decide = rota ? `canEnterAdminRoute\\('${esc(rota)}', member\\)` : `hasPermission\\(member, '${esc(perm)}'\\)`;
  const permissao = new RegExp(
    `function ${esc(fn)}\\(member: any\\): boolean \\{ if \\(!member\\) return false; return ${decide}; \\}`,
  ).test(c);
  const m = c.match(new RegExp(
    `gateAdminPage\\(\\{ allow: ${esc(fn)}, onAllowed: \\(\\) => \\{ void boot\\w+\\(\\); \\}, ` +
      'onDenied: \\(\\) => (show\\w+Notice)\\(([^()]*(?:\\([^()]*\\))?[^()]*)\\), ' +
      'onNoSession: \\(\\) => (show\\w+Notice)\\(adminSignInText\\(\\)\\), ' +
      `${rota ? 'onLoadFailed: \\(\\) => (show\\w+Notice)\\(adminLoadFailedText\\(\\)\\), ' : ''}\\}\\);`,
  ));
  return {
    permissao,
    gate: !!m,
    negadoNaoPedeLogin: !!m && !/adminSignInText/.test(m[2]),
    mesmoAviso: !!m && m[1] === m[3] && (!rota || m[4] === m[1]),
  };
}

for (const p of PORTOES) {
  const pergunta = p.rota ? `canEnterAdminRoute('${p.rota}')` : `hasPermission '${p.perm}'`;
  test(`${p.arq}: negado vem de ${p.fn} (${pergunta}), sem sessão pede para entrar`, () => {
    const r = portaoDaTela(ler(p.arq), p.fn, p.perm, p.rota);
    assert.ok(r.permissao, `${p.fn} não é "sem membro: falso; senão ${pergunta}"`);
    assert.ok(r.gate, 'a tela não passa pelo gateAdminPage com allow, onDenied e onNoSession');
    assert.ok(r.negadoNaoPedeLogin, 'o caminho de negado mostra o texto de entrar');
    assert.ok(r.mesmoAviso, 'negado e sem sessão usam funções de aviso diferentes');
  });
}

test('pilots: lê para todo membro cadastrado; sem cadastro, aviso; sem sessão, pede para entrar', () => {
  const c = ler('src/pages/admin/pilots.astro').replace(/\s+/g, ' ');
  assert.match(c, /gateAdminPage\(\{ allow: \(member\) => !!member, onAllowed: \(member\) => \{ void bootAdminPilots\(member\); \}, onDenied: \(\) => showPilotsNotice\(document\.getElementById\('i18n-pilots-noMember'\)/);
  assert.match(c, /onNoSession: \(\) => showPilotsNotice\(adminSignInText\(\)\)/);
  assert.match(c, /const canWrite = hasPermission\(member, 'admin\.portfolio'\);/, 'a escrita continua pedindo admin.portfolio');
});

test('selection: decide no applyGate (canAccessAdminRoute) a cada resolução; sem sessão pede para entrar', () => {
  const c = ler('src/pages/admin/selection.astro').replace(/\s+/g, ' ');
  assert.match(c, /onMemberResolved\(\(r\) => \{ if \(r\.kind === 'no-session'\) \{ showDenied\(adminSignInText\(\)\); return; \} sb = [^;]+; MEMBER = r\.kind === 'member' \? r\.member : null; [^}]*\} applyGate\(MEMBER\); \}\);/);
  assert.match(c, /function applyGate\(m: any\) \{ if \(m && canAccessAdminRoute\(m, 'admin_selection'\)\) \{[\s\S]*?\} else \{ showDenied\(\); \} \}/,
    'o negado da selection precisa vir do else de canAccessAdminRoute');
});

test('governance/documents: a espera do membro resolve por evento do Nav, não por prazo', () => {
  const c = ler('src/pages/admin/governance/documents.astro').replace(/\s+/g, ' ');
  const ini = c.indexOf('function waitForMember(');
  const fim = c.indexOf('pick(); }); }', ini);
  assert.ok(ini !== -1 && fim !== -1, 'waitForMember não encontrado na forma esperada');
  const corpo = c.slice(ini, fim + 'pick(); }); }'.length);
  assert.match(corpo, /if \(st === 'no-session' \|\| st === 'resolved'\) return done\(null\);/);
  assert.match(corpo, /window\.addEventListener\('nav:member', pick\); window\.addEventListener\('nav:no-session', pick\);/);
  assert.doesNotMatch(corpo, /tries|setTimeout/, 'a espera do membro voltou a ter prazo');
});

// ── 4. censo ──

const CONTADOR = /\+\+\s*\w*(?:[Rr]etries|tries)\b|\b\w*(?:[Rr]etries|tries)\s*(?:\+\+|\+=\s*1)/;
const ISENTOS = {
  'src/pages/admin/governance/documents.astro':
    'o contador é do waitForSb, que espera o cliente do banco e não decide acesso; a espera do membro é por evento (teste acima)',
};

function arquivos(dir, out = []) {
  for (const e of readdirSync(join(ROOT, dir))) {
    const p = join(dir, e);
    if (statSync(join(ROOT, p)).isDirectory()) arquivos(p, out);
    else if (/\.(astro|tsx?|jsx?)$/.test(e)) out.push(p);
  }
  return out;
}

test('censo: nada em src/pages/admin e src/components/admin espera o membro com contador de tentativas', () => {
  const todos = [...arquivos('src/pages/admin'), ...arquivos('src/components/admin')].map((p) => relative(ROOT, join(ROOT, p)));
  const violam = [];
  const isencaoUsada = new Set();
  for (const p of todos) {
    const c = ler(p);
    if (!(CONTADOR.test(c) && c.includes('navGetMember'))) continue;
    if (ISENTOS[p]) { isencaoUsada.add(p); continue; }
    violam.push(p);
  }
  assert.deepEqual(violam, [], `esperam o membro com contador:\n${violam.join('\n')}`);
  for (const p of Object.keys(ISENTOS)) {
    assert.ok(isencaoUsada.has(p), `isenção vencida: ${p} não tem mais contador com navGetMember; tire da lista`);
  }
});

// ── 5. ilhas que chamam RPC autenticada ──

test('useResolvedMember: memberId e capabilitiesFailed só existem quando o Nav entrega um membro', () => {
  const c = ler('src/hooks/useResolvedMember.ts').replace(/\s+/g, ' ');
  assert.match(c, /useEffect\(\(\) => onMemberResolved\(setResolution\), \[\]\);/);
  assert.match(c, /const memberId = resolution\?\.kind === 'member' \? String\(resolution\.member\?\.id \?\? ''\) \|\| null : null;/);
  assert.match(c, /const capabilitiesFailed = resolution\?\.kind === 'member' && resolution\.capabilitiesFailed === true;/);
  assert.match(c, /return \{ ready: resolution !== null, memberId, capabilitiesFailed \};/);
});

test('usePortfolio: a primeira chamada de get_portfolio_dashboard espera o membro e se repete quando ele muda', () => {
  const c = ler('src/hooks/usePortfolio.ts').replace(/\s+/g, ' ');
  assert.match(c,
    /useEffect\(\(\) => \{ if \(!ready\) return; if \(!memberId\) \{ [^}]*return; \} let cancelled = false;[\s\S]*?sb\.rpc\('get_portfolio_dashboard'[\s\S]*?\}, \[cycle, ready, memberId\]\);/,
    'get_portfolio_dashboard precisa vir depois de "sem membro: não chama", com memberId nas dependências');
  assert.doesNotMatch(c, /retries/, 'a espera por tentativas voltou');
});

test('PlannedVsActualSection: a primeira chamada espera o membro e se repete quando ele muda', () => {
  const c = ler('src/components/portfolio/PlannedVsActualSection.tsx').replace(/\s+/g, ' ');
  assert.match(c, /useEffect\(\(\) => \{ if \(memberId\) load\(\); \}, \[load, memberId\]\);/);
  assert.match(c, /const load = useCallback\(async \(\) => \{ const sb = \(window as any\)\.navGetSb\?\.\(\); if \(!sb\) return;/,
    'load voltou a se reagendar sozinho, fora do membro resolvido');
  assert.match(c, /if \(ready && !memberId\) return null;/);
});

// O censo das ilhas que chamam RPC sem esperar o membro está na catraca: 2974-catraca-de-espera.test.mjs.
