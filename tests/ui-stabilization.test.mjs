import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = '/home/vitormrodovalho/Desktop/ai-pm-research-hub';

function read(relativePath) {
  return readFileSync(resolve(ROOT, relativePath), 'utf8');
}

test('profile uses delegated credly normalization instead of per-render rebind helper', () => {
  const content = read('src/pages/profile.astro');
  assert.equal(content.includes('bindCredlyField('), false);
  assert.equal(content.includes("target.id === 'self-credly'"), true);
});

test('selection page no longer hardcodes cycle tabs or snapshot cycle title', () => {
  const content = read('src/pages/admin/selection.astro');
  assert.equal(content.includes('data-cycle="3"'), false);
  assert.equal(content.includes('Comparação de Snapshots — Ciclo 3'), false);
  assert.equal(content.includes('loadSelectionCycles()'), true);
});

test('confirm dialog no longer mutates confirm button onclick directly', () => {
  const content = read('src/components/ui/ConfirmDialog.astro');
  assert.equal(content.includes('btn.onclick ='), false);
  assert.equal(content.includes("document.getElementById('confirm-btn')?.addEventListener('click'"), true);
});

test('schedule flow no longer depends on far-future deadline sentinel', () => {
  const scheduleContent = read('src/lib/schedule.ts');
  const tribesContent = read('src/components/sections/TribesSection.astro');
  const heroContent = read('src/components/sections/HeroSection.astro');
  assert.equal(scheduleContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(tribesContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(heroContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(tribesContent.includes('selectionUnavailable'), true);
});

test('tribes section touched links no longer use inline onclick handlers', () => {
  const content = read('src/components/sections/TribesSection.astro');
  assert.equal(content.includes('onclick='), false);
  assert.equal(content.includes('data-stop-propagation'), true);
});
