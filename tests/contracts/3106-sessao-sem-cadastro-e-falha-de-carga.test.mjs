/**
 * #3106: quem já entrou não recebe pedido de login, e falha de carga não vira "link expirado".
 *
 * Sessão sem cadastro de membro (entrou pelo Google, sem linha em members): /minha-candidatura dizia
 * "Você precisa estar autenticado"; /volunteer-agreement, /minhas-avaliacoes e /minhas-vagas esperavam
 * o membro por tentativas contadas e depois diziam "login necessário"; /minha-pontuacao e /workspace
 * mostravam o portão de login. Agora cada tela decide pelo estado do Nav (member-ready) e, para sessão
 * sem cadastro, mostra o bloco da #3086 (seleção e vínculo), num componente único.
 *
 * Links por token (/interview-booking, /pmi-onboarding): falha de banco ou de rede caía no título de
 * link expirado, com a mensagem crua do erro. Agora tem estado próprio, sem a mensagem crua.
 *
 * As asserções recortam o bloco que decide e amarram a condição ao resultado, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { waitMemberResolved } from '../../src/lib/member-ready.ts';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
// Comentário HTML vira espaço, até o texto parar de mudar (CodeQL js/incomplete-multi-character-sanitization).
function blankHtmlComments(src) {
  let prev;
  let out = src;
  do { prev = out; out = out.replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' ')); } while (out !== prev);
  return out;
}
const maskAstro = (src) => blankHtmlComments(maskJsComments(src));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => `src/i18n/${l}.ts`);
const COMP = 'src/components/ui/GuestNoMember.astro';

test('componente: nasce escondido, a primeira ação é a candidatura e a segunda o vínculo, no idioma da página', () => {
  const src = maskAstro(read(COMP));
  const root = src.match(/<div id=\{id\} class="([^"]*)" data-guest-no-member>/);
  assert.ok(root, 'raiz com o id da página e a marca data-guest-no-member');
  assert.match(root[1], /(^|\s)hidden(\s|$)/, 'nasce escondido: a página mostra quando o Nav resolve sem membro');
  assert.match(src, /const langPrefix = lang === 'pt-BR' \? '' : lang === 'en-US' \? '\/en' : '\/es';/, 'prefixo do idioma calculado do lang');
  assert.match(src, /\{t\('guest\.contactAdmin', lang\)\}/, 'texto da #3086');
  const links = [...src.matchAll(/<a id=\{`\$\{id\}-(\w+)`\} href=\{`([^`]+)`\}[^>]*>\s*\{t\('([\w.]+)', lang\)\}/g)].map((m) => m.slice(1));
  assert.deepEqual(links, [['apply', '${langPrefix}/#join', 'guest.applyCta'], ['claim', '${langPrefix}/claim/start', 'guest.claimCta']],
    'candidatura em #join, depois vínculo em /claim/start, cada um com o seu rótulo');
});

// [arquivo, id do bloco, regex do ramo que decide e mostra o bloco]
const PAGES = [
  ['src/pages/minha-candidatura.astro', 'me-status-guest',
    /if \(!error && data\?\.error === 'not_authenticated'\) \{\s+show\('me-status-guest'\);\s+return;\s+\}/],
  ['src/pages/volunteer-agreement.astro', 'va-guest',
    /const resolution = await waitMemberResolved\(\);[\s\S]{0,200}?if \(resolution\.kind === 'no-member'\) \{\s+app\.innerHTML = '';\s+document\.getElementById\('va-guest'\)\?\.classList\.remove\('hidden'\);\s+return;\s+\}/],
  ['src/pages/minhas-avaliacoes.astro', 'me-guest',
    /const r = await waitMemberResolved\(\);\s+if \(r\.kind === 'no-session'\) \{ showDenied\(I\.loginRequired\); return; \}\s+if \(r\.kind === 'no-member'\) \{ showOnly\('guest'\); return; \}/],
  ['src/pages/minhas-vagas.astro', 'mv-guest',
    /const r = await waitMemberResolved\(\);\s+if \(r\.kind === 'no-session'\) \{ showNotice\(I\.loginRequired\); return; \}\s+if \(r\.kind === 'no-member'\) \{ showOnly\('guest'\); return; \}/],
  ['src/pages/minha-pontuacao.astro', 'mp-guest',
    /const r = await waitMemberResolved\(\);[\s\S]{0,120}?if \(r\.kind === 'member' && isRegisteredMember\(r\.member\)\) \{ MEMBER = r\.member; start\(\); return; \}\s+show\('mp-loading', false\);\s+show\(r\.kind === 'no-session' \? 'mp-gate' : 'mp-guest', true\);/],
  ['src/pages/workspace.astro', 'wk-guest',
    /const noMember = readMemberResolution\(window as any\)\?\.kind === 'no-member';\s+\$guest\?\.classList\.toggle\('hidden', !noMember\);\s+\$authGate\?\.classList\.toggle\('hidden', noMember\);/],
];

for (const [file, id, branch] of PAGES) {
  test(`${file}: sessão sem cadastro mostra o bloco ${id}, decidido pelo estado do Nav`, () => {
    const src = maskAstro(read(file));
    assert.ok(src, `${file} presente`);
    assert.match(src, /^import GuestNoMember from '\.\.\/components\/ui\/GuestNoMember\.astro';$/m, 'importa o componente');
    assert.match(src, new RegExp(`<GuestNoMember lang=\\{lang\\} id="${esc(id)}" />`), `renderiza o bloco com o id ${id}`);
    assert.match(src, branch, 'o ramo de sessão sem cadastro mostra esse bloco');
    assert.doesNotMatch(src, /bootRetries|Date\.now\(\) < deadline/, 'sem espera por tentativas contadas');
  });
}

test('minha-candidatura: o erro que sobra não vira "precisa estar autenticado"', () => {
  const src = maskAstro(read('src/pages/minha-candidatura.astro'));
  assert.doesNotMatch(src, /data\.error\) \? I\.notAuthenticated/, 'not_authenticated com sessão já foi tratado; o resto é erro de carga');
});

test('minhas-avaliacoes e minhas-vagas: o bloco de visitante entra no showOnly, que esconde os outros estados', () => {
  for (const [file, pre] of [['src/pages/minhas-avaliacoes.astro', 'me'], ['src/pages/minhas-vagas.astro', 'mv']]) {
    const src = maskAstro(read(file));
    const m = src.match(/function showOnly\(which: ([^)]*)\) \{\s+\[([^\]]*)\]\.forEach/);
    assert.ok(m, `${file}: showOnly`);
    assert.match(m[1], /'guest'/, `${file}: 'guest' é um estado`);
    assert.match(m[2], new RegExp(`'${pre}-guest'`), `${file}: ${pre}-guest é escondido quando outro estado aparece`);
  }
});

test('workspace: membro nulo no nav:member passa pela mesma decisão, e a tela não lê o membro por conta própria', () => {
  const src = maskAstro(read('src/pages/workspace.astro'));
  assert.match(src, /window\.addEventListener\('nav:member', \(\(e: CustomEvent\) => \{\s+if \(isRegisteredMember\(e\.detail\)\) \{\s+member = e\.detail;\s+onMemberReady\(\);\s+\} else \{\s+showNoMember\(\);\s+\}/,
    'nav:member com membro nulo decide entre login e bloco pelo estado do Nav');
  assert.doesNotMatch(src, /rpc\('get_member_by_auth'\)/, 'o membro vem do Nav, não de uma segunda leitura');
});

function fakeWin({ member = null, state = 'pending' } = {}) {
  const listeners = new Map();
  const win = {
    member, state,
    addEventListener: (t, fn) => { listeners.set(t, (listeners.get(t) || new Set()).add(fn)); },
    removeEventListener: (t, fn) => { listeners.get(t)?.delete(fn); },
    navGetMember: () => win.member,
    navAuthState: () => win.state,
    navCapabilitiesFailed: () => false,
    fire: (t) => { for (const fn of [...(listeners.get(t) || [])]) fn(); },
    count: () => [...listeners.values()].reduce((n, s) => n + s.size, 0),
  };
  return win;
}

test('waitMemberResolved: espera sem prazo, resolve uma vez com o estado do Nav e para de ouvir', async () => {
  const resolved = fakeWin({ state: 'resolved' });
  assert.deepEqual(await waitMemberResolved(resolved), { kind: 'no-member' }, 'sessão lida e sem membro é no-member');
  assert.equal(resolved.count(), 0, 'já resolvido: não fica ouvindo');

  const pending = fakeWin();
  let got = null;
  const p = waitMemberResolved(pending).then((r) => { got = r; });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(got, null, 'enquanto o Nav não leu a sessão, nada é decidido');
  pending.member = { id: 'm1' };
  pending.state = 'resolved';
  pending.fire('nav:member');
  await p;
  assert.equal(got.kind, 'member');
  assert.equal(pending.count(), 0, 'depois de resolver, para de ouvir');

  const noSession = fakeWin();
  const q = waitMemberResolved(noSession);
  noSession.state = 'no-session';
  noSession.fire('nav:no-session');
  assert.deepEqual(await q, { kind: 'no-session' });
});

const TOKEN_PAGES = [
  ['src/pages/interview-booking/[token].astro', 'interview.booking'],
  ['src/pages/pmi-onboarding/[token].astro', 'pmi.onboarding'],
];

for (const [file, prefix] of TOKEN_PAGES) {
  test(`${file}: falha de banco ou de rede tem estado próprio, sem a mensagem crua, antes do "link expirado"`, () => {
    const src = maskAstro(read(file));
    const end = src.indexOf('\n---', 4);
    const front = src.slice(0, end);
    const tpl = src.slice(end);
    assert.match(front, /: 'rpc_error';\s+if \(errorMessage === 'rpc_error'\) \{ loadFailed = true;/, 'rpc_error marca falha de carga');
    assert.match(front, /catch \(e: any\) \{\s+errorMessage = 'network_error';\s+loadFailed = true;/, 'falha de rede marca falha de carga');
    assert.doesNotMatch(front, /errorMessage = `[^`]*\$\{(?:error|e\?)\.?message/, 'a mensagem crua do erro não vai para errorMessage, que a tela mostra');
    const failed = tpl.indexOf('{errorMessage && loadFailed ? (');
    const expired = tpl.indexOf(`{t('${prefix}.error.expiredTitle', lang)}`);
    assert.ok(failed > 0 && expired > failed, 'o ramo de falha de carga vem antes do de link expirado');
    const block = tpl.slice(failed, expired);
    assert.match(block, /\{t\('tokenLink\.loadFailedTitle', lang\)\}[\s\S]*\{t\('tokenLink\.loadFailedBody', lang\)\}/, 'título e texto de falha de carga');
    assert.match(block, /<a href=\{Astro\.url\.pathname \+ Astro\.url\.search\}[^>]*>\{t\('tokenLink\.retry', lang\)\}<\/a>/, 'botão de tentar de novo na mesma URL');
    assert.doesNotMatch(block, /expiredTitle|expiredBody/, 'a falha de carga não fala de link expirado');
  });
}

test('i18n: as chaves de falha de carga existem nas 3 línguas, sem travessão longo e sem dizer que o link expirou', () => {
  for (const d of DICTS) {
    const src = read(d);
    for (const k of ['tokenLink.loadFailedTitle', 'tokenLink.loadFailedBody', 'tokenLink.retry']) {
      const m = src.match(new RegExp(`^  '${esc(k)}': '((?:[^'\\\\]|\\\\.)+)',$`, 'm'));
      assert.ok(m, `${k} em ${d}`);
      assert.doesNotMatch(m[1], /—/, `${k} em ${d} sem travessão longo`);
      assert.doesNotMatch(m[1], /expir|inválid|invalid|inválid/i, `${k} em ${d} não diz que o link expirou`);
    }
  }
});
