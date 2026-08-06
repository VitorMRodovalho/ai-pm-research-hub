/**
 * #1629 — sanitizeUserHtml: teste ADVERSARIAL por payload.
 *
 * Por que por payload e não por grep de fonte: o defeito que este arquivo existe para impedir
 * é "a defesa existe e não protege". Um `assert.match` no fonte provaria que a allowlist está
 * escrita; não prova que `onclick` cai. O `ultrahtml/transformers/sanitize` é o exemplo vivo —
 * bloqueia `<script>` e `<iframe>` (parece funcionar) e deixa passar `onclick`, `style` e
 * `href="javascript:"`, porque não nega atributo por padrão. Foi o que motivou escrever o
 * sanitizador em vez de configurá-lo. Mesma classe do tripwire do #1620.
 *
 * Regra para quem mexer aqui: todo vetor novo entra como payload, e o assert é sobre a SAÍDA.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { sanitizeUserHtml } from '../../src/lib/sanitize-html.ts';

/** Um payload é seguro se nenhuma destas marcas sobreviveu. */
function residuoPerigoso(html) {
  const marcas = [
    [/<\s*script/i, '<script>'],
    [/<\s*iframe/i, '<iframe>'],
    [/<\s*svg/i, '<svg>'],
    [/<\s*form/i, '<form>'],
    [/<\s*object|<\s*embed/i, '<object>/<embed>'],
    [/\son[a-z]+\s*=/i, 'handler on*='],
    [/javascript\s*:/i, 'javascript:'],
    [/\sstyle\s*=/i, 'style='],
    [/data:text\/html/i, 'data:text/html'],
    [/data:image\/svg/i, 'data:image/svg+xml'],
  ];
  return marcas.filter(([re]) => re.test(html)).map(([, nome]) => nome);
}

const VETORES = [
  ['script simples',          '<p>ok</p><script>alert(1)</script>'],
  ['script maiúsculo',        '<SCRIPT>alert(1)</SCRIPT>'],
  ['onerror em img',          '<img src=x onerror="alert(1)">'],
  ['onclick em tag permitida','<p onclick="alert(1)">clique</p>'],
  ['onload maiúsculo',        '<p OnLoAd="alert(1)">x</p>'],
  ['href javascript:',        '<a href="javascript:alert(1)">link</a>'],
  ['href JaVaScRiPt:',        '<a href="JaVaScRiPt:alert(1)">link</a>'],
  ['href com espaço',         '<a href=" javascript:alert(1)">link</a>'],
  ['href com tab no esquema', '<a href="java\tscript:alert(1)">link</a>'],
  ['href com newline',        '<a href="java\nscript:alert(1)">link</a>'],
  ['style com url(js)',       '<p style="background:url(javascript:alert(1))">x</p>'],
  ['iframe',                  '<iframe src="https://evil.tld"></iframe>'],
  ['svg onload',              '<svg onload="alert(1)"></svg>'],
  ['form + input',            '<form action="https://evil.tld"><input name="a"></form>'],
  ['object',                  '<object data="evil.swf"></object>'],
  ['embed',                   '<embed src="evil.swf">'],
  ['data:text/html em href',  '<a href="data:text/html;base64,PHNjcmlwdD4=">x</a>'],
  ['data:svg+xml em img',     '<img src="data:image/svg+xml;base64,PHN2Zz4=">'],
  ['meta refresh',            '<meta http-equiv="refresh" content="0;url=javascript:alert(1)">'],
  ['base href',               '<base href="https://evil.tld/">'],
  ['script aninhado em div',  '<div><p>a</p><script>alert(1)</script><p>b</p></div>'],
  ['script dentro de link',   '<a href="#"><script>alert(1)</script>texto</a>'],
  ['handler em td',           '<table><tr><td onmouseover="alert(1)">c</td></tr></table>'],
  ['noscript',                '<noscript><p>x</p></noscript>'],
  ['template',                '<template><script>alert(1)</script></template>'],
];

for (const [nome, payload] of VETORES) {
  test(`bloqueia: ${nome}`, () => {
    const saida = sanitizeUserHtml(payload);
    const residuo = residuoPerigoso(saida);
    assert.deepEqual(residuo, [],
      `payload ${JSON.stringify(payload)} deixou residuo ${residuo.join(', ')} -> ${JSON.stringify(saida)}`);
  });
}

// ─── O conteúdo legítimo tem de sobreviver ───────────────────────────────────
// Sanitizador que apaga tudo passa em todos os testes acima. Estes impedem isso.

test('preserva formatação legítima de post', () => {
  const html = '<h2>Título</h2><p>Texto com <strong>negrito</strong> e <em>itálico</em>.</p>'
    + '<ul><li>um</li><li>dois</li></ul><blockquote>citação</blockquote><code>x = 1</code>';
  const out = sanitizeUserHtml(html);
  for (const tag of ['h2', 'strong', 'em', 'ul', 'li', 'blockquote', 'code']) {
    assert.match(out, new RegExp(`<${tag}[ >]`), `<${tag}> deveria sobreviver`);
  }
  assert.match(out, /Texto com/, 'o texto deve sobreviver');
});

test('preserva tabela com colspan e link http', () => {
  const out = sanitizeUserHtml('<table><tr><td colspan="2"><a href="https://pmi.org">PMI</a></td></tr></table>');
  assert.match(out, /colspan="2"/, 'colspan é atributo legítimo de td');
  assert.match(out, /href="https:\/\/pmi\.org"/, 'link http deve sobreviver');
});

test('href relativo, âncora e mailto sobrevivem', () => {
  for (const href of ['/blog/post', '#secao', 'mailto:a@b.org', '../rel']) {
    const out = sanitizeUserHtml(`<a href="${href}">x</a>`);
    assert.match(out, /<a /, `href=${href} não deveria derrubar a tag`);
    assert.ok(out.includes(href), `href=${href} deveria sobreviver, saiu: ${out}`);
  }
});

test('link ganha rel="noopener noreferrer" (tabnabbing)', () => {
  const out = sanitizeUserHtml('<a href="https://externo.tld" target="_blank">x</a>');
  assert.match(out, /rel="noopener noreferrer"/,
    'todo <a href> deve sair com o par completo, sem depender do autor ter escrito target');
});

test('tag desconhecida é DESEMBRULHADA, não apagada (o texto do autor sobrevive)', () => {
  const out = sanitizeUserHtml('<section><p>conteudo importante</p></section>');
  assert.match(out, /conteudo importante/, 'o conteúdo não pode sumir junto com a tag');
  assert.doesNotMatch(out, /<section/, 'a tag desconhecida em si não deve sair');
});

test('script é dropado COM os filhos (corpo não vira texto visível)', () => {
  const out = sanitizeUserHtml('<p>antes</p><script>alert("XSS")</script><p>depois</p>');
  assert.match(out, /antes/);
  assert.match(out, /depois/);
  assert.doesNotMatch(out, /alert/, 'o corpo do script não pode reaparecer como texto');
});

test('entrada vazia/nula devolve string vazia', () => {
  assert.equal(sanitizeUserHtml(''), '');
  assert.equal(sanitizeUserHtml(null), '');
  assert.equal(sanitizeUserHtml(undefined), '');
});

test('idempotência: sanitizar a saída não muda mais nada', () => {
  const html = '<h2>t</h2><p onclick="x">a <a href="javascript:1">b</a> <strong>c</strong></p>';
  const uma = sanitizeUserHtml(html);
  assert.equal(sanitizeUserHtml(uma), uma, 'segunda passada deve ser no-op');
});
