import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeMemberCycleHistory, uniqueSortedCycleCodes } from '../src/lib/cycle-history.js';

test('normalizeMemberCycleHistory deduplicates by cycle_code preferring active record', () => {
  const input = [
    { cycle_code: 'cycle_2', cycle_start: '2025-07-01', is_active: false, cycle_label: '' },
    { cycle_code: 'cycle_2', cycle_start: '2025-08-01', is_active: true, cycle_label: '' },
    { cycle_code: 'cycle_1', cycle_start: '2025-01-01', is_active: true, cycle_label: 'C1' },
  ];
  const out = normalizeMemberCycleHistory(input);
  assert.equal(out.length, 2);
  assert.equal(out[1].cycle_code, 'cycle_2');
  assert.equal(out[1].is_active, true);
});

test('normalizeMemberCycleHistory adds fallback labels and sorts by cycle_start', () => {
  const input = [
    { cycle_code: 'cycle_3', cycle_start: '2026-01-01', is_active: true, cycle_label: '' },
    { cycle_code: 'pilot', cycle_start: '2024-03-01', is_active: false, cycle_label: '' },
  ];
  const out = normalizeMemberCycleHistory(input);
  assert.equal(out[0].cycle_code, 'pilot');
  assert.equal(out[0].cycle_label, 'Piloto 2024');
  assert.equal(out[1].cycle_label, 'Ciclo 3');
});

test('uniqueSortedCycleCodes returns deterministic unique code list', () => {
  const input = [
    { cycle_code: 'cycle_2', cycle_start: '2025-07-01', is_active: false },
    { cycle_code: 'cycle_2', cycle_start: '2025-08-01', is_active: true },
    { cycle_code: 'cycle_1', cycle_start: '2025-01-01', is_active: true },
  ];
  assert.deepEqual(uniqueSortedCycleCodes(input), ['cycle_1', 'cycle_2']);
});
