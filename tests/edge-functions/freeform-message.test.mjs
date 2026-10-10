// #2586 — renderização pura da mensagem avulsa de corpo livre (send-campaign).
import test from 'node:test';
import assert from 'node:assert/strict';
import { renderFreeform, resolveReplyTo, textToHtml, firstName } from '../../supabase/functions/_shared/freeform-message.ts';

const TEMPLATE_HTML = '{{content_html}}<p>Equipe</p><!--EXTERNO--><p>Aviso {unsubscribe_url}</p><!--/EXTERNO-->';
const TEMPLATE_TEXT = '{{content_text}}\n\nEquipe[[EXTERNO]]\n--\nAviso[[/EXTERNO]]';

const base = {
  subject: 'Olá, {first_name}',
  body: 'Linha 1\nLinha 2\n\n<script>alert(1)</script> & "aspas"',
  recipientName: 'Maria da Silva',
  isExternal: true,
  templateSubject: '{{subject}}',
  templateHtml: TEMPLATE_HTML,
  templateText: TEMPLATE_TEXT,
};

test('corpo digitado é escapado e vira parágrafos (nunca HTML cru)', () => {
  const { html } = renderFreeform(base);
  assert.match(html, /^<p>Linha 1<br>Linha 2<\/p><p>&lt;script&gt;alert\(1\)&lt;\/script&gt; &amp; &quot;aspas&quot;<\/p>/);
  assert.doesNotMatch(html, /<script\b/i);
});

test('{first_name} vira o primeiro nome no assunto e no corpo', () => {
  const r = renderFreeform({ ...base, body: 'Oi {first_name}' });
  assert.equal(r.subject, 'Olá, Maria');
  assert.match(r.html, /<p>Oi Maria<\/p>/);
  assert.match(r.text, /^Oi Maria/);
});

test('o aviso de privacidade fica só para o externo, sem os marcadores', () => {
  const ext = renderFreeform(base);
  assert.match(ext.html, /<p>Equipe<\/p><p>Aviso \{unsubscribe_url\}<\/p>$/);
  assert.doesNotMatch(ext.html, /EXTERNO/);
  assert.match(ext.text, /Equipe\n--\nAviso$/);
  const member = renderFreeform({ ...base, isExternal: false });
  assert.match(member.html, /<p>Equipe<\/p>$/);
  assert.doesNotMatch(member.html, /Aviso/);
  assert.doesNotMatch(member.text, /Aviso|EXTERNO/);
});

test('assunto não carrega quebra de linha (cabeçalho de e-mail)', () => {
  assert.equal(renderFreeform({ ...base, subject: 'A\r\nBcc: x@y.z' }).subject, 'A Bcc: x@y.z');
});

test('reply-to: o do tema; sem ele, o padrão; endereço inválido é ignorado', () => {
  assert.equal(resolveReplyTo('tema@example.org', 'padrao@example.org'), 'tema@example.org');
  assert.equal(resolveReplyTo(null, 'padrao@example.org'), 'padrao@example.org');
  assert.equal(resolveReplyTo('nao é email', 'padrao@example.org'), 'padrao@example.org');
  assert.equal(resolveReplyTo(null, null), null);
  // estrito: um endereço com "<" ou vírgula abriria outro destinatário no cabeçalho
  assert.equal(resolveReplyTo('x<alvo@example.org>', 'padrao@example.org'), 'padrao@example.org');
  assert.equal(resolveReplyTo('a@example.org, c@example.org', null), null);
});

test('auxiliares: primeiro nome e parágrafos', () => {
  assert.equal(firstName('  Ana  Souza '), 'Ana');
  assert.equal(firstName(null), '');
  assert.equal(textToHtml('a\r\n\r\nb'), '<p>a</p><p>b</p>');
});
