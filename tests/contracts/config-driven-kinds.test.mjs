/**
 * Domain Model V4 — Fase 6 — Config-Driven Initiative Kinds Fixtures
 *
 * Static analysis contract test for Phase 6 migrations (ADR-0009).
 * Validates that:
 *   1. initiative_kinds enrichment (4 new columns + book_club seed)
 *   2. Kind-aware engine (assert_initiative_capability + CRUD RPCs + admin RLS)
 *   3. Custom fields validation (validate_initiative_metadata + trigger)
 *   4. CPMAI data migration (initiative_member_progress + rewritten RPC)
 *   5. CPMAI deprecation (comments + revoke)
 *   6. Admin UI and frontend files exist
 *   7. i18n keys exist in all 3 dictionaries
 *   8. No hardcoded kind checks in engine code
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function findMigration(pattern) {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes(pattern));
  assert.ok(files.length > 0, `Migration matching "${pattern}" must exist`);
  return readFileSync(resolve(MIGRATIONS_DIR, files[0]), 'utf8');
}

function readFile(path) {
  const full = resolve(ROOT, path);
  assert.ok(existsSync(full), `File must exist: ${path}`);
  return readFileSync(full, 'utf8');
}

// ═══════════════════════════════════════════════════════════════════════════
// Migration 1: Schema Enrichment
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Migration 1: initiative_kinds enrichment', async (t) => {
  const sql = findMigration('v4_phase6_initiative_kinds_enrichment');

  await t.test('adds allowed_engagement_kinds column', () => {
    assert.ok(sql.includes('allowed_engagement_kinds'), 'Must add allowed_engagement_kinds');
  });

  await t.test('adds required_engagement_kinds column', () => {
    assert.ok(sql.includes('required_engagement_kinds'), 'Must add required_engagement_kinds');
  });

  await t.test('adds certificate_template_id column', () => {
    assert.ok(sql.includes('certificate_template_id'), 'Must add certificate_template_id');
  });

  await t.test('adds created_by column', () => {
    assert.ok(sql.includes('created_by'), 'Must add created_by');
  });

  await t.test('seeds book_club kind', () => {
    assert.ok(sql.includes("'book_club'"), 'Must seed book_club kind');
  });

  await t.test('updates research_tribe engagement mappings', () => {
    assert.ok(sql.includes("WHERE slug = 'research_tribe'"), 'Must update research_tribe');
  });

  await t.test('updates study_group engagement mappings', () => {
    assert.ok(sql.includes("WHERE slug = 'study_group'"), 'Must update study_group');
  });

  await t.test('has PostgREST reload', () => {
    assert.ok(sql.includes('NOTIFY pgrst'), 'Must notify pgrst');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 2: Kind-Aware Engine
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Migration 2: kind-aware engine RPCs', async (t) => {
  const sql = findMigration('v4_phase6_kind_aware_engine');

  await t.test('creates assert_initiative_capability guard', () => {
    assert.ok(sql.includes('assert_initiative_capability'), 'Must create guard function');
  });

  await t.test('guard validates known capabilities only', () => {
    for (const cap of ['has_board', 'has_meeting_notes', 'has_deliverables', 'has_attendance', 'has_certificate']) {
      assert.ok(sql.includes(cap), `Guard must know capability: ${cap}`);
    }
  });

  await t.test('creates create_initiative RPC', () => {
    assert.ok(sql.includes('create_initiative'), 'Must create create_initiative');
  });

  await t.test('create_initiative checks max_concurrent_per_org', () => {
    assert.ok(sql.includes('max_concurrent_per_org'), 'Must check concurrency limit');
  });

  await t.test('create_initiative auto-creates board', () => {
    assert.ok(sql.includes('has_board'), 'Must auto-create board when has_board=true');
    assert.ok(sql.includes('project_boards'), 'Must insert into project_boards');
  });

  await t.test('creates update_initiative RPC', () => {
    assert.ok(sql.includes('update_initiative'), 'Must create update_initiative');
  });

  await t.test('update_initiative validates lifecycle_states', () => {
    assert.ok(sql.includes('lifecycle_states'), 'Must validate status against kind lifecycle');
  });

  await t.test('creates list_initiatives RPC', () => {
    assert.ok(sql.includes('list_initiatives'), 'Must create list_initiatives');
  });

  await t.test('adds admin write RLS policies', () => {
    assert.ok(sql.includes('initiative_kinds_write_admin'), 'Must add INSERT policy');
    assert.ok(sql.includes('initiative_kinds_update_admin'), 'Must add UPDATE policy');
    assert.ok(sql.includes('initiative_kinds_delete_admin'), 'Must add DELETE policy');
  });

  await t.test('write policies use can_by_member', () => {
    assert.ok(sql.includes('can_by_member'), 'Must use V4 authority gate');
  });

  await t.test('engine RPCs use guard for feature-gated operations', () => {
    // Attendance RPC must call guard
    const attendanceSection = sql.substring(sql.indexOf('get_initiative_attendance_grid'));
    assert.ok(attendanceSection.includes('assert_initiative_capability'), 'Attendance must use guard');

    // Deliverables RPC must call guard
    const deliverablesSection = sql.substring(sql.indexOf('list_initiative_deliverables'));
    assert.ok(deliverablesSection.includes('assert_initiative_capability'), 'Deliverables must use guard');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 3: Custom Fields Validation
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Migration 3: custom fields validation', async (t) => {
  const sql = findMigration('v4_phase6_custom_fields_validation');

  await t.test('creates validate_initiative_metadata function', () => {
    assert.ok(sql.includes('validate_initiative_metadata'), 'Must create validator');
  });

  await t.test('validates required fields', () => {
    assert.ok(sql.includes("'required'"), 'Must check required fields');
  });

  await t.test('validates field types (string, number, boolean, array)', () => {
    for (const type of ['string', 'number', 'boolean', 'array']) {
      assert.ok(sql.includes(`'${type}'`), `Must validate type: ${type}`);
    }
  });

  await t.test('skips null values', () => {
    assert.ok(sql.includes("'null'"), 'Must skip null JSON values');
  });

  await t.test('creates trigger on initiatives table', () => {
    assert.ok(sql.includes('trg_validate_initiative_metadata'), 'Must create trigger');
  });

  await t.test('seeds study_group custom_fields_schema', () => {
    assert.ok(sql.includes('max_enrollment'), 'Must seed study_group schema with max_enrollment');
    assert.ok(sql.includes('exam_date'), 'Must seed study_group schema with exam_date');
  });

  await t.test('seeds congress custom_fields_schema', () => {
    assert.ok(sql.includes('venue'), 'Must seed congress schema with venue');
    assert.ok(sql.includes('expected_attendees'), 'Must seed congress schema with expected_attendees');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 4: CPMAI Data Migration
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Migration 4: CPMAI data migration', async (t) => {
  const sql = findMigration('v4_phase6_cpmai_migration');

  await t.test('creates initiative_member_progress table', () => {
    assert.ok(sql.includes('initiative_member_progress'), 'Must create generic progress table');
  });

  await t.test('progress table has correct columns', () => {
    assert.ok(sql.includes('progress_type'), 'Must have progress_type column');
    assert.ok(sql.includes('payload'), 'Must have payload jsonb column');
    assert.ok(sql.includes('person_id'), 'Must reference persons');
    assert.ok(sql.includes('initiative_id'), 'Must reference initiatives');
  });

  await t.test('progress table has RLS', () => {
    assert.ok(sql.includes('ENABLE ROW LEVEL SECURITY'), 'Must enable RLS');
    assert.ok(sql.includes('imp_org_scope'), 'Must have org scope policy');
  });

  await t.test('migrates cpmai_courses to initiatives', () => {
    assert.ok(sql.includes('cpmai_courses'), 'Must read from cpmai_courses');
    assert.ok(sql.includes("'study_group'"), 'Must create as study_group kind');
    assert.ok(sql.includes('cpmai_legacy_course_id'), 'Must store legacy ID in metadata');
  });

  await t.test('creates join_initiative RPC', () => {
    assert.ok(sql.includes('join_initiative'), 'Must create generic enrollment RPC');
  });

  await t.test('join_initiative checks capacity', () => {
    assert.ok(sql.includes('max_enrollment'), 'Must check capacity from metadata');
  });

  await t.test('join_initiative checks duplicate enrollment', () => {
    assert.ok(sql.includes('Already enrolled'), 'Must prevent duplicate enrollment');
  });

  await t.test('rewrites get_cpmai_course_dashboard to read from initiatives', () => {
    assert.ok(sql.includes('get_cpmai_course_dashboard'), 'Must rewrite dashboard RPC');
    // The dashboard function body must reference initiatives and initiative_member_progress
    const dashStart = sql.indexOf('CREATE OR REPLACE FUNCTION public.get_cpmai_course_dashboard');
    assert.ok(dashStart > -1, 'Must have CREATE OR REPLACE for dashboard');
    const dashSection = sql.substring(dashStart);
    assert.ok(dashSection.includes('public.initiatives'), 'Dashboard must read from initiatives table');
    assert.ok(dashSection.includes('initiative_member_progress'), 'Dashboard must read from progress table');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 5: CPMAI Deprecation
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Migration 5: CPMAI tables deprecation', async (t) => {
  const sql = findMigration('v4_phase6_cpmai_deprecation');

  const CPMAI_TABLES = ['cpmai_courses', 'cpmai_domains', 'cpmai_modules', 'cpmai_enrollments', 'cpmai_progress', 'cpmai_mock_scores', 'cpmai_sessions'];

  await t.test('comments deprecation on all 7 cpmai tables', () => {
    for (const table of CPMAI_TABLES) {
      assert.ok(sql.includes(`COMMENT ON TABLE public.${table}`), `Must comment deprecation on ${table}`);
      assert.ok(sql.includes('DEPRECATED'), 'Must include DEPRECATED marker');
    }
  });

  await t.test('revokes write access on all 7 cpmai tables', () => {
    for (const table of CPMAI_TABLES) {
      assert.ok(sql.includes(`REVOKE INSERT, UPDATE, DELETE ON public.${table}`), `Must revoke writes on ${table}`);
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Frontend: Admin UI
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Frontend: Admin UI exists', async (t) => {
  await t.test('initiative-kinds.astro page exists', () => {
    const path = resolve(ROOT, 'src/pages/admin/initiative-kinds.astro');
    assert.ok(existsSync(path), 'Admin page must exist');
  });

  await t.test('admin page imports AdminLayout', () => {
    const content = readFile('src/pages/admin/initiative-kinds.astro');
    assert.ok(content.includes('AdminLayout'), 'Must use AdminLayout');
  });

  await t.test('admin page has CRUD functionality', () => {
    const content = readFile('src/pages/admin/initiative-kinds.astro');
    assert.ok(content.includes('initiative_kinds'), 'Must interact with initiative_kinds table');
    assert.ok(content.includes('.insert('), 'Must support INSERT');
    assert.ok(content.includes('.update('), 'Must support UPDATE');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Frontend: CPMAI migration
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Frontend: CPMAI landing uses V4 RPCs', async (t) => {
  const content = readFile('src/components/cpmai/CpmaiLanding.tsx');

  await t.test('uses join_initiative instead of enroll_in_cpmai_course', () => {
    assert.ok(content.includes('join_initiative'), 'Must use generic join_initiative RPC');
    assert.ok(!content.includes('enroll_in_cpmai_course'), 'Must NOT use legacy enroll RPC');
  });

  await t.test('still uses get_cpmai_course_dashboard (rewritten server-side)', () => {
    assert.ok(content.includes('get_cpmai_course_dashboard'), 'Dashboard RPC call preserved for compat');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// i18n: All 3 dictionaries
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 i18n: keys in all 3 dictionaries', async (t) => {
  const REQUIRED_KEYS = [
    'admin.initiativeKinds', 'admin.initiativeKindsDesc', 'admin.newKind',
    'admin.displayName', 'admin.features', 'admin.customFieldsSchema',
    'admin.slugHint', 'admin.save',
  ];

  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const content = readFile(`src/i18n/${lang}.ts`);
    for (const key of REQUIRED_KEYS) {
      await t.test(`${lang} has key '${key}'`, () => {
        assert.ok(content.includes(`'${key}'`), `${lang} must have key ${key}`);
      });
    }
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// Invariant: No hardcoded kind checks in engine code
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 6 Invariant: no hardcoded kind checks in Phase 6 engine migrations', async (t) => {
  const engineSql = findMigration('v4_phase6_kind_aware_engine');

  // Engine functions should NOT contain kind-specific conditionals
  const kindCheckPattern = /IF\s+.*kind\s*=\s*'(research_tribe|study_group|congress|workshop|book_club)'/gi;
  const matches = engineSql.match(kindCheckPattern) || [];

  await t.test('engine migration has zero "IF kind = \'specific_kind\'" patterns', () => {
    assert.equal(matches.length, 0, `Found ${matches.length} hardcoded kind checks: ${matches.join(', ')}`);
  });
});
