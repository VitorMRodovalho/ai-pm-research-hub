/**
 * Forward-defense: BUG-218.A — auto-link new volunteer engagements to existing ciclo cert.
 *
 * Origin: p219 boot smoke of Vitor's engagement vs termo state revealed that
 * sign_volunteer_agreement() (mig 20260415020000) links cert ← all current
 * volunteer engagements at SIGNING TIME, but engagements created AFTER signing
 * are left orphan (agreement_certificate_id IS NULL), inflating the pending-
 * agreements backlog. Vitor had 2 such orphans (4711994b LIM coordinator,
 * fe0d18df CPMAI manager) — both volunteer-kind, both created after his
 * TERM-2026-7654C7 was issued 2026-04-08.
 *
 * Fix (p219): migration 20260803000003 adds:
 *   (1) BACKFILL — UPDATE all orphan kind=volunteer engagements where matching
 *       ciclo cert exists for the member (audited via admin_audit_log).
 *   (2) BEFORE INSERT trigger — auto-links new kind=volunteer engagements to
 *       existing ciclo cert at creation time.
 *
 * Scope (per PM, p219): kind='volunteer' ONLY. study_group_owner /
 * study_group_participant kinds also have requires_agreement=true but no
 * signing flow yet — handled separately (deferred to ADR amendment).
 *
 * Cross-ref:
 *   - supabase/migrations/20260803000003_p219_bug_218_a_auto_link_volunteer_engagement_to_cycle_cert.sql
 *   - supabase/migrations/20260415020000_v4_phase7_volunteer_agreement_engagement_link.sql (original RPC-side link)
 *   - ADR-0006 (Person + Engagement V4 model)
 *   - ADR-0007 (Authority via can_by_member())
 *   - P162 BUG-218.A
 *
 * Static-only bundle:
 *   1. Migration file contains backfill UPDATE + trigger function + trigger
 *   2. Filename canonical per migration glob
 *   3. Scope guard (kind='volunteer' only — SGO/SGP excluded)
 *   4. In-tx sanity DO block fails loud if orphans remain
 *
 * Behavioural verification lives inside the migration itself (sanity DO block
 * fails loud if any orphan volunteer engagement with matching ciclo cert
 * remains post-backfill — caught at apply time, not runtime).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260803000003_p219_bug_218_a_auto_link_volunteer_engagement_to_cycle_cert.sql'
);

test('p219 BUG-218.A migration installs BEFORE INSERT trigger on engagements', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Trigger function defined with SECURITY DEFINER + canonical search_path
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._trg_auto_link_volunteer_engagement_to_cycle_cert\(\)/i,
    'Trigger function must be defined with canonical name _trg_auto_link_volunteer_engagement_to_cycle_cert');
  assert.match(body, /SECURITY DEFINER/i,
    'Trigger function must be SECURITY DEFINER');
  assert.match(body, /SET search_path = 'public', 'pg_temp'/i,
    'Trigger function must pin search_path to public + pg_temp (CLAUDE.md GC-097)');

  // BEFORE INSERT trigger on engagements
  assert.match(body, /BEFORE INSERT ON public\.engagements/i,
    'Trigger must be BEFORE INSERT on public.engagements (to modify NEW before storage)');
  assert.match(body, /DROP TRIGGER IF EXISTS trg_auto_link_volunteer_engagement_to_cycle_cert/i,
    'Migration must DROP trigger IF EXISTS before CREATE (idempotent re-apply)');
});

test('p219 BUG-218.A trigger scope is strictly kind=volunteer', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Function body must guard against non-volunteer kinds
  assert.match(body, /IF NEW\.kind\s*<>\s*'volunteer'\s+THEN\s+RETURN NEW;/i,
    'Trigger must early-return if NEW.kind != volunteer (scope guard per PM p219)');
  assert.match(body, /IF NEW\.status\s*<>\s*'active'\s+THEN\s+RETURN NEW;/i,
    'Trigger must early-return if NEW.status != active (only active engagements need cert link)');
  assert.match(body, /IF NEW\.agreement_certificate_id IS NOT NULL\s+THEN\s+RETURN NEW;/i,
    'Trigger must early-return if NEW.agreement_certificate_id is already set (idempotency)');
});

test('p219 BUG-218.A trigger looks up cert via member_id derived from person_id', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Person → legacy member resolution
  assert.match(body, /SELECT\s+legacy_member_id\s+INTO\s+v_member_id\s+FROM\s+public\.persons\s+WHERE\s+id\s*=\s*NEW\.person_id/i,
    'Trigger must resolve member_id via persons.legacy_member_id (V4 V3 bridge per ADR-0006)');

  // Cycle derivation from engagement start_date
  assert.match(body, /EXTRACT\(YEAR FROM COALESCE\(NEW\.start_date, CURRENT_DATE\)\)::int/i,
    'Trigger must derive cycle from EXTRACT(YEAR FROM start_date), fallback CURRENT_DATE');

  // Cert lookup constraints — must match sign_volunteer_agreement() semantics
  assert.match(body, /type\s*=\s*'volunteer_agreement'/i,
    'Trigger must look up only volunteer_agreement type certificates');
  assert.match(body, /status\s*=\s*'issued'/i,
    'Trigger must look up only status=issued certificates (revoked certs do not link)');
});

test('p219 BUG-218.A backfill UPDATE targets only orphan volunteer engagements', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Backfill UPDATE clause
  assert.match(body, /UPDATE public\.engagements e\s+SET agreement_certificate_id\s*=\s*c\.id/i,
    'Backfill must UPDATE engagements.agreement_certificate_id from matched certificates.id');

  // Backfill WHERE clauses
  assert.match(body, /AND e\.kind\s*=\s*'volunteer'/i,
    'Backfill must filter to kind=volunteer (scope per PM p219)');
  assert.match(body, /AND e\.status\s*=\s*'active'/i,
    'Backfill must filter to status=active');
  assert.match(body, /AND e\.agreement_certificate_id IS NULL/i,
    'Backfill must filter to NULL agreement_certificate_id (idempotent re-apply)');
  assert.match(body, /AND c\.type\s*=\s*'volunteer_agreement'/i,
    'Backfill must join only volunteer_agreement certs');
  assert.match(body, /AND c\.status\s*=\s*'issued'/i,
    'Backfill must join only issued certs');
  assert.match(body, /c\.cycle\s*=\s*EXTRACT\(YEAR FROM e\.start_date\)::int/i,
    'Backfill must match cert.cycle to engagement start_year');
});

test('p219 BUG-218.A backfill writes admin_audit_log entries with cert + engagement traceability', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // admin_audit_log INSERT
  assert.match(body, /INSERT INTO public\.admin_audit_log/i,
    'Backfill must write to admin_audit_log for traceability');
  assert.match(body, /'bug_218_a_backfill_volunteer_engagement_cert'/i,
    'Audit action key must identify the migration (bug_218_a_backfill_volunteer_engagement_cert)');
  assert.match(body, /'migration'.*'20260803000003'/i,
    'Audit changes payload must reference migration version 20260803000003');
});

test('p219 BUG-218.A sanity DO block fails loud if orphan volunteer engagements with matching cert remain', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // In-tx sanity gate post-backfill — must RAISE EXCEPTION
  assert.match(body, /RAISE EXCEPTION 'BUG-218\.A sanity FAIL/i,
    'Migration must RAISE EXCEPTION post-backfill if orphans remain (fails loud at apply time)');
  assert.match(body, /v_orphan_count int/i,
    'Sanity block must declare v_orphan_count variable for orphan count assertion');
});

test('p219 BUG-218.A migration file is registered per timestamp pattern', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260803000003_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260803000003 (p219 BUG-218.A)');
  assert.match(files[0], /^20260803000003_p219_bug_218_a_auto_link_volunteer_engagement_to_cycle_cert\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p219 BUG-218.A migration reloads PostgREST schema cache', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Migration must NOTIFY pgrst reload schema (CLAUDE.md GC-097)');
});
