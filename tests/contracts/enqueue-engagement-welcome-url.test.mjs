// BUG-212.A contract: _enqueue_engagement_welcome() generates the engagement
// welcome notification link. Must point to /initiative/<id> (real route),
// NOT /iniciativas/<id> (legacy PT-BR path that 404s).
//
// Original bug (Issue #217): every engagement welcome email since ADR-0060 G7
// deployment had a broken link. Fixed by migration 20260802000007 (p211).
//
// Strategy: locate the LATEST CREATE OR REPLACE FUNCTION block for this
// function across supabase/migrations/ (lexicographically max filename wins),
// then assert the body has the correct path. If a future migration regresses
// by reintroducing /iniciativas/, this test fails before deploy.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const MIGRATIONS_DIR = join(process.cwd(), 'supabase', 'migrations');
const FN_NAME = '_enqueue_engagement_welcome';

function latestBodyFor(fnName) {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort(); // lexicographic = chronological for YYYYMMDDhhmmss-prefixed names

  const pattern = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${fnName}\\s*\\(`,
    'i'
  );
  // Match from CREATE OR REPLACE through the *closing* dollar-quoted body terminator
  // `$function$;` (the opening is `AS $function$` — same delimiter, so we want the
  // SECOND occurrence). Greedy match across newlines.
  const bodyPattern = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${fnName}\\s*\\([\\s\\S]*?\\$function\\$[\\s\\S]*?\\$function\\$\\s*;?`,
    'i'
  );

  let latestBody = null;
  let latestFile = null;

  for (const file of files) {
    const content = readFileSync(join(MIGRATIONS_DIR, file), 'utf8');
    if (pattern.test(content)) {
      const m = content.match(bodyPattern);
      if (m) {
        latestBody = m[0];
        latestFile = file;
      }
    }
  }
  return { body: latestBody, file: latestFile };
}

test('_enqueue_engagement_welcome links to /initiative/ not /iniciativas/ (BUG-212.A #217)', () => {
  const { body, file } = latestBodyFor(FN_NAME);
  assert.ok(body, `Function ${FN_NAME} must be defined in at least one migration file`);
  assert.ok(
    body.includes("'/initiative/'"),
    `Latest body (${file}) must use '/initiative/' route`
  );
  assert.ok(
    !body.includes("'/iniciativas/'"),
    `Latest body (${file}) must NOT use legacy '/iniciativas/' route — would 404 (BUG-212.A regression)`
  );
});
