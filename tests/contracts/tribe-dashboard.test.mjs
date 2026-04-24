/**
 * W117 Contract Test: Tribe Analytics Dashboard
 * Static analysis of migration SQL to verify:
 * - exec_tribe_dashboard RPC exists with correct signature
 * - exec_all_tribes_summary RPC exists
 * - Both are SECURITY DEFINER with GRANT EXECUTE
 * - Permission checks: tribe_leader, GP/DM, sponsor, superadmin
 * - Returns all required sections: tribe, members, production, engagement, gamification, trends
 * - Attendance rate calculation
 * - Inactive member detection (30d threshold)
 * - Gamification XP sums
 * - Trend grouping by month
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');

function findFunctionBody(funcName) {
  // Supports any dollar-quoted tag: $$, $function$, $BODY$, $func$, etc.
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

// ─── RPC existence + SECURITY DEFINER ───

const TRIBE_RPCS = ['exec_tribe_dashboard', 'exec_all_tribes_summary'];

for (const rpcName of TRIBE_RPCS) {
  test(`RPC ${rpcName} exists in migrations`, () => {
    const body = findFunctionBody(rpcName);
    assert.ok(body, `RPC ${rpcName} not found in migrations`);
  });

  test(`RPC ${rpcName} is SECURITY DEFINER`, () => {
    const pattern = new RegExp(`${rpcName}[\\s\\S]*?SECURITY\\s+DEFINER`, 'i');
    assert.ok(pattern.test(allSQL), `RPC ${rpcName} must be SECURITY DEFINER`);
  });

  test(`RPC ${rpcName} has GRANT EXECUTE to authenticated`, () => {
    const pattern = new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+(?:public\\.)?${rpcName}`, 'i');
    assert.ok(pattern.test(allSQL), `RPC ${rpcName} must GRANT EXECUTE to authenticated`);
  });
}

// ─── exec_tribe_dashboard ───

test('exec_tribe_dashboard accepts p_tribe_id int parameter', () => {
  const pattern = /exec_tribe_dashboard\s*\(\s*p_tribe_id\s+int/i;
  assert.ok(pattern.test(allSQL), 'Must accept p_tribe_id int');
});

test('exec_tribe_dashboard checks auth via auth.uid()', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/auth\.uid\(\)/i.test(body), 'Must use auth.uid()');
});

// ─── Permission checks ───

test('exec_tribe_dashboard allows tribe_leader for own tribe', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/tribe_leader/i.test(body), 'Must check tribe_leader role');
  assert.ok(/v_caller.*tribe_id\s*=\s*p_tribe_id/i.test(body), 'Must verify tribe_id match');
});

test('exec_tribe_dashboard allows manager and deputy_manager', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/manager/i.test(body), 'Must allow manager');
  assert.ok(/deputy_manager/i.test(body), 'Must allow deputy_manager');
});

test('exec_tribe_dashboard allows superadmin', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/is_superadmin/i.test(body), 'Must check is_superadmin');
});

test('exec_tribe_dashboard allows sponsor/chapter_liaison for chapter tribes', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/sponsor/i.test(body), 'Must check sponsor');
  assert.ok(/chapter_liaison/i.test(body), 'Must check chapter_liaison');
  assert.ok(/designations/i.test(body), 'Must check designations array');
});

test('exec_tribe_dashboard raises exception for unauthorized access', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/RAISE\s+EXCEPTION\s+.*Unauthorized/i.test(body), 'Must raise Unauthorized exception');
});

// ─── Return structure — tribe section ───

test('exec_tribe_dashboard returns tribe info', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/'tribe'/i.test(body), 'Must return tribe section');
  assert.ok(/v_tribe\.name/i.test(body), 'Must include tribe name');
  assert.ok(/quadrant/i.test(body), 'Must include quadrant');
  assert.ok(/quadrant_name/i.test(body), 'Must include quadrant_name');
  assert.ok(/leader/i.test(body), 'Must include leader info');
  assert.ok(/meeting_slots/i.test(body), 'Must include meeting_slots');
  assert.ok(/whatsapp_url/i.test(body), 'Must include whatsapp_url');
  assert.ok(/drive_url/i.test(body), 'Must include drive_url');
});

// ─── Return structure — members section ───

test('exec_tribe_dashboard returns members section', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/'members'/i.test(body), 'Must return members section');
  assert.ok(/v_members_total/i.test(body), 'Must include total count');
  assert.ok(/v_members_active/i.test(body), 'Must include active count');
  assert.ok(/by_role/i.test(body), 'Must include by_role breakdown');
  assert.ok(/by_chapter/i.test(body), 'Must include by_chapter breakdown');
});

test('exec_tribe_dashboard members list includes xp and attendance', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/xp_total/i.test(body), 'Must include xp_total per member');
  assert.ok(/attendance_rate/i.test(body), 'Must include attendance_rate per member');
});

// ─── Return structure — production section ───

test('exec_tribe_dashboard returns production section', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/'production'/i.test(body), 'Must return production section');
  assert.ok(/total_cards/i.test(body), 'Must include total_cards');
  assert.ok(/by_status/i.test(body), 'Must include by_status breakdown');
  assert.ok(/articles_submitted/i.test(body), 'Must include articles_submitted');
  assert.ok(/articles_approved/i.test(body), 'Must include articles_approved');
  assert.ok(/curation_pending/i.test(body), 'Must include curation_pending');
});

test('exec_tribe_dashboard production queries board_items via project_boards', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/project_boards/i.test(body), 'Must join with project_boards');
  assert.ok(/board_items/i.test(body), 'Must query board_items');
  assert.ok(/domain_key\s*=\s*'research_delivery'/i.test(body), 'Must filter research_delivery board');
});

// ─── Return structure — engagement section ───

test('exec_tribe_dashboard returns engagement section', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/'engagement'/i.test(body), 'Must return engagement section');
  assert.ok(/attendance_rate/i.test(body), 'Must include attendance_rate');
  assert.ok(/total_meetings/i.test(body), 'Must include total_meetings');
  assert.ok(/total_hours/i.test(body), 'Must include total_hours');
  assert.ok(/avg_attendance/i.test(body), 'Must include avg_attendance');
});

test('exec_tribe_dashboard calculates attendance from events and attendance tables', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/attendance\s+a/i.test(body), 'Must query attendance table');
  assert.ok(/events\s+e/i.test(body), 'Must query events table');
  assert.ok(/e\.tribe_id\s*=\s*p_tribe_id/i.test(body), 'Must filter by tribe_id');
  assert.ok(/a\.present\s*=\s*true/i.test(body), 'Must check present = true');
});

test('exec_tribe_dashboard detects inactive members (30d threshold)', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/members_inactive_30d/i.test(body), 'Must compute members_inactive_30d');
  assert.ok(/30\s*days/i.test(body), 'Must use 30 days threshold');
});

// ─── Return structure — gamification section ───

test('exec_tribe_dashboard returns gamification section', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/'gamification'/i.test(body), 'Must return gamification section');
  assert.ok(/tribe_total_xp/i.test(body), 'Must include tribe_total_xp');
  assert.ok(/tribe_avg_xp/i.test(body), 'Must include tribe_avg_xp');
  assert.ok(/top_contributors/i.test(body), 'Must include top_contributors');
});

test('exec_tribe_dashboard gamification sums from gamification_points', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/gamification_points/i.test(body), 'Must query gamification_points table');
  assert.ok(/SUM\s*\(\s*(?:gp\.)?points\s*\)/i.test(body), 'Must SUM(points)');
});

test('exec_tribe_dashboard includes CPMAI certification count', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/cpmai_certified/i.test(body), 'Must count cpmai_certified');
});

// ─── Return structure — trends section ───

test('exec_tribe_dashboard returns trends section', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/'trends'/i.test(body), 'Must return trends section');
  assert.ok(/attendance_by_month/i.test(body), 'Must include attendance_by_month');
  assert.ok(/production_by_month/i.test(body), 'Must include production_by_month');
});

test('exec_tribe_dashboard trends group by month', () => {
  const body = findFunctionBody('exec_tribe_dashboard');
  assert.ok(/TO_CHAR\s*\([^)]*'YYYY-MM'\s*\)/i.test(body), 'Must group by YYYY-MM format');
});

// ─── exec_all_tribes_summary ───

test('exec_all_tribes_summary requires GP/DM/superadmin', () => {
  const body = findFunctionBody('exec_all_tribes_summary');
  assert.ok(/is_superadmin/i.test(body), 'Must check is_superadmin');
  assert.ok(/manager/i.test(body), 'Must check manager');
  assert.ok(/deputy_manager/i.test(body), 'Must check deputy_manager');
});

test('exec_all_tribes_summary returns tribe summary array', () => {
  const body = findFunctionBody('exec_all_tribes_summary');
  assert.ok(/tribe_id/i.test(body), 'Must include tribe_id');
  assert.ok(/member_count/i.test(body), 'Must include member_count');
  assert.ok(/attendance_rate/i.test(body), 'Must include attendance_rate');
  assert.ok(/articles_count/i.test(body), 'Must include articles_count');
  assert.ok(/xp_total/i.test(body), 'Must include xp_total');
  assert.ok(/leader_name/i.test(body), 'Must include leader_name');
});

test('exec_all_tribes_summary filters active research tribes', () => {
  const body = findFunctionBody('exec_all_tribes_summary');
  assert.ok(/is_active\s*=\s*true/i.test(body), 'Must filter active tribes');
  assert.ok(/workstream_type\s*=\s*'research'/i.test(body), 'Must filter research workstream');
});

// ─── UI contract: page + island exist ───

test('Tribe dashboard page exists at admin/tribe/[id].astro', () => {
  const page = resolve(ROOT, 'src/pages/admin/tribe/[id].astro');
  assert.ok(existsSync(page), 'admin/tribe/[id].astro must exist');
});

test('TribeDashboardIsland component exists', () => {
  const comp = resolve(ROOT, 'src/components/islands/TribeDashboardIsland.tsx');
  assert.ok(existsSync(comp), 'TribeDashboardIsland.tsx must exist');
});

// ─── Navigation contract ───

test('AdminNav includes tribe-dashboard link', () => {
  const nav = readFileSync(resolve(ROOT, 'src/components/nav/AdminNav.astro'), 'utf8');
  assert.ok(/tribe-dashboard/i.test(nav), 'AdminNav must include tribe-dashboard key');
  assert.ok(/adminTribeDashboard/i.test(nav), 'AdminNav must reference adminTribeDashboard label');
});

test('navigation.config.ts includes admin-tribe-dashboard', () => {
  const config = readFileSync(resolve(ROOT, 'src/lib/navigation.config.ts'), 'utf8');
  assert.ok(/admin-tribe-dashboard/i.test(config), 'navigation.config must include admin-tribe-dashboard');
});

// ─── Workspace tribe leader card ───

test('Workspace shows dashboard link for tribe leaders', () => {
  const workspace = readFileSync(resolve(ROOT, 'src/pages/workspace.astro'), 'utf8');
  assert.ok(/tribeDashboard/i.test(workspace), 'Workspace must reference tribeDashboard');
  assert.ok(/admin\/tribe/i.test(workspace), 'Workspace must link to /admin/tribe/');
  assert.ok(/isLeader/i.test(workspace), 'Workspace must check isLeader for dashboard link');
});
