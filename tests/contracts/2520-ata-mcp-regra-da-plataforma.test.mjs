/**
 * #2520 — a ata pelo MCP segue a regra da plataforma.
 *
 * `meeting_minutes action='write'` passava por `eventWriteGate()`, que exige `manage_event` na
 * iniciativa do evento, ANTES de chamar `upsert_event_minutes`. A funcao do banco decide por
 * `_can_manage_event()`, que e mais larga: alem de `manage_event`, aceita a lideranca da tribo do
 * evento, pesquisador da tribo do evento ate 72 h depois da reuniao e quem criou o evento. A tela
 * chama a mesma funcao; o MCP recusava pesquisadores que a tela aceita.
 *
 * O que este guard amarra:
 *   1. cada ramo abre pelo proprio portao: `write` → so visibilidade (`eventSeeGate`); `close` →
 *      `eventWriteGate`, a mesma exigencia de `meeting_close`;
 *   2. o erro do portao e devolvido (nao so calculado);
 *   3. `eventSeeGate` nega quem nao ve a iniciativa (#785), com `unauthorized`;
 *   4. o ramo `write` nao reintroduz `manage_event` por conta propria;
 *   5. as recusas da funcao (`Unauthorized`, `Edit window expired`) viram `unauthorized` com a
 *      regra na acao, antes do `internal_error` generico.
 *
 * `eventWriteGate` chamar `eventSeeGate` primeiro fica em `semantic-envelope-w3.test.mjs`.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

function toolBlock(name) {
  const start = SRC.search(new RegExp(`mcp\\.tool\\(\\s*\\n?\\s*"${name}"`));
  assert.ok(start !== -1, `${name} registrada`);
  const next = SRC.slice(start + 10).search(/mcp\.tool\(\s*\n?\s*"[a-zA-Z0-9_]+"/);
  assert.ok(next !== -1, `fim do bloco de ${name}`);
  return maskJsComments(SRC.slice(start, start + 10 + next));
}

function helper(name) {
  const m = SRC.match(new RegExp(`async function ${name}\\([\\s\\S]*?\\n\\}`));
  assert.ok(m, `${name}() encontrada`);
  return maskJsComments(m[0]);
}

const MM = toolBlock('meeting_minutes');

function writeBranch() {
  const from = MM.indexOf('if (params.action === "write") {');
  const to = MM.indexOf('if (params.action === "close") {');
  assert.ok(from !== -1 && to > from, 'ramos write e close encontrados, nessa ordem');
  return MM.slice(from, to);
}

function closeBranch() {
  const from = MM.indexOf('if (params.action === "close") {');
  assert.ok(from !== -1, 'ramo close encontrado');
  return MM.slice(from);
}

test('#2520: write abre pela visibilidade e devolve a recusa, antes de qualquer escrita', () => {
  const w = writeBranch();
  assert.match(
    w,
    /^if \(params\.action === "write"\) \{\s*const seeErr = await eventSeeGate\(sb,\s*ev\.initiative_id\);\s*if \(seeErr\) \{[^}]*return denied\(seeErr\);\s*\}/,
    'a primeira coisa do ramo write e eventSeeGate, e o erro dele e devolvido',
  );
});

test('#2520: close segue abrindo pelo portao completo (a mesma exigencia de meeting_close)', () => {
  const c = closeBranch();
  assert.match(
    c,
    /^if \(params\.action === "close"\) \{\s*const gateErr = await eventWriteGate\(sb,\s*member\.id,\s*ev\.initiative_id\);\s*if \(gateErr\) \{[^}]*return denied\(gateErr\);\s*\}/,
    'a primeira coisa do ramo close e eventWriteGate, e o erro dele e devolvido',
  );
  const gate = c.search(/await eventWriteGate\(/);
  const rpc = c.search(/sb\.rpc\("meeting_close"/);
  assert.ok(gate !== -1 && rpc > gate, 'o portao vem antes do meeting_close');
});

test('#2520: eventSeeGate nega quem nao ve a iniciativa do evento (#785)', () => {
  const h = helper('eventSeeGate');
  assert.match(
    h,
    /if \(initiativeId && !\(await canSee\(sb,\s*"initiative",\s*initiativeId\)\)\)\s*\{\s*return \{ code: "unauthorized"/,
    'eventSeeGate tem de devolver unauthorized quando canSee(initiative) e falso',
  );
  assert.doesNotMatch(h, /canV4\(/, 'eventSeeGate e so visibilidade: autoridade fica com a funcao do banco');
});

test('#2520: o ramo write nao reintroduz manage_event por conta propria', () => {
  const w = writeBranch();
  assert.doesNotMatch(w, /canV4\(/, 'write nao pode perguntar can(manage_event) antes da funcao');
  assert.doesNotMatch(w, /eventWriteGate\(/, 'write nao pode voltar ao portao completo');
  assert.match(w, /sb\.rpc\("upsert_event_minutes"/, 'write despacha upsert_event_minutes');
});

test('#2520: as recusas da funcao viram unauthorized com a regra, antes do internal_error', () => {
  const w = writeBranch();
  const unauth = w.search(/if \(\/\^Unauthorized\\b\/\.test\(error\.message \?\? ""\)\) \{\s*return denied\(\{ code: "unauthorized", message: "You cannot write the minutes of this event\.", action: "[^"]*within 72h[^"]*" \}\);/);
  const expired = w.search(/if \(\/\^Edit window expired\\b\/\.test\(error\.message \?\? ""\)\) \{\s*return denied\(\{ code: "unauthorized", message: "The 72h window[^"]*", action: "[^"]*tribe leader or the GP[^"]*" \}\);/);
  const generic = w.search(/code: "internal_error"/);
  assert.ok(unauth !== -1, 'Unauthorized da funcao → unauthorized com a regra na acao');
  assert.ok(expired !== -1, 'Edit window expired → unauthorized dizendo a quem mandar o texto');
  assert.ok(generic !== -1, 'o resto segue como internal_error');
  assert.ok(unauth < generic && expired < generic, 'os dois mapeamentos vem ANTES do internal_error generico');
});
