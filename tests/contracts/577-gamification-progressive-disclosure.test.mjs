/**
 * Contract: #577 — gamification cockpit progressive disclosure (toggle).
 *
 * Frontend-only follow-up to #425 (PR #575). The summary table had 16 columns;
 * the 7 raw-pillar POINT columns competed with the high-signal columns for scan
 * attention. PM decision (toggle middle-ground, NOT full removal): default to a
 * 9-column COMPACT view; a "show points breakdown" toggle reveals the 7 point
 * columns INLINE. No RPC change, no data loss (toggle = visibility only).
 *
 * Why a toggle and not full removal: the per-member drill-down (MemberDrillDown)
 * does NOT render 6 of the 7 pillar point values today (only champions_points
 * appears, in the Recognition StatCard) — a full column removal would have lost
 * those values. The toggle keeps them one click away inline in both states.
 *
 * This is a static source contract (no DB): it locks the toggle wiring, the
 * column gating, the colSpan-follows-width invariant, and 3-dict i18n parity.
 *
 * Cross-ref: issue #577; PR #575 (#425 cockpit); docs/council/decisions/2026-06-08-577-gamification-progressive-disclosure.md
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const TSX = resolve(ROOT, 'src/components/tribes/TribeGamificationTab.tsx');
const tsx = existsSync(TSX) ? readFileSync(TSX, 'utf8') : '';

// The 7 raw-pillar POINT columns that move behind the toggle.
const GATED_PILLARS = [
  'attendance_points', 'cert_points', 'badge_points',
  'learning_points', 'producao_points', 'curadoria_points', 'champions_points',
];
// Columns that STAY visible in the COMPACT (default) view — high-signal, not point pillars.
const ALWAYS_ON_SORTKEYS = ['total_points', 'cycle_points', 'current_streak', 'attendance_rate', 'name'];

test('577 static: TribeGamificationTab.tsx exists', () => {
  assert.ok(existsSync(TSX), 'component file present');
});

test('577 static: showBreakdown state defaults to collapsed (false)', () => {
  assert.match(tsx, /const \[showBreakdown, setShowBreakdown\] = useState\(false\)/,
    'showBreakdown state declared, default false (COMPACT by default)');
});

test('577 static: toggle button is wired + accessible', () => {
  assert.match(tsx, /onClick=\{toggleBreakdown\}/, 'toggle uses the toggleBreakdown handler');
  assert.match(tsx, /const toggleBreakdown = \(\) =>/, 'toggleBreakdown handler defined');
  assert.match(tsx, /aria-pressed=\{showBreakdown\}/, 'aria-pressed reflects toggle state');
  assert.match(tsx, /aria-controls="gamif-members-table"/, 'aria-controls points at the table');
  assert.match(tsx, /id="gamif-members-table"/, 'the controlled table carries the matching id');
  // label switches between the two i18n keys
  assert.match(tsx, /comp\.gamification\.hideBreakdown/, 'hide label key used');
  assert.match(tsx, /comp\.gamification\.showBreakdown/, 'show label key used');
});

test('577 static: collapsing the breakdown resets an orphan pillar sort (council HIGH)', () => {
  // BREAKDOWN_SORT_KEYS lists the 7 hidden-column sort keys; toggleBreakdown resets
  // to total_points when collapsing while sorted by one of them.
  assert.match(tsx, /const BREAKDOWN_SORT_KEYS: SortKey\[\] = \[/, 'BREAKDOWN_SORT_KEYS constant defined');
  for (const p of GATED_PILLARS) {
    assert.ok(tsx.includes(`'${p}'`), `BREAKDOWN_SORT_KEYS includes ${p}`);
  }
  assert.match(tsx, /BREAKDOWN_SORT_KEYS\.includes\(sortKey\)/, 'toggle checks current sort against hidden keys');
  assert.match(tsx, /setSortKey\('total_points'\)/, 'orphan sort resets to total_points on collapse');
});

test('577 static: table has an accessible name (council WCAG 1.3.1)', () => {
  assert.match(tsx, /id="gamif-members-table-label"/, 'the h3 carries the label id');
  assert.match(tsx, /aria-labelledby="gamif-members-table-label"/, 'the table is labelled by the h3');
});

test('577 static: the 7 raw-pillar point columns are gated behind showBreakdown', () => {
  // At least 4 conditional blocks: header (2 — split by the always-on Pres.% column) + body (2).
  const blocks = (tsx.match(/\{showBreakdown && \(/g) || []).length;
  assert.ok(blocks >= 4, `expected >=4 {showBreakdown && (} gates (2 header + 2 body), found ${blocks}`);
  // Each gated pillar sortKey appears (header) — they are not deleted, just gated.
  for (const p of GATED_PILLARS) {
    assert.ok(tsx.includes(`sortKey="${p}"`) || tsx.includes(`m.${p}`),
      `pillar ${p} still rendered (gated, not removed)`);
  }
});

test('577 static: high-signal columns stay visible (Pres.%, CPMAI, Trilha not gated)', () => {
  // attendance_rate (Pres. %) must sit BETWEEN the two gated header blocks — i.e. it is
  // present but its <Th> is NOT inside a showBreakdown wrapper. Structural proxy: the
  // Pres.% header line is immediately followed by a `{showBreakdown && (` opener.
  assert.match(
    tsx,
    /sortKey="attendance_rate"[^\n]*\/>\s*\n\s*\{showBreakdown && \(/,
    'Pres. % header stays out of the gate (gated cert-block opens right after it)',
  );
  // CPMAI + Trilha headers exist outside any gate (they trail the second gated block).
  assert.match(tsx, /<Th label="CPMAI" \/>/, 'CPMAI column header present (always-on)');
  assert.match(tsx, /comp\.gamification\.trail'/, 'Trilha column header present (always-on)');
});

test('577 static: colSpan follows the active table width (no stale TABLE_COLS)', () => {
  assert.match(tsx, /const TABLE_COLS_FULL = 16;/, 'FULL width constant');
  assert.match(tsx, /const TABLE_COLS_COMPACT = 9;/, 'COMPACT width constant');
  assert.match(tsx, /const visibleCols = showBreakdown \? TABLE_COLS_FULL : TABLE_COLS_COMPACT;/,
    'visibleCols derives from the toggle');
  // both colSpans use the dynamic width, not the removed module const
  assert.ok(!/colSpan=\{TABLE_COLS\}/.test(tsx), 'old static colSpan={TABLE_COLS} fully replaced');
  assert.equal((tsx.match(/colSpan=\{visibleCols\}/g) || []).length, 2,
    'both drill-down + empty-state rows span the active width');
});

test('577 invariant: FULL = COMPACT + the 7 gated pillars (column arithmetic)', () => {
  const full = Number((tsx.match(/const TABLE_COLS_FULL = (\d+);/) || [])[1]);
  const compact = Number((tsx.match(/const TABLE_COLS_COMPACT = (\d+);/) || [])[1]);
  assert.equal(full - compact, GATED_PILLARS.length,
    `FULL(${full}) - COMPACT(${compact}) must equal the ${GATED_PILLARS.length} gated pillar columns`);
});

test('577 static: per-row drill-down a11y is untouched (regression lock)', () => {
  assert.match(tsx, /aria-expanded=\{isOpen\}/, 'row expand control keeps aria-expanded');
  assert.match(tsx, /MemberDrillDown/, 'drill-down component still wired');
});

test('577 static: MemberDrillDown section headers use semantic h4 elements', () => {
  const drill = tsx.slice(tsx.indexOf('function MemberDrillDown'));
  assert.match(drill, /<h4 className="text-sm font-bold text-navy m-0">/,
    'drill-down title is a semantic heading');
  for (const key of ['coachingSignals', 'trailBreakdown', 'xpByPillar', 'recognition']) {
    assert.ok(drill.includes(`<h4 className="text-[.72rem] font-bold uppercase tracking-wide text-[var(--text-secondary)] m-0 mb-2">\n          {t('comp.gamification.${key}'`),
      `${key} section header is a semantic h4`);
  }
});

test('577 static: i18n 3-dict parity for the toggle + gated-column keys', () => {
  // the 2 new toggle keys + the 7 pillar column-header keys that the toggle reveals
  // (the latter pre-date #577 but are now load-bearing for the breakdown view).
  const KEYS = [
    'showBreakdown', 'hideBreakdown',
    'attendanceCol', 'certsCol', 'badgesCol', 'learningCol', 'producaoCol', 'curadoriaCol', 'championsCol',
  ];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const txt = readFileSync(resolve(ROOT, `src/i18n/${dict}.ts`), 'utf8');
    for (const k of KEYS) {
      assert.match(txt, new RegExp(`'comp\\.gamification\\.${k}':`), `${dict} has comp.gamification.${k}`);
    }
  }
});

// belt-and-suspenders: ALWAYS_ON_SORTKEYS referenced so the list is not dead.
test('577 static: high-signal sort keys still wired', () => {
  for (const k of ALWAYS_ON_SORTKEYS) {
    assert.ok(tsx.includes(`sortKey="${k}"`), `always-on sort key ${k} present`);
  }
});
