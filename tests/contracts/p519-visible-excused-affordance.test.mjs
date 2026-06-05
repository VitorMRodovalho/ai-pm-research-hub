/**
 * #519 contract test — attendance meeting grid exposes a VISIBLE excused affordance.
 *
 * Gap: the excused ("Falta justificada") + optional-reason capability existed but was
 *   reachable ONLY via a hidden 300ms long-press, so PMs saw just Presente/Ausente and
 *   the feature read as missing. PM decision 2026-06-05 = add a visible per-cell affordance
 *   that opens the existing modal.
 *
 * Fix: a small always-visible ⋮ button (data-excuse-affordance) on every manageable cell
 *   opens the SAME setExcusedModal (Presente / Ausente / Falta justificada + motivo). No
 *   backend change — mark_member_excused already accepts p_reason.
 *
 * Static-only: the grid is a client React island; assert the affordance + the click
 *   interception + the help-banner mention against the source.
 *
 * Cross-ref: #519.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const FILE = resolve(process.cwd(), 'src/components/attendance/AttendanceGridTab.tsx');
const src = readFileSync(FILE, 'utf8');

test('#519: the visible excuse affordance is rendered across the cell layouts', () => {
  const refs = src.match(/data-excuse-affordance/g) || [];
  // 3 cell render layouts + 1 click-handler interception = >=4 references
  assert.ok(refs.length >= 4,
    `expected data-excuse-affordance in all 3 cell layouts + the handler (>=4), found ${refs.length}`);
});

test('#519: clicking the affordance opens the excused modal (not the present/absent toggle)', () => {
  const anchor = "closest('[data-excuse-affordance]')";
  assert.ok(src.includes(anchor), 'click handler must detect the affordance via closest()');
  const slice = src.slice(src.indexOf(anchor), src.indexOf(anchor) + 700);
  assert.match(slice, /setExcusedModal\(/, 'affordance click must open setExcusedModal');
  assert.match(slice, /setReasonDraft\(/, 'affordance click must prime the reason draft for the cell');
});

test('#519: help banner advertises the visible ⋮ affordance', () => {
  assert.match(src, /attendance\.helpExcuse/, 'help banner should reference the visible excuse affordance');
});
