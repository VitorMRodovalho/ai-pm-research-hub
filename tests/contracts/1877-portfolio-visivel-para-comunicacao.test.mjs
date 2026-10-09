// tests/contracts/1877-portfolio-visivel-para-comunicacao.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
// (Hermetic: reads two source files.)
/**
 * #1877 — the communication team sees /admin/portfolio, through BOTH lists that decide it.
 *
 * Measured 2026-10-08: 0 of the 6 active members of the Hub de Comunicacao could open /admin/portfolio. All six are
 * `researcher` with the `comms_member` or `comms_leader` designation, and neither designation held `admin.portfolio`.
 * The data was never the barrier: the page RPCs (get_portfolio_dashboard, get_portfolio_planned_vs_actual,
 * exec_portfolio_board_summary) returned to a comms member exactly what they return to the GP.
 *
 * Two lists decide this page and they had ALREADY diverged (curator and chapter_board in the menu but without the page
 * permission; tribe_leader with the page permission but without the menu entry). So this guard binds the two for the
 * comms designations: a menu entry without the permission is a link to "access denied", and a permission without the
 * menu entry is an access nobody finds.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PERMS = readFileSync(resolve(ROOT, 'src/lib/permissions.ts'), 'utf8');
const NAV = readFileSync(resolve(ROOT, 'src/lib/navigation.config.ts'), 'utf8');
const COMMS = ['comms_member', 'comms_leader'];

function designationBlock(key) {
  const start = PERMS.indexOf('DESIGNATION_PERMISSIONS');
  assert.ok(start > 0, 'DESIGNATION_PERMISSIONS not found');
  const end = PERMS.indexOf('\n};', start);
  const m = PERMS.slice(start, end).match(new RegExp(`\\n  ${key}: \\[([\\s\\S]*?)\\]`));
  assert.ok(m, `designation ${key} not found in DESIGNATION_PERMISSIONS`);
  return m[1];
}

function portfolioNavEntry() {
  const line = NAV.split('\n').find((l) => /key:\s*'admin-portfolio'/.test(l));
  assert.ok(line, "navigation entry 'admin-portfolio' not found");
  const m = line.match(/allowedDesignations:\s*\[([^\]]*)\]/);
  assert.ok(m, 'admin-portfolio has no allowedDesignations');
  return m[1];
}

test('#1877: each comms designation holds admin.portfolio (the page gate)', () => {
  for (const d of COMMS) {
    assert.match(designationBlock(d), /'admin\.portfolio'/, `${d} must hold admin.portfolio`);
  }
});

test('#1877: each comms designation is in the admin-portfolio menu entry (the way to find it)', () => {
  const allowed = portfolioNavEntry();
  for (const d of COMMS) {
    assert.match(allowed, new RegExp(`'${d}'`), `${d} must be in admin-portfolio allowedDesignations`);
  }
});
