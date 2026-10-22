/**
 * Contract #2738 (parte E): a grade "Tribe Meetings" da home mostra os horários ao visitante anônimo.
 *
 * DEFEITO, medido em 19/10/2026 como anônimo: a grade dizia "No meetings scheduled." em toda língua.
 * Ela lia tribe_meeting_slots (o anônimo recebe as linhas) e tribes (o anônimo recebe 0 linhas), e
 * descartava todo horário sem tribo. Os cards de Research Streams, logo abaixo, mostravam o horário de
 * 11 das 13 tribos, porque leem a RPC pública get_tribe_public_profiles.
 *
 * Depois da correção, exercido como anônimo no servidor local: a grade lista as mesmas 11 tribos, por
 * nome, que os cards com horário, em EN e PT.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. Os horários vêm de get_tribe_public_profiles (tribo ativa e visível, slot ativo), e a grade não lê
 *      mais tribe_meeting_slots direto.
 *   B. O nome vem da mesma fonte da lista de linhas (#2553: get_public_research_lines, no SSR), não da tabela tribes; tribes é lida
 *      só pelo meeting_link, que é de membro.
 *   C. A grade não desiste quando tribes volta vazia (o caso do anônimo).
 *   D. A hora sai como HH:MM (a RPC devolve "19:30:00") e a grade diz que é horário de Brasília.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const SRC = maskAstro(readFileSync(join(ROOT, 'src/components/sections/WeeklyScheduleSection.astro'), 'utf8'));
const LOAD = (SRC.match(/async function loadSchedule\(\) \{[\s\S]*?\n    \}\n/) || [''])[0];

test('A: os horários vêm da RPC pública dos cards, não da tabela de slots', () => {
  assert.ok(LOAD, 'loadSchedule encontrada');
  assert.match(LOAD, /sb\.rpc\('get_tribe_public_profiles'\)/);
  assert.match(LOAD, /for \(const p of profiles\) \{[\s\S]*?for \(const slot of \(p\.slots \|\| \[\]\)\)/, 'cada slot da RPC vira entrada');
  assert.doesNotMatch(LOAD, /from\('tribe_meeting_slots'\)/);
});

test('B: o nome vem da lista de linhas (get_public_research_lines); tribes só dá o meeting_link', () => {
  assert.match(SRC, /const tribeNames: Record<number, string> = Object\.fromEntries\(\(\(await loadResearchLines\(lang\)\) \?\? \[\]\)\.map\(\(l\) => \[l\.id, l\.name\]\)\);/);
  assert.match(SRC, /<script id="schedule-tribe-names" type="application\/json" set:html=\{JSON\.stringify\(tribeNames\)\}><\/script>/);
  assert.match(LOAD, /tribe_name: tribeNames\[String\(tribeId\)\]/);
  assert.match(LOAD, /from\('tribes'\)\.select\('id, meeting_link'\)/);
  assert.doesNotMatch(LOAD, /name_i18n/);
});

test('D: a hora sai como HH:MM e a grade diz o fuso', () => {
  // A RPC devolve "19:30:00". Sem o corte, o visitante lia os segundos, e sem o rótulo não sabia o fuso.
  // #2553 PR 2: sem nome (leitura das linhas falhou) a entrada fica só "T05 (19:00)", nunca "T05: T05"
  const entries = LOAD.match(/T\$\{entry\.tribe_id\}\$\{entry\.tribe_name \? ': ' \+ escHtml\(entry\.tribe_name\) : ''\} \(.*?\)\$\{badge\}/g) || [];
  assert.equal(entries.length, 2, 'os dois ramos (com e sem link) montam a entrada');
  for (const e of entries) assert.match(e, /\(\$\{String\(entry\.time_start\)\.slice\(0, 5\)\}\)/);
  assert.match(SRC, /<p id="schedule-timezone"[^>]*>\{t\('schedule\.timezone', lang\)\}<\/p>\s*<div id="schedule-tribe-grid"/);
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.match(readFileSync(join(ROOT, `src/i18n/${dict}.ts`), 'utf8'), /'schedule\.timezone': '[^']*UTC−3\)',/, dict);
  }
});

test('C: a grade não desiste quando tribes volta vazia', () => {
  assert.match(LOAD, /if \(!Array\.isArray\(profiles\)\) return;/);
  assert.doesNotMatch(LOAD, /!tribes\)\s*return/);
});
