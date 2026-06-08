/**
 * Contract: #592 + #591a — gamification cockpit polish (frontend-only).
 *
 * Closes the #425/#577 cockpit arc with three changes to TribeGamificationTab.tsx:
 *
 *   #592 (a11y, LOW):
 *     - Per-row expand button + sortable <Th> headers get the forced-colors focus
 *       fallback ring (Windows High Contrast strips box-shadow → focus:ring is
 *       invisible). Mirrors the #577 toggle button. The headers are keyboard-
 *       focusable (tabIndex 0), so they need it too — same defect class.
 *     - aria-controls on the expand button is now conditional on isOpen, because
 *       the drill-down panel (gamif-detail-*) is only in the DOM while open; a
 *       dangling aria-controls makes some screen readers announce a missing target.
 *
 *   #591a (lossless full-collapse enabler):
 *     - MemberDrillDown gains an "XP por pilar" section rendering ALL 7 raw-pillar
 *       point values. Before, only champions_points appeared (in Recognition); the
 *       other 6 (attendance/cert/badge/learning/producao/curadoria) lived ONLY in
 *       the summary-table columns the #577 toggle hides. Surfacing all 7 in the
 *       drill-down makes a future full column-removal lossless. Reuses the
 *       pie-chart pillar labels + StatCard (one new label key: xpByPillar).
 *
 *   #591b enabler (NOT persistence — that stays deferred):
 *     - toggleBreakdown captures gamification_breakdown_toggled so a future session
 *       can measure the expand-on-landing cohort that gates persistence. The toggle
 *       had 0 interactions in the trailing 30d (PostHog, 2026-06-08), so there is no
 *       cohort to gate on yet — persistence is intentionally NOT shipped here.
 *
 * Static source contract (no DB): locks the a11y wiring, the 7-pillar breakdown,
 * the toggle instrumentation, and 3-dict i18n parity for the one new key.
 *
 * Cross-ref: issues #592, #591; #425 (PR #575) cockpit; #577 (PR #590) toggle;
 *   docs/council/decisions/2026-06-08-577-gamification-progressive-disclosure.md
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const TSX = resolve(ROOT, 'src/components/tribes/TribeGamificationTab.tsx');
const tsx = existsSync(TSX) ? readFileSync(TSX, 'utf8') : '';

// The 7 raw-pillar point values that must ALL be reachable in the drill-down now.
const PILLAR_VALUES = [
  'attendance_points', 'cert_points', 'badge_points',
  'learning_points', 'producao_points', 'curadoria_points', 'champions_points',
];

test('592/591 static: TribeGamificationTab.tsx exists', () => {
  assert.ok(existsSync(TSX), 'component file present');
});

// ── #592 a11y ──────────────────────────────────────────────────────────────────────
test('592 a11y: aria-controls on the expand button is conditional on isOpen', () => {
  // the drill-down id only renders while open → aria-controls must too
  assert.match(tsx, /aria-controls=\{isOpen \? `gamif-detail-\$\{m\.id\}` : undefined\}/,
    'expand button aria-controls gated on isOpen');
  // the old unconditional form must be gone (would dangle when collapsed)
  assert.ok(!tsx.includes('aria-controls={`gamif-detail-${m.id}`}'),
    'old unconditional aria-controls={`gamif-detail-${m.id}`} fully replaced');
  // the controlled panel still carries the matching id (regression)
  assert.match(tsx, /id=\{`gamif-detail-\$\{member\.id\}`\}/, 'drill-down panel keeps its id');
});

test('592 a11y: forced-colors focus ring on toggle + expand button + sortable headers', () => {
  // the complete pair (outline + outline-2) appears on all three focusable controls
  const rings = (tsx.match(/forced-colors:focus:outline forced-colors:focus:outline-2/g) || []).length;
  assert.ok(rings >= 3,
    `expected >=3 forced-colors rings (toggle + expand + sortable Th), found ${rings}`);
  // council (a11y verifier) fold: outline-offset so the ring does not overlap the
  // element border under forced-colors — applied to all 3 rings.
  assert.equal((tsx.match(/forced-colors:focus:outline-offset-2/g) || []).length, 3,
    'forced-colors:focus:outline-offset-2 on all 3 rings');
  // expand button specifically (the #592 ask) carries it
  assert.match(tsx, /rounded-md px-2 py-1[^\n]*focus:ring-\[#00799E\] forced-colors:focus:outline forced-colors:focus:outline-2/,
    'per-row expand button has the forced-colors ring');
  // sortable header (keyboard-focusable, same defect class) carries it
  assert.match(tsx, /focus:ring-inset focus:ring-\[#00799E\] forced-colors:focus:outline forced-colors:focus:outline-2/,
    'sortable <Th> header has the forced-colors ring');
});

// ── #591a per-pillar breakdown ───────────────────────────────────────────────────────
test('591a static: drill-down renders ALL 7 raw-pillar point values (lossless)', () => {
  // before #591a only member.champions_points appeared in the drill-down; now all 7 do
  for (const p of PILLAR_VALUES) {
    assert.ok(tsx.includes(`member.${p}`),
      `drill-down references member.${p} (XP-por-pilar breakdown)`);
  }
  // section header uses the new i18n key, reuses the pie-chart pillar labels (no new label keys)
  assert.match(tsx, /comp\.gamification\.xpByPillar/, 'XP-por-pilar section header key used');
  for (const k of ['attendance', 'certs', 'badges', 'learning', 'producao', 'curadoria', 'champions']) {
    assert.ok(tsx.includes(`'comp.gamification.${k}'`),
      `breakdown reuses pie-chart label comp.gamification.${k}`);
  }
  // reuses StatCard via a keyed <Fragment> — StatCard is a plain function that
  // does NOT forward a React key, so a bare key={…} on it is a TS2322. Locking the
  // Fragment pattern prevents regressing to the type error.
  assert.match(tsx, /<Fragment key=\{labelKey\}>\s*<StatCard label=\{t\(labelKey, fallback\)\} value=\{String\(value \?\? 0\)\} \/>/,
    'each pillar renders through StatCard inside a keyed Fragment (TS2322-safe)');
  assert.ok(!/<StatCard key=/.test(tsx), 'no bare key={…} directly on StatCard (would be TS2322)');
});

test('591a static: XP-por-pilar sits AFTER the trail/coaching narrative, before Recognition', () => {
  // council (ux-leader) fold: keep the behavioural cluster (signals) adjacent to
  // the learning cluster (trail); the raw XP decomposition follows, then credentials.
  const drill = tsx.slice(tsx.indexOf('function MemberDrillDown'));
  const byPillar = drill.indexOf('comp.gamification.xpByPillar');
  const trail = drill.indexOf('comp.gamification.trailBreakdown');
  const recognition = drill.indexOf('comp.gamification.recognition');
  assert.ok(byPillar > 0, 'XP-por-pilar section lives in MemberDrillDown');
  assert.ok(trail < byPillar, 'XP-por-pilar renders AFTER the trail breakdown');
  assert.ok(byPillar < recognition, 'XP-por-pilar renders before Recognition');
});

test('591a static: champions_points has a single home in the drill-down (council dedup)', () => {
  // council (4/5 reviewers): champions was rendered twice (XP-por-pilar + Recognition).
  // The Recognition champions StatCard was removed; champions now lives only in
  // XP-por-pilar (its canonical XP-source home). Lock the single occurrence.
  const drill = tsx.slice(tsx.indexOf('function MemberDrillDown'));
  const n = (drill.match(/member\.champions_points/g) || []).length;
  assert.equal(n, 1, `champions_points should render exactly once in the drill-down, found ${n}`);
});

// ── #591b enabler (instrumentation only — persistence deferred) ───────────────────────
test('591b enabler: breakdown toggle is instrumented (best-effort, not persisted)', () => {
  assert.match(tsx, /posthog\?\.capture\?\.\('gamification_breakdown_toggled', \{/,
    'toggle captures gamification_breakdown_toggled');
  assert.match(tsx, /expanded: next/, 'capture carries the expanded flag');
  // council (gp-leader) fold: tribe/initiative context for future cohort segmentation
  assert.match(tsx, /tribe_id: tribeId \?\? null/, 'capture carries tribe context');
  assert.match(tsx, /initiative_id: initiativeId \?\? null/, 'capture carries initiative context');
  // best-effort: analytics must never break the toggle
  assert.match(tsx, /try \{[\s\S]*?gamification_breakdown_toggled[\s\S]*?\} catch/,
    'capture is wrapped in try/catch (analytics is best-effort)');
  // persistence is NOT shipped: no sessionStorage/localStorage read seeds showBreakdown
  assert.match(tsx, /const \[showBreakdown, setShowBreakdown\] = useState\(false\)/,
    'showBreakdown still defaults false in-memory (no persistence shipped)');
  assert.ok(!/sessionStorage\.getItem\(['"]gamif-breakdown/.test(tsx),
    'no sessionStorage seeding of the breakdown (persistence deferred pending cohort)');
});

// ── regression locks (#577 / #425 must not have regressed) ────────────────────────────
test('592/591 regression: #577 toggle wiring + orphan-sort reset intact', () => {
  assert.match(tsx, /const toggleBreakdown = \(\) =>/, 'toggleBreakdown handler present');
  assert.match(tsx, /BREAKDOWN_SORT_KEYS\.includes\(sortKey\)/, 'orphan pillar-sort guard kept');
  assert.match(tsx, /setSortKey\('total_points'\)/, 'orphan sort still resets to total_points');
  assert.match(tsx, /const TABLE_COLS_FULL = 16;/, 'FULL width constant unchanged');
  assert.match(tsx, /const TABLE_COLS_COMPACT = 9;/, 'COMPACT width constant unchanged');
  assert.match(tsx, /aria-expanded=\{isOpen\}/, 'expand control keeps aria-expanded (#425/#577)');
});

// ── i18n 3-dict parity for the one new key ────────────────────────────────────────────
test('592/591 static: i18n 3-dict parity for comp.gamification.xpByPillar', () => {
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const txt = readFileSync(resolve(ROOT, `src/i18n/${dict}.ts`), 'utf8');
    assert.match(txt, /'comp\.gamification\.xpByPillar':/, `${dict} has comp.gamification.xpByPillar`);
  }
});
