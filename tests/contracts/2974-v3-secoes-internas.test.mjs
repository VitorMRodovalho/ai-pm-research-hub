/**
 * #2974: as seções internas de /admin/webinars decidem pela pergunta do servidor, não por papel ou designação V3.
 *
 * Os botões de criar e de editar webinar (e, pelo modal, o de ligar o evento) apareciam só para superadmin, papel
 * `manager` ou `deputy_manager` e designação `co_gp`. O servidor pergunta outra coisa: `upsert_webinar` cria com
 * `manage_member` sem recurso, e edita com `manage_member`, organizador ou co-gestor. O portão da página
 * (`ADMIN_ROUTE_ACCESS['/admin/webinars']`) já pergunta `manage_member`.
 *
 * O guard lê a ação do ramo de criação no corpo VIGENTE de `upsert_webinar` (`latestFunctionCapture`) e exige que o
 * `canEdit` da página pergunte exatamente essa, pelo `canForUnscoped`, que é o espelho no front do `can()` sem recurso.
 * Se a pergunta do servidor mudar, o guard reprova até a tela mudar junto.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { ADMIN_ROUTE_ACCESS } from '../../src/lib/navigation.config.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const PAGINA = 'src/pages/admin/webinars.astro';
const pagina = () => maskJsComments(readFileSync(resolve(ROOT, PAGINA), 'utf8'));

function corpoDe(fonte, assinatura) {
  const i = fonte.indexOf(assinatura);
  assert.ok(i >= 0, `${PAGINA}: não tem ${assinatura}`);
  const fim = fonte.indexOf('\n  }\n', i);
  assert.ok(fim > i, `${PAGINA}: ${assinatura} sem fechamento`);
  return fonte.slice(i + assinatura.length, fim);
}

/** A ação que `upsert_webinar` pergunta no ramo de criação (sem `p_id`), lida do corpo vigente. */
function acaoDeCriarWebinar() {
  const { file, body } = latestFunctionCapture(ROOT, 'upsert_webinar');
  const sql = maskLineComments(body);
  const m = sql.match(
    /\bELSE\s+IF NOT public\.can_by_member\(v_member_id, '([a-z_]+)'\) THEN\s+RAISE EXCEPTION 'Unauthorized: admin role required for webinar creation';/,
  );
  assert.ok(m, `upsert_webinar (${file}): o ramo de criação não tem a forma que o guard lê`);
  return m[1];
}

test('webinars: canEdit pergunta, pelo canForUnscoped, a ação com que upsert_webinar cria', () => {
  const acao = acaoDeCriarWebinar();
  const src = pagina();
  assert.match(src, /^\s*import \{ canForUnscoped \} from '\.\.\/\.\.\/lib\/permissions';$/m,
    'a página não importa o canForUnscoped');
  const corpo = corpoDe(src, 'function canEdit(): boolean {');
  assert.match(corpo, new RegExp(`^\\s*if \\(!MEMBER\\) return false;\\s*return canForUnscoped\\('${acao}'\\);\\s*$`),
    `canEdit não é "sem membro, falso; senão canForUnscoped('${acao}')"`);
});

test('webinars: a ação do canEdit é a do portão da página, então dentro dela quem entra pode criar', () => {
  assert.deepEqual(ADMIN_ROUTE_ACCESS['/admin/webinars'].actions, [acaoDeCriarWebinar()],
    'o portão de /admin/webinars não pergunta a mesma ação que upsert_webinar pergunta para criar');
});

test('webinars: a página não decide por papel, designação ou superadmin do membro', () => {
  assert.doesNotMatch(pagina(), /\bMEMBER\??\.(operational_role|designations|is_superadmin)\b/,
    'a página voltou a ler papel, designação ou superadmin do membro');
});

test('webinars: criar e editar só aparecem com canEdit, e o modal só abre por esses botões', () => {
  const src = pagina();
  assert.match(src, /if \(!canEdit\(\)\) \{\s*document\.getElementById\('btn-new-webinar'\)\?\.classList\.add\('hidden'\);\s*\}/,
    'o botão de criar não some sem canEdit');
  const editar = src.match(/data-edit="\$\{w\.id\}"/g) || [];
  const editarComPortao = src.match(/\$\{canEdit\(\) \? `<button type="button" data-edit="\$\{w\.id\}"/g) || [];
  assert.ok(editar.length >= 2, `esperava os botões de editar das duas listas, achei ${editar.length}`);
  assert.equal(editarComPortao.length, editar.length, 'há botão de editar fora do canEdit');
  const aberturas = (src.match(/\bopenModal\([^)]*\)/g) || []).filter((c) => !/^openModal\(w\?: any\)$/.test(c));
  assert.deepEqual(aberturas.sort(), ['openModal()', 'openModal(w)'],
    'o modal abre por outro caminho além do botão de criar e dos botões de editar');
  assert.match(src, /getElementById\('btn-new-webinar'\)\?\.addEventListener\('click', \(\) => openModal\(\)\);/,
    'o openModal() não é o do botão de criar');
  assert.match(src, /if \(w\) openModal\(w\);/, 'o openModal(w) não é o dos botões de editar');
});
