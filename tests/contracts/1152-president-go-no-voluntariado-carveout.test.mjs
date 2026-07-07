/**
 * #1152 — president_go gate must NOT include the voluntariado_director carve-out.
 *
 * The president_go predicate in _can_sign_gate fused two roles for volunteer_term_template:
 * legal_signer (Ivan, SEDE — the correct legal signatory of the version) AND voluntariado_director
 * (Lorena — whose real function is the COUNTERPARTY of the signed instrument with the volunteer,
 * not a version-approval gate). Migration 20260805000353 removes the carve-out so president_go
 * always requires legal_signer (uniform with president_others).
 *
 * Static guard (mirrors repo convention for DDL-body invariants): the coverage + body-drift
 * contract tests pin the live function to this migration, so asserting the migration text is
 * sufficient to lock the fix against regression.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIG_DIR = join(__dirname, '..', '..', 'supabase', 'migrations');

function latestCanSignGateMigration() {
  const files = readdirSync(MIG_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  // newest migration that (re)defines _can_sign_gate is the authoritative body
  for (let i = files.length - 1; i >= 0; i--) {
    const body = readFileSync(join(MIG_DIR, files[i]), 'utf8');
    if (/CREATE OR REPLACE FUNCTION public\._can_sign_gate\b/.test(body)) {
      return { file: files[i], body };
    }
  }
  return null;
}

function presidentGoBranch(body) {
  // isolate the WHEN 'president_go' THEN ... branch up to the next WHEN
  const m = body.match(/WHEN 'president_go' THEN([\s\S]*?)WHEN 'president_others'/);
  return m ? m[1] : null;
}

test('#1152 — latest _can_sign_gate migration exists', () => {
  const latest = latestCanSignGateMigration();
  assert.ok(latest, 'a migration defining _can_sign_gate must exist');
});

test('#1152 — president_go requires legal_signer and has NO voluntariado_director carve-out', () => {
  const latest = latestCanSignGateMigration();
  assert.ok(latest, 'migration present');
  const branch = presidentGoBranch(latest.body);
  assert.ok(branch, 'president_go branch must be parseable');
  assert.match(branch, /'legal_signer' = ANY\(v_member\.designations\)/, 'president_go must require legal_signer');
  assert.doesNotMatch(
    branch,
    /voluntariado_director/,
    'president_go must NOT carve out voluntariado_director (#1152 — that role is the instrument counterparty, not a version gate)'
  );
  assert.match(branch, /v_member\.chapter = 'PMI-GO'/, 'president_go still scoped to PMI-GO board');
});
