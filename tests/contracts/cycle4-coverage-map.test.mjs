import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

// R9 (Ciclo 4) lock — the national coverage map must stay data-driven and on-brand:
//   - BrazilMap.astro carries the static SVG geometry (27 UF ids) but NO hardcoded list
//     of which states are active — it paints whatever `activeUFs`/`founderUF` it receives.
//   - ChaptersSection derives those props from the LIVE chapter registry (chapter_code +
//     is_contracting), never a literal array of states, honoring the "nada hardcoded" trava.
//   - The map keys exist in all 3 dictionaries (i18n parity).
// PD-MAP (heatmap por estado) extends R9 with a density layer behind LGPD gates:
//   - BrazilMap accepts a `density` prop and paints intensity (teal + fill-opacity); the
//     founder rule comes last so the orange landmark always wins.
//   - ChaptersSection reads get_public_state_reach and only ACENDE density with >=2 UFs
//     (product gate against an empty map while opt-in has no substrate).
//   - The state-reach migration carries the LGPD gates: opt-in column (default false) +
//     k>=5 suppression + SECURITY DEFINER. (No longer a FE-pure slice.)
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const MAP = 'src/components/sections/BrazilMap.astro';
const SECTION = 'src/components/sections/ChaptersSection.astro';
const MIG_COL = 'supabase/migrations/20260805000226_pd_map_2_allow_state_column.sql';
const MIG_RPC = 'supabase/migrations/20260805000227_pd_map_4_get_public_state_reach.sql';

test('R9 static: BrazilMap holds 27 UF shapes and is painted by props, not hardcoded states', () => {
  const body = read(MAP);
  assert.ok(body, 'BrazilMap.astro present');
  const ufIds = [...body.matchAll(/id="([A-Z]{2})"/g)].map((m) => m[1]);
  assert.equal(new Set(ufIds).size, 27, 'all 27 Brazilian UFs present in the SVG');
  // props-driven coloring (no literal active-state list inside the map)
  assert.match(body, /activeUFs/, 'map takes activeUFs prop');
  assert.match(body, /founderUF/, 'map takes founderUF prop');
  // on-brand fills via design tokens (no rogue hex for the highlight colors)
  assert.match(body, /var\(--color-teal\)/, 'active states use the teal brand token');
  assert.match(body, /var\(--color-orange\)/, 'founder state uses the orange brand token');
});

test('R9 static: ChaptersSection derives map data from the live registry (anti-hardcode)', () => {
  const body = read(SECTION);
  assert.ok(body, 'ChaptersSection.astro present');
  assert.match(body, /import BrazilMap/, 'ChaptersSection mounts the BrazilMap');
  // activeUFs comes from chapters (chapter_code), founderUF from is_contracting — live data
  assert.match(body, /chapters\.map\(\(c\)\s*=>\s*c\.chapter_code\)/, 'activeUFs derived from chapter_code');
  assert.match(body, /is_contracting\)\?\.chapter_code/, 'founderUF derived from is_contracting');
  // no hardcoded UF array feeding the map
  assert.doesNotMatch(body, /activeUFs\s*=\s*\[\s*['"][A-Z]{2}['"]/, 'activeUFs is not a hardcoded literal array');
});

test('R9 static: coverage-map i18n keys exist in all 3 dictionaries', () => {
  const keys = ['chapters.mapTitle', 'chapters.mapAria', 'chapters.mapLegendActive'];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const body = read(`src/i18n/${dict}.ts`);
    assert.ok(body, `${dict} dictionary present`);
    for (const k of keys) {
      assert.ok(body.includes(`'${k}'`), `${dict} has ${k}`);
    }
  }
});

test('PD-MAP static: BrazilMap accepts a density prop and paints intensity, founder still wins', () => {
  const body = read(MAP);
  assert.match(body, /density\?:\s*Record<string,\s*number>/, 'map takes a density prop');
  assert.match(body, /fill-opacity/, 'density paints via fill-opacity intensity (teal scale)');
  // founder rule emitted after density → orange landmark wins
  assert.match(body, /founderUF\s*\?[^]*color-orange/, 'founder still painted orange on top');
});

test('PD-MAP static: ChaptersSection gates density on >=2 UFs and feeds it to the map', () => {
  const body = read(SECTION);
  assert.match(body, /get_public_state_reach/, 'fetches the state-reach RPC');
  assert.match(body, /stateReach\.length\s*>=\s*2/, 'density gated on >=2 states (product decision)');
  assert.match(body, /density=\{densityMap\}/, 'passes density to BrazilMap');
  // density comes from the RPC, never a hardcoded UF→count literal
  assert.doesNotMatch(body, /densityMap\s*=\s*\{\s*['"][A-Z]{2}['"]/, 'densityMap is not a hardcoded literal');
});

test('PD-MAP static: heatmap i18n keys exist in all 3 dictionaries', () => {
  const keys = ['chapters.mapLegendDensity', 'chapters.mapDensityNote', 'profile.allowStateMapLabel', 'profile.statePlaceholder'];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const body = read(`src/i18n/${dict}.ts`);
    assert.ok(body, `${dict} dictionary present`);
    for (const k of keys) assert.ok(body.includes(`'${k}'`), `${dict} has ${k}`);
  }
});

test('PD-MAP static: LGPD gates captured in the migrations (opt-in default-false + k>=5 + DEFINER)', () => {
  const col = read(MIG_COL);
  assert.ok(col, 'opt-in column migration present');
  assert.match(col, /allow_state_in_public_map boolean NOT NULL DEFAULT false/, 'opt-out by default (privacy by design)');
  const rpc = read(MIG_RPC);
  assert.ok(rpc, 'state-reach migration present');
  assert.match(rpc, /allow_state_in_public_map/, 'RPC filters on the opt-in column');
  assert.match(rpc, /count\(\*\)\s*>=\s*5/, 'RPC suppresses buckets below k=5');
  assert.match(rpc, /SECURITY DEFINER/, 'RPC is SECURITY DEFINER (zero-PII public surface)');
});
