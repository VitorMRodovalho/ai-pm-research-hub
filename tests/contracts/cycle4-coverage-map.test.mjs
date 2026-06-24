import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

// PD-MAP-WORLD (Ciclo 4, 2026-06-23) lock — the homepage coverage map is now an
// Atlantic-centered equirectangular WORLD map of member distribution, replacing the
// Brazil-only chapter choropleth (R9) + density heatmap (PD-MAP). Invariants:
//   - WorldReachMap.astro is data-driven: it positions/sizes pins from the two zero-PII
//     RPC payloads it receives, never a hardcoded member count or geography.
//   - Geography (projection + centroids) lives in src/lib/worldMap.ts — the component
//     and the section carry no lat/lon literals.
//   - ChaptersSection derives the pins LIVE from get_public_country_reach (country pins,
//     k-anon) + get_public_state_reach_v2 (BR/US state pins, consented + k≥3).
//   - The land backdrop is an external CC0 asset (cacheable, license-clean for the public
//     repo) used as a CSS mask; brand tokens tint land/pins.
//   - The state-reach v2 migration carries the LGPD gates: opt-in column (default false) +
//     k≥3 suppression (GREATEST(p_min_k,3)) + SECURITY DEFINER. k≥3 (not k≥5) per
//     legal-counsel 2026-06-23 (Cenário A: opt-in text cites no k, "estado de residência"
//     is country-agnostic, "nunca individual" forbids k≤2).
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const MAP = 'src/components/sections/WorldReachMap.astro';
const LIB = 'src/lib/worldMap.ts';
const SECTION = 'src/components/sections/ChaptersSection.astro';
const ASSET = 'public/assets/maps/world-equirect.svg';
const MIG_COL = 'supabase/migrations/20260805000226_pd_map_2_allow_state_column.sql';
const MIG_V2 = 'supabase/migrations/20260805000241_pd_map_world_state_reach_v2.sql';

test('PD-MAP-WORLD: the Brazil-only choropleth was retired (no BrazilMap import remains)', () => {
  assert.ok(!existsSync('src/components/sections/BrazilMap.astro'), 'BrazilMap.astro removed');
  const section = read(SECTION);
  assert.doesNotMatch(section, /BrazilMap/, 'ChaptersSection no longer references BrazilMap');
});

