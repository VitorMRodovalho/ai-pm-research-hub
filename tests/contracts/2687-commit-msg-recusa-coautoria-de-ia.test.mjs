/**
 * #2687: .githooks/commit-msg recusa Co-Authored-By que nomeia assistente de IA.
 *
 * Exercita o hook como o git o chama (um argumento: o arquivo da mensagem) e
 * afirma o EXIT CODE, nao a presenca de string no script. Cada caso negativo
 * tem um positivo irmao, para provar que o instrumento sabe dizer sim e nao.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

const HOOK = resolve(process.cwd(), '.githooks/commit-msg');

function runHook(message) {
  const dir = mkdtempSync(join(tmpdir(), 'commit-msg-2687-'));
  const file = join(dir, 'COMMIT_EDITMSG');
  writeFileSync(file, message);
  const r = spawnSync('bash', [HOOK, file], { encoding: 'utf8' });
  rmSync(dir, { recursive: true, force: true });
  return r.status;
}

const SUBJECT = 'fix: algo no codigo (#1)\n\nCorpo.\n\n';

test('recusa Co-Authored-By de assistente de IA', () => {
  assert.equal(runHook(SUBJECT + 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n'), 1);
  assert.equal(runHook(SUBJECT + 'co-authored-by: GitHub Copilot <copilot@github.com>\n'), 1);
  assert.equal(runHook(SUBJECT + '  Co-authored-by: ChatGPT <x@openai.com>\n'), 1);
});

test('aceita Assisted-By, que e a atribuicao correta', () => {
  assert.equal(runHook(SUBJECT + 'Assisted-By: Claude (Anthropic) <noreply@anthropic.com>\n'), 0);
});

test('aceita Co-Authored-By de pessoa', () => {
  assert.equal(runHook(SUBJECT + 'Co-Authored-By: Maria Silva <maria@example.org>\n'), 0);
});

test('linha de comentario (#) nao conta, porque o git a remove', () => {
  assert.equal(runHook(SUBJECT + '# Co-Authored-By: Claude <noreply@anthropic.com>\n'), 0);
});
