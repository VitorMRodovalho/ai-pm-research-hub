/**
 * Domain Model V4 — Fase 2 — Initiative Primitive Fixtures
 *
 * Static analysis contract test for Phase 2 migrations (ADR-0005).
 * Validates that:
 *   1. initiative_kinds migration exists with correct seed
 *   2. initiatives table migration exists with legacy_tribe_id bridge
 *   3. initiative_id retrofit covers all expected domain tables
 *   4. Dual-write triggers exist on all retrofitted tables
 *   5. _by_initiative RPC wrappers exist
 *   6. resolve_tribe_id bridge helper exists
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

// ─── Initiative kinds seed slugs ───
const EXPECTED_KINDS = ['research_tribe', 'study_group', 'congress', 'workshop'];

// ─── Tables that must have initiative_id column (retrofit) ───
const RETROFIT_TABLES = [
  'events', 'meeting_artifacts', 'tribe_deliverables', 'project_boards',
  'webinars', 'announcements', 'publication_submissions', 'pilots',
  'hub_resources', 'broadcast_log', 'members', 'public_publications', 'ia_pilots'
];

// ─── Initiative RPC wrappers ───
const INITIATIVE_RPCS = [
  'exec_initiative_dashboard', 'get_initiative_attendance_grid',
  'list_initiative_deliverables', 'list_initiative_meeting_artifacts',
  'get_initiative_stats', 'get_initiative_events_timeline',
  'list_initiative_boards', 'search_initiative_board_items',
  'get_initiative_gamification'
];

// ═══════════════════════════════════════════════════════════════════════════
// Migration 1: initiative_kinds
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 2 Migration 1: initiative_kinds table', async (t) => {
  const sql = findMigration('v4_phase2_initiative_kinds');

  await t.test('creates initiative_kinds table', () => {
    assert.match(sql, /CREATE TABLE public\.initiative_kinds/i);
  });

  await t.test('slug is PRIMARY KEY', () => {
    assert.match(sql, /slug\s+text\s+PRIMARY KEY/i);
  });

  await t.test('has RLS enabled', () => {
    assert.match(sql, /ENABLE ROW LEVEL SECURITY/i);
  });

  await t.test('has org-scoped RESTRICTIVE policy', () => {
    assert.match(sql, /RESTRICTIVE/i);
    assert.match(sql, /auth_org\(\)/i);
  });

  for (const kind of EXPECTED_KINDS) {
    await t.test(`seeds kind: ${kind}`, () => {
      assert.ok(sql.includes(`'${kind}'`), `Kind "${kind}" must be seeded`);
    });
  }

  await t.test('has organization_id FK to organizations', () => {
    assert.match(sql, /REFERENCES public\.organizations\(id\)/i);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 2: initiatives table
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 2 Migration 2: initiatives table', async (t) => {
  const sql = findMigration('v4_phase2_initiatives_table');

  await t.test('creates initiatives table', () => {
    assert.match(sql, /CREATE TABLE public\.initiatives/i);
  });

  await t.test('id is uuid PRIMARY KEY', () => {
    assert.match(sql, /id\s+uuid\s+PRIMARY KEY/i);
  });

  await t.test('kind FK to initiative_kinds', () => {
    assert.match(sql, /REFERENCES public\.initiative_kinds\(slug\)/i);
  });

  await t.test('has legacy_tribe_id integer UNIQUE bridge column', () => {
    assert.match(sql, /legacy_tribe_id\s+integer\s+UNIQUE/i);
  });

  await t.test('has parent_initiative_id self-reference', () => {
    assert.match(sql, /parent_initiative_id\s+uuid\s+REFERENCES public\.initiatives\(id\)/i);
  });

  await t.test('has metadata jsonb', () => {
    assert.match(sql, /metadata\s+jsonb/i);
  });

  await t.test('has status CHECK constraint', () => {
    assert.match(sql, /CHECK.*status.*IN.*draft.*active.*concluded.*archived/i);
  });

  await t.test('has RLS enabled with RESTRICTIVE org scope', () => {
    assert.match(sql, /ENABLE ROW LEVEL SECURITY/i);
    assert.match(sql, /RESTRICTIVE/i);
    assert.match(sql, /auth_org\(\)/i);
  });

  await t.test('seeds from tribes table', () => {
    assert.match(sql, /FROM public\.tribes/i);
    assert.match(sql, /legacy_tribe_id/i);
    assert.ok(sql.includes("'research_tribe'"), 'Seeds must use kind research_tribe');
  });

  await t.test('has indexes on kind, org, status, parent, legacy_tribe', () => {
    assert.match(sql, /idx_initiatives_kind/i);
    assert.match(sql, /idx_initiatives_org/i);
    assert.match(sql, /idx_initiatives_status/i);
    assert.match(sql, /idx_initiatives_parent/i);
    assert.match(sql, /idx_initiatives_legacy_tribe/i);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 3: initiative_id retrofit
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 2 Migration 3: initiative_id retrofit', async (t) => {
  const sql = findMigration('v4_phase2_initiative_id_retrofit');

  for (const table of RETROFIT_TABLES) {
    await t.test(`${table} gets initiative_id column`, () => {
      const pattern = new RegExp(`ALTER TABLE public\\.${table}[\\s\\S]*?initiative_id\\s+uuid`, 'i');
      assert.match(sql, pattern, `${table} must get initiative_id uuid column`);
    });

    await t.test(`${table} initiative_id FK to initiatives`, () => {
      assert.ok(
        sql.includes(`REFERENCES public.initiatives(id)`),
        `${table} must have FK to initiatives`
      );
    });

    await t.test(`${table} has backfill from legacy_tribe_id`, () => {
      const pattern = new RegExp(`UPDATE public\\.${table}`, 'i');
      assert.match(sql, pattern, `${table} must have backfill UPDATE`);
    });

    await t.test(`${table} has index on initiative_id`, () => {
      const pattern = new RegExp(`idx_${table}_initiative`, 'i');
      assert.match(sql, pattern, `${table} must have initiative_id index`);
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 4: dual-write triggers
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 2 Migration 4: dual-write triggers', async (t) => {
  const sql = findMigration('v4_phase2_dual_write_triggers');

  await t.test('creates sync_initiative_from_tribe function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.sync_initiative_from_tribe/i);
  });

  await t.test('creates sync_tribe_from_initiative function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.sync_tribe_from_initiative/i);
  });

  await t.test('sync_initiative uses legacy_tribe_id bridge', () => {
    assert.ok(sql.includes('legacy_tribe_id'), 'Must resolve via legacy_tribe_id');
  });

  for (const table of RETROFIT_TABLES) {
    await t.test(`${table} has tribe→initiative trigger`, () => {
      const pattern = new RegExp(`trg_a_sync_initiative_${table}`, 'i');
      assert.match(sql, pattern, `${table} must have sync_initiative trigger`);
    });

    await t.test(`${table} has initiative→tribe trigger`, () => {
      const pattern = new RegExp(`trg_b_sync_tribe_${table}`, 'i');
      assert.match(sql, pattern, `${table} must have sync_tribe trigger`);
    });
  }

  await t.test('triggers are BEFORE INSERT OR UPDATE', () => {
    const triggerCount = (sql.match(/BEFORE INSERT OR UPDATE/gi) || []).length;
    assert.ok(triggerCount >= RETROFIT_TABLES.length * 2,
      `Expected at least ${RETROFIT_TABLES.length * 2} triggers, found ${triggerCount}`);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 5: _by_initiative RPCs
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 2 Migration 5: initiative RPC wrappers', async (t) => {
  const sql = findMigration('v4_phase2_initiative_rpcs');

  await t.test('creates resolve_tribe_id bridge helper', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.resolve_tribe_id/i);
    assert.ok(sql.includes('legacy_tribe_id'), 'resolve_tribe_id must use legacy_tribe_id');
  });

  for (const rpc of INITIATIVE_RPCS) {
    await t.test(`creates ${rpc} wrapper`, () => {
      const pattern = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${rpc}`, 'i');
      assert.match(sql, pattern, `RPC ${rpc} must exist`);
    });

    await t.test(`${rpc} delegates via resolve_tribe_id`, () => {
      assert.ok(sql.includes('resolve_tribe_id'), `${rpc} must use resolve_tribe_id bridge`);
    });

    await t.test(`${rpc} grants to authenticated`, () => {
      const pattern = new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${rpc}`, 'i');
      assert.match(sql, pattern, `${rpc} must grant to authenticated`);
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// Cross-cutting: NOTIFY pgrst in all migrations
// ═══════════════════════════════════════════════════════════════════════════
test('All Phase 2 migrations include PostgREST reload', async (t) => {
  const phase2Files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes('v4_phase2'));

  for (const file of phase2Files) {
    await t.test(`${file} has NOTIFY pgrst`, () => {
      const sql = readFileSync(resolve(MIGRATIONS_DIR, file), 'utf8');
      assert.match(sql, /NOTIFY pgrst/i, `${file} must reload PostgREST schema`);
    });
  }
});
