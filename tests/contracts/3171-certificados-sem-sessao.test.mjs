/**
 * #3171: /certificates sem sessão pede login.
 *
 * Sem sessão, get_my_certificates procura o membro por auth.uid(), não acha e devolve lista vazia; a tela dizia
 * "nenhum certificado" com a CTA do termo, que não serve a quem não entrou. Agora a tela decide pelo Nav antes de
 * ler e, sem sessão, mostra o pedido de login com o botão que abre o modal do layout ('open-auth' no document,
 * o único ouvinte, #1997).
 *
 * Comentários JS e HTML saem antes do assert; o HTML repete até estabilizar (CodeQL
 * js/incomplete-multi-character-sanitization).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
function stripHtmlComments(src) {
  let prev;
  let out = src;
  do { prev = out; out = out.replace(/<!--[\s\S]*?-->/g, ''); } while (out !== prev);
  return out;
}
const flat = (p) => stripHtmlComments(maskJsComments(read(p))).replace(/\s+/g, ' ');
// Lê o valor da chave sem montar regex com a chave (CodeQL js/incomplete-sanitization).
function keyIn(src, k) {
  const head = `'${k}': '`;
  const a = src.indexOf(head);
  if (a < 0) return undefined;
  const b = src.indexOf("'", a + head.length);
  return b < 0 ? undefined : src.slice(a + head.length, b);
}

test('#3171: o bloco de login nasce escondido, com o texto e o botão de entrar', () => {
  const s = flat('src/pages/certificates.astro');
  assert.match(s, /<div id="certs-login" class="hidden [^"]*"> <p[^>]*>\{t\('certificates\.loginRequired', lang\)\}<\/p> <button id="certs-login-btn" type="button"[^>]*>\{t\('nav\.login', lang\)\}<\/button> <\/div>/);
});

test('#3171: sem sessão a tela mostra o login e para antes de ler os certificados', () => {
  const s = flat('src/pages/certificates.astro');
  const espera = s.indexOf('const r = await waitMemberResolved();');
  const m = /if \(r\.kind === 'no-session'\) \{ container\.classList\.add\('hidden'\); document\.getElementById\('certs-login'\)\?\.classList\.remove\('hidden'\); document\.getElementById\('certs-login-btn'\)\?\.addEventListener\('click', \(\) => \{ document\.dispatchEvent\(new CustomEvent\('open-auth'\)\); \}\); return; \}/.exec(s);
  assert.ok(m, 'sem sessão: esconde a lista, mostra o login, o botão abre o modal, e a página para');
  const leitura = s.search(/\.rpc\('get_my_certificates'/);
  assert.ok(espera > -1 && espera < m.index, 'decide depois de esperar o Nav');
  assert.ok(leitura > -1 && m.index < leitura, 'decide antes de qualquer leitura dos certificados');
});

test('#3171: a chave nova está nos 3 dicionários, com o texto decidido em pt-BR', () => {
  assert.equal(keyIn(read('src/i18n/pt-BR.ts'), 'certificates.loginRequired'), 'Entre para ver seus certificados.');
  for (const l of ['en-US', 'es-LATAM']) assert.ok(keyIn(read(`src/i18n/${l}.ts`), 'certificates.loginRequired'), l);
});
