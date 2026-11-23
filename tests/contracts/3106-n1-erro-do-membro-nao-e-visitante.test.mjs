/**
 * #3106 N1: erro ao ler o membro não vira "Conta não cadastrada".
 *
 * O Nav lia só memberRes.data de get_member_by_auth. Com erro (timeout, banco sob carga), o dado vinha nulo, a
 * pessoa era tratada como visitante, o header dizia "Conta não cadastrada" e as telas mostravam o bloco de quem não
 * tem cadastro, convidando um membro real a vincular a conta de novo. Agora a falha tem estado próprio,
 * 'member-failed': o header pede para recarregar, nav:member e nav:guest-with-session não disparam, e as telas que
 * esperam o membro mostram "não conseguimos carregar sua conta".
 *
 * A primeira parte exercita member-ready de verdade (o módulo é importado). As demais recortam o bloco que decide
 * e amarram a condição ao resultado, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { readMemberResolution, onMemberResolved, gateAdminPage } from '../../src/lib/member-ready.ts';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
// Comentário HTML removido até o texto parar de mudar: uma passada só deixa "<!--" remontado (CodeQL
// js/incomplete-multi-character-sanitization).
function stripHtmlComments(src) {
  let prev;
  let out = src;
  do { prev = out; out = out.replace(/<!--[\s\S]*?-->/g, ''); } while (out !== prev);
  return out;
}
const mask = (src) => stripHtmlComments(maskJsComments(src));
const flat = (src) => mask(src).replace(/\s+/g, ' ');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => `src/i18n/${l}.ts`);

/** Janela falsa do Nav: estado da sessão, membro e eventos. */
function janela(state, member = null) {
  const listeners = {};
  return {
    state, member,
    navGetMember: function () { return this.member; },
    navAuthState: function () { return this.state; },
    navCapabilitiesFailed: () => false,
    addEventListener(t, fn) { (listeners[t] ||= new Set()).add(fn); },
    removeEventListener(t, fn) { listeners[t]?.delete(fn); },
    fire(t) { [...(listeners[t] || [])].forEach((fn) => fn()); },
  };
}

// ── 1. member-ready, exercitado ──

test('member-ready: Nav em member-failed resolve como member-failed, não como sem cadastro', () => {
  assert.deepEqual(readMemberResolution(janela('member-failed')), { kind: 'member-failed' });
  assert.deepEqual(readMemberResolution(janela('resolved')), { kind: 'no-member' }, 'controle: resolvido sem membro continua no-member');
});

test('member-ready: o evento nav:member-failed acorda quem espera', () => {
  const w = janela('pending');
  const got = [];
  const stop = onMemberResolved((r) => got.push(r.kind), w);
  assert.deepEqual(got, [], 'pendente não decide');
  w.state = 'member-failed';
  w.fire('nav:member-failed');
  stop();
  assert.deepEqual(got, ['member-failed']);
});

test('portão do admin: member-failed chama onLoadFailed; sem ele, onDenied; nunca libera nem pede login', () => {
  const run = (withLoadFailed) => {
    const log = [];
    gateAdminPage({
      allow: () => true,
      onAllowed: () => log.push('allowed'),
      onDenied: () => log.push('denied'),
      onNoSession: () => log.push('no-session'),
      ...(withLoadFailed ? { onLoadFailed: () => log.push('load-failed') } : {}),
    }, janela('member-failed'));
    return log;
  };
  assert.deepEqual(run(true), ['load-failed']);
  assert.deepEqual(run(false), ['denied']);
});

// ── 2. o Nav ──

function resolveBlock() {
  const nav = flat(read('src/components/nav/Nav.astro'));
  const ini = nav.indexOf('async function resolveSessionMember() {');
  const fim = nav.indexOf('async function bootNav()', ini);
  assert.ok(ini !== -1 && fim !== -1, 'resolveSessionMember não encontrada');
  return { nav, corpo: nav.slice(ini, fim) };
}

