/**
 * #2974: o formulário de edição de membro não oferece a designação `comms_team`.
 *
 * Nenhum membro tem `comms_team`; os membros da comunicação usam `comms_leader` e `comms_member`. O formulário
 * oferecia as três, então bastava um clique para atribuir uma designação que nenhum fluxo do produto usa.
 *
 * O guard lê a lista que cada formulário de fato oferece (o array `ALL_DESIGS` das duas ilhas) e afirma sobre ELA:
 *   - `comms_team` não está na lista;
 *   - `comms_leader` e `comms_member` estão. É o controle: prova que o guard achou a lista certa, e não uma lista
 *     vazia ou outro array.
 * Os mapas de rótulo e cor continuam com `comms_team` de propósito: servem para exibir um valor já gravado.
 * Comentários são mascarados antes da leitura, e a declaração tem de ser única: uma lista comentada ou uma segunda
 * declaração não podem responder no lugar da que o formulário usa.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');

/** Os literais do array `const ALL_DESIGS = [...]`, ou null se não houver exatamente uma declaração. */
function allDesigs(src) {
  const decls = [...maskJsComments(src).matchAll(/const ALL_DESIGS\s*=\s*\[([^\]]*)\]/g)];
  if (decls.length !== 1) return null;
  return [...decls[0][1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
}

const FORMS = [
  { file: 'src/components/admin/members/MemberDetailIsland.tsx', list: allDesigs },
  { file: 'src/components/admin/members/MemberListIsland.tsx', list: allDesigs },
];

for (const { file, list } of FORMS) {
  test(`${file}: o formulário oferece comms_leader e comms_member, e não comms_team`, () => {
    const offered = list(read(file));
    assert.ok(offered, `${file}: a lista de designações do formulário não foi encontrada`);
    assert.ok(
      offered.includes('comms_leader') && offered.includes('comms_member'),
      `${file}: controle falhou, a lista lida não é a do formulário (${JSON.stringify(offered)})`,
    );
    assert.ok(
      !offered.includes('comms_team'),
      `${file}: o formulário voltou a oferecer comms_team (${JSON.stringify(offered)})`,
    );
  });
}
