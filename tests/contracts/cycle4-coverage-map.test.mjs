import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

// R9 (Ciclo 4) lock — the national coverage map must stay data-driven and on-brand:
//   - BrazilMap.astro carries the static SVG geometry (27 UF ids) but NO hardcoded list
//     of which states are active — it paints whatever `activeUFs`/`founderUF` it receives.
//   - ChaptersSection derives those props from the LIVE chapter registry (chapter_code +
//     is_contracting), never a literal array of states, honoring the "nada hardcoded" trava.
//   - The map keys exist in all 3 dictionaries (i18n parity).
// FE-pure slice: no migration/RPC, so there is no live-DB assertion here.
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const MAP = 'src/components/sections/BrazilMap.astro';
const SECTION = 'src/components/sections/ChaptersSection.astro';

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
