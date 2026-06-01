/**
 * Contract: p277 / #419 (ADR-0100) metric 4 — PR4-D: frontend single-source + i18n.
 *
 * Two surfaces converge onto the canonical member_count + i18n the one hardcoded label that
 * active=total made visible (SPEC §M4.5 / §M4.6 PR4-D):
 *   1) src/pages/tribe/[id].astro header badge: was `👥 ${membersMap.size}` (the CLIENT-side fourth
 *      count — membersMap also includes selection candidates, so it diverged from the stats card which
 *      reads the RPC member_count). Now the badge rides the canonical RPC member_count via a module var
 *      (_canonicalMemberCount) set in loadTribeStats + a DOM update by id (order-independent), falling
 *      back to membersMap.size only pre-load.
 *   2) src/components/islands/TribeDashboardIsland.tsx:143 KPI sub `${members.active} ativos` had a
 *      hardcoded PT word; now `${members.active} ${t('comp.tribe.activemembers', 'ativos')}` with the
 *      key in all 3 dictionaries (pt 'ativos' / en 'active' / es 'activos').
 *
 * Frontend-only (no migration). This is a forward-defense static contract.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const ASTRO = readFileSync(resolve(ROOT, 'src/pages/tribe/[id].astro'), 'utf8');
const ISLAND = readFileSync(resolve(ROOT, 'src/components/islands/TribeDashboardIsland.tsx'), 'utf8');
const PT = readFileSync(resolve(ROOT, 'src/i18n/pt-BR.ts'), 'utf8');
const EN = readFileSync(resolve(ROOT, 'src/i18n/en-US.ts'), 'utf8');
const ES = readFileSync(resolve(ROOT, 'src/i18n/es-LATAM.ts'), 'utf8');

test('M4-D: tribe header badge reads the canonical RPC member_count, not membersMap.size', () => {
  // the badge memberCount must prefer the canonical count
  assert.match(ASTRO, /const memberCount = _canonicalMemberCount \?\? membersMap\.size;/,
    'header memberCount = canonical RPC count, fallback membersMap.size only pre-load');
  // the module var must be declared and set from the stats RPC payload
  assert.match(ASTRO, /let _canonicalMemberCount: number \| null = null;/, '_canonicalMemberCount declared');
  assert.match(ASTRO, /_canonicalMemberCount = data\.member_count \?\? null;/,
    'loadTribeStats sets _canonicalMemberCount from the canonical RPC member_count');
  // order-independent: the badge element has an id and is updated after the RPC resolves
  assert.match(ASTRO, /id="tribe-header-member-count"/, 'badge element carries an id for the post-load DOM update');
  assert.match(ASTRO, /getElementById\('tribe-header-member-count'\)[\s\S]{0,80}?textContent = `👥 \$\{data\.member_count \?\? 0\}`/,
    'loadTribeStats updates the badge by id (handles header-rendered-before-stats)');
});

test('M4-D: the hardcoded "ativos" KPI sub-label is i18n-keyed', () => {
  assert.match(ISLAND, /\$\{members\.active \|\| 0\} \$\{t\('comp\.tribe\.activemembers', 'ativos'\)\}/,
    "KPI sub uses t('comp.tribe.activemembers','ativos'), not a bare 'ativos' literal");
  // forward-defense: no bare " ativos`" template-literal tail remains in the file
  assert.ok(!/\|\| 0\} ativos`/.test(ISLAND), 'no bare "${...} ativos" template literal survives');
});

test('M4-D: comp.tribe.activemembers exists in ALL 3 dictionaries (i18n parity)', () => {
  assert.match(PT, /'comp\.tribe\.activemembers': 'ativos',/, 'pt-BR key');
  assert.match(EN, /'comp\.tribe\.activemembers': 'active',/, 'en-US key');
  assert.match(ES, /'comp\.tribe\.activemembers': 'activos',/, 'es-LATAM key');
});
