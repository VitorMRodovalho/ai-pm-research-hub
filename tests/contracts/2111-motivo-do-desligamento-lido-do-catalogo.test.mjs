// tests/contracts/2111-motivo-do-desligamento-lido-do-catalogo.test.mjs
// Hermetic: reads the members island and the 3 dictionaries; comments are masked before matching.
/**
 * Onboarding wave 0, PR-6 (#2111 part 1). The offboard reason menu of /admin/members offered 6 codes fixed in the
 * component, none of them in offboard_reason_categories, with 'time' (also absent) as the default.
 * admin_offboard_member stores an unknown code as 'other' (#449a, kept on purpose and pinned by
 * 1200-offboard-reason-category-propagation), so every offboard made from the screen recorded 'other'.
 *
 *   A  the menu reads offboard_reason_categories, active rows only, ordered by sort_order, and that result is what
 *      the menu state holds;
 *   B  every option with a value comes from that state: the only fixed option is the empty, disabled placeholder,
 *      and the RPC receives the chosen code;
 *   C  there is no default reason: the state starts empty, and the "Gerenciar Status" button resets it to empty;
 *   D  without a reason, Confirm is disabled and handleOffboard returns before calling the RPC;
 *   E  the label follows the screen language, with label_pt as the fallback;
 *   F  the two new strings exist in the 3 dictionaries and are the keys the island asks for.
 *
 * Out of scope, decided apart: the RPC keeps storing 'other' for an unknown code; parts 2 and 3 of #2111.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const ISLAND = maskJsComments(read('src/components/admin/members/MemberListIsland.tsx'));
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, read(`src/i18n/${l}.ts`)]);
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function between(text, from, to, label) {
  const start = text.indexOf(from);
  assert.ok(start >= 0, `${label}: "${from}" is gone`);
  const stop = text.indexOf(to, start + from.length);
  assert.ok(stop > start, `${label}: "${to}" no longer follows "${from}"`);
  return text.slice(start, stop + to.length);
}

const reasonSelect = () => between(ISLAND, '<select value={offboardCategory}', '</select>', 'the reason menu');
const handleOffboard = () => between(ISLAND, 'const handleOffboard = async () => {', '\n  };', 'handleOffboard');

test('A: the menu reads the catalog, active rows only, by sort_order, and keeps that result', () => {
  const load = between(ISLAND, "sb.from('offboard_reason_categories')", 'setReasonCategories(data as ReasonCategory[]);', 'A');
  assert.match(load,
    /^sb\.from\('offboard_reason_categories'\)\s*\.select\('code, label_pt, label_en, label_es'\)\s*\.eq\('is_active', true\)\s*\.order\('sort_order', \{ ascending: true \}\)\s*\.order\('code', \{ ascending: true \}\);/,
    'the menu does not read the active catalog ordered by sort_order');
  assert.match(load,
    /if \(error \|\| !data \|\| data\.length === 0\) \{ setReasonLoadError\(true\); return; \}\s*setReasonCategories\(data as ReasonCategory\[\]\);$/,
    'the catalog result is not what the menu state holds, or a failed load is silent');
  assert.equal((ISLAND.match(/setReasonCategories\(/g) || []).length, 1, 'the menu state has a second writer');
  // The load runs when the modal opens and stops once one load succeeded.
  assert.match(ISLAND, /useEffect\(\(\) => \{\s*if \(!offboardMember \|\| reasonCategories\) return;/,
    'the catalog is not loaded when the offboard modal opens');
});

test('B: every option with a value comes from the catalog state, and the RPC gets the chosen code', () => {
  const sel = reasonSelect();
  const literal = [...sel.matchAll(/<option value="([^"]*)"/g)].map((m) => m[1]);
  assert.deepEqual(literal, [''], `the reason menu has fixed options: ${JSON.stringify(literal)}`);
  assert.match(sel, /<option value="" disabled>\{t\('comp\.memberList\.reasonPlaceholder', '[^']+'\)\}<\/option>/,
    'the placeholder is not the empty, disabled option');
  assert.match(sel,
    /\{\(reasonCategories \|\| \[\]\)\.map\(c => \(\s*<option key=\{c\.code\} value=\{c\.code\}>\{reasonLabel\(c, locale\)\}<\/option>\s*\)\)\}/,
    'the options are not the catalog codes with their label');
  assert.match(sel, /onChange=\{e => setOffboardCategory\(e\.target\.value\)\}/, 'the menu does not set the chosen code');
  assert.match(handleOffboard(), /sb\.rpc\('admin_offboard_member', \{[^}]*p_reason_category: offboardCategory,/,
    'the RPC does not receive the chosen code');
});

test('C: there is no default reason, at start or when the modal opens', () => {
  assert.match(ISLAND, /const \[offboardCategory, setOffboardCategory\] = useState\(''\);/, 'the reason has a default');
  const args = [...ISLAND.matchAll(/setOffboardCategory\(([^)]*)\)/g)].map((m) => m[1]);
  const unexpected = args.filter((a) => a !== "''" && a !== 'e.target.value');
  assert.deepEqual(unexpected, [], `the reason is set to a fixed code: ${JSON.stringify(unexpected)}`);
  assert.match(ISLAND, /setOffboardMember\(editMember\); setOffboardStatus\('alumni'\); setOffboardCategory\(''\);/,
    'opening the modal does not reset the reason to empty');
});

test('D: without a reason, Confirm is disabled and the handler stops before the RPC', () => {
  const body = handleOffboard();
  const guard = body.indexOf('if (!offboardMember || !offboardCategory) return;');
  const rpc = body.indexOf("sb.rpc('admin_offboard_member'");
  assert.ok(guard > 0 && rpc > guard, 'handleOffboard calls the RPC without a reason');
  assert.match(ISLAND, /<button onClick=\{handleOffboard\} disabled=\{offboardSaving \|\| !offboardCategory\}/,
    'Confirm is enabled without a reason');
});

test('E: the label follows the screen language, with label_pt as the fallback', () => {
  assert.match(ISLAND,
    /function reasonLabel\(c: ReasonCategory, locale: Locale\): string \{\s*if \(locale === 'en-US'\) return c\.label_en \|\| c\.label_pt;\s*if \(locale === 'es-LATAM'\) return c\.label_es \|\| c\.label_pt;\s*return c\.label_pt;\s*\}/,
    'the reason label does not follow the screen language');
  assert.match(ISLAND, /const \[locale\] = useState<Locale>\(\(\) => getEffectiveLocale\(\) as Locale\);/,
    'the locale is not the screen language');
});

test('F: the two new strings exist in the 3 dictionaries and are the keys the island asks for', () => {
  const keys = ['comp.memberList.reasonPlaceholder', 'comp.memberList.reasonLoadError'];
  for (const k of keys) {
    assert.match(ISLAND, new RegExp(`t\\('${esc(k)}', '[^']+'\\)`), `the island does not ask for ${k}`);
    for (const [lang, src] of DICTS) {
      assert.match(src, new RegExp(`^  '${esc(k)}': '[^']+',$`, 'm'), `${lang} lacks ${k}`);
    }
  }
  assert.match(ISLAND, /\{reasonLoadError && \(\s*<div[^>]*>\{t\('comp\.memberList\.reasonLoadError', '[^']+'\)\}<\/div>\s*\)\}/,
    'a failed catalog load is not shown');
});
