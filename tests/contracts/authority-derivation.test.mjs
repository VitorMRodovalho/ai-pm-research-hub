/**
 * Domain Model V4 — Fase 4 — Authority Derivation Fixtures
 *
 * Static analysis contract test for Phase 4 migrations (ADR-0007).
 * Validates that:
 *   1. engagement_kind_permissions table exists with correct seed
 *   2. auth_engagements view exists with is_authoritative derivation
 *   3. can() function exists with correct signature
 *   4. can_by_member() bridge exists
 *   5. why_denied() diagnostic exists
 *   6. operational_role cache sync trigger exists
 *   7. Daily expiration shadow function + cron exists
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function findMigration(pattern) {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes(pattern));
  assert.ok(files.length > 0, `Migration matching "${pattern}" must exist`);
  return readFileSync(resolve(MIGRATIONS_DIR, files[0]), 'utf8');
}

const EXPECTED_ACTIONS = ['write', 'write_board', 'manage_partner', 'manage_member', 'manage_event', 'view_pii', 'promote'];

// ═══════════════════════════════════════════════════════════════════════════
// Migration 1: engagement_kind_permissions
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 4 Migration 1: engagement_kind_permissions table', async (t) => {
  const sql = findMigration('v4_phase4_engagement_permissions');

  await t.test('creates engagement_kind_permissions table', () => {
    assert.match(sql, /CREATE TABLE public\.engagement_kind_permissions/i);
  });

  await t.test('has kind FK to engagement_kinds', () => {
    assert.match(sql, /REFERENCES public\.engagement_kinds\(slug\)/i);
  });

  await t.test('has UNIQUE constraint on (kind, role, action)', () => {
    assert.match(sql, /UNIQUE.*kind.*role.*action/i);
  });

  await t.test('has scope CHECK constraint', () => {
    for (const scope of ['global', 'organization', 'initiative']) {
      assert.ok(sql.includes(`'${scope}'`), `Must include scope: ${scope}`);
    }
  });

  for (const action of EXPECTED_ACTIONS) {
    await t.test(`seeds action: ${action}`, () => {
      assert.ok(sql.includes(`'${action}'`), `Action "${action}" must be seeded`);
    });
  }

  await t.test('manager gets all 7 actions', () => {
    const managerLines = sql.split('\n').filter(l => l.includes("'manager'") && l.includes('volunteer'));
    assert.ok(managerLines.length >= 7, `Manager should have 7+ permission rows, found ${managerLines.length}`);
  });

  await t.test('researcher gets write_board only', () => {
    assert.ok(sql.includes("'researcher', 'write_board', 'initiative'"));
  });

  await t.test('has RLS enabled', () => {
    assert.match(sql, /ENABLE ROW LEVEL SECURITY/i);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 2: auth_engagements view
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 4 Migration 2: auth_engagements view', async (t) => {
  const sql = findMigration('v4_phase4_auth_engagements_view');

  await t.test('creates auth_engagements view', () => {
    assert.match(sql, /CREATE OR REPLACE VIEW public\.auth_engagements/i);
  });

  await t.test('derives is_authoritative boolean', () => {
    assert.ok(sql.includes('is_authoritative'));
  });

  await t.test('checks engagement status = active', () => {
    assert.ok(sql.includes("e.status = 'active'"));
  });

  await t.test('checks start_date <= CURRENT_DATE', () => {
    assert.match(sql, /start_date\s*<=\s*CURRENT_DATE/i);
  });

  await t.test('checks end_date validity', () => {
    assert.match(sql, /end_date IS NULL OR e\.end_date >= CURRENT_DATE/i);
  });

  await t.test('checks agreement requirement', () => {
    assert.ok(sql.includes('agreement_certificate_id'));
    assert.ok(sql.includes('requires_agreement'));
  });

  await t.test('joins persons for legacy_member_id bridge', () => {
    assert.ok(sql.includes('legacy_member_id'));
    assert.ok(sql.includes('auth_id'));
  });

  await t.test('joins initiatives for legacy_tribe_id bridge', () => {
    assert.ok(sql.includes('legacy_tribe_id'));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 3: can() function
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 4 Migration 3: can() function + helpers', async (t) => {
  const sql = findMigration('v4_phase4_can_function');

  await t.test('creates can(person_id, action, resource_type, resource_id)', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.can\(/i);
    assert.ok(sql.includes('p_person_id uuid'));
    assert.ok(sql.includes('p_action text'));
  });

  await t.test('can() joins auth_engagements with engagement_kind_permissions', () => {
    assert.ok(sql.includes('auth_engagements'));
    assert.ok(sql.includes('engagement_kind_permissions'));
  });

  await t.test('can() checks is_authoritative', () => {
    assert.ok(sql.includes('is_authoritative'));
  });

  await t.test('can() handles organization and initiative scopes', () => {
    assert.ok(sql.includes("'organization'"));
    assert.ok(sql.includes("'initiative'"));
  });

  await t.test('creates can_by_member() bridge', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.can_by_member\(/i);
    assert.ok(sql.includes('legacy_member_id'));
  });

  await t.test('creates why_denied() diagnostic', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.why_denied\(/i);
  });

  await t.test('why_denied checks: person_not_found, no_active_engagements, no_authoritative, no_matching_permission', () => {
    for (const reason of ['person_not_found', 'no_active_engagements', 'no_authoritative_engagements', 'no_matching_permission']) {
      assert.ok(sql.includes(reason), `why_denied must check for: ${reason}`);
    }
  });

  await t.test('all functions granted to authenticated', () => {
    const grants = (sql.match(/GRANT EXECUTE/gi) || []).length;
    assert.ok(grants >= 3, `Expected 3+ GRANT EXECUTE, found ${grants}`);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 4: operational_role cache sync
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 4 Migration 4: operational_role cache sync', async (t) => {
  const sql = findMigration('v4_phase4_role_cache_sync');

  await t.test('creates sync_operational_role_cache function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.sync_operational_role_cache/i);
  });

  await t.test('trigger on engagements table', () => {
    assert.match(sql, /CREATE TRIGGER.*ON public\.engagements/is);
  });

  await t.test('trigger fires AFTER INSERT OR UPDATE OR DELETE', () => {
    assert.match(sql, /AFTER INSERT OR UPDATE OR DELETE/i);
  });

  await t.test('maps volunteer+manager → manager', () => {
    assert.ok(sql.includes("'manager'"));
  });

  await t.test('maps volunteer+leader → tribe_leader', () => {
    assert.ok(sql.includes("'tribe_leader'"));
  });

  await t.test('uses auth_engagements view for derivation', () => {
    assert.ok(sql.includes('auth_engagements'));
    assert.ok(sql.includes('is_authoritative'));
  });

  await t.test('only updates when role actually changed (IS DISTINCT FROM)', () => {
    assert.ok(sql.includes('IS DISTINCT FROM'));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 5: expiration shadow
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 4 Migration 5: daily expiration shadow', async (t) => {
  const sql = findMigration('v4_phase4_expiration_shadow');

  await t.test('creates v4_expire_engagements_shadow function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.v4_expire_engagements_shadow/i);
  });

  await t.test('is shadow mode (does not change engagement status)', () => {
    assert.ok(sql.includes("'shadow'"));
    assert.ok(!sql.includes("UPDATE public.engagements SET status"));
  });

  await t.test('logs to admin_audit_log', () => {
    assert.ok(sql.includes('admin_audit_log'));
    assert.ok(sql.includes('v4_expiration_shadow'));
  });

  await t.test('checks end_date < CURRENT_DATE', () => {
    assert.ok(sql.includes('end_date'));
    assert.ok(sql.includes('CURRENT_DATE'));
  });

  await t.test('schedules via cron.schedule', () => {
    assert.match(sql, /cron\.schedule/i);
    assert.ok(sql.includes('v4_engagement_expiration_shadow'));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Cross-cutting
// ═══════════════════════════════════════════════════════════════════════════
test('All Phase 4 migrations include PostgREST reload', async (t) => {
  const phase4Files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes('v4_phase4'));
  for (const file of phase4Files) {
    await t.test(`${file} has NOTIFY pgrst`, () => {
      const sql = readFileSync(resolve(MIGRATIONS_DIR, file), 'utf8');
      assert.match(sql, /NOTIFY pgrst/i);
    });
  }
});
