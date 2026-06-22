import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

// #842 — governance comment inheritance must reach UNLOCKED predecessors.
//
// p93b gated the prior version (comment inheritance + the "anterior↔atual" diff baseline)
// on `dv.locked_at IS NOT NULL`. A version superseded WITHOUT being locked (real case: TAP
// CPMAI doc d7447a94 — R00 chain=superseded, locked=false, 4 unresolved comments; R01
// current/locked shows 0) escaped that gate, hiding R00's open comments from the R01 reviewer.
//
// Fix (signal-only): relax the predecessor predicate in both get_previous_locked_version and
// list_document_comments to the "exclude only chain.status='withdrawn'" model. Read-only /
// additive — no comment rows mutated. This test pins that the locked_at gate is gone and the
// withdrawn-exclusion is present, so a future careless edit can't silently re-introduce the gap.

const MIGRATION_PATH = 'supabase/migrations/20260805000235_p842_comment_inheritance_unlocked_predecessor.sql';

describe('#842 — comment inheritance reaches unlocked predecessors', () => {
  it('migration file exists at canonical timestamp', () => {
    assert.ok(existsSync(MIGRATION_PATH), `missing ${MIGRATION_PATH}`);
  });

  const SQL = existsSync(MIGRATION_PATH) ? readFileSync(MIGRATION_PATH, 'utf8') : '';

  // Helper: isolate the body of one CREATE OR REPLACE FUNCTION block, with `-- ...` line
  // comments stripped so an explanatory comment (which quotes the OLD gate) can't false-match.
  function fnBody(name) {
    const start = SQL.indexOf(`CREATE OR REPLACE FUNCTION public.${name}`);
    assert.ok(start >= 0, `${name} not (re)defined in migration`);
    // up to the next CREATE OR REPLACE (or end of file)
    const next = SQL.indexOf('CREATE OR REPLACE FUNCTION', start + 1);
    const block = SQL.slice(start, next === -1 ? undefined : next);
    return block.replace(/--.*$/gm, '');
  }

  it('redefines both predecessor RPCs', () => {
    assert.ok(SQL.includes('CREATE OR REPLACE FUNCTION public.get_previous_locked_version'));
    assert.ok(SQL.includes('CREATE OR REPLACE FUNCTION public.list_document_comments'));
  });

  it('get_previous_locked_version no longer gates the predecessor on locked_at IS NOT NULL', () => {
    const body = fnBody('get_previous_locked_version');
    assert.ok(!/locked_at\s+IS\s+NOT\s+NULL/i.test(body),
      'locked_at IS NOT NULL gate must be removed from the predecessor query');
    assert.match(body, /status\s*=\s*'withdrawn'/i,
      'must keep the withdrawn-chain exclusion to drop IP-1 seeds');
  });

  it('list_document_comments inherits prior versions without the locked_at gate, excluding withdrawn', () => {
    const body = fnBody('list_document_comments');
    assert.ok(!/locked_at\s+IS\s+NOT\s+NULL/i.test(body),
      'prior-version inheritance branch must not require locked_at');
    assert.match(body, /p_include_prior_versions/,
      'inheritance is still opt-in via p_include_prior_versions');
    assert.match(body, /status\s*=\s*'withdrawn'/i,
      'withdrawn-exclusion now does the seed-filtering that locked_at used to');
    // provenance fields kept so the UI can badge inherited comments
    assert.match(body, /is_inherited/);
    assert.match(body, /from_version_label/);
  });

  it('does not mutate comment rows (signal-only: no UPDATE/INSERT on document_comments)', () => {
    assert.ok(!/\b(UPDATE|INSERT\s+INTO|DELETE\s+FROM)\s+(public\.)?document_comments\b/i.test(SQL),
      'fix must be read-only — no carry-forward mutation of document_comments');
  });
});
