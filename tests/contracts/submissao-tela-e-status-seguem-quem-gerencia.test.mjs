/**
 * A tela de submissão e a troca de status seguem a regra de quem gerencia a submissão (#2565).
 *
 * A regra mora no servidor, em _can_manage_publication_submission (lote 2b): autor principal, quem
 * criou, gestão e liderança de Publicações & Submissões.
 *
 * O QUE ESTE GUARD AFIRMA:
 *   A. update_publication_submission_status aplica a regra, na captura vigente, antes de escrever.
 *   B. A tela de detalhe pergunta a regra ao servidor, e é essa resposta que decide os controles;
 *      não sobra regra local (papel, designação, escrita genérica, autoria).
 *   C. A lista não guarda a regra antiga de edição.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();

test('A: a troca de status checa quem gerencia antes de escrever', () => {
  const b = maskLineComments(latestFunctionCapture(ROOT, 'update_publication_submission_status').block);
  const g = b.search(/IF public\._request_is_rest_caller\(\) AND NOT public\._can_manage_publication_submission\(p_submission_id\) THEN\s+RAISE EXCEPTION/);
  assert.ok(g >= 0, 'a regra existe e recusa');
  assert.ok(b.indexOf('UPDATE public.publication_submissions SET status') > g, 'a regra vem antes da escrita');
});

test('B: a tela de detalhe pergunta ao servidor quem gerencia', () => {
  const src = maskJsComments(readFileSync('src/pages/publications/submissions/[id].astro', 'utf8'));
  const i = src.indexOf('async function canManage(');
  assert.ok(i >= 0, 'canManage existe');
  const fn = src.slice(i, src.indexOf('\n  }\n', i));
  assert.match(
    fn,
    /const \{ data, error \} = await sb\.rpc\('_can_manage_publication_submission', \{ p_submission_id: subId \}\);\s+return !error && data === true;/,
    'a resposta do servidor é a decisão',
  );
  assert.doesNotMatch(fn, /__nucleoCanFor|operational_role|designations|primary_author_id|is_superadmin/, 'nenhuma regra local');
  assert.match(src, /const manage = await canManage\(subId\);/, 'a decisão vem do servidor');
  assert.match(src, /\$\{manage \? `<button id="pub-add-coauthor"/, 'e é ela que mostra os controles');
});

test('C: a lista não guarda a regra antiga de edição', () => {
  const src = maskJsComments(readFileSync('src/pages/publications/submissions.astro', 'utf8'));
  assert.doesNotMatch(src, /function canEdit\(/);
});
