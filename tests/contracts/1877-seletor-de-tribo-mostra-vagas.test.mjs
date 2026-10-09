// tests/contracts/1877-seletor-de-tribo-mostra-vagas.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
// (DB-aware: the C layer opens a connection. A and B are hermetic.)
/**
 * #1877 — the tribe picker shows the free slots of each tribe, and a tribe can be taken out of self-service.
 *
 * Measured 2026-10-08, before reopening the tribe request window: 13 active research tribes listed, 3 of them
 * full. The full error only came at submit, after the person wrote a 50-character motivation. A pilot tribe
 * whose places are filled by a separate process was listed like any other, so reopening the window would
 * have exposed it. Decision of the GP the same day: show the slots, keep the pilot out of self-service.
 *
 * The flag lives on the tribe (`initiatives.metadata.self_request_closed`), never as a number in code.
 *
 * Layers:
 *   A (static, SQL)  the context lists only tribes WITHOUT the flag and carries `slots_left` from the same cap
 *                    and the same view the request gate counts; the request gate REFUSES a flagged tribe.
 *   B (static, FE)   a tribe with `slots_left <= 0` renders a DISABLED radio, not just a label.
 *   C (live)         every flagged tribe is an active research tribe (a flag on something else protects
 *                    nothing), and at least one flagged tribe exists (else A's filter is vacuous today).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const CTX = maskLineComments(latestFunctionCapture(ROOT, 'get_my_tribe_request_context').body);
const RTA = maskLineComments(latestFunctionCapture(ROOT, 'request_tribe_assignment').body);
const BLOCK = readFileSync(resolve(ROOT, 'src/components/tribe/TribeRequestBlock.tsx'), 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, (m) => ' '.repeat(m.length))
  .replace(/(^|[^:])\/\/[^\n]*/g, (m, p) => p + ' '.repeat(m.length - p.length));

// The statement that builds v_tribes, cut out so every assertion is about the block that decides.
function tribesBlock() {
  const end = CTX.indexOf('INTO v_tribes');
  assert.ok(end > 0, 'get_my_tribe_request_context no longer builds v_tribes');
  const start = CTX.lastIndexOf('SELECT coalesce(', end);
  const stop = CTX.indexOf(';', end);
  return CTX.slice(start, stop);
}

test('#1877 A: the picker list excludes a flagged tribe, in the WHERE that builds it', () => {
  assert.match(
    tribesBlock(),
    /WHERE[\s\S]*i\.kind\s*=\s*'research_tribe'[\s\S]*AND\s+\(i\.metadata->>'self_request_closed'\)::boolean\s+IS\s+NOT\s+TRUE/,
    'the v_tribes WHERE must drop tribes flagged self_request_closed',
  );
});

test('#1877 A: slots_left uses the request gate cap and the same canonical view', () => {
  assert.match(
    tribesBlock(),
    /'slots_left'\s*,\s*greatest\(\s*public\.tribe_capacity_limit\(\)\s*-\s*\(\s*SELECT\s+count\(\*\)\s+FROM\s+public\.v_tribe_active_members\s+v\s+WHERE\s+v\.legacy_tribe_id\s*=\s*i\.legacy_tribe_id\s*\)\s*,\s*0\s*\)/,
    'slots_left must be cap minus the canonical active count, floored at 0',
  );
  // The gate counts the same way; if it ever stops, the badge and the gate disagree.
  assert.match(RTA, /FROM\s+public\.v_tribe_active_members\s+v\s+WHERE\s+v\.legacy_tribe_id\s*=\s*p_tribe_id/);
  assert.match(RTA, /v_max_slots\s+integer\s*:=\s*public\.tribe_capacity_limit\(\)/);
});

test('#1877 A: the request gate refuses a flagged tribe (the picker is not the gate)', () => {
  assert.match(
    RTA,
    /IF\s+\(v_initiative\.metadata->>'self_request_closed'\)::boolean\s+IS\s+TRUE\s+THEN\s+RAISE\s+EXCEPTION/,
    'request_tribe_assignment must RAISE when the tribe is flagged',
  );
  // Order: the flag check runs before the invitation INSERT, or a refused request would still leave a row.
  assert.ok(
    RTA.search(/self_request_closed'\)::boolean\s+IS\s+TRUE/) < RTA.indexOf('INSERT INTO public.initiative_invitations'),
    'the flag check must run before the invitation is inserted',
  );
});

test('#1877 B: a full tribe renders a disabled radio', () => {
  assert.match(BLOCK, /const\s+full\s*=\s*typeof\s+tr\.slots_left\s*===\s*'number'\s*&&\s*tr\.slots_left\s*<=\s*0/);
  assert.match(BLOCK, /name="tribe-request"[\s\S]{0,200}disabled=\{full\}/, 'the radio itself must be disabled');
});

test('#1877 B: the slot badge copy exists in the 3 languages', () => {
  for (const [label, re] of [
    ['pt-BR', /slotsLeft:\s*\(n\)\s*=>\s*`\$\{n\} vaga/],
    ['en-US', /slotsLeft:\s*\(n\)\s*=>\s*`\$\{n\} spot/],
    ['es-LATAM', /slotsLeft:\s*\(n\)\s*=>\s*`\$\{n\} cupo/],
  ]) assert.match(BLOCK, re, `slotsLeft missing for ${label}`);
});

test('#1877 C (live): every flagged tribe is an active research tribe, and one exists', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await supa.from('initiatives').select('kind, status, legacy_tribe_id, metadata');
  assert.equal(error, null, error ? `select failed: ${error.message}` : '');
  const flagged = (data ?? []).filter((r) => r.metadata?.self_request_closed === true);
  assert.ok(flagged.length >= 1, 'no tribe is flagged: the picker filter has nothing to exclude today');
  for (const r of flagged) {
    assert.equal(r.kind, 'research_tribe', `flag on a non-tribe initiative (${r.kind}) protects nothing`);
    assert.ok(r.legacy_tribe_id != null, 'flagged tribe without legacy_tribe_id cannot reach the picker');
  }
});
