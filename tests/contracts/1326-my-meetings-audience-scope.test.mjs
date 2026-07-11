/**
 * Contract: #1326 — get_my_meetings escopa por AUDIÊNCIA real, não pelo proxy `initiative_id IS NULL`.
 *
 * Incidente (2026-07-11, reportado pela membra Ligia Ribeiro): a widget "Minhas reuniões" mostrava
 * entrevistas de candidatos e reuniões de liderança para TODO membro, porque o escopo usava
 * `e.initiative_id IS NULL` como proxy de "evento geral" — e entrevista/lideranca/1on1 também têm
 * initiative_id NULL. Consequências: lideranca (rule role) barrava no register_own_presence com
 * not_in_audience (o erro do print), e entrevista SEM rule pulava o gate (v_has_rules=false) →
 * marcação de presença errada na entrevista de um candidato (ruído + privacidade dos candidatos).
 *
 * Fix (#1326): escopar pela audiência real, espelhando event_audience_rules como register_own_presence
 * (role/tribe/all_active_operational/specific_members) + branch explícito de tribo + histórico próprio.
 *
 * Travas:
 *  (1) static — o corpo capturado NÃO usa mais o proxy `initiative_id IS NULL` como catch-all de
 *      visibilidade, e ESPELHA os quatro target_type de event_audience_rules.
 *  (2) DB — member-scoping fail-closed: service_role (auth.uid()=null) recebe 'Forbidden'; e a
 *      superfície de vazamento EXISTE nos dados (a guarda é load-bearing).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');

function latestBodyMatching(re) {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  let body = null;
  for (const f of files) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    if (re.test(sql)) body = sql;
  }
  return body;
}

test('#1326 static: get_my_meetings scopes by audience rules, not the initiative_id-null proxy', () => {
  const body = latestBodyMatching(/CREATE OR REPLACE FUNCTION public\.get_my_meetings\s*\(/);
  assert.ok(body, 'a migration must capture CREATE OR REPLACE FUNCTION public.get_my_meetings(');
  const norm = body.replace(/\s+/g, ' ');

  // Regression guard: the blanket `e.initiative_id IS NULL` visibility catch-all must be GONE.
  // (entrevista/lideranca/1on1 all have initiative_id NULL — that proxy leaked them to everyone.)
  assert.doesNotMatch(
    norm,
    /e\.initiative_id IS NULL OR i\.legacy_tribe_id = v_tribe_id/,
    'the initiative_id-null visibility proxy must be replaced by a real audience scope (#1326)',
  );

  // Must mirror register_own_presence: query event_audience_rules with the four target types.
  assert.match(norm, /FROM public\.event_audience_rules ar/, 'must scope via event_audience_rules');
  for (const tt of ['role', 'tribe', 'all_active_operational', 'specific_members']) {
    assert.match(
      norm,
      new RegExp(`ar\\.target_type = '${tt}'`),
      `must handle audience target_type '${tt}' (parity with register_own_presence)`,
    );
  }
  // Preserved guards.
  assert.match(norm, /public\.rls_can_see_initiative\(e\.initiative_id\)/, '#785 confidential gate preserved');
  assert.match(norm, /e\.status <> 'cancelled'/, 'cancelled events excluded');
});

test('#1326 static: the audience predicate matches register_own_presence target types', () => {
  const rop = latestBodyMatching(/CREATE OR REPLACE FUNCTION public\.register_own_presence\s*\(/);
  const gmm = latestBodyMatching(/CREATE OR REPLACE FUNCTION public\.get_my_meetings\s*\(/);
  assert.ok(rop && gmm, 'both function bodies must be captured in migrations');
  const targetTypes = (s) =>
    [...s.matchAll(/ar\.target_type = '([a-z_]+)'/g)].map((m) => m[1]).sort();
  const ropTypes = [...new Set(targetTypes(rop))];
  const gmmTypes = [...new Set(targetTypes(gmm))];
  assert.deepEqual(
    gmmTypes,
    ropTypes,
    `get_my_meetings must gate on the same audience target types as register_own_presence ` +
      `(rop=${JSON.stringify(ropTypes)} gmm=${JSON.stringify(gmmTypes)})`,
  );
});

test('#1326 DB: get_my_meetings is member-scoped (service_role → Forbidden)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service_role has no auth.uid() → fail-closed. Behavioral audience filtering (a non-leader no
  // longer sees entrevista/lideranca) is verified via impersonated set_config JWT in manual QA,
  // since supabase-js cannot set request.jwt.claims + call the RPC in one transaction.
  const { error } = await sb.rpc('get_my_meetings', { p_days_back: 30, p_days_forward: 60 });
  assert.ok(error, 'service_role (auth.uid null) must be rejected (member-scoped, no IDOR)');
  assert.match(error.message, /Forbidden/i, `expected Forbidden, got: ${error.message}`);
});

test('#1326 DB: the leak surface exists — the audience guard is load-bearing', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // There ARE initiative-less entrevista/lideranca events (which the old proxy leaked to everyone).
  // If this ever drops to zero the guard is moot, but today it proves the fix is not a no-op.
  const { data, error } = await sb
    .from('events')
    .select('id, type, initiative_id')
    .is('initiative_id', null)
    .in('type', ['entrevista', 'lideranca'])
    .neq('status', 'cancelled')
    .limit(1);
  assert.ok(!error, `query must not error: ${error?.message}`);
  assert.ok(
    (data || []).length > 0,
    'expected initiative-less entrevista/lideranca events to exist (the class the proxy leaked)',
  );
});
