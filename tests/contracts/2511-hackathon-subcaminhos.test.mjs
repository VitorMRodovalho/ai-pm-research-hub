/**
 * Contract #2511 — a entrada /hackathon repassa o subcaminho e a query, e fica em 302.
 *
 * Medido em 28/09/2026: /hackathon e /hackathon/ iam ao site do hackathon, e /hackathon/edital dava
 * 404, porque a rota era uma página só. O endereço curto vai para material impresso, então o
 * subcaminho tem de chegar. O 302 é decisão do GP no mesmo dia: o apelido aponta para a próxima
 * edição, e um 301 fica guardado no navegador de cada visitante.
 *
 * O efeito (servidor de verdade, Location e status) é conferido pelo scripts/smoke-routes.mjs no CI;
 * aqui fica a regra de montagem, que é o que impede um subcaminho de trocar o host.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { hackathonTarget, HACKATHON_REDIRECT_STATUS, HACKATHON_URL } from '../../src/lib/hackathon.js';

const ROOT = process.cwd();
const HOST = new URL(HACKATHON_URL).host;

test('#2511: o subcaminho e a query chegam ao site do hackathon', () => {
  assert.equal(hackathonTarget(undefined, ''), HACKATHON_URL);
  assert.equal(hackathonTarget('', ''), HACKATHON_URL);
  assert.equal(hackathonTarget('edital', ''), `${HACKATHON_URL}edital`);
  assert.equal(hackathonTarget('edital', '?utm_source=impresso'), `${HACKATHON_URL}edital?utm_source=impresso`);
  assert.equal(hackathonTarget('a/b/', ''), `${HACKATHON_URL}a/b`);
  assert.equal(hackathonTarget('a b', ''), `${HACKATHON_URL}a%20b`);
});

test('#2511: nenhum subcaminho troca o host de destino', () => {
  for (const rest of ['//evil.example/x', '/\\evil.example', '..', '../../x', 'a\\b', '%2F%2Fevil.example', 'https://evil.example', '@evil.example']) {
    const out = new URL(hackathonTarget(rest, ''));
    assert.equal(out.host, HOST, `"${rest}" levou a ${out.host}`);
    assert.equal(out.protocol, 'https:');
  }
});

test('#2511: o status é 302, por decisão do GP (nunca 301)', () => {
  assert.equal(HACKATHON_REDIRECT_STATUS, 302);
});

test('#2511: as três entradas usam a mesma montagem, sem página fixa sobrando', () => {
  for (const dir of ['src/pages', 'src/pages/en', 'src/pages/es']) {
    const page = resolve(ROOT, dir, 'hackathon/[...rest].astro');
    assert.ok(existsSync(page), page);
    assert.match(readFileSync(page, 'utf8'),
      /return Astro\.redirect\(hackathonTarget\(Astro\.params\.rest, Astro\.url\.search\), HACKATHON_REDIRECT_STATUS\);/);
    assert.ok(!existsSync(resolve(ROOT, dir, 'hackathon.astro')), `${dir}/hackathon.astro sobrou`);
  }
});

test('#2511: o smoke de rotas confere subcaminho, query, status e host no servidor de verdade', () => {
  const smoke = readFileSync(resolve(ROOT, 'scripts/smoke-routes.mjs'), 'utf8');
  assert.match(smoke, /if \(expectedStatus && res\.status !== expectedStatus\) \{\s+throw new Error/);
  assert.match(smoke, /assertRedirect\('\/hackathon\/edital\?utm_source=impresso', `\$\{HACKATHON_URL\}edital\?utm_source=impresso`, 302\);/);
  assert.match(smoke, /assertRedirect\('\/en\/hackathon\/edital', `\$\{HACKATHON_URL\}edital`, 302\);/);
  assert.match(smoke, /assertRedirect\('\/es\/hackathon\/a\/b', `\$\{HACKATHON_URL\}a\/b`, 302\);/);
  assert.match(smoke, /assertRedirect\('\/hackathon\/\/evil\.example\/x', `\$\{HACKATHON_URL\}evil\.example\/x`, 302\);/);
});
