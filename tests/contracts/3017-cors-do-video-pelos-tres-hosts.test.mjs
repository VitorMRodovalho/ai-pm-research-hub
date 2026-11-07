/**
 * Contract: #3017 — o envio de vídeo do portal funciona pelos três hosts que servem o portal.
 *
 *   As duas Edge Functions do vídeo respondiam CORS com um host fixo, e a página aberta pelo domínio institucional
 *   ou pelo .org era recusada pelo navegador. A init também criava a sessão do Drive presa a esse host.
 *   - comms-host.ts: PORTAL_ORIGINS e origemDoPortal(req), que devolve o Origin só se ele estiver na lista;
 *   - cada função: Origin fora da lista recebe 403 antes de qualquer leitura; dentro, o allow-origin é ele mesmo,
 *     com Vary: Origin; sem Origin, sem allow-origin;
 *   - a init passa ao Google a mesma origem.
 * Camada B (comportamento): o handler roda de verdade, empacotado pelo esbuild com um Deno falso e o cliente do
 * Supabase trocado por um que estoura se for usado. Camada S (estática) só para a linha do Drive, que exige token e
 * sessão do Google.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { build } from 'esbuild';

const ROOT = process.cwd();
const HOSTS = ['https://nucleoia.vitormr.dev', 'https://nucleoia.pmigo.org.br', 'https://nucleoia.org'];
const FORA = ['https://evil.example', 'https://nucleoia.org/', 'http://nucleoia.org', 'null'];

async function handlerDe(ef) {
  const out = await build({
    entryPoints: [resolve(ROOT, `supabase/functions/${ef}/index.ts`)],
    bundle: true, write: false, format: 'esm', platform: 'neutral', logLevel: 'silent',
    plugins: [{
      name: 'stub-supabase',
      setup(b) {
        b.onResolve({ filter: /^jsr:@supabase\/supabase-js/ }, () => ({ path: 'stub', namespace: 'stub' }));
        b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({
          contents: "export function createClient() { throw new Error('o teste não deveria chegar ao banco'); }",
          loader: 'js',
        }));
      },
    }],
  });
  let handler = null;
  globalThis.Deno = { env: { get: () => 'x' }, serve: (h) => { handler = h; } };
  await import(`data:text/javascript;base64,${Buffer.from(out.outputFiles[0].text).toString('base64')}#${ef}-${Date.now()}`);
  assert.equal(typeof handler, 'function', `${ef}: Deno.serve não recebeu o handler`);
  return handler;
}
const pedido = (metodo, origem, corpo) => new Request('https://ef.local/', {
  method: metodo,
  headers: { ...(origem ? { Origin: origem } : {}), 'Content-Type': 'application/json' },
  ...(corpo !== undefined ? { body: corpo } : {}),
});

test('#3017: origemDoPortal devolve o Origin só quando ele é um dos 3 hosts', async () => {
  const { origemDoPortal, PORTAL_ORIGINS } = await import(resolve(ROOT, 'supabase/functions/_shared/comms-host.ts'));
  assert.deepEqual([...PORTAL_ORIGINS].sort(), [...HOSTS].sort(), 'a lista de hosts do portal mudou');
  for (const h of HOSTS) assert.equal(origemDoPortal(pedido('GET', h)), h, `${h} deveria passar`);
  for (const h of FORA) assert.equal(origemDoPortal(pedido('GET', h)), null, `${h} não deveria passar`);
  assert.equal(origemDoPortal(pedido('GET', null)), null, 'sem Origin, a função inventou uma origem');
});

for (const ef of ['pmi-video-init-upload', 'pmi-video-finalize-upload']) {
  test(`#3017 B: ${ef} responde CORS pela origem, recusa a de fora e não inventa origem`, async () => {
    const h = await handlerDe(ef);
    for (const origem of HOSTS) {
      const r = await h(pedido('OPTIONS', origem));
      assert.equal(r.status, 200, `${ef}: OPTIONS de ${origem} deu ${r.status}`);
      assert.equal(r.headers.get('Access-Control-Allow-Origin'), origem, `${ef}: allow-origin errado para ${origem}`);
      assert.equal(r.headers.get('Vary'), 'Origin', `${ef}: sem Vary: Origin`);
      // Um POST que para cedo (JSON inválido) também leva o allow-origin da origem.
      const p = await h(pedido('POST', origem, '{'));
      assert.equal(p.status, 400, `${ef}: POST inválido de ${origem} deu ${p.status}`);
      assert.equal(p.headers.get('Access-Control-Allow-Origin'), origem, `${ef}: o erro saiu sem o allow-origin de ${origem}`);
    }
    for (const origem of FORA) {
      for (const metodo of ['OPTIONS', 'POST']) {
        const r = await h(pedido(metodo, origem, metodo === 'POST' ? '{}' : undefined));
        assert.equal(r.status, 403, `${ef}: ${metodo} de ${origem} deu ${r.status}, e não 403`);
        assert.equal(r.headers.get('Access-Control-Allow-Origin'), null, `${ef}: devolveu allow-origin a ${origem}`);
      }
    }
    const semOrigem = await h(pedido('OPTIONS', null));
    assert.equal(semOrigem.headers.get('Access-Control-Allow-Origin'), null, `${ef}: sem Origin, devolveu allow-origin`);
  });
}

test('#3017 S: a init cria a sessão do Drive com a mesma origem da requisição', () => {
  const src = readFileSync(resolve(ROOT, 'supabase/functions/pmi-video-init-upload/index.ts'), 'utf8').replace(/\s+/g, ' ');
  assert.match(src, /"X-Upload-Content-Length": String\(size_bytes\), (?:\/\/[^"]*)?"Origin": origem \?\? PLATFORM_ORIGIN, \}/,
    'a sessão do Drive voltou a nascer presa a um host fixo');
  assert.match(src, /Deno\.serve\(async \(req\) => \{ (?:\/\/[^;]*)?const origem = origemDoPortal\(req\);/,
    'a origem deixou de ser lida no começo do handler');
  for (const ef of ['pmi-video-init-upload', 'pmi-video-finalize-upload']) {
    const s = readFileSync(resolve(ROOT, `supabase/functions/${ef}/index.ts`), 'utf8');
    assert.doesNotMatch(s, /Access-Control-Allow-Origin": ["'](?:\*|https?:)/, `${ef}: allow-origin fixo ou '*' voltou`);
  }
});
