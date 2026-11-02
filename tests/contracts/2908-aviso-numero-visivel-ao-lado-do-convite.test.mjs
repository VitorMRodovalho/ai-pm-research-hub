// tests/contracts/2908-aviso-numero-visivel-ao-lado-do-convite.test.mjs
// Hermetic (reads files and calls one pure module). Lands in the structural bucket by content.
/**
 * Every WhatsApp group invite the platform serves shows, next to the link, that joining makes the person's phone
 * number visible to the group's members. Owner's decision 2026-11-01: the onboarding group (pre-onboarding card),
 * the general group (its card and the Term success screen) and the tribe groups (tribe page and tribe dashboard).
 *
 * Measured 2026-11-01 on main eb3aa985: the five places that render an invite from get_community_group_link or
 * get_tribe_group_link said nothing about the phone number; the warning lived only in code comments.
 *
 * Layers (all static except E, which calls the module):
 *   A  in each of the five places, the notice is rendered inside the block that renders the invite, so the
 *      link never shows without it;
 *   B  the pre-onboarding card names the group generically ("onboarding do Núcleo"), not "pré-onboarding",
 *      since the same group is served after the Term too;
 *   C  the set of files that ask for an invite is exactly these five, so a sixth place cannot render a link
 *      without the notice going unnoticed;
 *   E  the module returns the approved sentence for each language, and Portuguese for anything else.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));

const PLACES = {
  preOnboarding: 'src/components/onboarding/PreOnboardingChecklist.tsx',
  generalCard: 'src/components/onboarding/GeneralGroupCard.tsx',
  termSuccess: 'src/pages/volunteer-agreement.astro',
  tribePage: 'src/pages/tribe/[id].astro',
  tribeDashboard: 'src/components/islands/TribeDashboardIsland.tsx',
};
const MODULE = 'src/lib/whatsapp-group-notice.ts';
const INVITE_CALL = /\.rpc\(\s*['"](get_community_group_link|get_tribe_group_link)['"]/;

function between(body, from, to, label) {
  const start = body.indexOf(from);
  assert.ok(start >= 0, `${label}: "${from}" is gone`);
  const stop = body.indexOf(to, start + from.length);
  assert.ok(stop > start, `${label}: "${to}" no longer follows "${from}"`);
  return body.slice(start, stop + to.length);
}

test('A: pre-onboarding card, the notice sits inside {groupUrl && (...)}, before the link', () => {
  const block = between(read(PLACES.preOnboarding), '{groupUrl && (', 'href={groupUrl}', 'pre-onboarding card');
  assert.match(block, /\{phoneVisibleNotice\(lang\)\}/, 'the onboarding group invite renders without the phone notice');
});

test('A: general group card, the notice sits in the render that only runs with an invite, before the link', () => {
  const block = between(read(PLACES.generalCard), 'if (hidden || !url) return null;', 'href={url}', 'general group card');
  assert.match(block, /\{phoneVisibleNotice\(lang\)\}/, 'the general group invite renders without the phone notice');
});

test('A: Term success screen, the notice renders when either invite renders', () => {
  const body = read(PLACES.termSuccess);
  const render = between(body, 'function renderSuccess(', "app.innerHTML = renderSuccess(", 'Term success screen');
  assert.match(
    render,
    /\$\{\(tribeLink \|\| generalLink\) \? `[^`]*\$\{esc\(phoneVisibleNotice\(lang\)\)\}[^`]*` : ''\}/,
    'the tribe or general invite on the Term screen renders without the phone notice',
  );
});

test('A: tribe page, the notice is in the same innerHTML as the invite', () => {
  const block = between(read(PLACES.tribePage), "rpc('get_tribe_group_link'", '} catch (_)', 'tribe page');
  assert.match(
    block,
    /ctaEl\.innerHTML = `[^`]*href="\$\{escapeHtml\(waRes\.whatsapp_url\)\}"[^`]*\$\{escapeHtml\(phoneVisibleNotice\(_langCode\(\)\)\)\}[^`]*`;/,
    'the tribe group invite on the tribe page renders without the phone notice',
  );
});

test('A: tribe dashboard, the notice is inside {waLink && (...)}', () => {
  const block = between(read(PLACES.tribeDashboard), '{waLink && (', ')}', 'tribe dashboard');
  assert.match(block, /href=\{waLink\}[\s\S]*\{phoneVisibleNotice\(/, 'the tribe group invite on the dashboard renders without the phone notice');
});

test('B: the pre-onboarding card names the group generically, in the 3 languages', () => {
  const body = read(PLACES.preOnboarding);
  for (const [label, re] of [
    ['pt-BR', /helpBody:\s*'Entre no grupo de WhatsApp do onboarding do Núcleo:/],
    ['en-US', /helpBody:\s*'Join the Hub onboarding WhatsApp group:/],
    ['es-LATAM', /helpBody:\s*'Únase al grupo de WhatsApp de onboarding del Núcleo:/],
  ]) assert.match(body, re, `card label (${label}) is not the generic one`);
  const bodies = [...body.matchAll(/helpBody:\s*'([^']*)'/g)].map((m) => m[1]);
  assert.equal(bodies.length, 3, `expected 3 helpBody strings, found ${bodies.length}`);
  for (const b of bodies) assert.doesNotMatch(b, /pré-onboarding|pre-onboarding|pre-integración/i, `card still says pre-onboarding: ${b}`);
});

test('C: the files that ask for an invite are exactly the five that render the notice', () => {
  const files = readdirSync(resolve(ROOT, 'src'), { recursive: true })
    .map((f) => `src/${String(f).split(sep).join('/')}`)
    .filter((f) => /\.(tsx?|astro)$/.test(f) && !f.endsWith('database.gen.ts'));
  assert.ok(files.length > 200, `only ${files.length} source files listed: the walk is not looking at src`);
  const callers = files.filter((f) => INVITE_CALL.test(read(f))).sort();
  assert.deepEqual(callers, Object.values(PLACES).sort(), 'a file asks for a WhatsApp invite and is not covered by the notice guard');
  for (const f of callers) {
    assert.match(read(f), /import \{ phoneVisibleNotice \} from '[./]+lib\/whatsapp-group-notice'/, `${f} does not import the notice`);
  }
});

test('E: the module returns the approved sentence for each language, Portuguese otherwise', async () => {
  const { phoneVisibleNotice } = await import(pathToFileURL(resolve(ROOT, MODULE)).href);
  const PT = 'Ao entrar, seu número fica visível aos participantes.';
  const EN = "When you join, your phone number is visible to the group's members.";
  const ES = 'Al entrar, su número queda visible para los participantes.';
  for (const [input, expected] of [
    ['pt-BR', PT], ['pt', PT], ['', PT], [undefined, PT], [null, PT], ['fr', PT],
    ['en-US', EN], ['en', EN],
    ['es-LATAM', ES], ['es', ES],
  ]) assert.equal(phoneVisibleNotice(input), expected, `phoneVisibleNotice(${JSON.stringify(input)})`);
});
