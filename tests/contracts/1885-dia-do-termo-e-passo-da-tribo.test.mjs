// tests/contracts/1885-dia-do-termo-e-passo-da-tribo.test.mjs
// Hermetic: reads three source files; comments are masked before matching.
/**
 * Onboarding wave 0, PR-4 (#1885 and 06 §3.1). Two dead ends of who signed the Term and has no tribe:
 *
 *   A  the "Conheça sua tribo" step rendered no action at all without a tribe (its own CTA needs tribe_id and the
 *      step is excluded from the generic fallback); now it points to the tribe block of the same /workspace page;
 *   B  /workspace carries that anchor around the tribe block;
 *   C  for who has the Term and no tribe (`eligible`), the onboarding checklist gives its place to the card of the day
 *      of the Term, after the celebration branch, which is not affected;
 *   D  the card shows the next General Meeting from get_next_general_meeting (public agenda, no personal data), only
 *      for that cohort, rendered without a timezone shift, with the link to the General Meetings agenda;
 *   E  the picker state of the card also carries the onboarding contact and the meeting line;
 *   F  the new copy exists in the 3 languages, and each checklist dictionary stays on one line (#2718 reads it so).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const CHECKLIST = maskJsComments(read('src/components/onboarding/OnboardingChecklist.tsx'));
const BLOCK = maskJsComments(read('src/components/tribe/TribeRequestBlock.tsx'));
const WORKSPACE = read('src/pages/workspace.astro').replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));

function between(text, from, to, label) {
  const start = text.indexOf(from);
  assert.ok(start >= 0, `${label}: "${from}" is gone`);
  const stop = text.indexOf(to, start + from.length);
  assert.ok(stop > start, `${label}: "${to}" no longer follows "${from}"`);
  return text.slice(start, stop + to.length);
}

test('A: the tribe step without a tribe points to the tribe block of the page', () => {
  assert.match(CHECKLIST, /\{s\.step_id === 'meet_tribe' && !member\?\.tribe_id && \(\s*<a href="#escolher-tribo"[^>]*>\s*🧭 \{l\.chooseTribe\}\s*<\/a>/,
    'the "Conheça sua tribo" step of who has no tribe renders no action');
  // The step with a tribe keeps its own link to the tribe page.
  assert.match(CHECKLIST, /\{s\.step_id === 'meet_tribe' && member\?\.tribe_id && \(\s*<a href=\{`\$\{lp\}\/tribe\/\$\{member\.tribe_id\}`\}/);
});

test('B: /workspace wraps the tribe block in the anchor the step points to', () => {
  assert.match(WORKSPACE, /<div id="escolher-tribo"[^>]*>\s*<TribeRequestBlock client:load lang=\{lang\} \/>\s*<\/div>/,
    'the anchor #escolher-tribo is not around the tribe block');
  assert.equal((WORKSPACE.match(/id="escolher-tribo"/g) || []).length, 1, 'the anchor must be unique on the page');
});

test('C: who has the Term and no tribe gets the card in place of the checklist, after the celebration', () => {
  assert.match(CHECKLIST, /sb\.rpc\('get_my_tribe_request_context'\),\s*\]\);\s*setDayOfTerm\(trc\?\.data\?\.eligible === true\);/,
    'the checklist does not read the cohort of the day of the Term');
  const celebration = CHECKLIST.indexOf('if (allComplete) {');
  const hide = CHECKLIST.indexOf('if (dayOfTerm) return null;');
  const list = CHECKLIST.indexOf('const pct = total > 0');
  assert.ok(celebration > 0 && hide > celebration && hide < list,
    'the checklist does not step aside for the card, or it hides the celebration too');
});

test('D: the next General Meeting comes from the public agenda reader, only for the cohort, without a timezone shift', () => {
  assert.match(BLOCK, /if \(next\.eligible\) loadNextGeral\(sb\);/, 'the meeting is not read for the cohort');
  const loader = between(BLOCK, 'const loadNextGeral = useCallback(async (sb: any) => {', '}, []);', 'loadNextGeral');
  assert.match(loader, /sb\.rpc\('get_next_general_meeting'\)/);
  assert.match(loader, /if \(d && typeof d\.date === 'string'\) \{\s*setNextGeral\(/, 'a failed read would show a meeting line');
  const fmt = between(BLOCK, 'function formatGeralDate(', '\n}\n', 'formatGeralDate');
  assert.match(fmt, /new Date\(`\$\{date\}T12:00:00Z`\)\.toLocaleDateString\(lang, \{[^}]*timeZone: 'UTC' \}\)/, 'the calendar date is shifted by the viewer timezone');
  const line = between(BLOCK, 'function GeralLine(', '\n}\n', 'GeralLine');
  assert.match(line, /href=\{`\$\{lp\}\/reunioes-gerais`\}/, 'the line does not link to the General Meetings agenda');
});

test('E: every state of the card shows the meeting line, and the picker also shows the contact', () => {
  const picker = between(BLOCK, 'const pickerLangPrefix', '</section>', 'picker state');
  assert.match(picker, /\{nextGeral && <GeralLine geral=\{nextGeral\} copy=\{copy\} lang=\{lang\} \/>\}\s*\{contact && <ContactBlock lead=\{copy\.contactLeadPicker\}/,
    'the picker state lost the meeting line or the contact');
  for (const [label, from] of [['pending', 'if (ctx.pending) {'], ['expired', 'if (ctx.expired && !pickerOpen) {'], ['empty', 'if (!ctx.tribes || ctx.tribes.length === 0) {']]) {
    const state = between(BLOCK, from, '</section>', `${label} state`);
    assert.match(state, /\{nextGeral && <GeralLine geral=\{nextGeral\}/, `the ${label} state has no meeting line`);
  }
  assert.match(BLOCK, /if \(next\.pending \|\| next\.eligible\) loadContact\(sb\);/, 'the contact is not loaded for the picker');
});

test('F: the new copy is in the 3 languages, and each checklist dictionary stays on one line', () => {
  for (const key of ['contactLeadPicker', 'geralLead', 'geralWhen', 'geralAgenda']) {
    assert.equal((BLOCK.match(new RegExp(`\\n    ${key}: `, 'g')) || []).length, 3, `${key} is not in the 3 languages`);
  }
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const entry = CHECKLIST.match(new RegExp(`'${loc}': \\{[^\\n]*\\}`));
    assert.ok(entry, `checklist dictionary ${loc} is gone or split across lines`);
    assert.match(entry[0], /chooseTribe: '[^']+'/, `${loc} has no chooseTribe`);
  }
  for (const s of [...BLOCK.matchAll(/geralWhen: \(date, time\) => \(time \? `([^`]*)` : date\)/g)].map((m) => m[1])) {
    assert.match(s, /Bras[ií]lia/, `the meeting time does not say it is Brasília time: ${s}`);
  }
});
