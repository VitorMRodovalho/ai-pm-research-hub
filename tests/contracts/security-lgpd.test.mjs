/**
 * W125 Contract Test: Security & LGPD Hardening
 * Static analysis — reads migration files and verifies security properties.
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
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?\\$(\\w*?)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  if (matches.length === 0) return null;
  return matches[matches.length - 1][2];
}

// ─── P0-A: RLS POLICIES on selection/onboarding tables ───

const RPC_ONLY_TABLES = [
  'selection_cycles',
  'selection_committee',
  'selection_applications',
  'selection_evaluations',
  'selection_interviews',
  'selection_diversity_snapshots',
  'onboarding_progress',
];

for (const table of RPC_ONLY_TABLES) {
  test(`Table ${table} has explicit deny-all RLS policy`, () => {
    const hasPolicy = new RegExp(
      `CREATE\\s+POLICY\\s+.*ON\\s+(?:public\\.)?${table}.*USING\\s*\\(\\s*false\\s*\\)`,
      'i'
    ).test(allSQL);
    assert.ok(hasPolicy, `${table} must have deny-all policy (USING (false))`);
  });
}

// ─── P0-B: SECURITY DEFINER auth fixes ───

// V3 legacy pattern was 'operational_role'; updated 2026-04-17 to V4 'can_by_member'
// after ADR-0015 writers batch B migrated create_event to V4 auth (ADR-0011).
// Spirit preserved: create_event MUST have a role/authority-based auth check.
const AUTH_FIXED_RPCS = [
  { name: 'create_event', shouldCheck: ['Unauthorized', 'can_by_member'] },
  { name: 'mark_member_present', shouldCheck: ['Not authenticated', 'v_caller_id = p_member_id'] },
  { name: 'get_member_attendance_hours', shouldCheck: ['Not authenticated', 'v_caller_id = p_member_id'] },
];

for (const rpc of AUTH_FIXED_RPCS) {
  test(`RPC ${rpc.name} has auth.uid() check`, () => {
    const body = findFunctionBody(rpc.name);
    assert.ok(body, `RPC ${rpc.name} not found`);
    assert.ok(/auth\.uid\(\)/i.test(body), `${rpc.name} must check auth.uid()`);
  });

  test(`RPC ${rpc.name} raises exception on unauthorized`, () => {
    const body = findFunctionBody(rpc.name);
    assert.ok(body);
    assert.ok(
      /RAISE\s+EXCEPTION/i.test(body) || /error.*Unauthorized/i.test(body),
      `${rpc.name} must RAISE EXCEPTION or return error`
    );
  });

  for (const check of rpc.shouldCheck) {
    test(`RPC ${rpc.name} contains check: ${check}`, () => {
      const body = findFunctionBody(rpc.name);
      assert.ok(body);
      assert.ok(body.includes(check), `${rpc.name} must contain: ${check}`);
    });
  }
}

// ─── P1-A: LGPD Data Export ───

test('export_my_data RPC exists and is SECURITY DEFINER', () => {
  const body = findFunctionBody('export_my_data');
  assert.ok(body, 'export_my_data not found');
  const funcDef = allSQL.match(/export_my_data[\s\S]*?SECURITY\s+DEFINER/i);
  assert.ok(funcDef, 'export_my_data must be SECURITY DEFINER');
});

test('export_my_data checks auth.uid()', () => {
  const body = findFunctionBody('export_my_data');
  assert.ok(body);
  assert.ok(/auth\.uid\(\)/i.test(body), 'export_my_data must check auth.uid()');
  assert.ok(/RAISE\s+EXCEPTION/i.test(body), 'export_my_data must RAISE EXCEPTION on unauthenticated');
});

test('export_my_data returns all required data categories', () => {
  const body = findFunctionBody('export_my_data');
  assert.ok(body);
  const categories = ['profile', 'attendance', 'gamification', 'notifications', 'board_assignments', 'cycle_history', 'selection_applications', 'onboarding', 'exported_at'];
  for (const cat of categories) {
    assert.ok(body.includes(cat), `export_my_data must include ${cat}`);
  }
});

test('export_my_data is granted to authenticated', () => {
  assert.ok(
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+.*export_my_data.*TO\s+authenticated/i.test(allSQL),
    'export_my_data must be granted to authenticated'
  );
});

// ─── P1-B: LGPD Data Erasure ───

test('admin_anonymize_member RPC exists and is SECURITY DEFINER', () => {
  const body = findFunctionBody('admin_anonymize_member');
  assert.ok(body, 'admin_anonymize_member not found');
  const funcDef = allSQL.match(/admin_anonymize_member[\s\S]*?SECURITY\s+DEFINER/i);
  assert.ok(funcDef, 'admin_anonymize_member must be SECURITY DEFINER');
});

test('admin_anonymize_member requires superadmin', () => {
  const body = findFunctionBody('admin_anonymize_member');
  assert.ok(body);
  assert.ok(/is_superadmin\s*=\s*true/i.test(body), 'Must check is_superadmin');
  assert.ok(/RAISE\s+EXCEPTION/i.test(body), 'Must RAISE EXCEPTION on unauthorized');
});

test('admin_anonymize_member scrubs PII fields', () => {
  const body = findFunctionBody('admin_anonymize_member');
  assert.ok(body);
  // Schema reality: members uses `name` (not full_name) and `photo_url` (not avatar_url).
  // The RPC was corrected in migration 20260410160000 to match real column names.
  const piiFields = ['name', 'email', 'phone', 'linkedin_url', 'photo_url', 'auth_id'];
  for (const field of piiFields) {
    assert.ok(body.includes(field), `Must scrub ${field}`);
  }
});

test('admin_anonymize_member deletes notifications', () => {
  const body = findFunctionBody('admin_anonymize_member');
  assert.ok(body);
  assert.ok(/DELETE\s+FROM\s+.*notifications/i.test(body), 'Must delete notifications');
});

test('admin_anonymize_member breaks auth link (auth_id = NULL)', () => {
  const body = findFunctionBody('admin_anonymize_member');
  assert.ok(body);
  assert.ok(/auth_id\s*=\s*NULL/i.test(body), 'Must set auth_id = NULL');
});

test('members table has anonymized_at column', () => {
  assert.ok(
    /ALTER\s+TABLE\s+.*members\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+anonymized_at/i.test(allSQL),
    'Must add anonymized_at column'
  );
});

// ─── P1-C: Data Retention Policy ───

test('data_retention_policy table exists', () => {
  assert.ok(
    /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+.*data_retention_policy/i.test(allSQL),
    'data_retention_policy table must exist'
  );
});

test('data_retention_policy has RLS enabled', () => {
  assert.ok(
    /ALTER\s+TABLE\s+.*data_retention_policy\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i.test(allSQL),
    'data_retention_policy must have RLS enabled'
  );
});

test('data_retention_policy seeded with 5 policies', () => {
  const seedMatch = allSQL.match(/INSERT\s+INTO\s+.*data_retention_policy[\s\S]*?VALUES([\s\S]*?)ON\s+CONFLICT/i);
  assert.ok(seedMatch, 'Must seed data_retention_policy');
  const rowCount = (seedMatch[1].match(/\(/g) || []).length;
  assert.ok(rowCount >= 5, `Must have at least 5 seed policies, found ${rowCount}`);
});

test('admin_run_retention_cleanup RPC exists', () => {
  const body = findFunctionBody('admin_run_retention_cleanup');
  assert.ok(body, 'admin_run_retention_cleanup not found');
});

test('admin_run_retention_cleanup requires admin', () => {
  const body = findFunctionBody('admin_run_retention_cleanup');
  assert.ok(body);
  // V3 legacy pattern was 'is_superadmin'/'operational_role'; updated p60 Pacote E
  // to V4 'can_by_member(..., manage_platform)' (Phase B'' easy-convert).
  // Spirit preserved: must gate on admin authority.
  assert.ok(
    /is_superadmin\s*=\s*true/i.test(body)
      || /operational_role/i.test(body)
      || /can_by_member\s*\([^)]*manage_platform/i.test(body),
    'Must check admin role (V3 is_superadmin/operational_role OR V4 can_by_member manage_platform)'
  );
  assert.ok(/RAISE\s+EXCEPTION/i.test(body), 'Must RAISE EXCEPTION on unauthorized');
});

// ─── P0-C: XSS Prevention ───

test('Nav.astro has avatar URL domain allowlist', () => {
  const navPath = resolve(ROOT, 'src/components/nav/Nav.astro');
  assert.ok(existsSync(navPath), 'Nav.astro must exist');
  const nav = readFileSync(navPath, 'utf8');
  assert.ok(nav.includes('ALLOWED_AVATAR_DOMAINS'), 'Nav must have ALLOWED_AVATAR_DOMAINS');
  assert.ok(nav.includes('sanitizeAvatarUrl'), 'Nav must have sanitizeAvatarUrl');
  assert.ok(nav.includes('lh3.googleusercontent.com'), 'Must allow Google avatar domain');
});

test('Nav.astro escapes HTML in user name', () => {
  const nav = readFileSync(resolve(ROOT, 'src/components/nav/Nav.astro'), 'utf8');
  assert.ok(nav.includes('escapeHtml'), 'Nav must have escapeHtml function');
  assert.ok(nav.includes('safeFirst'), 'Nav must use safeFirst (escaped name)');
});

// ─── P1-D: Edge Function Retry Logic ───

const EDGE_FUNCTIONS_WITH_RETRY = [
  'send-notification-digest',
  'send-global-onboarding',
  'verify-credly',
  'sync-comms-metrics',
];

for (const fn of EDGE_FUNCTIONS_WITH_RETRY) {
  test(`Edge Function ${fn} has fetchWithRetry`, () => {
    const fnPath = resolve(ROOT, `supabase/functions/${fn}/index.ts`);
    assert.ok(existsSync(fnPath), `${fn}/index.ts must exist`);
    const content = readFileSync(fnPath, 'utf8');
    assert.ok(content.includes('fetchWithRetry'), `${fn} must use fetchWithRetry`);
    assert.ok(content.includes('exponential backoff') || content.includes('Math.pow(2, attempt)'),
      `${fn} must implement exponential backoff`);
  });
}

// ─── P1-E: File Upload Security ───

test('CardDetail.tsx has EXIF stripping', () => {
  const cdPath = resolve(ROOT, 'src/components/board/CardDetail.tsx');
  assert.ok(existsSync(cdPath), 'CardDetail.tsx must exist');
  const content = readFileSync(cdPath, 'utf8');
  assert.ok(content.includes('stripExif'), 'Must have stripExif function');
  assert.ok(content.includes('canvas'), 'Must use canvas for EXIF stripping');
});

test('CardDetail.tsx validates MIME type', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/board/CardDetail.tsx'), 'utf8');
  assert.ok(content.includes('ALLOWED_TYPES'), 'Must have ALLOWED_TYPES');
  assert.ok(content.includes('file.type'), 'Must check file.type');
});

// ─── Profile Data Export UI ───

test('Profile page has LGPD export button', () => {
  const profilePath = resolve(ROOT, 'src/pages/profile.astro');
  assert.ok(existsSync(profilePath), 'profile.astro must exist');
  const content = readFileSync(profilePath, 'utf8');
  assert.ok(content.includes('export-my-data'), 'Must have export-my-data action');
  assert.ok(content.includes('export_my_data'), 'Must call export_my_data RPC');
});

// ─── i18n keys ───

test('LGPD i18n keys exist in all languages', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const path = resolve(ROOT, `src/i18n/${lang}.ts`);
    const content = readFileSync(path, 'utf8');
    assert.ok(content.includes('profile.lgpdTitle'), `${lang} must have profile.lgpdTitle`);
    assert.ok(content.includes('profile.lgpdExportBtn'), `${lang} must have profile.lgpdExportBtn`);
  }
});
