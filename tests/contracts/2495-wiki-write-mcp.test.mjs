/**
 * #2495 / ADR-0132: o assistente escreve no wiki pelas mesmas funções da tela.
 *
 * O que este guard amarra, sempre condição junto do resultado:
 *   1. toda escrita (draft, submit, suggest) devolve a PRÉVIA quando confirm não é true, ANTES da RPC
 *      que grava, e a prévia é registrada como prévia no log;
 *   2. pelo assistente o rótulo padrão é 'sintese_ia', e é esse rótulo que chega a wiki_save_draft;
 *   3. aprovar, devolver, auditar e responder sugestão não existem aqui (ADR-0132 §2);
 *   4. nenhuma autoridade nova: a ferramenta não pergunta can() por conta própria, quem decide é a RPC;
 *      recusa da RPC por autoridade (42501) volta como unauthorized;
 *   5. a descrição da ferramenta é texto fixo (ADR-0018 D2.3);
 *   6. a leitura marca a página de síntese de IA para o assistente (executado, não procurado no texto).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { withWikiAuditNotice, WIKI_AI_SYNTHESIS_NOTICE, WIKI_AUDIT_PENDING_NOTICE } from '../../supabase/functions/nucleo-mcp/wiki-audit.mjs';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

function toolBlock(name) {
  const start = SRC.search(new RegExp(`mcp\\.tool\\(\\s*\\n?\\s*"${name}"`));
  assert.ok(start !== -1, `${name} registrada`);
  const rest = SRC.slice(start + 10);
  const next = rest.search(/\n  mcp\.tool\(|\n\}\n/);
  assert.ok(next !== -1, `fim do bloco de ${name}`);
  return maskJsComments(SRC.slice(start, start + 10 + next));
}

const W = toolBlock('wiki_write');

function branch(action) {
  const from = W.indexOf(`if (params.action === "${action}") {`);
  assert.ok(from !== -1, `ramo ${action}`);
  const after = W.slice(from + 10).search(/\n      if \(params\.action === "|\n      return invalid\(`Unknown action/);
  return W.slice(from, from + 10 + after);
}

test('ADR-0132: wiki_write fica na superfície semântica, anotada como escrita não destrutiva', () => {
  const start = SRC.indexOf('function registerSemanticTools(');
  const end = SRC.indexOf('// #1377 — /actions overflow surface.', start);
  assert.ok(SRC.slice(start, end).includes('"wiki_write",'), 'registrada dentro de registerSemanticTools');
  assert.match(SRC, /\n  wiki_write: SEM_WRITE,\n/);
});

for (const [action, rpc] of [['draft', 'wiki_save_draft'], ['submit', 'wiki_submit'], ['suggest', 'wiki_suggest']]) {
  test(`ADR-0132: ${action} devolve a prévia antes de ${rpc}, e só grava com confirm=true`, () => {
    const b = branch(action);
    const gate = b.search(/if \(params\.confirm !== true\) \{/);
    const call = b.search(new RegExp(`sb\\.rpc\\("${rpc}"`));
    assert.ok(gate !== -1 && call !== -1 && gate < call, 'o portão da prévia vem antes da gravação');
    const preview = b.slice(gate, call);
    assert.match(preview, /await logUsage\(sb, member\.id, "wiki_write", true, undefined, start, "preview"\);\s*return semanticOk\(\{\s*data: \{\s*action: "[a-z]+", preview: true,/,
      'dentro do portão: registra como prévia e RETORNA a prévia');
    assert.equal((b.match(new RegExp(`sb\\.rpc\\("${rpc}"`, 'g')) || []).length, 1, 'uma única chamada de gravação, depois do portão');
  });
}

test('ADR-0132: pelo assistente o rótulo padrão é sintese_ia, e é ele que vai para a função', () => {
  const b = branch('draft');
  assert.match(b, /const label = params\.epistemic_label \?\? "sintese_ia";/);
  assert.match(b, /sb\.rpc\("wiki_save_draft", \{[^}]*p_epistemic_label: label,\s*\}\)/);
});

test('ADR-0132: decidir, auditar e responder sugestão não existem na ferramenta', () => {
  for (const rpc of ['wiki_decide', 'wiki_audit', 'wiki_suggestion_decide']) {
    assert.doesNotMatch(W, new RegExp(`sb\\.rpc\\("${rpc}"`), `${rpc} fica na tela`);
  }
  assert.match(W, /action: z\.enum\(\["context", "draft", "submit", "suggest"\]\)/, 'só as quatro ações');
});

test('ADR-0132: nenhuma autoridade nova; recusa da função por autoridade volta como unauthorized', () => {
  assert.doesNotMatch(W, /canV4\(|canSee\(/, 'quem decide é a RPC, como na tela');
  assert.match(W, /const code = e\?\.code === "42501" \? "unauthorized" : msg\.startsWith\("wiki:"\) \? "invalid_input" : "internal_error";/);
});

test('ADR-0018 D2.3: a descrição da ferramenta é texto fixo', () => {
  assert.match(W, /mcp\.tool\(\s*"wiki_write",\s*"(?:[^"\\\n]|\\.)+",\s*\{/, 'string literal comum entre aspas duplas: sem template, logo sem interpolação');
});

test('ADR-0132: a leitura marca a página de síntese de IA, e só ela', () => {
  const ai = { path: 'nucleo/x', epistemic_label: 'sintese_ia', audit_status: 'audited' };
  assert.equal(withWikiAuditNotice(ai).epistemic_notice, WIKI_AI_SYNTHESIS_NOTICE);
  assert.equal(ai.epistemic_notice, undefined, 'não altera a linha recebida');
  const both = withWikiAuditNotice({ epistemic_label: 'sintese_ia', audit_status: 'pending' });
  assert.equal(both.audit_notice, WIKI_AUDIT_PENDING_NOTICE, 'o aviso de auditoria continua');
  assert.equal(both.epistemic_notice, WIKI_AI_SYNTHESIS_NOTICE);
  const list = withWikiAuditNotice([ai, { epistemic_label: 'fonte' }, { epistemic_label: null }, null]);
  assert.deepEqual(list.map((r) => r?.epistemic_notice ?? null), [WIKI_AI_SYNTHESIS_NOTICE, null, null, null]);
  assert.match(WIKI_AI_SYNTHESIS_NOTICE, /síntese produzida por IA/);
});
