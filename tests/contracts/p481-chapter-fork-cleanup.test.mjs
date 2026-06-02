/**
 * Contract: #481 — finish the chapter-metric fork cleanup (follow-up to #479 / PR #480).
 *
 * Locks migration 20260805000094:
 *   1. The 3 UNRENDERED chapter RPCs (get_homepage_stats / get_public_platform_stats /
 *      get_executive_kpis) read get_chapter_metrics()->>'signed', NOT count(DISTINCT members.chapter).
 *   2. get_chapter_metrics excludes international chapters via partner_entities.is_international,
 *      NOT the brittle name ILIKE '%washington%' match.
 *   3. get_public_impact_data.chapters_summary is the SIGNED chapters (partner_entities), so the
 *      grid length == the headline (signed), no members.chapter noise (Outro / PMI-SP).
 *   4. check_schema_invariants gains Y_chapter_pipeline_parity + Z_webinar_status_domain (both 0).
 *
 * Behavioural checks assert RELATIONSHIPS (== signed; summary length == signed) rather than hardcoding
 * live counts, so the contract survives legitimate pipeline growth.
 *
 * Cross-ref: #481 (follow-up to #479); ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000094_p481_chapter_fork_cleanup_invariants.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, ''); // strip SQL line-comments (prose names the retired forks)

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#481 static: migration exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000094 exists');
});

test('#481 static: is_international column + PMI-WDC backfill', () => {
  assert.match(migRaw, /ADD COLUMN IF NOT EXISTS is_international boolean NOT NULL DEFAULT false/, 'adds is_international');
  assert.match(mig, /UPDATE public\.partner_entities[\s\S]*?is_international = true[\s\S]*?ILIKE '%washington%'/, 'backfills PMI-WDC by name (one-time)');
});

test('#481 static: get_chapter_metrics uses is_international, not name-match', () => {
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.get_chapter_metrics[\s\S]*?\$function\$;/);
  assert.ok(fn, 'helper block parses');
  const body = fn[0];
  assert.match(body, /NOT COALESCE\(is_international, false\)/, 'excludes via is_international flag');
  assert.doesNotMatch(body, /ILIKE '%washington%'/, 'no surviving %washington% name-match');
  assert.match(body, /FROM public\.partner_entities/, 'still sources partner_entities');
});

test('#481 static: 3 unrendered RPCs repointed, no count(DISTINCT chapter) fork remains', () => {
  for (const fn of ['get_homepage_stats', 'get_public_platform_stats', 'get_executive_kpis']) {
    const m = mig.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}[\\s\\S]*?\\$function\\$;`));
    assert.ok(m, `${fn} redefined in this migration`);
    assert.match(m[0], /get_chapter_metrics\(\)->>'signed'/, `${fn} reads canonical signed`);
    assert.doesNotMatch(m[0], /COUNT\(DISTINCT chapter\)/i, `${fn} drops the count(DISTINCT chapter) fork`);
  }
});

test('#481 static: chapters_summary sourced from partner_entities (signed), not members.chapter', () => {
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.get_public_impact_data[\s\S]*?\$function\$;/);
  assert.ok(fn, 'impact RPC block parses');
  const summary = fn[0].match(/'chapters_summary',[\s\S]*?\), '\[\]'::jsonb\)/);
  assert.ok(summary, 'chapters_summary block parses');
  assert.match(summary[0], /FROM partner_entities pe[\s\S]*?entity_type = 'pmi_chapter' AND pe\.status = 'active'/, 'iterates signed partner chapters');
});

test('#481 static: Y + Z invariants added to check_schema_invariants', () => {
  assert.match(mig, /'Y_chapter_pipeline_parity'::text/, 'Y invariant present');
  assert.match(mig, /'Z_webinar_status_domain'::text/, 'Z invariant present');
});

// ── BEHAVIOURAL (DB-gated) ────────────────────────────────────────────────────────
test('#481 behavioural: 3 unrendered RPCs == get_chapter_metrics signed', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const { data: m, error } = await sb.rpc('get_chapter_metrics');
  assert.ifError(error);
  const signed = Number(m.signed);

  const { data: home, error: e1 } = await sb.rpc('get_homepage_stats');
  assert.ifError(e1);
  assert.equal(Number(home.chapters), signed, 'get_homepage_stats.chapters == signed');

  const { data: plat, error: e2 } = await sb.rpc('get_public_platform_stats');
  assert.ifError(e2);
  assert.equal(Number(plat.total_chapters), signed, 'get_public_platform_stats.total_chapters == signed');

  const { data: exec, error: e3 } = await sb.rpc('get_executive_kpis');
  assert.ifError(e3);
  assert.equal(Number(exec.chapters), signed, 'get_executive_kpis.chapters == signed');
});

test('#481 behavioural: is_international flag set on the international chapter; in_negotiation excludes it', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  // every name ILIKE %washington% must now carry is_international=true
  const { data: wdc, error } = await sb
    .from('partner_entities').select('name,is_international')
    .eq('entity_type', 'pmi_chapter').ilike('name', '%washington%');
  assert.ifError(error);
  for (const r of wdc) assert.equal(r.is_international, true, `${r.name} flagged international`);

  const { data: m, error: e1 } = await sb.rpc('get_chapter_metrics');
  assert.ifError(e1);
  const { count: domesticNeg, error: e2 } = await sb
    .from('partner_entities').select('id', { count: 'exact', head: true })
    .eq('entity_type', 'pmi_chapter').eq('status', 'negotiation').eq('is_international', false);
  assert.ifError(e2);
  assert.equal(Number(m.in_negotiation), Number(domesticNeg), 'in_negotiation == domestic (non-international) negotiation rows');
});

test('#481 behavioural: chapters_summary length == signed; every row is an active pmi_chapter', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const { data: impact, error } = await sb.rpc('get_public_impact_data');
  assert.ifError(error);
  const { data: m, error: e1 } = await sb.rpc('get_chapter_metrics');
  assert.ifError(e1);
  const summary = impact.chapters_summary || [];
  assert.equal(summary.length, Number(m.signed), 'chapters_summary length == signed (no members.chapter noise)');

  const { data: signedRows, error: e2 } = await sb
    .from('partner_entities').select('name')
    .eq('entity_type', 'pmi_chapter').eq('status', 'active');
  assert.ifError(e2);
  const signedNames = new Set(signedRows.map((r) => r.name));
  for (const row of summary) {
    assert.ok(signedNames.has(row.chapter), `${row.chapter} is a signed chapter`);
    assert.ok(Number.isInteger(row.member_count) && row.member_count >= 0, `${row.chapter} has integer member_count`);
    // LGPD trip-wire (security review): sponsor is the only member-PII-adjacent field on this anon-callable
    // public RPC. It must be a name (or null) — never an email or other identifier substituted by accident.
    assert.ok(row.sponsor === null || typeof row.sponsor === 'string', `${row.chapter} sponsor is null or a string name`);
    assert.doesNotMatch(row.sponsor ?? '', /@/, `${row.chapter} sponsor must not be an email address`);
  }
});

test('#481 behavioural: Y + Z invariants report 0 violations', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const { data: rows, error } = await sb.rpc('check_schema_invariants');
  assert.ifError(error);
  const byName = Object.fromEntries(rows.map((r) => [r.invariant_name, r]));
  for (const name of ['Y_chapter_pipeline_parity', 'Z_webinar_status_domain']) {
    assert.ok(byName[name], `${name} present`);
    assert.equal(byName[name].violation_count, 0, `${name} == 0`);
  }
});
