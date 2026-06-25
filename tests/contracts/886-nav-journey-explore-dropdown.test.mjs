// tests/contracts/886-nav-journey-explore-dropdown.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json before running.
/**
 * Contract: the #886 navigation journey — the "Minha Tribo" primary slot must ALWAYS
 * surface the explore dropdown (tribes + "Todas Iniciativas") for members who can browse,
 * even when they already belong to a tribe.
 *
 * WHY: before #886, a member assigned to a tribe got a FLAT direct link ("Minha Tribo"),
 * collapsing away every menu path to discover other tribes/initiatives. The comms team
 * (all in tribes) lost access to the Communication Hub catalog. The fix inverts the branch
 * order so canExploreTribes() is checked FIRST; the dropdown's first row links to the
 * member's own tribe ("Ir para minha tribo"), then all tribes, then "Todas Iniciativas".
 *
 * This is a static-source ratchet (the nav logic lives inline in Nav.astro's client <script>
 * and references DOM/window, so it is not unit-importable). It guards against a refactor
 * silently reverting the branch ordering and reintroducing the original bug.
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const NAV = read('src/components/nav/Nav.astro');

test('#886: primary nav checks canBrowseTribes BEFORE the direct-link fallback (no collapse for tribe members)', () => {
  const idxCanBrowse = NAV.indexOf('if (canBrowseTribes) {');
  const idxHrefFallback = NAV.indexOf('} else if (href) {');
  assert.ok(idxCanBrowse !== -1, 'desktop/mobile block gates on canBrowseTribes');
  assert.ok(idxHrefFallback !== -1, 'the direct-link path is now an else-if fallback');
  assert.ok(
    idxCanBrowse < idxHrefFallback,
    'canBrowseTribes must be the FIRST branch — a tribe-having member must still get the dropdown',
  );
});

test('#886: drawer SSR checks canExploreTribes BEFORE the resolved direct-link fallback', () => {
  const idxCanExplore = NAV.indexOf('if (canExploreTribes(_member)) {');
  const idxResolvedFallback = NAV.indexOf('} else if (resolved) {');
  assert.ok(idxCanExplore !== -1, 'drawer gates on canExploreTribes');
  assert.ok(idxResolvedFallback !== -1, 'drawer direct-link is an else-if fallback');
  assert.ok(idxCanExplore < idxResolvedFallback, 'canExploreTribes must precede the direct-link fallback');
});

test('#886: all three tribe dropdown renderers prepend the "go to my tribe" row', () => {
  // desktop + drawer + mobile each compute resolveMyTribeHref() and gate a first row on it.
  const occurrences = NAV.split('const myHref = resolveMyTribeHref();').length - 1;
  assert.ok(occurrences >= 3, `expected >=3 "go to my tribe" prepends, found ${occurrences}`);
  const goToKey = NAV.split('i18n.goToMyTribe').length - 1;
  assert.ok(goToKey >= 3, `expected the goToMyTribe label in all 3 renderers, found ${goToKey}`);
});

test('#886: all three tribe dropdown renderers link to the initiatives catalog footer', () => {
  // The mobile + drawer renderers GAINED this footer (desktop already had it) — 3 total.
  const footers = NAV.split("i18n.myInitiatives || 'Todas Iniciativas'").length - 1;
  assert.ok(footers >= 3, `expected the /initiatives footer in all 3 renderers, found ${footers}`);
  // Each footer points at the catalog route (built as `base + '/initiatives"...'`).
  assert.match(NAV, /\/initiatives"/, 'footer links to the /initiatives catalog route');
});

test('#886: nav.goToMyTribe is wired into the Nav.astro client i18n object', () => {
  assert.match(NAV, /goToMyTribe:\s*t\('nav\.goToMyTribe',\s*lang\)/, 'i18n.goToMyTribe is populated');
});

test('#886: nav.goToMyTribe exists in all three dictionaries', () => {
  for (const dict of ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts']) {
    assert.match(read(dict), /'nav\.goToMyTribe':\s*'[^']+'/, `${dict} declares nav.goToMyTribe`);
  }
});
