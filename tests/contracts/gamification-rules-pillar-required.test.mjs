// gamification_rules.pillar required column contract test (p171 #14)
// -----------------------------------------------------------------------------
// Scans all migrations for INSERT INTO public.gamification_rules statements and
// asserts that the `pillar` column is referenced in each. The DB enforces
// NOT NULL + CHECK (pillar in 6 valid values) at the schema level, but a
// future INSERT statement that forgets pillar would either:
//   (a) fail loudly (good) or
//   (b) silently succeed via DEFAULT/trigger fallback (bad, masks intent).
//
// Sediment p138 (supabase-js INSERT silencioso 400) — even loud DB failures
// can be masked by callers without `.throwOnError()`. This test ensures any
// new migration author can't accidentally introduce an INSERT without pillar
// (which would also fail to compile against the catalog of allowed pillars).
//
// p171 — closing P162_GAP item #14 (preventive contract).

import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const MIGRATIONS_DIR = path.join(__dirname, '..', '..', 'supabase', 'migrations');

const migrations = fs.readdirSync(MIGRATIONS_DIR)
  .filter(f => f.endsWith('.sql'))
  .sort()
  .map(f => ({ name: f, content: fs.readFileSync(path.join(MIGRATIONS_DIR, f), 'utf-8') }));

const stripSqlLineComments = (sql) => sql.replace(/--[^\n]*/g, '');

// Migrations that introduced pillar column itself OR that pre-date it.
// Pillar column was added 2026-04-15 in `20260649000000_p162_gamification_pillar_column.sql`
// via ALTER TABLE + UPDATE backfill (UPDATE statements don't need to set pillar
// as the SET clause IS the pillar assignment).
const PILLAR_COLUMN_INTRO_VERSION = '20260649000000';

// Pre-pillar migrations: pillar didn't exist yet, so INSERTs naturally omit it.
// Post-pillar migrations: must include pillar in any INSERT INTO gamification_rules.
function isPostPillarMigration(filename) {
  const versionMatch = filename.match(/^(\d{14})/);
  if (!versionMatch) return false;
  return versionMatch[1] >= PILLAR_COLUMN_INTRO_VERSION;
}

test('gamification_rules — every post-2026-04-15 INSERT includes pillar column', () => {
  const violations = [];

  for (const m of migrations) {
    if (!isPostPillarMigration(m.name)) continue;

    const sql = stripSqlLineComments(m.content);
    // Match INSERT INTO [public.]gamification_rules ( col1, col2, ... )
    // capture only the column list to validate
    const regex = /INSERT\s+INTO\s+(?:public\.)?gamification_rules\s*\(([^)]+)\)/gi;
    let match;
    while ((match = regex.exec(sql)) !== null) {
      const columnList = match[1].toLowerCase().replace(/\s+/g, ' ');
      // Must contain pillar as a column name (word boundary to avoid false matches like "pillar_foo")
      if (!/\bpillar\b/.test(columnList)) {
        violations.push({
          migration: m.name,
          columns: match[1].trim(),
        });
      }
    }
  }

  if (violations.length > 0) {
    const lines = violations.map(v => `  - ${v.migration}\n      columns: (${v.columns})`).join('\n');
    assert.fail(
      `Found ${violations.length} INSERT INTO gamification_rules without pillar column ` +
      `(post-${PILLAR_COLUMN_INTRO_VERSION}):\n${lines}\n\n` +
      `Fix: add 'pillar' to the column list and provide a valid value ` +
      `(presenca, trilha, certificacoes, producao, curadoria, champions).`
    );
  }
});

test('gamification_rules — pillar CHECK constraint values match catalog', () => {
  // Sanity: the catalog of allowed pillars matches what we expect (6 values).
  // If a future migration adds a 7th pillar, both the CHECK constraint AND
  // this test should be updated together — forcing the author to think
  // through downstream impact (get_gamification_leaderboard, gamification panels, etc).
  const VALID_PILLARS = new Set([
    'presenca', 'trilha', 'certificacoes', 'producao', 'curadoria', 'champions'
  ]);

  // Find latest constraint definition in migrations
  const allSQL = migrations.map(m => stripSqlLineComments(m.content)).join('\n');
  // Match ADD CONSTRAINT ... CHECK (pillar = ANY (ARRAY[...]))
  // or CHECK ((pillar = ANY (ARRAY[...])))
  const constraintRegex = /CHECK\s*\(\s*\(?\s*pillar\s*=\s*ANY\s*\(\s*ARRAY\s*\[([^\]]+)\]/gi;
  const matches = [...allSQL.matchAll(constraintRegex)];

  if (matches.length === 0) {
    // No declarative CHECK found in migrations — could be added via ALTER TABLE in a way our regex misses.
    // Skip rather than fail; the DB-level constraint is the source of truth.
    return;
  }

  // Take the last (most recent) declaration
  const lastDecl = matches[matches.length - 1][1];
  const declaredPillars = new Set(
    [...lastDecl.matchAll(/'([^']+)'/g)].map(m => m[1])
  );

  // Bidirectional check
  for (const p of declaredPillars) {
    assert.ok(
      VALID_PILLARS.has(p),
      `Pillar '${p}' declared in CHECK constraint but not in test allowlist. ` +
      `If this is intentional (new pillar), add it to VALID_PILLARS and update ` +
      `get_gamification_leaderboard + gamification panels.`
    );
  }
  for (const p of VALID_PILLARS) {
    assert.ok(
      declaredPillars.has(p),
      `Pillar '${p}' in test allowlist but not in latest CHECK constraint. ` +
      `Sync test or CHECK declaration.`
    );
  }
});
