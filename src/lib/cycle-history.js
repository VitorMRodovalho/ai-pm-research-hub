const CYCLE_LABELS = {
  pilot: 'Piloto 2024',
  cycle_1: 'Ciclo 1',
  cycle_2: 'Ciclo 2',
  cycle_3: 'Ciclo 3',
};

function dateScore(value, fallback) {
  if (!value) return fallback;
  const time = new Date(value).getTime();
  return Number.isNaN(time) ? fallback : time;
}

function recordScore(record) {
  return dateScore(record?.cycle_start, 0);
}

export function normalizeMemberCycleHistory(records) {
  const list = Array.isArray(records) ? records : [];
  const byCode = new Map();

  for (const record of list) {
    const code = record?.cycle_code || '';
    if (!code) continue;
    const existing = byCode.get(code);
    if (!existing) {
      byCode.set(code, record);
      continue;
    }

    const existingActive = !!existing.is_active;
    const nextActive = !!record.is_active;
    if (nextActive && !existingActive) {
      byCode.set(code, record);
      continue;
    }
    if (nextActive === existingActive && recordScore(record) > recordScore(existing)) {
      byCode.set(code, record);
    }
  }

  return [...byCode.values()]
    .map((record) => ({
      ...record,
      cycle_label: record.cycle_label || CYCLE_LABELS[record.cycle_code] || record.cycle_code,
    }))
    .sort((a, b) => recordScore(a) - recordScore(b));
}

export function uniqueSortedCycleCodes(records) {
  return normalizeMemberCycleHistory(records)
    .map((record) => record.cycle_code)
    .filter(Boolean);
}
