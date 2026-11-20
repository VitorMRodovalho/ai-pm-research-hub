/**
 * #3116: /admin/selection, aba pipeline: o checkbox e o nome ficam fixos na rolagem horizontal.
 *
 * A tabela tem 18 colunas dentro de um `overflow-x-auto`; ao rolar para ver Pipeline ou Entrevista, o nome saía da
 * tela e a linha deixava de dizer de quem era. O padrão é o mesmo de TribeGamificationTab e AttendanceGrid.
 *
 * O QUE ESTE GUARD AFIRMA (sempre sobre a TAG que contém o elemento, não sobre o arquivo):
 *   A. no cabeçalho, a célula do "marcar todos" é sticky left-0 e a do nome (data-sort="applicant_name") é sticky
 *      left-8, as duas com fundo opaco por token e acima das células do corpo (z-20);
 *   B. no corpo, a linha é `group`; a célula do checkbox da linha é sticky left-0 e a do nome é sticky left-8, com
 *      fundo opaco (--surface-card) e z-10;
 *   C. o hover da linha chega às células fixas por group-hover, e a camada de hover fica SOBRE --surface-card: o
 *      --surface-hover é translúcido nos dois temas, e sozinho deixaria o conteúdo rolado aparecer por baixo;
 *   D. o deslocamento do nome (left-8) é a largura TRAVADA da coluna do checkbox (w-8 min-w-8 max-w-8), no
 *      cabeçalho e no corpo; sem a trava a coluna encolhe e abre uma fresta por onde o conteúdo rolado aparece.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SRC = maskJsComments(readFileSync(resolve(process.cwd(), 'src/pages/admin/selection.astro'), 'utf8'));

// A classe da tag <tag ...> mais próxima antes de `marker` (o marcador está dentro dela ou no seu conteúdo direto).
// O marcador tem de ser único no arquivo, para a tag recortada ser a que decide.
function classOfTagBefore(tag, marker) {
  const at = SRC.indexOf(marker);
  assert.ok(at >= 0, `marcador presente: ${marker}`);
  assert.equal(SRC.indexOf(marker, at + 1), -1, `marcador único: ${marker}`);
  const open = SRC.lastIndexOf(`<${tag} `, at);
  assert.ok(open >= 0, `<${tag}> antes de ${marker}`);
  const between = SRC.slice(open, at + marker.length);
  assert.ok(!new RegExp(`</${tag}>`).test(between), `nenhuma </${tag}> entre a tag e ${marker}`);
  const cls = /class="([^"]*)"/.exec(between);
  assert.ok(cls, `a <${tag}> de ${marker} tem class`);
  return cls[1].split(/\s+/);
}

const OPAQUE_HOVER = 'group-hover:[background:linear-gradient(var(--surface-hover),var(--surface-hover)),var(--surface-card)]';

test('A. cabeçalho: checkbox em left-0 e nome em left-8, opacos, z-20', () => {
  const chk = classOfTagBefore('th', 'id="sel-check-all"');
  for (const c of ['sticky', 'left-0', 'z-20', 'bg-[var(--surface-base)]']) assert.ok(chk.includes(c), `th do marcar-todos: ${c}`);
  const name = classOfTagBefore('th', 'data-sort="applicant_name"');
  for (const c of ['sticky', 'left-8', 'z-20', 'bg-[var(--surface-base)]']) assert.ok(name.includes(c), `th do nome: ${c}`);
});

test('B. corpo: linha é group; checkbox em left-0 e nome em left-8, opacos, z-10', () => {
  const tr = classOfTagBefore('tr', 'cursor-pointer" data-action="view-applicant" data-id="${esc(r.id)}">\n');
  assert.ok(tr.includes('group'), 'a linha da candidatura é group');
  const chk = classOfTagBefore('td', 'class="sel-row-check');
  for (const c of ['sticky', 'left-0', 'z-10', 'bg-[var(--surface-card)]']) assert.ok(chk.includes(c), `td do checkbox: ${c}`);
  const name = classOfTagBefore('td', '">${esc(r.applicant_name)}${noMembership');
  for (const c of ['sticky', 'left-8', 'z-10', 'bg-[var(--surface-card)]']) assert.ok(name.includes(c), `td do nome: ${c}`);
});

test('C. hover chega às células fixas e continua opaco', () => {
  for (const marker of ['class="sel-row-check', '">${esc(r.applicant_name)}${noMembership']) {
    const cls = classOfTagBefore('td', marker);
    assert.ok(cls.includes(OPAQUE_HOVER), `td de ${marker}: hover em camada sobre --surface-card`);
    assert.ok(!cls.includes('group-hover:bg-[var(--surface-hover)]'), `td de ${marker}: sem hover translúcido sozinho`);
  }
});

test('D. o deslocamento do nome é a largura da coluna do checkbox', () => {
  // Medido 20/11/2026: só com w-8 a coluna encolhe para 29px no layout automático e o conteúdo rolado aparece na
  // fresta entre o checkbox e o nome. min-w-8 e max-w-8 travam os 2rem que o left-8 assume.
  for (const [tag, marker] of [['th', 'id="sel-check-all"'], ['td', 'class="sel-row-check']]) {
    const cls = classOfTagBefore(tag, marker);
    for (const c of ['w-8', 'min-w-8', 'max-w-8']) assert.ok(cls.includes(c), `${tag} do checkbox: ${c}`);
  }
});
