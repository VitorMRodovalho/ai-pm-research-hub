import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

/**
 * #2760: a Agenda Viva mostrava "25 min livres" e o menu de duração era fixo (5, 10, 15, 20, 30).
 * Quem queria o bloco restante não tinha 25, e quem escolhia 30 recebia capacity_exceeded, que a
 * tela traduz como "Capacidade esgotada para esta reunião" com 25 min ainda livres.
 *
 * A: os helpers de módulo, exercidos de verdade: o menu só oferece o que cabe, 25 incluso, e a
 *    duração enviada cai para a maior que cabe.
 * B: o <select> de duração lista fitDurations(cap) e mostra fitDuration(d.duration_min, cap).
 * C: reservar envia a duração que cabe no que sobra da reunião.
 * D: editar envia a duração que cabe no que sobra MAIS o próprio bloco (a RPC o exclui da soma).
 * E: sem nenhuma duração que caiba, o formulário dá lugar ao aviso de capacidade esgotada.
 */

const SRC = maskJsComments(
  readFileSync(resolve(process.cwd(), 'src/components/agenda/AgendaVivaReservationIsland.tsx'), 'utf8'),
);

function loadHelpers() {
  const block = SRC.match(/const DURATIONS = \[[^\]]*\];[\s\S]*?const fitDuration = \([\s\S]*?\n\};/)?.[0];
  assert.ok(block, 'DURATIONS, fitDurations e fitDuration devem estar juntos no nível do módulo');
  const js = block.replace(/:\s*number/g, '');
  return new Function(`${js}; return { DURATIONS, fitDurations, fitDuration };`)();
}

function fnBody(name) {
  const start = SRC.indexOf(`const ${name} = async (`);
  assert.ok(start >= 0, `${name} deve existir`);
  const end = SRC.indexOf('finally {', start);
  assert.ok(end > start, `${name} deve terminar num finally`);
  return SRC.slice(start, end);
}

test('A: o menu só oferece o que cabe, com 25, e a duração enviada cai para a maior que cabe', () => {
  const { DURATIONS, fitDurations, fitDuration } = loadHelpers();
  assert.ok(DURATIONS.includes(25), 'sem 25 o bloco restante de 25 min não tem opção');
  assert.deepEqual(fitDurations(25), [5, 10, 15, 20, 25]);
  assert.deepEqual(fitDurations(0), []);
  assert.equal(fitDuration(30, 25), 25, 'pedir 30 com 25 livres envia 25');
  assert.equal(fitDuration(20, 25), 20, 'o que cabe fica como está');
  assert.equal(fitDuration(20, 12), 10, 'com 12 livres, a maior que cabe é 10');
});

test('B: o select de duração lista fitDurations(cap) e mostra fitDuration(d.duration_min, cap)', () => {
  assert.match(
    SRC,
    /<select value=\{fitDuration\(d\.duration_min, cap\)\} onChange=\{[^}]*\}\)\} className=\{inputCls\}>\s*\{fitDurations\(cap\)\.map\(\(m\) => <option/,
    'o select deve ler a capacidade, não a lista fixa',
  );
  assert.doesNotMatch(SRC, /\{DURATIONS\.map\(/, 'a lista fixa não pode voltar a alimentar o menu');
});

test('C: reservar envia a duração que cabe no que sobra da reunião', () => {
  const body = fnBody('reserve');
  assert.match(body, /const dur = fitDuration\(d\.duration_min, capFor\(eventId\)\);/);
  assert.match(body, /sb\.rpc\('reserve_agenda_block', \{[\s\S]*?p_duration_min: dur,/);
  assert.match(
    SRC,
    /const capFor = \(eventId: string\): number => events\.find\(\(ev\) => ev\.id === eventId\)\?\.capacity_remaining_min \?\? 0;/,
  );
});

test('D: editar envia a duração que cabe no que sobra mais o próprio bloco', () => {
  const body = fnBody('saveEdit');
  assert.match(body, /const dur = fitDuration\(d\.duration_min, editCapFor\(blockId\)\);/);
  assert.match(body, /sb\.rpc\('update_agenda_block', \{[\s\S]*?p_duration_min: dur,/);
  assert.match(SRC, /return \(ev\?\.capacity_remaining_min \?\? 0\) \+ own;/, 'a edição soma o próprio bloco ao que sobra');
  assert.match(SRC, /`edit-\$\{myBlock\.id\}`, editCapFor\(myBlock\.id\), true\)/, 'o formulário de edição recebe a capacidade da edição');
  assert.match(SRC, /`new-\$\{ev\.id\}`, ev\.capacity_remaining_min\)/, 'o formulário novo recebe o que sobra');
});

test('E: sem duração que caiba, o formulário dá lugar ao aviso de capacidade esgotada', () => {
  assert.match(
    SRC,
    /!ev\.is_past && allowed && draft && fitDurations\(ev\.capacity_remaining_min\)\.length === 0 \? \(\s*<p[^>]*>\{t\('comp\.agendaViva\.errCapacity'/,
  );
});
