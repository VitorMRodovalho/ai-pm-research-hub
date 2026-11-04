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
 *      isenções declaradas abaixo, cada uma com o motivo.
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

function janela(state = 'pending', member = null) {
  const ouvintes = new Map();
  const w = {
    state, member,
    navAuthState: () => w.state,
    navGetMember: () => w.member,
    addEventListener: (t, fn) => { if (!ouvintes.has(t)) ouvintes.set(t, new Set()); ouvintes.get(t).add(fn); },
    removeEventListener: (t, fn) => { ouvintes.get(t)?.delete(fn); },
    disparar: (t) => { for (const fn of [...(ouvintes.get(t) || [])]) fn(); },
    ouvindo: () => [...ouvintes.values()].reduce((n, s) => n + s.size, 0),
  };
  return w;
}

function portao(w, allow) {
  const log = [];
  const chamadasAllow = [];
  gateAdminPage({
    allow: (m) => { chamadasAllow.push(m); return allow(m); },
    onAllowed: (m) => log.push(['allowed', m?.id]),
    onDenied: () => log.push(['denied']),
    onNoSession: () => log.push(['no-session']),
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

// ── 3. as telas ──

const PORTOES = [
  { arq: 'src/pages/admin/portfolio.astro', fn: 'hasPortfolioAccess', perm: 'admin.portfolio' },
  { arq: 'src/pages/admin/partnerships.astro', fn: 'hasPartnershipsAccess', perm: 'admin.partners' },
  { arq: 'src/pages/admin/cycle-report.astro', fn: 'hasAccess', perm: 'admin.analytics' },
  { arq: 'src/pages/admin/governance-v2.astro', fn: 'hasBoardGovAccess', perm: 'admin.access' },
];

/** O portão da tela, ligado: allow é a função de permissão, negado e sem sessão mostram textos diferentes. */
export function portaoDaTela(src, fn, perm) {
  const c = src.replace(/\s+/g, ' ');
  const permissao = new RegExp(
    `function ${esc(fn)}\\(member: any\\): boolean \\{ if \\(!member\\) return false; return hasPermission\\(member, '${esc(perm)}'\\); \\}`,
  ).test(c);
  const m = c.match(new RegExp(
    `gateAdminPage\\(\\{ allow: ${esc(fn)}, onAllowed: \\(\\) => \\{ void boot\\w+\\(\\); \\}, ` +
      'onDenied: \\(\\) => (show\\w+Notice)\\(([^()]*(?:\\([^()]*\\))?[^()]*)\\), ' +
      'onNoSession: \\(\\) => (show\\w+Notice)\\(adminSignInText\\(\\)\\), \\}\\);',
  ));
  return {
    permissao,
    gate: !!m,
    negadoNaoPedeLogin: !!m && !/adminSignInText/.test(m[2]),
    mesmoAviso: !!m && m[1] === m[3],
  };
}

for (const p of PORTOES) {
  test(`${p.arq}: negado vem de ${p.fn} (hasPermission '${p.perm}'), sem sessão pede para entrar`, () => {
    const r = portaoDaTela(ler(p.arq), p.fn, p.perm);
    assert.ok(r.permissao, `${p.fn} não é "sem membro: falso; senão hasPermission(member, '${p.perm}')"`);
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

test('useResolvedMember: memberId só existe quando o Nav entrega um membro', () => {
  const c = ler('src/hooks/useResolvedMember.ts').replace(/\s+/g, ' ');
  assert.match(c, /useEffect\(\(\) => onMemberResolved\(setResolution\), \[\]\);/);
  assert.match(c, /const memberId = resolution\?\.kind === 'member' \? String\(resolution\.member\?\.id \?\? ''\) \|\| null : null;/);
  assert.match(c, /return \{ ready: resolution !== null, memberId \};/);
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

// Ilhas que chamam .rpc( depois de esperar só o cliente (navGetSb), sem esperar o membro. Lista medida em
// 04/11/2026, a classificar: chamada na montagem (o defeito do portfolio) ou só em clique (já com sessão), e RPC
// com ou sem EXECUTE para anon. Entrada nova reprova; entrada corrigida precisa sair da lista.
const ILHAS_SEM_MEMBRO = new Set([
  'src/components/admin/AdminAgendaVivaPanel.tsx',
  'src/components/admin/AiCalibrationIsland.tsx',
  'src/components/admin/CommsDashboard.tsx',
  'src/components/admin/CommsSchedulerPanel.tsx',
  'src/components/admin/GpActionTodayWidget.tsx',
  'src/components/admin/RecurringAgendaIsland.tsx',
  'src/components/admin/audit/AuditLogIsland.tsx',
  'src/components/admin/campaigns/OneOffMessageIsland.tsx',
  'src/components/admin/members/DriveTeardownIsland.tsx',
  'src/components/admin/members/InactiveCandidatesIsland.tsx',
  'src/components/admin/members/MemberCommunicationsPanel.tsx',
  'src/components/admin/members/MemberDetailIsland.tsx',
  'src/components/board/CardDetail.tsx',
  'src/components/events/EventMinutesEditor.tsx',
  'src/components/governance/ChainAuditReportIsland.tsx',
  'src/components/governance/ChainDocxExportIsland.tsx',
  'src/components/governance/ChainPDFExportIsland.tsx',
  'src/components/governance/ClauseCommentDrawer.tsx',
  'src/components/governance/DocumentIntakeWizard.tsx',
  'src/components/governance/DocumentVersionEditor.tsx',
  'src/components/governance/GovernanceLibrary.tsx',
  'src/components/governance/ManualDocumentViewer.tsx',
  'src/components/initiative/InitiativeRecurringMeetingsPanel.tsx',
  'src/components/islands/CrossTribeIsland.tsx',
  'src/components/islands/ImpactPageIsland.tsx',
  'src/components/islands/PartnerPipelineIsland.tsx',
  'src/components/islands/TribeDashboardIsland.tsx',
  'src/components/report/ReportPage.tsx',
  'src/components/sections/InterestForm.tsx',
  'src/components/selection/DiversityDashboard.tsx',
  'src/components/tribes/TribeGamificationTab.tsx',
  'src/components/workspace/KpiDashboard.tsx',
  'src/components/workspace/MyMeetingsIsland.tsx',
  'src/components/workspace/MyTasksIsland.tsx',
  'src/hooks/useBoard.ts',
  'src/hooks/usePilots.ts',
]);

const ESPERA_MEMBRO = /navGetMember|nav:member|onMemberResolved|useResolvedMember|getSession|onAuthStateChange/;

test('censo: nenhuma ilha nova chama RPC sem esperar o membro, e a lista declarada não guarda corrigidas', () => {
  const todos = [...arquivos('src/components'), ...arquivos('src/hooks')].filter((p) => /\.(tsx?|jsx?)$/.test(p));
  const achadas = new Set();
  for (const p of todos) {
    const c = ler(p);
    if (c.includes('navGetSb') && /\.rpc\(/.test(c) && !ESPERA_MEMBRO.test(c)) achadas.add(p);
  }
  const novas = [...achadas].filter((p) => !ILHAS_SEM_MEMBRO.has(p)).sort();
  const vencidas = [...ILHAS_SEM_MEMBRO].filter((p) => !achadas.has(p)).sort();
  assert.deepEqual(novas, [], `ilhas novas chamando RPC sem esperar o membro:\n${novas.join('\n')}`);
  assert.deepEqual(vencidas, [], `já esperam o membro (ou sumiram); tire da lista:\n${vencidas.join('\n')}`);
});
