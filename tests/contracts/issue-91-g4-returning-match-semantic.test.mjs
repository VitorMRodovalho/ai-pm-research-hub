/**
 * #91 G4 contract — `is_returning_member` predicate is tied to
 * `member_offboarding_records`, not to broad "any member match".
 *
 * Background: the original `import_vep_applications` body flipped the flag
 * whenever any active member shared the email; later it drifted to flip on
 * any member match (including active members promoted from the same cycle).
 * The G4 panel only renders useful content when an offboarding record exists,
 * so the import predicate must match exactly that data source.
 *
 * This contract walks the migration files (the live function body is captured
 * in 20260514020000_*) and asserts the new predicate is present + plumbed
 * through the INSERT.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const FIX = resolve(
  ROOT,
  'supabase/migrations/20260514020000_issue_91_g4_fix_returning_match_semantic.sql'
);
const RESYNC = resolve(
  ROOT,
  'supabase/migrations/20260514030000_issue_91_g4_resync_is_returning_member.sql'
);

const fixSQL = readFileSync(FIX, 'utf8');
const resyncSQL = readFileSync(RESYNC, 'utf8');

test('#91 G4: import_vep_applications declares the tightened returning predicate', () => {
  assert.match(
    fixSQL,
    /v_is_returning_offboarded\s+boolean/i,
    'Fix migration must declare v_is_returning_offboarded boolean local.'
  );
  assert.match(
    fixSQL,
    /v_is_returning_offboarded\s*:=\s*v_existing_member\.id\s+IS\s+NOT\s+NULL\s+AND\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+member_offboarding_records/i,
    'Predicate must require a matched member AND an existing offboarding record.'
  );
});

test('#91 G4: INSERT writes v_is_returning_offboarded to is_returning_member', () => {
  // Find the INSERT INTO selection_applications (...) VALUES (...) block.
  const insertMatch = fixSQL.match(
    /INSERT\s+INTO\s+selection_applications[\s\S]*?VALUES\s*\(([\s\S]*?)\)\s*RETURNING/i
  );
  assert.ok(insertMatch, 'Migration must contain the selection_applications INSERT.');
  assert.match(
    insertMatch[1],
    /v_is_returning_offboarded/,
    'INSERT VALUES must thread v_is_returning_offboarded through to is_returning_member.'
  );
});

test('#91 G4: returning_members counter uses the same predicate', () => {
  assert.match(
    fixSQL,
    /IF\s+v_is_returning_offboarded\s+THEN\s+v_returning\s*:=\s*v_returning\s*\+\s*1\s*;\s*END\s+IF;/i,
    'Counter must increment from the same predicate so the import summary stays accurate.'
  );
});

test('#91 G4: resync migration converges flag with new predicate (idempotent)', () => {
  // Resync must SET is_returning_member = EXISTS (... member_offboarding_records ...)
  assert.match(
    resyncSQL,
    /SET\s+is_returning_member\s*=\s*EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+member_offboarding_records/i,
    'Resync must align the flag with the offboarding-records predicate.'
  );
  // And gate on a current-state mismatch so re-running is a no-op.
  assert.match(
    resyncSQL,
    /WHERE\s+sa\.is_returning_member\s*<>\s*EXISTS/i,
    'Resync UPDATE must short-circuit rows already in sync (idempotency).'
  );
});
