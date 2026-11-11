/**
 * Contract: the non-signed partner_chapters state is 'participating_pending_signature' (GP 11/11/2026),
 * replacing 'announced_at_risk' (#1175 D2). The 10 chapters announced at the CBGPL take part while
 * their agreement awaits signature; the label must not read as "at risk".
 *
 * The #1175 D2 guard keeps asserting its own (immutable) migration. This guard asserts the LATEST
 * CHECK domain across all migrations, the remap of the old value inside the same migration, and that
 * no function body gates on the old value.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
const MIG_FILE = '20261111035326_partner_status_participating_pending_signature.sql';
const MIG = readFileSync(join(MIGRATIONS_DIR, MIG_FILE), 'utf8');
const stripComments = (s) => s.replace(/--[^\n]*/g, '');

test('the latest partnership_status CHECK is signed / participating_pending_signature', () => {
  const checks = [];
  for (const f of files) {
    const sql = stripComments(readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
    for (const m of sql.matchAll(/CHECK\s*\(\s*partnership_status\s+IN\s*\(([^)]*)\)\s*\)/gi)) {
      checks.push({ f, values: m[1].replace(/\s+/g, '') });
    }
  }
  assert.ok(checks.length > 0, 'no CHECK on partnership_status found');
  const last = checks[checks.length - 1];
  assert.equal(last.f, MIG_FILE, `the latest CHECK must come from ${MIG_FILE}, got ${last.f}`);
  assert.equal(last.values, "'signed','participating_pending_signature'");
});

test('the migration remaps the old value to the new one, before the new CHECK', () => {
  const body = stripComments(MIG);
  const update = body.search(
    /UPDATE\s+public\.partner_chapters\s+SET\s+partnership_status\s*=\s*'participating_pending_signature'\s+WHERE\s+partnership_status\s*=\s*'announced_at_risk'/i,
  );
  const add = body.search(/ADD\s+CONSTRAINT\s+partner_chapters_partnership_status_check/i);
  assert.ok(update >= 0, 'the UPDATE from announced_at_risk to participating_pending_signature is missing');
  assert.ok(add > update, 'the new CHECK must be added after the remap');
});

test('no function captured after the change gates on the old value', () => {
  const after = files.filter((f) => f > MIG_FILE);
  for (const f of after) {
    const sql = stripComments(readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
    assert.ok(!/'announced_at_risk'/.test(sql), `${f} still cites 'announced_at_risk'`);
  }
});
