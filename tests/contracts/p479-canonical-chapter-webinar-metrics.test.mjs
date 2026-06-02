/**
 * Contract: #479 — canonical chapter metrics + status-based webinar "realizado".
 *
 * Locks migration 20260805000093 so a future change cannot silently re-fork:
 *   1. CHAPTERS — get_chapter_metrics() is the canonical source off public.partner_entities
 *      (entity_type='pmi_chapter'): signed = status='active'; in_negotiation = status='negotiation'
 *      excluding international (currently PMI-WDC, by name); engaged = signed + in_negotiation.
 *      The dashboard/impact/kpi/portfolio surfaces no longer use count(DISTINCT members.chapter).
 *   2. WEBINARS — get_webinars_count 'realized' is STATUS-based (status='completed'), NOT the old
 *      time-based scheduled_at<now() from mig-080 (which falsely assumed no 'completed' status).
 *      'planned' = status IN (planned, confirmed).
 *   3. get_public_impact_data.webinars shows REALIZED (PM decision 2026-06-02 "Realizados = 0").
 *
 * Static checks read the migration file; behavioural checks (DB-gated) assert the RELATIONSHIPS
 * (engaged == signed + in_negotiation; chapters == signed; realized == completed-count) rather than
 * hardcoding the live counts, so the contract survives legitimate pipeline growth.
 *
 * Cross-ref: issue #479 (supersedes the M8 all-count for the public webinars surface); #419/#421; ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000093_p479_canonical_chapter_webinar_metrics.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, ''); // strip SQL line-comments (prose names the retired fork)

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#479 static: migration exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000093 exists');
});

test('#479 static: get_chapter_metrics canonical helper off partner_entities', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_chapter_metrics\s*\(\s*\)/, 'declares get_chapter_metrics');
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.get_chapter_metrics[\s\S]*?\$function\$;/);
  assert.ok(fn, 'helper block parses');
  const body = fn[0];
  assert.match(body, /FROM public\.partner_entities/, 'sources partner_entities');
  assert.match(body, /entity_type\s*=\s*'pmi_chapter'/, 'scoped to pmi_chapter');
  for (const key of ['signed', 'in_negotiation', 'engaged']) {
    assert.match(body, new RegExp(`'${key}'`), `returns ${key}`);
  }
  assert.match(body, /status\s*=\s*'active'/, 'signed = active');
  assert.match(body, /NOT ILIKE '%washington%'/, 'excludes international (washington) from BR figures');
  // headline source must NOT be the old members free-text fork
  assert.doesNotMatch(body, /FROM\s+(public\.)?members/i, 'helper does not read members.chapter');
});

test('#479 static: get_chapter_metrics grant ladder', () => {
  assert.match(migRaw, /REVOKE ALL ON FUNCTION public\.get_chapter_metrics\(\) FROM PUBLIC/, 'REVOKE PUBLIC');
  assert.match(migRaw, /GRANT EXECUTE ON FUNCTION public\.get_chapter_metrics\(\) TO anon, authenticated, service_role/, 'GRANT anon+authenticated+service_role');
});

test('#479 static: get_webinars_count realized is status-based (not time-based)', () => {
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.get_webinars_count[\s\S]*?\$function\$;/);
  assert.ok(fn, 'webinars helper block parses');
  const body = fn[0];
  assert.match(body, /WHEN 'realized' THEN w\.status\s*=\s*'completed'/, "realized = status='completed'");
  assert.match(body, /WHEN 'planned'\s+THEN w\.status IN \('planned', 'confirmed'\)/, 'planned = status IN (planned,confirmed)');
  assert.doesNotMatch(body, /scheduled_at < now\(\)/, 'no surviving time-based realized predicate');
});

test('#479 static: 4 rendered surfaces repointed onto get_chapter_metrics, no members.chapter fork remains', () => {
  for (const fn of ['get_admin_dashboard', 'exec_portfolio_health', 'get_public_impact_data', 'get_kpi_dashboard']) {
    assert.match(mig, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\s*\\(`), `${fn} repointed in this migration`);
  }
  assert.match(mig, /get_chapter_metrics\(\)/, 'surfaces call the canonical helper');
  // the old fork must be gone from the migration's SQL (comments stripped above)
  assert.doesNotMatch(mig, /count\(DISTINCT chapter\)/i, 'no count(DISTINCT chapter) survives in the repointed bodies');
  // public impact webinars must use the realized mode (#479 decision), not all
  assert.match(mig, /'webinars',\s*public\.get_webinars_count\(NULL,\s*NULL,\s*'realized'\)/, "get_public_impact_data.webinars uses 'realized'");
});

// ── BEHAVIOURAL (DB-gated) ────────────────────────────────────────────────────────
test('#479 behavioural: get_chapter_metrics relationships hold', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: m, error } = await sb.rpc('get_chapter_metrics');
  assert.ifError(error);
  const signed = Number(m.signed), inNeg = Number(m.in_negotiation), engaged = Number(m.engaged);
  assert.ok(Number.isInteger(signed) && signed >= 0, 'signed is a non-negative integer');
  assert.equal(engaged, signed + inNeg, 'engaged == signed + in_negotiation');
  // signed must equal the canonical active DOMESTIC pmi_chapter partner rows.
  // #481 made all three metrics domestic-only (is_international=false) so engaged == signed + in_negotiation
  // stays exact even if an international chapter is ever onboarded to status='active'.
  const { count: activeCount, error: e1 } = await sb
    .from('partner_entities').select('id', { count: 'exact', head: true })
    .eq('entity_type', 'pmi_chapter').eq('status', 'active').eq('is_international', false);
  assert.ifError(e1);
  assert.equal(signed, Number(activeCount), 'signed == active domestic pmi_chapter partner_entities');
});

test('#479 behavioural: get_webinars_count realized == webinars status=completed', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: realized, error } = await sb.rpc('get_webinars_count', { p_start: null, p_end: null, p_mode: 'realized' });
  assert.ifError(error);
  const { count: completed, error: e1 } = await sb
    .from('webinars').select('id', { count: 'exact', head: true }).eq('status', 'completed');
  assert.ifError(e1);
  assert.equal(Number(realized), Number(completed), "realized == count(status='completed')");
});

test('#479 behavioural: get_public_impact_data chapters/engaged/webinars track the canonical sources', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: impact, error } = await sb.rpc('get_public_impact_data');
  assert.ifError(error);
  const { data: m, error: e1 } = await sb.rpc('get_chapter_metrics');
  assert.ifError(e1);
  const { data: realized, error: e2 } = await sb.rpc('get_webinars_count', { p_start: null, p_end: null, p_mode: 'realized' });
  assert.ifError(e2);
  assert.equal(Number(impact.chapters), Number(m.signed), 'impact.chapters == signed');
  assert.equal(Number(impact.chapters_engaged), Number(m.engaged), 'impact.chapters_engaged == engaged');
  assert.equal(Number(impact.webinars), Number(realized), 'impact.webinars == realized (completed)');
});

test('#479 behavioural: exec_portfolio_health chapters_participating == signed', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: health, error } = await sb.rpc('exec_portfolio_health');
  assert.ifError(error);
  const { data: m, error: e1 } = await sb.rpc('get_chapter_metrics');
  assert.ifError(e1);
  const row = (health || []).find((r) => r.metric_key === 'chapters_participating');
  assert.ok(row, 'portfolio health has chapters_participating');
  assert.equal(Number(row.current), Number(m.signed), 'chapters_participating current == signed');
});
