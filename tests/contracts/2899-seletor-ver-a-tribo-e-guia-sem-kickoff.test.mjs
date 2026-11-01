// tests/contracts/2899-seletor-ver-a-tribo-e-guia-sem-kickoff.test.mjs
// Hermetic (reads files only). Lands in the structural bucket by content (scripts/classify-test-suite.mjs).
/**
 * #2899 + #2889 part 1 (onboarding wave 0, PR-1): the tribe picker lets a newcomer read the tribe before choosing,
 * and the guide and the help stop telling them to wait for a kickoff that is not ahead of them.
 *
 * Measured 2026-10-31 on main 8832b217: each picker option showed only the title and the free slots; the
 * public page /tribe/<id> already had a description for the 13 active tribes and the meeting time from the
 * recurring rule (#2609), but nothing in the picker linked to it. The guide (journey step 6 and the FAQ) and
 * the help entry `wrong_tribe` said the choice opens "from the cycle kickoff", while entries happen every month,
 * and none of them said the leader has a deadline or what happens when it passes.
 *
 * Layers (all static):
 *   A  inside the option map, the link goes to the page of THAT option's tribe and sits outside the <label>;
 *      the time comes from the profile of the same tribe, and "to be defined" only when a profile was read;
 *      the public-profile read only happens when the picker is going to render.
 *   B  the guide and the help no longer frame the choice by the kickoff, in the 3 languages of the help;
 *      the FAQ answer about when to choose is bound to the signed Term and to the deadline.
 *   C  the deadline the texts promise is the one the request gate writes (7 days), so changing one
 *      without the other fails here.
 *   D  the contact in these static texts is the Núcleo address, with no response-time promise. Owner's
 *      decision 2026-11-01 (contact by stage): static and public texts carry the address only; the
 *      onboarding group, its contacts and the "3 business days" promise appear only on signed-in screens.
 *      That no group invite is versioned is already asserted by 740-convites-whatsapp-pelo-banco (D, H).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));

const BLOCK = read('src/components/tribe/TribeRequestBlock.tsx');
const GUIDE = read('src/data/pre-onboarding-guide.ts');
const HELP = read('src/components/help/HelpFloatingButton.tsx');
const RTA = maskLineComments(latestFunctionCapture(ROOT, 'request_tribe_assignment').body);

// The picker's option map, from the map call to the end of the fieldset that holds it.
function optionMap() {
  const start = BLOCK.indexOf('ctx.tribes.map((tr) =>');
  assert.ok(start > 0, 'the picker no longer maps ctx.tribes into options');
  const stop = BLOCK.indexOf('</fieldset>', start);
  assert.ok(stop > start, 'the option map is no longer inside a fieldset');
  return BLOCK.slice(start, stop);
}

// One help entry, from its id to the next entry's id.
function helpEntry(id) {
  const start = HELP.indexOf(`id: '${id}'`);
  assert.ok(start > 0, `help entry ${id} is gone`);
  const next = HELP.indexOf("id: '", start + 5);
  return HELP.slice(start, next > 0 ? next : undefined);
}

// One FAQ entry of the guide, from its question to the next question.
function guideFaq(questionStart) {
  const start = GUIDE.indexOf(`q: '${questionStart}`);
  assert.ok(start > 0, `guide FAQ "${questionStart}" is gone`);
  const next = GUIDE.indexOf("q: '", start + 4);
  return GUIDE.slice(start, next > 0 ? next : undefined);
}

// One journey step of the guide, from its title to the next step's title.
function journeyStep(title) {
  const start = GUIDE.indexOf(`title: '${title}'`);
  assert.ok(start > 0, `guide step "${title}" is gone`);
  const next = GUIDE.indexOf("title: '", start + 7);
  return GUIDE.slice(start, next > 0 ? next : GUIDE.indexOf('];', start));
}

const KICKOFF_FRAME = /(a partir do|from the|a partir del)\s+(kick-?off|cycle\s+kick-?off)/i;
const RESPONSE_PROMISE = /dias [úu]teis|business days|d[íi]as h[áa]biles/i;

test('A: the option link goes to the page of the same tribe, outside the label', () => {
  const map = optionMap();
  assert.match(
    map,
    /href=\{`\$\{pickerLangPrefix\}\/tribe\/\$\{tr\.tribe_id\}`\}/,
    'the "see the tribe" href must use the tribe_id of the option being rendered',
  );
  const labelClose = map.indexOf('</label>');
  const link = map.search(/href=\{`\$\{pickerLangPrefix\}\/tribe\//);
  assert.ok(labelClose > 0 && link > labelClose, 'the link must sit after </label>, so following it never toggles the radio');
  assert.match(map, /target="_blank"[\s\S]{0,80}rel="noopener noreferrer"/, 'new tab, so the motivation typed below is not lost');
});

test('A: the meeting time comes from the profile of the same tribe, and "to be defined" only after a read', () => {
  const map = optionMap();
  assert.match(map, /const\s+profile\s*=\s*profiles\?\.get\(\s*tr\.tribe_id\s*\)/, 'the profile must be looked up by the option tribe_id');
  assert.match(
    map,
    /const\s+schedule\s*=\s*profile\s*\?\s*\(\s*formatMeetingSlots\(\s*profile\.slots\s*,\s*lang\s*\)\s*\|\|\s*copy\.scheduleTbd\s*\)\s*:\s*''/,
    'no profile read means no time shown; a read profile with no slots means "to be defined"',
  );
});

test('A: the public-profile read happens only when the picker will render', () => {
  const at = BLOCK.indexOf("sb.rpc('get_tribe_public_profiles')");
  assert.ok(at > 0, 'the picker no longer reads get_tribe_public_profiles');
  const gate = BLOCK.lastIndexOf('if (', at);
  assert.match(
    BLOCK.slice(gate, at),
    /if\s*\(\s*next\.eligible\s*&&\s*!next\.pending\s*&&\s*Array\.isArray\(next\.tribes\)\s*&&\s*next\.tribes\.length\s*>\s*0\s*\)\s*\{\s*const/,
    'the read must be gated on the same condition that renders the picker',
  );
});

test('A: the link and the time have copy in the 3 languages', () => {
  for (const [label, re] of [
    ['pt-BR', /viewTribe:\s*'Ver a tribo'/],
    ['en-US', /viewTribe:\s*'See the tribe'/],
    ['es-LATAM', /viewTribe:\s*'Ver la tribu'/],
    ['pt-BR tbd', /scheduleTbd:\s*'horário a definir'/],
    ['en-US tbd', /scheduleTbd:\s*'time to be defined'/],
    ['es-LATAM tbd', /scheduleTbd:\s*'horario por definir'/],
  ]) assert.match(BLOCK, re, `copy missing: ${label}`);
});

test('B: the guide no longer frames the tribe choice by the kickoff', () => {
  assert.doesNotMatch(GUIDE, KICKOFF_FRAME, 'the guide still says the choice opens from the kickoff');
  const faq = guideFaq('Quando escolho minha tribo');
  assert.match(faq, /a:\s*'Assim que o <strong>Termo estiver assinado<\/strong>/, 'the answer must open with the signed Term');
  assert.match(faq, /O líder da tribo tem <strong>7 dias<\/strong> para responder/, 'the answer must state the leader deadline');
  assert.match(faq, /isso não é uma recusa/, 'the answer must say an expired request is not a rejection');
});

test('B: the help entry wrong_tribe drops the kickoff and states the deadline, in the 3 languages', () => {
  const entry = helpEntry('wrong_tribe');
  assert.doesNotMatch(entry, KICKOFF_FRAME, 'wrong_tribe still frames the choice by the kickoff');
  assert.match(entry, /'pt-BR':\s*'[^']*O líder tem 7 dias para responder/);
  assert.match(entry, /'en-US':\s*'[^']*The leader has 7 days to reply/);
  assert.match(entry, /'es-LATAM':\s*'[^']*El líder tiene 7 días para responder/);
});

test('D: the guide step and FAQ about the tribe point to the Núcleo address', () => {
  const step = journeyStep('Escolha sua tribo na plataforma');
  assert.match(
    step,
    /detail:\s*'[^']*Dúvidas sobre a escolha ou o pedido: escreva para <strong>nucleoia@pmigo\.org\.br<\/strong>\.'/,
    'step 6 must end with the Núcleo address as the contact',
  );
  const faq = guideFaq('Quando escolho minha tribo');
  assert.match(
    faq,
    /a:\s*'[^']*Dúvidas: escreva para <strong>nucleoia@pmigo\.org\.br<\/strong>\.'/,
    'the tribe FAQ answer must end with the Núcleo address as the contact',
  );
});

test('D: the help entry wrong_tribe points to the Núcleo address instead of "the GP", in the 3 languages', () => {
  const entry = helpEntry('wrong_tribe');
  for (const [lang, tail] of [
    ['pt-BR', /confirme que o Termo foi assinado ou escreva para nucleoia@pmigo\.org\.br\.'/],
    ['en-US', /confirm the Term was signed or write to nucleoia@pmigo\.org\.br\.'/],
    ['es-LATAM', /confirme que el Término fue firmado o escriba a nucleoia@pmigo\.org\.br\.'/],
  ]) {
    assert.match(entry, new RegExp(`'${lang}':\\s*'[^']*${tail.source}`), `wrong_tribe ${lang} must end with the Núcleo address`);
  }
  assert.doesNotMatch(entry, /fale com o GP|contact the GP|contacte al GP/, 'wrong_tribe still sends the newcomer to "the GP"');
});

test('D: the static texts carry no response-time promise', () => {
  for (const [label, body] of [['guide', GUIDE], ['help wrong_tribe', helpEntry('wrong_tribe')]]) {
    assert.doesNotMatch(body, RESPONSE_PROMISE, `${label}: the response-time promise belongs on the signed-in screens, next to the group`);
  }
});

test('C: the 7 days the texts promise is the window the request gate writes', () => {
  assert.match(
    RTA,
    /INSERT INTO public\.initiative_invitations[\s\S]{0,400}now\(\)\s*\+\s*interval\s*'7 days'/,
    'request_tribe_assignment no longer writes a 7-day window: update the guide and the help with the new deadline',
  );
});
