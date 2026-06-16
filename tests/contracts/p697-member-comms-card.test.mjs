/**
 * #697 — get_member_comms_card: comms/divulgação card lookup for banners/posts.
 *
 * The data (headshot, LinkedIn, Credly badges) already lived in persons and was already
 * returned by get_person — but there was no name lookup (you needed a person_id), the
 * get_person tool description omitted those fields, and nothing consolidated credentials
 * + roles for credits. This slice adds a dedicated RPC + MCP tool.
 *
 * Lawful basis for image use = Cláusula 11 do Termo de Voluntariado (signed term), NOT
 * persons.consent_status (a different LGPD purpose — legal-counsel 2026-06-15). The route
 * does NOT block when the term is unsigned: it returns comms_clearance=false + a reason and
 * lets the controller decide. Sensitive PII (email/phone/address) is never returned.
 *
 * Locks: (1) migration shape + authority gate via can(person_id, ...) — NOT can(auth.uid()),
 * which would always fail since can() keys on auth_engagements.person_id; (2) clearance logic;
 * (3) no sensitive-PII leak; (4) MCP tool wiring + LGPD-audit logging + get_person description;
 * (5) live gate is closed to non-authenticated callers (service_role → Not authenticated).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = readFileSync(resolve(ROOT, 'supabase/migrations/20260805000182_p697_get_member_comms_card.sql'), 'utf8');
const INDEX = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#697 migration — SECURITY DEFINER + pinned search_path', () => {
  assert.ok(MIG.length > 0, 'migration must exist');
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_member_comms_card\(/);
  assert.match(MIG, /SECURITY DEFINER/);
  assert.match(MIG, /SET search_path TO 'public', 'pg_temp'/);
});

test('#697 gate — can(person_id, manage_event/manage_member), NOT can(auth.uid())', () => {
  // can() joins auth_engagements.person_id (= persons.id); passing auth.uid() never matches.
  assert.match(MIG, /SELECT id INTO v_caller_person_id FROM public\.persons WHERE auth_id = auth\.uid\(\)/);
  assert.match(MIG, /public\.can\(v_caller_person_id, 'manage_event', NULL, NULL\)/);
  assert.match(MIG, /public\.can\(v_caller_person_id, 'manage_member', NULL, NULL\)/);
  assert.doesNotMatch(MIG, /public\.can\(auth\.uid\(\)/, 'must not pass auth.uid() into can()');
});

test('#697 clearance — Cláusula 11 via member_is_pre_onboarding, not consent_status', () => {
  assert.match(MIG, /public\.member_is_pre_onboarding\(v_target, v_member_status\)/);
  assert.match(MIG, /'clearance_reason', v_reason/);
  for (const reason of ['signed_term', 'pre_onboarding', 'no_member_record']) {
    assert.ok(MIG.includes(`'${reason}'`), `clearance reason ${reason} must be present`);
  }
  // consent_status is a different LGPD purpose — it must NOT gate comms.
  // Scope the check to executable SQL (strip `-- ...` comment lines, where we explain the why).
  const MIG_CODE = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
  assert.doesNotMatch(MIG_CODE, /consent_status/, 'consent_status must not be used in the comms gate');
});

test('#697 no sensitive-PII leak (email/phone/address/birth_date)', () => {
  // The card is non-sensitive only. None of these columns may be selected into the output.
  for (const col of ['email', 'phone', 'address', 'birth_date']) {
    assert.doesNotMatch(MIG, new RegExp(`p\\.${col}\\b`), `must not return p.${col}`);
  }
});

test('#697 excludes anonymized persons (LGPD Art.16)', () => {
  assert.match(MIG, /anonymized_at IS NULL/);
});

test('#697 consolidates credentials (from credly_badges) + roles (active engagements)', () => {
  assert.match(MIG, /jsonb_array_elements\(COALESCE\(p\.credly_badges/);
  assert.match(MIG, /'credentials',/);
  assert.match(MIG, /'roles',/);
  assert.match(MIG, /FROM public\.engagements e[\s\S]*?WHERE e\.person_id = p\.id AND e\.status = 'active'/);
});

test('#697 name lookup disambiguates >1 match', () => {
  assert.match(MIG, /'ambiguous', true/);
  assert.match(MIG, /'match_count', v_match_count/);
});

test('#697 MCP tool wired with LGPD-audit logging', () => {
  assert.match(INDEX, /mcp\.tool\("get_member_comms_card"/);
  assert.match(INDEX, /sb\.rpc\("get_member_comms_card", \{ p_query: params\.query \|\| null, p_person_id: params\.person_id \|\| null \}\)/);
  // Art. 37: log which person was consulted + the clearance returned.
  assert.match(INDEX, /person_id: data\?\.person_id, comms_clearance: data\?\.comms_clearance/);
});

test('#697 get_person tool description now advertises headshot + LinkedIn', () => {
  const desc = (INDEX.match(/mcp\.tool\("get_person", "([^"]*)"/) || [])[1] ?? '';
  assert.ok(/headshot|photo_url/.test(desc), 'get_person desc must mention headshot/photo_url');
  assert.ok(/linkedin/i.test(desc), 'get_person desc must mention LinkedIn');
});

test('#697 live gate: service_role (no auth.uid) → Not authenticated', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_member_comms_card', { p_query: 'anyone' });
  // No JWT → auth.uid() null → persons lookup empty → {error:'Not authenticated'}.
  assert.ok(!error, `RPC itself should not throw: ${error?.message}`);
  assert.equal(data?.error, 'Not authenticated', `expected gate-closed, got: ${JSON.stringify(data)}`);
});
