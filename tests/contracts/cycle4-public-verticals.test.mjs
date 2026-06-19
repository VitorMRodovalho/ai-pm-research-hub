/**
 * Contract: Cycle 4 Fatia B1 — public data layer for the verticals landing.
 *
 * Migration 20260805000222 adds:
 *  (1) get_public_verticals() — anon-safe SECURITY DEFINER list of community_vertical
 *      initiatives for the hub-and-spoke (bloco 3) + CTA (bloco 6). It surfaces ONLY
 *      config keys from metadata; metadata.intended_lead (person name/id = LGPD PII)
 *      is deliberately NOT selected.
 *  (2) visitor_leads.target_vertical (uuid FK) + capture_visitor_lead resolving it
 *      defensively (real community_vertical or NULL) — founder interest per vertical.
 *  (3) get_public_platform_stats.total_verticals — live counter (bloco 2).
 *
 * Ref: ADR-0103, docs/strategy/cycle4_landing_value_prop.md (§5a, §4, §3).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG = 'supabase/migrations/20260805000222_cycle4_b1_public_verticals.sql';
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'SUPABASE_URL + key env vars required (DB-aware)';

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('mig 222 static: get_public_verticals is anon-executable and PII-safe', () => {
  assert.ok(existsSync(MIG), 'migration 222 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_public_verticals\(\)/);
  assert.match(body, /SECURITY DEFINER/);
  assert.match(body, /REVOKE ALL ON FUNCTION public\.get_public_verticals\(\) FROM PUBLIC;/);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.get_public_verticals\(\) TO anon, authenticated, service_role;/);
  assert.match(body, /WHERE i\.kind = 'community_vertical'\s+AND i\.status = 'active'/,
    'only active community_vertical initiatives are public');
  // PII guard: scope to the function definition (the file header comment legitimately
  // names intended_lead to document the guard). The SELECT list must not touch it.
  const fnStart = body.indexOf('CREATE OR REPLACE FUNCTION public.get_public_verticals()');
  const fnBody = body.slice(fnStart, body.indexOf('GRANT EXECUTE ON FUNCTION public.get_public_verticals'));
  assert.ok(!/intended_lead/.test(fnBody), 'public RPC body must not select metadata.intended_lead');
  assert.ok(!/i\.metadata\b(?![-]>>'(status|anchor_credential|credential_body|partner_org)')/.test(fnBody),
    'only whitelisted metadata keys are surfaced');
});

test('mig 222 static: target_vertical is a uuid FK resolved defensively in capture_visitor_lead', () => {
  assert.match(body, /ADD COLUMN IF NOT EXISTS target_vertical uuid\s+REFERENCES public\.initiatives\(id\) ON DELETE SET NULL/);
  assert.match(body, /CREATE INDEX IF NOT EXISTS idx_visitor_leads_target_vertical/);
  // defensive resolution: keep only when it points at a real community_vertical
  assert.match(body, /v_target_vertical := \(p_payload->>'target_vertical'\)::uuid;/);
  assert.match(body, /PERFORM 1 FROM public\.initiatives WHERE id = v_target_vertical AND kind = 'community_vertical';/);
  assert.match(body, /IF NOT FOUND THEN v_target_vertical := NULL; END IF;/);
});

test('mig 222 static: total_verticals added to get_public_platform_stats', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_public_platform_stats\(\)/);
  assert.match(body, /'total_verticals',\s*\(\s*SELECT count\(\*\) FROM public\.initiatives\s+WHERE kind = 'community_vertical' AND status = 'active'/);
});

// ── DB-GATED ──────────────────────────────────────────────────────────────────────
const svc = () => createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

test('behavioural: get_public_verticals returns shaped rows with vertical_status, zero PII', { skip: anonGated ? false : skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await anon.rpc('get_public_verticals');
  assert.ifError(error);
  assert.ok(Array.isArray(data), 'returns a json array');
  const raw = JSON.stringify(data);
  assert.ok(!/intended_lead/.test(raw) && !/person_id/.test(raw),
    'no intended_lead / person_id PII leaks to anon');
  for (const v of data) {
    assert.deepEqual(Object.keys(v).sort(),
      ['anchor_credential', 'credential_body', 'description', 'id', 'partner_org', 'title', 'vertical_status'],
      'exactly the whitelisted public keys');
    assert.ok(['forming', 'open', 'paused', null].includes(v.vertical_status));
  }
});

test('behavioural: total_verticals == live count of active community_vertical', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = svc();
  const { data: stats, error: e1 } = await sb.rpc('get_public_platform_stats');
  assert.ifError(e1);
  const { count, error: e2 } = await sb
    .from('initiatives')
    .select('id', { count: 'exact', head: true })
    .eq('kind', 'community_vertical')
    .eq('status', 'active');
  assert.ifError(e2);
  assert.equal(Number(stats.total_verticals), Number(count),
    'total_verticals tracks the live active community_vertical count');
});

test('behavioural: capture_visitor_lead resolves target_vertical defensively (real → kept, bogus → NULL)', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = svc();
  const { data: verticals } = await sb.rpc('get_public_verticals');
  const realId = verticals?.[0]?.id ?? null;
  const bogusId = '00000000-0000-0000-0000-000000000000';
  const stamp = `cycle4-b1-contract-${process.pid}-${realId ? 'a' : 'b'}`;
  const emails = [`${stamp}-real@example.test`, `${stamp}-bogus@example.test`];

  try {
    // bogus uuid (well-formed, non-existent) must store NULL, never block capture
    const { data: r2, error: e2 } = await sb.rpc('capture_visitor_lead', {
      p_payload: { name: 'B1 Bogus', email: emails[1], lgpd_consent: true, target_vertical: bogusId, source: 'contract-test' },
    });
    assert.ifError(e2);
    assert.equal(r2.success, true);
    const { data: lead2 } = await sb.from('visitor_leads').select('target_vertical').eq('id', r2.lead_id).single();
    assert.equal(lead2.target_vertical, null, 'bogus vertical resolves to NULL (defensive)');

    if (realId) {
      const { data: r1, error: e1 } = await sb.rpc('capture_visitor_lead', {
        p_payload: { name: 'B1 Real', email: emails[0], lgpd_consent: true, target_vertical: realId, source: 'contract-test' },
      });
      assert.ifError(e1);
      assert.equal(r1.success, true);
      const { data: lead1 } = await sb.from('visitor_leads').select('target_vertical').eq('id', r1.lead_id).single();
      assert.equal(lead1.target_vertical, realId, 'real community_vertical uuid is persisted');
    }
  } finally {
    await sb.from('visitor_leads').delete().in('email', emails);
  }
});

test('ACL: anon can execute get_public_verticals', { skip: anonGated ? false : skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('get_public_verticals');
  assert.ifError(error);
});
