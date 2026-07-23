/**
 * Contract: #1350 request_tribe_assignment must block (with a clear message) a full tribe,
 * and the clear message must reach the user on BOTH surfaces (request + leader review).
 *
 * Migration: supabase/migrations/20260805000431_1350_request_tribe_assignment_capacity_gate.sql
 *
 * Root cause: the capacity gate lived only on approve (review_tribe_request) + legacy select_tribe.
 * request_tribe_assignment had none, so a request against a full tribe entered as pending but was
 * un-approvable (leader's approve raised "Tribo lotada" -> HTTP 400). Anchor: Guilherme -> Tribo 6 (8/8).
 *
 * Invariants (static — the DB behaviour was proven live via an impersonated rolled-back DO block in
 * the PR: full tribe 6 -> RAISE 'Tribo lotada (8/8)', open tribe 5 -> ok=true; request_tribe_assignment
 * depends on auth.uid() so it can't be driven from a service-role client without mutating live data):
 *  - migration re-captures request_tribe_assignment;
 *  - it gates on tribe_capacity_limit() with the SAME slot formula as review_tribe_request
 *    (operational_role NOT IN sponsor/chapter_liaison/guest/none — the leader counts);
 *  - the gate raises "Tribo lotada" and sits BEFORE the INSERT INTO initiative_invitations
 *    (so no un-approvable pending is created);
 *  - FE surfaces the message on both surfaces (not the generic error):
 *    - TribeRequestBlock (request): COPY.toastFull in all 3 langs + /lotad/ branch in submit;
 *    - tribe/[id].astro (leader review): reqToastFull wired + /lotad/ branch + key in all 3 dicts.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG = 'supabase/migrations/20260805000431_1350_request_tribe_assignment_capacity_gate.sql';
const mig = read(MIG);

test('#1350: migration present + re-captures request_tribe_assignment', () => {
  assert.ok(existsSync(resolve(ROOT, MIG)), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.request_tribe_assignment\(/);
});

// #1476 Onda 1 rebased request_tribe_assignment's slot formula onto the canonical set
// (v_tribe_active_members). The gate BEHAVIOUR is unchanged (cap from SSOT, blocks at/over cap,
// "Tribo lotada" before the INSERT); only the counting source moved off operational_role. The
// live definition now lives in mig 484 — assert there, not against the stale 431 formula.
const MIG_1476 = 'supabase/migrations/20260805000484_1476_wave1_tribe_membership_canonical.sql';
const mig1476 = read(MIG_1476);

test('#1350/#1476: capacity gate uses tribe_capacity_limit() + the canonical slot formula', () => {
  assert.match(mig1476, /CREATE OR REPLACE FUNCTION public\.request_tribe_assignment\(/, '484 recaptures request_tribe_assignment');
  assert.match(mig1476, /v_max_slots integer := public\.tribe_capacity_limit\(\)/, 'cap from SSOT');
  // slot count now derives from the engagement-based canonical set, not the operational_role label
  assert.match(mig1476, /SELECT count\(\*\) INTO v_slot_count\s*\n\s*FROM public\.v_tribe_active_members v\s*\n\s*WHERE v\.legacy_tribe_id = p_tribe_id;/,
    'slot count derives from v_tribe_active_members (canonical, engagement-based)');
  assert.match(mig1476, /v_slot_count >= v_max_slots/, 'blocks at/over cap');
  assert.match(mig1476, /RAISE EXCEPTION 'Tribo lotada \(%\/%\)/, 'clear "Tribo lotada (X/Y)" message');
});

test('#1350/#1476: gate sits BEFORE the invitation INSERT (no un-approvable pending is created)', () => {
  const gateIdx = mig1476.indexOf("RAISE EXCEPTION 'Tribo lotada");
  const insertIdx = mig1476.indexOf('INSERT INTO public.initiative_invitations');
  assert.ok(gateIdx > 0 && insertIdx > 0, 'both present');
  assert.ok(gateIdx < insertIdx, 'capacity RAISE precedes the pending INSERT');
});

test('#1350 FE (request): TribeRequestBlock surfaces toastFull in all 3 langs + branches on /lotad/', () => {
  const fe = read('src/components/tribe/TribeRequestBlock.tsx');
  assert.ok(fe, 'TribeRequestBlock present');
  const full = fe.match(/toastFull:/g) || [];
  assert.ok(full.length >= 3, `toastFull defined in all 3 langs (found ${full.length})`);
  assert.match(fe, /toastFull: string;/, 'toastFull is on the Copy type');
  assert.match(fe, /\/lotad\/i\.test\(msg\)\s*\?\s*copy\.toastFull/, 'submit branches to toastFull on a full-tribe error');
});

test('#1350 FE (review): tribe/[id].astro surfaces reqToastFull + branches on /lotad/', () => {
  const page = read('src/pages/tribe/[id].astro');
  assert.ok(page, '[id].astro present');
  assert.match(page, /reqToastFull: t\('tribe\.requests\.toastFull', lang\)/, 'reqToastFull wired from the dict');
  assert.match(page, /\/lotad\/i\.test\(emsg\)\s*\?\s*\(I18N\.reqToastFull/, 'review branches to reqToastFull on a full-tribe error');
});

test('#1350 i18n: tribe.requests.toastFull exists in all 3 dictionaries', () => {
  for (const dict of ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts']) {
    const d = read(dict);
    assert.match(d, /'tribe\.requests\.toastFull':/, `${dict} has tribe.requests.toastFull`);
  }
});
