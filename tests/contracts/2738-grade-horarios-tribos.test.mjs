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
 *   B. O nome vem da mesma fonte dos cards (resolveTribes, no SSR), não da tabela tribes; tribes é lida
 *      só pelo meeting_link, que é de membro.
 *   C. A grade não desiste quando tribes volta vazia (o caso do anônimo).
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

test('B: o nome vem de resolveTribes (fonte dos cards); tribes só dá o meeting_link', () => {
  assert.match(SRC, /const tribeNames: Record<number, string> = Object\.fromEntries\(resolveTribes\(lang\)\.map\(\(tr\) => \[tr\.id, tr\.name\]\)\);/);
  assert.match(SRC, /<script id="schedule-tribe-names" type="application\/json" set:html=\{JSON\.stringify\(tribeNames\)\}><\/script>/);
  assert.match(LOAD, /tribe_name: tribeNames\[String\(tribeId\)\]/);
  assert.match(LOAD, /from\('tribes'\)\.select\('id, meeting_link'\)/);
  assert.doesNotMatch(LOAD, /name_i18n/);
});

test('C: a grade não desiste quando tribes volta vazia', () => {
  assert.match(LOAD, /if \(!Array\.isArray\(profiles\)\) return;/);
  assert.doesNotMatch(LOAD, /!tribes\)\s*return/);
});
