/**
 * O desafio 401 das rotas MCP segue o host da requisicao.
 *
 * As rotas /mcp, /mcp/semantic e /mcp/actions respondem 401 sem token, com
 * `WWW-Authenticate: Bearer resource_metadata="<origem>/.well-known/oauth-protected-resource/<superficie>"`.
 * A origem sai de `url.origin`, a mesma regra dos .well-known (que ja derivam issuer e resource da
 * requisicao). Assim cada host anuncia a propria identidade e um cliente que conectou em um host nao e
 * mandado descobrir outro.
 *
 * Cada asserção casa a condicao junto com o resultado, dentro do bloco que decide (o `if (!authHeader)`),
 * com comentarios mascarados:
 *
 *   1. o bloco devolve 401 e o cabecalho cita `${url.origin}` seguido do caminho da PROPRIA superficie;
 *   2. o arquivo nao importa nem usa a constante do host canonico (CANONICAL_ORIGIN / CANONICAL_HOST);
 *   3. o manipulador recebe `url` do contexto;
 *   4. o middleware nunca lista nucleoia.vitormr.dev em LEGACY_HOSTS (um 301 perde o corpo dos POSTs
 *      dos clientes MCP e quebra os certificados ja emitidos).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => maskJsComments(readFileSync(join(ROOT, p), 'utf8'));

const SURFACES = [
  ['src/pages/mcp.ts', 'mcp'],
  ['src/pages/mcp/semantic.ts', 'mcp/semantic'],
  ['src/pages/mcp/actions.ts', 'mcp/actions'],
];

/** O bloco `if (!authHeader) { ... }`, do `if` ate o `}` que fecha na mesma indentacao. */
function challengeBlock(src) {
  const at = src.search(/if \(!authHeader\) \{/);
  assert.ok(at !== -1, 'o bloco if (!authHeader) existe');
  const close = src.indexOf('\n  }\n', at);
  assert.ok(close > at, 'o bloco if (!authHeader) fecha');
  return src.slice(at, close + 4);
}

for (const [file, surface] of SURFACES) {
  test(`${file}: o 401 cita a origem da requisicao e o caminho de ${surface}`, () => {
    const src = read(file);
    const block = challengeBlock(src);
    assert.match(block, /status:\s*401/, 'o bloco devolve 401');
    const want = new RegExp(
      "'WWW-Authenticate':\\s*`Bearer resource_metadata=\"\\$\\{url\\.origin\\}/\\.well-known/oauth-protected-resource/" +
        surface.replace('/', '\\/') +
        '"`',
    );
    assert.match(block, want, 'o cabecalho usa url.origin e o caminho da propria superficie');
  });

  test(`${file}: nao usa a constante do host canonico e recebe url do contexto`, () => {
    const src = read(file);
    assert.doesNotMatch(src, /CANONICAL_(ORIGIN|HOST)/);
    assert.match(src, /export const ALL: APIRoute = async \(\{[^}]*\burl\b[^}]*\}\) =>/);
  });
}

test('middleware: nucleoia.vitormr.dev nunca entra em LEGACY_HOSTS', () => {
  const src = read('src/middleware.ts');
  const m = src.match(/const LEGACY_HOSTS = \[([\s\S]*?)\];/);
  assert.ok(m, 'LEGACY_HOSTS existe');
  assert.match(m[1], /"platform\.ai-pm-research-hub\.workers\.dev"/, 'a lista ainda tem os hosts legados esperados');
  assert.doesNotMatch(m[1], /nucleoia\.vitormr\.dev/);
});
