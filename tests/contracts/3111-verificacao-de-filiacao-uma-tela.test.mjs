/**
 * #3111: a verificação de filiação mora numa tela só, /admin/filiacao.
 *
 * Antes, /admin/members (MemberListIsland) tinha um modal de verificação, um lote via VEP e um modal de ateste
 * próprios, chamando as mesmas RPCs da fila. Este guard trava:
 *   A. a lista de membros não chama nenhuma RPC de verificação nem de ateste;
 *   B. o selo de filiação da lista é um link para /admin/filiacao;
 *   C. a fila continua sendo a casa dessas RPCs (controle: o guard não fica verde se a verificação sumir de todo lugar).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));
const LIST = read('src/components/admin/members/MemberListIsland.tsx');
const QUEUE = read('src/components/admin/AffiliationQueueIsland.tsx');

const RPCS = ['verify_member_affiliation', 'verify_member_affiliations_bulk', 'attest_affiliation_access', 'get_my_affiliation_attestation'];

test('A. a lista de membros não verifica filiação nem pede ateste', () => {
  for (const rpc of RPCS) {
    assert.doesNotMatch(LIST, new RegExp(`\\.rpc\\(\\s*['"\`]${rpc}['"\`]`), `MemberListIsland chama ${rpc}`);
  }
});

test('B. o selo de filiação da lista leva para /admin/filiacao', () => {
  assert.match(LIST, /const filiacaoHref = `\$\{locale === 'en-US' \? '\/en' : locale === 'es-LATAM' \? '\/es' : ''\}\/admin\/filiacao`;/);
  assert.match(
    LIST,
    /\{\(\(\) => \{ const f = affiliationFarol\(m, t\); return \(\s+<a href=\{filiacaoHref\} data-testid="ml-affiliation-link"/,
  );
});

test('C. a fila continua sendo a casa da verificação', () => {
  for (const rpc of RPCS) {
    assert.match(QUEUE, new RegExp(`\\.rpc\\(\\s*['"\`]${rpc}['"\`]`), `AffiliationQueueIsland não chama mais ${rpc}`);
  }
});
