/**
 * Domain Model V4 — Fase 3 — Person + Engagement Fixtures
 *
 * Static analysis contract test for Phase 3 migrations (ADR-0006).
 * Validates that:
 *   1. engagement_kinds migration exists with correct seed
 *   2. persons table exists with identity columns + legacy bridge
 *   3. engagements table exists with contextual binding columns
 *   4. Backfill logic maps operational_role → engagement kind+role
 *   5. Designation backfill creates additional engagements
 *   6. RLS and org-scope policies exist on all new tables
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

// ─── Engagement kinds seed slugs ───
const EXPECTED_KINDS = [
  'volunteer', 'observer', 'alumni', 'ambassador', 'chapter_board',
  'sponsor', 'guest', 'candidate', 'study_group_participant',
  'study_group_owner', 'speaker', 'partner_contact'
];

// ─── Legal basis values ───
const LEGAL_BASES = ['contract_volunteer', 'consent', 'legitimate_interest'];

// ═══════════════════════════════════════════════════════════════════════════
// Migration 1: engagement_kinds
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 3 Migration 1: engagement_kinds table', async (t) => {
  const sql = findMigration('v4_phase3_engagement_kinds');

  await t.test('creates engagement_kinds table', () => {
    assert.match(sql, /CREATE TABLE public\.engagement_kinds/i);
  });

  await t.test('slug is PRIMARY KEY', () => {
    assert.match(sql, /slug\s+text\s+PRIMARY KEY/i);
  });

  await t.test('has legal_basis column with CHECK constraint', () => {
    assert.match(sql, /legal_basis/i);
    for (const basis of LEGAL_BASES) {
      assert.ok(sql.includes(`'${basis}'`), `Must include legal basis: ${basis}`);
    }
  });

  await t.test('has requires_agreement boolean', () => {
    assert.match(sql, /requires_agreement\s+boolean/i);
  });

  await t.test('has retention_days_after_end for LGPD', () => {
    assert.match(sql, /retention_days_after_end/i);
  });

  await t.test('has RLS with RESTRICTIVE org scope', () => {
    assert.match(sql, /ENABLE ROW LEVEL SECURITY/i);
    assert.match(sql, /RESTRICTIVE/i);
    assert.match(sql, /auth_org\(\)/i);
  });

  for (const kind of EXPECTED_KINDS) {
    await t.test(`seeds kind: ${kind}`, () => {
      assert.ok(sql.includes(`'${kind}'`), `Kind "${kind}" must be seeded`);
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 2: persons table
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 3 Migration 2: persons table', async (t) => {
  const sql = findMigration('v4_phase3_persons_table');

  await t.test('creates persons table', () => {
    assert.match(sql, /CREATE TABLE public\.persons/i);
  });

  await t.test('id is uuid PRIMARY KEY', () => {
    assert.match(sql, /id\s+uuid\s+PRIMARY KEY/i);
  });

  await t.test('has auth_id uuid UNIQUE for login linkage', () => {
    assert.match(sql, /auth_id\s+uuid\s+UNIQUE/i);
  });

  await t.test('has PII fields: name, email, phone, address', () => {
    for (const field of ['name', 'email', 'phone', 'address']) {
      assert.ok(sql.includes(field), `Must have PII field: ${field}`);
    }
  });

  await t.test('has consent_status with CHECK', () => {
    assert.match(sql, /consent_status/i);
    assert.ok(sql.includes("'pending'") && sql.includes("'accepted'") && sql.includes("'revoked'"));
  });

  await t.test('has legacy_member_id uuid UNIQUE bridge', () => {
    assert.match(sql, /legacy_member_id\s+uuid\s+UNIQUE/i);
  });

  await t.test('has RLS with RESTRICTIVE org scope', () => {
    assert.match(sql, /ENABLE ROW LEVEL SECURITY/i);
    assert.match(sql, /RESTRICTIVE/i);
  });

  await t.test('backfills from members table', () => {
    assert.match(sql, /FROM public\.members/i);
    assert.ok(sql.includes('legacy_member_id'));
  });

  await t.test('adds person_id bridge column to members', () => {
    assert.match(sql, /ALTER TABLE public\.members/i);
    assert.match(sql, /person_id\s+uuid/i);
    assert.match(sql, /REFERENCES public\.persons\(id\)/i);
  });

  await t.test('backfills person_id on members', () => {
    assert.match(sql, /UPDATE public\.members/i);
    assert.ok(sql.includes('legacy_member_id'));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 3: engagements table
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 3 Migration 3: engagements table', async (t) => {
  const sql = findMigration('v4_phase3_engagements_table');

  await t.test('creates engagements table', () => {
    assert.match(sql, /CREATE TABLE public\.engagements/i);
  });

  await t.test('has person_id FK to persons', () => {
    assert.match(sql, /person_id\s+uuid\s+NOT NULL\s+REFERENCES public\.persons\(id\)/i);
  });

  await t.test('has initiative_id FK to initiatives', () => {
    assert.match(sql, /initiative_id\s+uuid\s+REFERENCES public\.initiatives\(id\)/i);
  });

  await t.test('has kind FK to engagement_kinds', () => {
    assert.match(sql, /REFERENCES public\.engagement_kinds\(slug\)/i);
  });

  await t.test('has role field', () => {
    assert.match(sql, /role\s+text\s+NOT NULL/i);
  });

  await t.test('has status with CHECK constraint', () => {
    assert.match(sql, /status\s+text\s+NOT NULL/i);
    for (const s of ['pending', 'active', 'suspended', 'expired', 'offboarded', 'anonymized']) {
      assert.ok(sql.includes(`'${s}'`), `Must include status: ${s}`);
    }
  });

  await t.test('has legal_basis with CHECK', () => {
    assert.match(sql, /legal_basis\s+text\s+NOT NULL/i);
  });

  await t.test('has temporal fields: start_date, end_date', () => {
    assert.match(sql, /start_date\s+date/i);
    assert.match(sql, /end_date\s+date/i);
  });

  await t.test('has governance fields: granted_by, revoked_at, revoke_reason', () => {
    for (const field of ['granted_by', 'revoked_at', 'revoke_reason']) {
      assert.ok(sql.includes(field), `Must have governance field: ${field}`);
    }
  });

  await t.test('has agreement_certificate_id for term linkage', () => {
    assert.ok(sql.includes('agreement_certificate_id'));
  });

  await t.test('has vep_opportunity_id for VEP linkage', () => {
    assert.ok(sql.includes('vep_opportunity_id'));
  });

  await t.test('has RLS with RESTRICTIVE org scope', () => {
    assert.match(sql, /ENABLE ROW LEVEL SECURITY/i);
    assert.match(sql, /RESTRICTIVE/i);
  });

  await t.test('has indexes on person, org, initiative, kind, status, active', () => {
    for (const idx of ['idx_engagements_person', 'idx_engagements_org',
      'idx_engagements_initiative', 'idx_engagements_kind',
      'idx_engagements_status', 'idx_engagements_active']) {
      assert.ok(sql.includes(idx), `Must have index: ${idx}`);
    }
  });

  // Backfill validation
  await t.test('backfills primary engagements from operational_role', () => {
    assert.match(sql, /FROM public\.members m/i);
    assert.match(sql, /JOIN public\.persons p/i);
    assert.ok(sql.includes('operational_role'));
  });

  await t.test('maps researcher → volunteer kind', () => {
    assert.ok(sql.includes("'researcher'") && sql.includes("'volunteer'"));
  });

  await t.test('maps tribe_leader → volunteer kind with leader role', () => {
    assert.ok(sql.includes("'tribe_leader'") && sql.includes("'leader'"));
  });

  await t.test('creates separate engagements for ambassador designation', () => {
    assert.match(sql, /ambassador.*ANY.*designations/i);
  });

  await t.test('creates separate engagements for chapter_board designation', () => {
    assert.match(sql, /chapter_board.*ANY.*designations/i);
  });

  await t.test('creates separate engagements for founder designation', () => {
    assert.match(sql, /founder.*ANY.*designations/i);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Cross-cutting
// ═══════════════════════════════════════════════════════════════════════════
test('All Phase 3 migrations include PostgREST reload', async (t) => {
  const phase3Files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes('v4_phase3'));
  for (const file of phase3Files) {
    await t.test(`${file} has NOTIFY pgrst`, () => {
      const sql = readFileSync(resolve(MIGRATIONS_DIR, file), 'utf8');
      assert.match(sql, /NOTIFY pgrst/i);
    });
  }
});