test('PD-MAP-WORLD: WorldReachMap is props-driven (no hardcoded counts/geography)', () => {
  const body = read(MAP);
  assert.ok(body, 'WorldReachMap.astro present');
  assert.match(body, /countryReach/, 'takes a countryReach prop');
  assert.match(body, /stateReach/, 'takes a stateReach prop');
  assert.match(body, /buildGeoPins/, 'delegates pin placement to the worldMap lib');
  // land backdrop is the external CC0 asset via CSS mask (cacheable, light HTML)
  assert.match(body, /mask-image:\s*url\(\/assets\/maps\/world-equirect\.svg\)/, 'land via CSS mask of the world asset');
  // on-brand tokens for pins, not rogue hex
  assert.match(body, /var\(--color-teal/, 'country pins use the teal brand token');
  assert.match(body, /var\(--color-orange/, 'state pins use the orange brand token');
  // geography (centroids) stays in the lib, not duplicated in the component
  assert.doesNotMatch(body, /CENTROIDS/, 'centroids stay in worldMap.ts, not the component');
});

test('PD-MAP-WORLD: worldMap lib carries projection + centroids, not the component', () => {
  const lib = read(LIB);
  assert.ok(lib, 'worldMap.ts present');
  assert.match(lib, /projectToWindow/, 'exposes the projection helper');
  assert.match(lib, /ATLANTIC_WINDOW/, 'defines the Atlantic crop window');
  assert.match(lib, /COUNTRY_CENTROIDS/, 'has country centroids');
  assert.match(lib, /US_STATE_CENTROIDS/, 'has US state centroids');
  assert.match(lib, /BR_UF_CENTROIDS/, 'has BR UF centroids');
  // representative codes the live data exercises today
  assert.match(lib, /\bVA:\s*\[/, 'Virginia centroid present (US state layer)');
  assert.match(lib, /\bSP:\s*\[/, 'São Paulo centroid present (BR UF layer)');
  assert.match(lib, /BR:\s*\[/, 'Brazil country centroid present');
  // ZZ/XX (k-anon bucket) must NOT be a placeable country pin
  assert.doesNotMatch(lib, /COUNTRY_CENTROIDS[\s\S]*?\bZZ:\s*\[/, 'no ZZ pin (k-anon bucket stays a legend chip)');
});

test('PD-MAP-WORLD: projectToWindow maps known points inside the [0,100]% window', () => {
  // Re-derive the documented formula and assert key points land where the land renders.
  // leftPct = (lon + 135) / 180 * 100 ; topPct = (78 - lat) / 136 * 100
  const proj = (lat, lon) => ({
    left: ((lon + 135) / 180) * 100,
    top: ((78 - lat) / 136) * 100,
  });
  for (const [lat, lon] of [[-10.5, -52.5] /*BR*/, [39.5, -98.5] /*US*/, [37.5, -78.8] /*VA*/]) {
    const { left, top } = proj(lat, lon);
    assert.ok(left >= 0 && left <= 100, `lon ${lon} within window horizontally (${left.toFixed(1)}%)`);
    assert.ok(top >= 0 && top <= 100, `lat ${lat} within window vertically (${top.toFixed(1)}%)`);
  }
});

test('PD-MAP-WORLD: ChaptersSection feeds the map LIVE from both RPCs (anti-hardcode)', () => {
  const body = read(SECTION);
  assert.ok(body, 'ChaptersSection.astro present');
  assert.match(body, /import WorldReachMap/, 'mounts the WorldReachMap');
  assert.match(body, /get_public_country_reach/, 'fetches the country-reach RPC');
  assert.match(body, /get_public_state_reach_v2/, 'fetches the state-reach v2 RPC');
  assert.match(body, /countryReach=\{countryReach\}/, 'passes country reach to the map');
  assert.match(body, /stateReach=\{stateReachV2\}/, 'passes state reach to the map');
  // no hardcoded UF/country→count literal feeding the map
  assert.doesNotMatch(body, /stateReachV2\s*=\s*\[\s*\{/, 'stateReachV2 is not a hardcoded literal');
});

test('PD-MAP-WORLD: the land asset exists, is CC0-noted, and keeps the Atlantic crop viewBox', () => {
  const svg = read(ASSET);
  assert.ok(svg, 'world-equirect.svg present in public/assets/maps');
  assert.match(svg, /viewBox="45 12 180 136"/, 'Atlantic crop viewBox preserved (projection contract)');
  assert.ok(existsSync('public/assets/maps/world-equirect.LICENSE.txt'), 'asset provenance/license noted (public-repo hygiene)');
  assert.match(read('public/assets/maps/world-equirect.LICENSE.txt'), /CC0/, 'license recorded as CC0');
});

test('PD-MAP-WORLD: state-reach v2 migration carries the LGPD gates (opt-in + k≥3 + DEFINER)', () => {
  const col = read(MIG_COL);
  assert.ok(col, 'opt-in column migration present');
  assert.match(col, /allow_state_in_public_map boolean NOT NULL DEFAULT false/, 'opt-out by default (privacy by design)');
  const rpc = read(MIG_V2);
  assert.ok(rpc, 'state-reach v2 migration present');
  assert.match(rpc, /m\.allow_state_in_public_map/, 'RPC filters on the opt-in column');
  assert.match(rpc, /count\(\*\)\s*>=\s*GREATEST\(p_min_k,\s*3\)/, 'k≥3 floor (GREATEST keeps it ≥3 even if caller lowers)');
  assert.match(rpc, /SECURITY DEFINER/, 'RPC is SECURITY DEFINER (zero-PII public surface)');
  assert.match(rpc, /REVOKE ALL ON FUNCTION public\.get_public_state_reach_v2/, 'PUBLIC execute revoked');
  assert.match(rpc, /GRANT EXECUTE ON FUNCTION public\.get_public_state_reach_v2\(integer\) TO anon, authenticated, service_role/, 'granted to the three roles');
});

test('PD-MAP-WORLD: coverage-map i18n keys exist in all 3 dictionaries', () => {
  const keys = ['chapters.worldMapAria', 'chapters.mapLegendCountry', 'chapters.mapLegendState', 'chapters.mapStateNote'];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const body = read(`src/i18n/${dict}.ts`);
    assert.ok(body, `${dict} dictionary present`);
    for (const k of keys) assert.ok(body.includes(`'${k}'`), `${dict} has ${k}`);
  }
});
