import { describe, it, expect } from 'vitest';
import { pickCohortCycleByContractStart, type CycleWindow } from './db';

/**
 * #1316 — the Núcleo contract start (serviceStartDateUTC, scoped to the
 * opportunity) is the SSOT determinant of an approved app's cohort cycle.
 * Rule: the cycle whose application window OPENED most recently on or before
 * the contract start. Validated live against prod 2026-07-13: the rule matches
 * the current cycle_id of all 82 in-db approved apps (49 cycle4 + 32 cycle3 +
 * 1 b2), 0 mismatches. This unit test locks the pure function that mirrors the
 * DB SSOT public.nucleo_contract_cohort_cycle_id(date).
 */

// Live selection_cycles windows (prod, 2026-07-13) after #1316 paving.
const CYCLES: CycleWindow[] = [
  { id: 'c3', cycle_code: 'cycle3-2026', status: 'closed', open_date: '2025-12-01', close_date: '2026-03-27' },
  { id: 'b2', cycle_code: 'cycle3-2026-b2', status: 'closed', open_date: '2026-03-28', close_date: '2026-05-14' },
  { id: 'c4', cycle_code: 'cycle4-2026', status: 'open', open_date: '2026-05-15', close_date: null },
];

describe('#1316 pickCohortCycleByContractStart', () => {
  it('maps S1 contract start (2026-01-20) to cycle3', () => {
    expect(pickCohortCycleByContractStart('2026-01-20', CYCLES)?.cycle_code).toBe('cycle3-2026');
  });

  it('maps S2 contract start (2026-07-01) to cycle4, even though it is AFTER cycle4 close', () => {
    // Contract starts after the application window closed — window containment
    // would fail; the "greatest open_date <= start" rule still resolves cycle4.
    expect(pickCohortCycleByContractStart('2026-07-01', CYCLES)?.cycle_code).toBe('cycle4-2026');
  });

  it('maps a mid-window contract start (2026-04-01) to b2', () => {
    expect(pickCohortCycleByContractStart('2026-04-01', CYCLES)?.cycle_code).toBe('cycle3-2026-b2');
  });

  it('returns null for a pre-cycle3 legacy 2025 contract (#1284 territory)', () => {
    expect(pickCohortCycleByContractStart('2025-08-22', CYCLES)).toBeNull();
  });

  it('returns null when no contract start (rejected/pending — caller uses temporal lens)', () => {
    expect(pickCohortCycleByContractStart(null, CYCLES)).toBeNull();
    expect(pickCohortCycleByContractStart(undefined, CYCLES)).toBeNull();
  });

  it('normalizes an ISO timestamp to date-only before comparing', () => {
    expect(pickCohortCycleByContractStart('2026-07-01T00:00:00.000Z', CYCLES)?.cycle_code).toBe('cycle4-2026');
  });

  it('returns null on an empty cycle list', () => {
    expect(pickCohortCycleByContractStart('2026-01-20', [])).toBeNull();
  });
});
