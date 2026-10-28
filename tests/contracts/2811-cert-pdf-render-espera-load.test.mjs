/**
 * #2811: o render de PDF de certificado espera `load`, nao `networkidle0`, e cabe nos 30 s do pg_net.
 *
 * Desde 27/10/2026 todo render estourou `Navigation timeout of 30000 ms exceeded` no
 * `page.setContent(..., { waitUntil: 'networkidle0', timeout: 30000 })`, com um documento cujas imagens sao
 * todas data URIs. O gatilho e a varredura chamam o endpoint com `timeout_milliseconds := 30000`, entao o
 * cliente desistia antes de a rota responder.
 *
 * O QUE ESTE GUARD AFIRMA, no renderizador do servidor, com comentarios mascarados:
 *   R1. o setContent espera `load`;
 *   R2. nenhum `networkidle0` volta ao renderizador;
 *   R3. as duas esperas (setContent e IMAGES_LOADED_PREDICATE) somam menos que os 30 s do pg_net;
 *   R4. a resposta de render_failed leva as requisicoes pendentes, e elas saem sem query string.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const src = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/api/internal/cert-pdf-render/[id].ts'), 'utf8'));
const PG_NET_TIMEOUT_MS = 30000;

const SET_CONTENT = /await page\.setContent\(fullDoc, \{ waitUntil: '([a-z0-9]+)', timeout: (\d+) \}\);/;
const IMAGES_WAIT = /await page\.waitForFunction\(IMAGES_LOADED_PREDICATE, \{ timeout: (\d+) \}\);/;

test('R1. o setContent do renderizador espera load', () => {
  const m = src.match(SET_CONTENT);
  assert.ok(m, 'setContent(fullDoc, { waitUntil, timeout }) existe');
  assert.equal(m[1], 'load', 'o setContent espera load');
});

test('R2. networkidle0 nao volta ao renderizador', () => {
  assert.doesNotMatch(src, /networkidle0/);
});

test('R3. as duas esperas cabem no timeout do pg_net', () => {
  const sc = src.match(SET_CONTENT);
  const iw = src.match(IMAGES_WAIT);
  assert.ok(sc && iw, 'as duas esperas existem');
  const total = Number(sc[2]) + Number(iw[1]);
  assert.ok(total < PG_NET_TIMEOUT_MS, `setContent ${sc[2]} + imagens ${iw[1]} = ${total} ms, abaixo de ${PG_NET_TIMEOUT_MS}`);
});

test('R4. render_failed leva as pendentes, sem query string', () => {
  assert.match(src, /page\.on\('request', \(r: any\) => \{\s+const url = String\(r\.url\(\)\);\s+if \(!url\.startsWith\('data:'\)\) pending\.set\(r, url\.split\('\?'\)\[0\]\.slice\(0, 200\)\);/,
    'a requisicao pendente entra sem query string');
  assert.match(src, /page\.on\('requestfinished', \(r: any\) => \{ pending\.delete\(r\); \}\);/);
  assert.match(src, /page\.on\('requestfailed', \(r: any\) => \{ pending\.delete\(r\); \}\);/);
  assert.match(src, /JSON\.stringify\(\{ error: 'render_failed', detail: e\?\.message \?\? String\(e\), pending: pendingUrls, cert_id: row\.id \}\)/,
    'a resposta de render_failed leva as pendentes');
});
