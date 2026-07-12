// #1132 — Shared StatusFarol SSOT drift guard (static source scan).
//
// The status→colour "farol" (🔴🟡🟢) was reimplemented in three admin screens
// and had already diverged (final_eval purple vs indigo; cancelled gray vs red;
// VEP -100 vs -50 shades). This locks the single source of truth:
//   - src/lib/statusFarol.ts owns the palette (TONE_BADGE) + the status→tone maps;
//   - the three screens DERIVE their palettes from it, never redefine a local map.
//
// Pure source scan (no .ts import) so it runs under both `test` and
// `test:contracts` (the latter has no --experimental-strip-types).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

const MOD = read('src/lib/statusFarol.ts');
const VEP = read('src/components/admin/VepReconciliationIsland.tsx');
const AFF = read('src/components/admin/AffiliationQueueIsland.tsx');
const SEL = read('src/pages/admin/selection.astro');

// ── P1 — the module is the single source ─────────────────────────────────────
test('P1: statusFarol exports the palette + status→tone maps + helpers', () => {
  for (const sym of [
    'export const TONE_BADGE',
    'export function toneClasses',
    'export const SELECTION_STATUS_TONE',
    'export const VEP_STATUS_TONE',
    'export const VALIDITY_FAROL',
    'export function validityFarol',
    'export const COHORT_TONE',
    'export const GROUP_TONE',
  ]) {
    assert.ok(MOD.includes(sym), `statusFarol.ts must export "${sym}"`);
  }
});

test('P1: TONE_BADGE is the only place the tailwind class pairs are written', () => {
  // A representative tone class pair lives in the module.
  assert.match(MOD, /positive:\s*\{\s*bg:\s*'bg-emerald-50',\s*text:\s*'text-emerald-700'\s*\}/,
    'positive tone must be defined in TONE_BADGE');
  assert.match(MOD, /negative:\s*\{\s*bg:\s*'bg-red-50',\s*text:\s*'text-red-700'\s*\}/,
    'negative tone must be defined in TONE_BADGE');
});

// ── P2 — the three screens derive, not redefine ──────────────────────────────
test('P2: VepReconciliationIsland derives both palettes from the SSOT', () => {
  assert.match(VEP, /from '\.\.\/\.\.\/lib\/statusFarol'/, 'imports statusFarol');
  assert.match(VEP, /NUCLEO_STATUS_COLOR[^\n]*=\s*Object\.fromEntries\(\s*\n?\s*Object\.entries\(SELECTION_STATUS_TONE\)/,
    'NUCLEO_STATUS_COLOR derived from SELECTION_STATUS_TONE');
  assert.match(VEP, /VEP_STATUS_COLOR[^\n]*=\s*Object\.fromEntries\(\s*\n?\s*Object\.entries\(VEP_STATUS_TONE\)/,
    'VEP_STATUS_COLOR derived from VEP_STATUS_TONE');
  // no local per-status colour map survived (the diverged status keys are gone)
  for (const key of ['final_eval', 'interview_pending', 'objective_eval']) {
    assert.ok(!VEP.includes(`${key}:`), `VepReconciliationIsland must not redefine status "${key}" locally`);
  }
});

test('P2: selection.astro derives STATUS_BADGE + STATUS_GROUPS colours from the SSOT', () => {
  assert.match(SEL, /from '\.\.\/\.\.\/lib\/statusFarol'/, 'imports statusFarol');
  assert.match(SEL, /STATUS_BADGE[^\n]*=\s*Object\.fromEntries\(\s*\n?\s*Object\.entries\(SELECTION_STATUS_TONE\)/,
    'STATUS_BADGE derived from SELECTION_STATUS_TONE');
  assert.match(SEL, /badge\(GROUP_TONE\.submitted\)/, 'STATUS_GROUPS colours derived from GROUP_TONE');
  // no local hardcoded per-status badge literal survived
  assert.ok(!/final_eval:\s*\{\s*color:/.test(SEL), 'selection.astro must not hardcode final_eval badge colour');
  assert.ok(!/screening:\s*\{\s*color:/.test(SEL), 'selection.astro must not hardcode screening badge colour');
});

test('P2: AffiliationQueueIsland derives farol/term/VEP/cohort from the SSOT', () => {
  assert.match(AFF, /from '\.\.\/\.\.\/lib\/statusFarol'/, 'imports statusFarol');
  assert.match(AFF, /validityFarol\(key\)/, 'farol() derives emoji+cls from validityFarol');
  assert.match(AFF, /validityFarol\(status\)/, 'termMeta() derives from validityFarol');
  assert.match(AFF, /Object\.entries\(VEP_STATUS_TONE\)/, 'VEP_CLS derived from VEP_STATUS_TONE');
  assert.match(AFF, /COHORT_TONE\[cls\]/, 'cohortMeta() derives from COHORT_TONE');
  // the old rose farol shade is gone (unified to the shared negative tone)
  assert.ok(!AFF.includes('bg-rose-50'), 'AffiliationQueueIsland must not keep the old bg-rose-50 farol literal');
});

// ── P3 — the diverged pair is actually unified ───────────────────────────────
test('P3: final_eval has one canonical tone (decision), no purple/indigo split', () => {
  assert.match(MOD, /final_eval:\s*'decision'/, 'final_eval canonical tone = decision');
  // purple was the diverged VepReconciliation value; it must not resurface as a status colour
  assert.ok(!/final_eval[^\n]*purple/.test(VEP), 'final_eval must not map to purple anywhere');
});
