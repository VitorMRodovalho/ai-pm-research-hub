/**
 * /claim/start mostra o caminho de quem NÃO se candidatou.
 *
 * Quem entra pelo Google sem ser membro nem candidato cai em "Conta não cadastrada" e o banner do
 * header leva a /claim/start, que vincula conta de APROVADO no VEP. A resposta do RPC é genérica de
 * propósito (não revela quais e-mails existem), então esse visitante digita o próprio e-mail e nada
 * chega. A página passa a dizer, visível antes de digitar, que o vínculo é só para aprovados e
 * oferece os dois caminhos: candidatura (seção #join da home) e a Reunião Geral (/reunioes-gerais).
 *
 * Cada asserção amarra a condição ao resultado dentro do bloco que decide, sobre o corpo com os
 * comentários mascarados, porque o comentário do frontmatter cita as mesmas âncoras.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const PAGE = 'src/pages/claim/start.astro';
const JOIN = 'src/components/sections/JoinSection.astro';
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => `src/i18n/${l}.ts`);
const KEYS = ['claim.notApplied.title', 'claim.notApplied.body', 'claim.notApplied.apply', 'claim.notApplied.geral'];

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function parts() {
  const src = maskAstro(read(PAGE));
  assert.ok(src, `${PAGE} presente`);
  const end = src.indexOf('\n---', 4);
  assert.ok(end > 0, 'frontmatter fechado');
  return { front: src.slice(0, end), template: src.slice(end) };
}

test('frontmatter: os destinos do aviso são a seção #join da home e /reunioes-gerais, no idioma da página', () => {
  const { front } = parts();
  const block = front.match(/const NOT_APPLIED = \{([\s\S]*?)\n\};/);
  assert.ok(block, 'bloco NOT_APPLIED presente no frontmatter');
  assert.match(block[1], /applyHref:\s*`\$\{langPrefix\}\/#join`/, 'candidatura aponta para #join da home, com o prefixo do idioma');
  assert.match(block[1], /geralHref:\s*`\$\{langPrefix\}\/reunioes-gerais`/, 'Geral aponta para /reunioes-gerais, com o prefixo do idioma');
  for (const k of KEYS) {
    assert.match(block[1], new RegExp(`:\\s*t\\('${esc(k)}', lang\\)`), `${k} traduzido pelo idioma da página`);
  }
});

test('template: o aviso é estático, visível antes de digitar, abaixo do formulário e liga cada texto ao seu destino', () => {
  const { template } = parts();
  const open = template.match(/<section id="claim-not-applied"[^>]*>/);
  assert.ok(open, 'seção #claim-not-applied renderizada no template');
  const cls = open[0].match(/class="([^"]*)"/);
  assert.ok(cls, 'seção tem class');
  assert.doesNotMatch(cls[1], /(^|\s)hidden(\s|$)/, 'a seção não nasce escondida: é para ser lida antes de digitar');

  const formEnd = template.indexOf('</form>');
  const fallback = template.indexOf('{CLAIM_I18N.fallbackAdmin}');
  assert.ok(formEnd > 0 && fallback > 0, 'formulário e contato do gestor presentes');
  assert.ok(open.index > formEnd && open.index < fallback, 'o aviso fica abaixo do formulário, antes do contato do gestor');

  const body = template.slice(open.index, template.indexOf('</section>', open.index));
  assert.match(body, /<a id="claim-not-applied-apply" href=\{NOT_APPLIED\.applyHref\}[^>]*>\{NOT_APPLIED\.apply\}/,
    'o link de candidatura leva ao destino de candidatura com o texto de candidatura');
  assert.match(body, /<a id="claim-not-applied-geral" href=\{NOT_APPLIED\.geralHref\}[^>]*>\{NOT_APPLIED\.geral\}/,
    'o link da Geral leva à agenda da Geral com o texto da Geral');
  assert.match(body, /\{NOT_APPLIED\.body\}/, 'explica que o vínculo é só para aprovados');
});

test('destinos existem: #join é a seção sempre renderizada da home, e /reunioes-gerais tem rota nas 3 línguas', () => {
  const join = maskAstro(read(JOIN));
  assert.match(join, /^<section [^>]*id="join"/m, '#join é a <section> de topo do JoinSection, não um bloco condicional');
  for (const p of ['src/pages/reunioes-gerais.astro', 'src/pages/en/reunioes-gerais.astro', 'src/pages/es/reunioes-gerais.astro']) {
    assert.ok(existsSync(p), `${p} existe`);
  }
});

test('i18n: as 4 chaves existem nas 3 línguas, sem travessão longo e sem promessa proibida', () => {
  for (const d of DICTS) {
    const src = read(d);
    for (const k of KEYS) {
      const m = src.match(new RegExp(`^  '${esc(k)}': '((?:[^'\\\\]|\\\\.)+)',$`, 'm'));
      assert.ok(m, `${k} em ${d}`);
      assert.doesNotMatch(m[1], /—/, `${k} em ${d} sem travessão longo`);
      assert.doesNotMatch(m[1], /\bPDUs?\b|oficial do PMI|official PMI|oficial del PMI|chancelad|endorsed|avalad/i,
        `${k} em ${d} sem prometer PDU nem chancela`);
    }
  }
});

const NAV = 'src/components/nav/Nav.astro';
const val = (src, k) => {
  const m = src.match(new RegExp(`^  '${esc(k)}': '((?:[^'\\\\]|\\\\.)+)',$`, 'm'));
  return m ? m[1].replace(/\\(.)/g, '$1') : null;
};

test('header: o botão do visitante logado sem cadastro leva a /claim/start com um rótulo que não presume aprovação', () => {
  const nav = maskAstro(read(NAV));
  const start = nav.indexOf('function renderGuestWithSession()');
  assert.ok(start > 0, 'renderGuestWithSession presente');
  const block = nav.slice(start, nav.indexOf('\n  }\n', start));
  assert.match(block, /<a href="\/claim\/start\?lang=\$\{langCode\}"[^>]*>\s*\$\{i18n\.claimCta \|\| '([^']+)'\}\s*<\/a>/,
    'o link do banner para /claim/start carrega o rótulo claimCta');
  const fallback = block.match(/\$\{i18n\.claimCta \|\| '([^']+)'\}/)[1];
  assert.doesNotMatch(fallback, /vincul|link my/i, 'o fallback do rótulo não presume conta a vincular');
  for (const d of DICTS) {
    const cta = val(read(d), 'claim.cta');
    assert.ok(cta, `claim.cta em ${d}`);
    assert.doesNotMatch(cta, /vincul|link my/i, `claim.cta em ${d} não presume aprovação: o visitante sem candidatura também vê o botão`);
  }
});

test('link expirado: a instrução cita o rótulo que o header de fato mostra, em cada língua', () => {
  for (const d of DICTS) {
    const src = read(d);
    const cta = val(src, 'claim.cta');
    const expired = val(src, 'claim.confirmExpired');
    assert.ok(cta && expired, `claim.cta e claim.confirmExpired em ${d}`);
    assert.ok(expired.includes(`"${cta}"`), `confirmExpired em ${d} cita "${cta}", o rótulo atual do botão`);
  }
});
