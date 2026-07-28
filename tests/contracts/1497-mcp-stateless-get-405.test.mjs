/**
 * Contract: #1497 — GET numa superfície MCP stateless responde 405, nunca um SSE pendurado.
 *
 * As três superfícies (`/mcp`, `/semantic`, `/actions`) constroem o transporte com
 * `sessionIdGenerator: undefined`, que é o modo stateless: não há sessão para sustentar um
 * canal servidor→cliente. Registradas com `app.all`, o GET caía no `handleRequest` e abria
 * um stream que nunca emitia e nunca fechava.
 *
 * Medido em 2026-07-28, com bearer inválido e `Accept: text/event-stream`, nas três rotas e
 * também direto na Edge Function (sem o Worker): pendura até o timeout do cliente, sem
 * devolver cabeçalho de resposta. Sem o header SSE a mesma rota responde 406 em ~1s, o que
 * localizava a parada dentro do transporte. `POST initialize` responde em <1s.
 *
 * Efeito colateral relevante: o stream abria ANTES de validar o bearer, então nem token
 * inválido recebia 401. Um cliente externo lê isso como servidor travado.
 *
 * NOTA de método: o fonte é lido SEM COMENTÁRIOS. O comentário deste fix cita `app.all`,
 * `sessionIdGenerator`, 405 e o nome do guard, e um regex ingênuo casaria com a prosa.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const EF = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const SURFACES = ['/mcp', '/semantic', '/actions'];
const GUARD = 'statelessGetNotAllowed';

function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function code() {
  assert.ok(existsSync(EF), `deve existir: ${EF}`);
  return stripComments(readFileSync(EF, 'utf8'));
}

/** Recorta o corpo do handler de uma superfície até o próximo `app.all(`. */
function handlerBlock(src, surface) {
  const start = src.indexOf(`app.all("${surface}"`);
  assert.ok(start >= 0, `handler de ${surface} deve existir`);
  const next = src.indexOf('app.all(', start + 1);
  return src.slice(start, next === -1 ? src.length : next);
}

test('1497: o guard existe e responde 405 com Allow', () => {
  const src = code();
  const fn = src.match(new RegExp(`function\\s+${GUARD}\\s*\\([\\s\\S]*?\\n\\}`))?.[0] || '';
  assert.ok(fn, `${GUARD} deve estar definido`);
  assert.match(fn, /req\.method\s*!==\s*"GET"[\s\S]*?return null/,
    'só GET pode ser bloqueado; qualquer outro método segue o fluxo');
  assert.match(fn, /status:\s*405/, 'a resposta deve ser 405');
  assert.match(fn, /"allow":\s*"POST, OPTIONS"/, 'deve anunciar os métodos aceitos');
});

test('1497: as tres superficies aplicam o guard', () => {
  const src = code();
  for (const s of SURFACES) {
    assert.match(handlerBlock(src, s), new RegExp(`${GUARD}\\(c\\.req\\.raw\\)`),
      `${s} deve chamar o guard`);
  }
});

test('1497: o guard roda ANTES de o transporte assumir a requisicao', () => {
  const src = code();
  for (const s of SURFACES) {
    const block = handlerBlock(src, s);
    const guardAt = block.indexOf(GUARD);
    const handleAt = block.indexOf('transport.handleRequest');
    assert.ok(guardAt >= 0 && handleAt >= 0, `${s} deve ter guard e handleRequest`);
    assert.ok(guardAt < handleAt,
      `${s}: o guard tem de preceder handleRequest, senao o stream ja abriu`);
  }
});

test('1497: as superficies seguem stateless (a premissa do 405)', () => {
  const src = code();
  for (const s of SURFACES) {
    assert.match(handlerBlock(src, s), /sessionIdGenerator:\s*undefined/,
      `${s}: se deixar de ser stateless, o 405 precisa ser reavaliado (#1497)`);
  }
});

test('1497: POST segue intacto nas tres superficies', () => {
  const src = code();
  for (const s of SURFACES) {
    const block = handlerBlock(src, s);
    assert.match(block, /transport\.handleRequest\(c\.req\.raw\)/,
      `${s}: o caminho POST deve continuar entregando ao transporte`);
    assert.doesNotMatch(block, /req\.method\s*!==\s*"POST"/,
      `${s}: o guard nao pode virar allow-list de metodo e derrubar OPTIONS/DELETE`);
  }
});