test('Nav: erro de get_member_by_auth marca member-failed e sai antes de nav:member e de nav:guest-with-session', () => {
  const { corpo } = resolveBlock();
  assert.match(corpo, /let failed = !!memberRes\.error; let data = failed \? null : memberRes\.data;/,
    'o erro da leitura do membro é lido, e o dado só vale sem erro');
  const falha = corpo.match(/if \(failed\) \{ _member = null; _authState = 'member-failed'; renderMemberFailed\(\); window\.dispatchEvent\(new CustomEvent\('nav:member-failed'\)\); return; \}/);
  assert.ok(falha, "com falha: estado member-failed, header de falha, evento próprio e return");
  const iFalha = corpo.indexOf(falha[0]);
  assert.ok(iFalha < corpo.indexOf("new CustomEvent('nav:member'"), 'a saída por falha vem antes do nav:member');
  assert.ok(iFalha < corpo.indexOf("'nav:guest-with-session'"), 'a saída por falha vem antes do nav:guest-with-session');
});

test('Nav: o auto-vínculo só roda sem erro, e o erro dele também é falha', () => {
  const { corpo } = resolveBlock();
  assert.match(corpo, /if \(!failed && !data\) \{ const autoLink = await sb\.rpc\('try_auto_link_ghost'\); if \(autoLink\.error\) \{ failed = true; \} else if \(autoLink\.data\) \{/);
});

test('Nav: boot e SIGNED_IN passam por resolveSessionMember, e não sobra leitura do membro fora dela', () => {
  const { nav, corpo } = resolveBlock();
  assert.equal((nav.match(/await resolveSessionMember\(\);/g) || []).length, 2);
  const fora = nav.replace(corpo, '');
  assert.doesNotMatch(fora, /sb\.rpc\('get_member_by_auth'\)/, 'nenhuma leitura do membro escapa da função que trata o erro');
});

test('Nav: o header de falha pede para recarregar, com texto próprio, e a ação recarrega', () => {
  const { nav } = resolveBlock();
  const ini = nav.indexOf('function renderMemberFailed() {');
  const fim = nav.indexOf('// ── Notification', ini) === -1 ? nav.indexOf('let notifInterval', ini) : nav.indexOf('// ── Notification', ini);
  assert.ok(ini !== -1 && fim > ini, 'renderMemberFailed não encontrada');
  const corpo = nav.slice(ini, fim);
  assert.match(corpo, /\$\{i18n\.memberFailed \|\| '[^']+'\}/, 'texto de falha, não o de conta não cadastrada');
  assert.doesNotMatch(corpo, /guestNotFound|claim\/start|open-auth/, 'nem "Conta não cadastrada", nem vínculo, nem Entrar');
  assert.match(corpo, /<button data-action="reload"[^>]*>\s*\$\{i18n\.memberFailedReload \|\| '[^']+'\}/);
  assert.match(nav, /if \(action === 'reload'\) \{ window\.location\.reload\(\); \}/);
  assert.match(nav, /memberFailed: t\('nav\.memberFailed', lang\), memberFailedReload: t\('nav\.memberFailedReload', lang\),/);
});

// ── 3. as telas ──

// [arquivo, id do bloco, regex do ramo que decide e mostra o bloco de falha]
const PAGES = [
  ['src/pages/minha-pontuacao.astro', 'mp-failed',
    /show\(r\.kind === 'no-session' \? 'mp-gate' : r\.kind === 'member-failed' \? 'mp-failed' : 'mp-guest', true\);/],
  ['src/pages/minhas-avaliacoes.astro', 'me-failed',
    /if \(r\.kind === 'no-member'\) \{ showOnly\('guest'\); return; \} if \(r\.kind === 'member-failed'\) \{ showOnly\('failed'\); return; \} sb = /],
  ['src/pages/minhas-vagas.astro', 'mv-failed',
    /if \(r\.kind === 'no-member'\) \{ showOnly\('guest'\); return; \} if \(r\.kind === 'member-failed'\) \{ showOnly\('failed'\); return; \} sb = /],
  ['src/pages/volunteer-agreement.astro', 'va-failed',
    /if \(resolution\.kind === 'member-failed'\) \{ app\.innerHTML = ''; document\.getElementById\('va-failed'\)\?\.classList\.remove\('hidden'\); return; \} if \(!member\) \{/],
  ['src/pages/workspace.astro', 'wk-failed',
    /const failed = kind === 'member-failed'; \$guest\?\.classList\.toggle\('hidden', !noMember\); \$failed\?\.classList\.toggle\('hidden', !failed\); \$authGate\?\.classList\.toggle\('hidden', noMember \|\| failed\);/],
];

for (const [file, id, branch] of PAGES) {
  test(`${file}: falha ao ler o membro mostra ${id}, não o bloco de sem cadastro nem o login`, () => {
    const src = flat(read(file));
    assert.ok(src.trim(), `${file} presente`);
    assert.match(src, /import MemberLoadFailed from '\.\.\/components\/ui\/MemberLoadFailed\.astro';/, 'importa o componente');
    assert.match(src, new RegExp(`<MemberLoadFailed lang=\\{lang\\} id="${id}" />`), `renderiza o bloco com o id ${id}`);
    assert.match(src, branch, 'o ramo de falha mostra esse bloco');
  });
}

test('minhas-avaliacoes e minhas-vagas: o bloco de falha entra no showOnly, que esconde os outros estados', () => {
  for (const [file, pre] of [['src/pages/minhas-avaliacoes.astro', 'me'], ['src/pages/minhas-vagas.astro', 'mv']]) {
    const m = flat(read(file)).match(/function showOnly\(which: ([^)]*)\) \{ \[([^\]]*)\]\.forEach/);
    assert.ok(m, `${file}: showOnly`);
    assert.match(m[1], /'failed'/, `${file}: 'failed' no tipo`);
    assert.match(m[2], new RegExp(`'${pre}-failed'`), `${file}: ${pre}-failed na lista`);
  }
});

test('workspace: carregar o membro esconde o bloco de falha', () => {
  assert.match(flat(read('src/pages/workspace.astro')),
    /async function onMemberReady\(\) \{[^}]*\$guest\?\.classList\.add\('hidden'\); \$failed\?\.classList\.add\('hidden'\);/);
});

test('admin/selection: falha ao ler o membro mostra o texto de falha de carga, não o de sem acesso', () => {
  assert.match(flat(read('src/pages/admin/selection.astro')),
    /onMemberResolved\(\(r\) => \{ if \(r\.kind === 'no-session'\) \{ showDenied\(adminSignInText\(\)\); return; \} if \(r\.kind === 'member-failed'\) \{ showDenied\(adminLoadFailedText\(\)\); return; \}/);
});

// ── 4. componente e textos ──

test('componente: nasce escondido, recarrega a mesma página e não oferece vínculo nem candidatura', () => {
  const src = mask(read('src/components/ui/MemberLoadFailed.astro'));
  const root = src.match(/<div id=\{id\} class="([^"]*)" data-member-load-failed>/);
  assert.ok(root, 'raiz com o id e a marca data-member-load-failed');
  assert.match(root[1], /(^|\s)hidden(\s|$)/, 'nasce escondido');
  assert.match(src, /<a id=\{`\$\{id\}-reload`\} href=\{Astro\.url\.pathname \+ Astro\.url\.search\}[^>]*>\s*\{t\('memberFailed\.reload', lang\)\}/);
  assert.match(src, /\{t\('memberFailed\.title', lang\)\}/);
  assert.match(src, /\{t\('memberFailed\.body', lang\)\}/);
  assert.doesNotMatch(src, /claim\/start|#join|guest\./, 'falha de leitura não é sessão sem cadastro');
});

test('textos: as 5 chaves existem nos 3 dicionários', () => {
  for (const d of DICTS) {
    const src = read(d);
    for (const k of ['nav.memberFailed', 'nav.memberFailedReload', 'memberFailed.title', 'memberFailed.body', 'memberFailed.reload']) {
      assert.match(src, new RegExp(`^  '${k.replace('.', '\\.')}': (?:'[^']+'|"[^"]+"),$`, 'm'), `${d}: ${k}`);
    }
  }
});

test('controle do limpador de comentário HTML: remonta e remove na volta seguinte', () => {
  assert.equal(stripHtmlComments('<!<!-- a -->-- b -->x'), 'x');
});
