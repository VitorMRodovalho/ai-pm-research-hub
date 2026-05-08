#!/usr/bin/env node
/**
 * p123 Fase D — i18n value parity audit.
 * Detects keys whose values are identical across pt-BR/en-US/es-LATAM
 * (sign of untranslated keys — value copy-pasted from PT without translating).
 */
import fs from 'node:fs/promises';
import path from 'node:path';

const ROOT = path.resolve('src/i18n');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'];

async function loadDict(name) {
  const src = await fs.readFile(path.join(ROOT, `${name}.ts`), 'utf-8');
  const out = {};
  const re = /^\s*'([^']+)':\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)\s*,?\s*$/gm;
  let m;
  while ((m = re.exec(src)) !== null) {
    const key = m[1];
    let val = m[2].slice(1, -1).replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/\\\\/g, '\\').replace(/\\n/g, '\n');
    out[key] = val;
  }
  return out;
}

function isPlaceholder(val) {
  if (val == null) return false;
  const t = val.trim();
  return t === '' || t === 'TODO' || t === 'FIXME' || t === 'TBD' || t === '???';
}

const args = new Set(process.argv.slice(2));
const jsonOut = args.has('--json');

const dicts = Object.fromEntries(await Promise.all(DICTS.map(async d => [d, await loadDict(d)])));
const ptKeys = Object.keys(dicts['pt-BR']);
const tier1 = [], tier2 = [], tier3 = [];

for (const key of ptKeys) {
  const pt = dicts['pt-BR'][key];
  const en = dicts['en-US'][key];
  const es = dicts['es-LATAM'][key];
  if (en === undefined || es === undefined) continue;
  if (isPlaceholder(en) || isPlaceholder(es)) { tier3.push({ key, pt, en, es }); continue; }
  if (pt.length <= 2) continue;
  if (/^[\d\s.,:%/\-_+=]+$/.test(pt)) continue;
  if (/^[A-Z][A-Z0-9_]*$/.test(pt)) continue;
  if (pt === en && pt === es) tier1.push({ key, pt });
  else if (pt === en || pt === es) tier2.push({ key, pt, en, es, gap: pt === en ? 'en-US' : 'es-LATAM' });
}

if (jsonOut) {
  process.stdout.write(JSON.stringify({
    summary: { ptKeys: ptKeys.length, tier1: tier1.length, tier2: tier2.length, tier3: tier3.length },
    tier1, tier2, tier3,
  }, null, 2));
} else {
  console.log(`\n=== p123 Fase D — i18n value parity audit ===`);
  console.log(`PT-BR keys total: ${ptKeys.length}`);
  console.log(`tier1 (pt == en == es): ${tier1.length}`);
  console.log(`tier2 (single-lang gap): ${tier2.length}`);
  console.log(`tier3 (placeholder/empty): ${tier3.length}\n`);

  if (tier1.length > 0) {
    console.log(`=== tier1 — first 30 ===`);
    for (const t of tier1.slice(0, 30)) console.log(`  ${t.key}\n    "${t.pt.slice(0, 100)}"`);
    if (tier1.length > 30) console.log(`  ... +${tier1.length - 30} more`);
  }
  if (tier2.length > 0) {
    console.log(`\n=== tier2 — first 15 ===`);
    for (const t of tier2.slice(0, 15)) console.log(`  ${t.key} [missing ${t.gap}]\n    pt: "${t.pt.slice(0, 80)}"\n    en: "${t.en.slice(0, 80)}"\n    es: "${t.es.slice(0, 80)}"`);
    if (tier2.length > 15) console.log(`  ... +${tier2.length - 15} more`);
  }
  if (tier3.length > 0) {
    console.log(`\n=== tier3 — first 10 ===`);
    for (const t of tier3.slice(0, 10)) console.log(`  ${t.key}\n    pt: "${t.pt.slice(0, 60)}" | en: "${t.en}" | es: "${t.es}"`);
  }
}
