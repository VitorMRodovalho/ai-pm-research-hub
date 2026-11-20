/**
 * Contract: /admin/comms-ops abre o board do Hub de Comunicação PELO ID.
 *
 * A página usava `<BoardEngine domainKey="communication" />`. Sem id, `useBoard` chama
 * `get_board_by_domain('communication')`, que devolve o board ativo com essa chave por
 * `ORDER BY created_at DESC LIMIT 1`. Medido em 20/11/2026: havia 5 boards ativos com a chave, e a
 * página abria o mais novo, não o do Hub, que é o mais antigo dos 5. O link "board-comms" do menu
 * do workspace já ia ao Hub por id, então as duas portas abriam boards diferentes.
 *
 * Passar a iniciativa não resolve: `get_board_by_domain` converte `p_initiative_id` em tribo por
 * `resolve_tribe_id`, que devolve NULL fora de tribo, e com NULL a busca não filtra nada.
 *
 * As asserções amarram a condição ao resultado, dentro da tag que decide. O `<BoardEngine>` da
 * página recebe `boardId`, não recebe `domainKey`, e o id que recebe é o mesmo do link
 * "board-comms" do workspace. Comentários são removidos antes, porque o motivo da correção cita
 * justamente a forma antiga.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = resolve(ROOT, 'src/pages/admin/comms-ops.astro');
const WORKSPACE = resolve(ROOT, 'src/pages/workspace.astro');
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

/** Remove comentário HTML, de bloco e de linha inteira, sem tocar em `//` dentro de string. */
function stripComments(src) {
  return src
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/[^\n]*$/gm, '');
}

/** O id que o `<BoardEngine>` da página recebe, ou um motivo de reprovação. */
export function boardIdOfCommsOps(pageSrc) {
  const src = stripComments(pageSrc);
  const tags = src.match(/<BoardEngine\b[^>]*>/g) ?? [];
  if (tags.length !== 1) return { error: `esperado 1 <BoardEngine>, achei ${tags.length}` };
  const tag = tags[0];
  if (/\bdomainKey\s*=/.test(tag)) return { error: `a tag ainda passa domainKey: ${tag}` };

  const literal = tag.match(new RegExp(`\\bboardId\\s*=\\s*["'](${UUID})["']`));
  if (literal) return { id: literal[1] };

  const bound = tag.match(/\bboardId\s*=\s*\{\s*([A-Za-z_$][\w$]*)\s*\}/);
  if (!bound) return { error: `a tag não passa boardId: ${tag}` };
  const decl = src.match(new RegExp(`\\bconst\\s+${bound[1]}\\s*=\\s*["'](${UUID})["']`));
  if (!decl) return { error: `boardId={${bound[1]}} sem const com um uuid literal` };
  return { id: decl[1] };
}

/** O id do link "board-comms" do menu do workspace. */
export function boardIdOfWorkspaceMenu(workspaceSrc) {
  const m = stripComments(workspaceSrc).match(
    new RegExp(`key:\\s*'board-comms'[^}]*?href:\\s*'/admin/board/(${UUID})'`),
  );
  return m ? m[1] : null;
}

test('comms-ops: o BoardEngine abre por boardId, sem domainKey', () => {
  const r = boardIdOfCommsOps(readFileSync(PAGE, 'utf8'));
  assert.equal(r.error, undefined, r.error);
  assert.match(r.id, new RegExp(`^${UUID}$`));
});

test('comms-ops: o id é o mesmo do link "board-comms" do workspace', () => {
  const page = boardIdOfCommsOps(readFileSync(PAGE, 'utf8'));
  const menu = boardIdOfWorkspaceMenu(readFileSync(WORKSPACE, 'utf8'));
  assert.ok(menu, 'link "board-comms" não encontrado em workspace.astro');
  assert.equal(page.id, menu, `comms-ops abre ${page.id}, o menu abre ${menu}`);
});

test('controle: o detector reprova as formas que o bug tinha', () => {
  const id = 'a6b78238-11aa-476a-b7e2-a674d224fd79';
  const antiga = `---\n---\n<BoardEngine client:load domainKey="communication" />`;
  const ambas = `---\nconst X = '${id}';\n---\n<BoardEngine client:load boardId={X} domainKey="communication" />`;
  const semConst = `---\n---\n<BoardEngine client:load boardId={X} />`;
  const comentada = `---\n// <BoardEngine boardId="${id}" />\n---\n<BoardEngine client:load domainKey="communication" />`;
  for (const [nome, src] of Object.entries({ antiga, ambas, semConst, comentada })) {
    assert.ok(boardIdOfCommsOps(src).error, `o detector aceitou a forma "${nome}"`);
  }
  const literal = `---\n---\n<BoardEngine client:load boardId="${id}" />`;
  assert.equal(boardIdOfCommsOps(literal).id, id, 'o detector recusou a forma certa com id literal');
});
