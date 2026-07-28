/**
 * Contract: #1445 — get_vep_divergence_report must surface the "approved/converted + VEP offer
 * retracted + member still active" class (the Hector case), which no prior bucket caught:
 *   - selection_divergent requires the app to be in the active funnel (excludes approved/converted);
 *   - active_members_divergent requires member.is_active = FALSE (excludes an active member);
 *   - onboarding_divergent only covers Submitted/OfferExtended (a retracted offer is out).
 *
 * Fix (migration 20260805000470): bucket E `offer_retracted_active_divergent` =
 * status approved/converted + vep_status_raw IN (OfferNotExtended, Withdrawn, Declined) +
 * a linked member with is_active = true. Count folded into summary.total_divergent. The card
 * exposes an offboard action (admin_offboard_member inactive) reachable per row.
 *
 * Static test (always run) + forward-defense (no later migration drops the bucket).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX = '20260805000470_1445_vep_offer_retracted_active_bucket.sql';
const FIX_FILE = resolve(MIGRATIONS_DIR, FIX);

function reportBlock(body) {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_vep_divergence_report\s*\([\s\S]*?\$function\$[\s\S]*?\$function\$/i;
  return body.match(re)?.[0] || '';
}

test('1445: fix migration exists', () => {
  assert.ok(existsSync(FIX_FILE), `migration must exist at ${FIX_FILE}`);
});

test('1445: report emits the offer_retracted_active bucket + folds it into the total', () => {
  const block = reportBlock(readFileSync(FIX_FILE, 'utf8'));
  assert.ok(block, 'get_vep_divergence_report CREATE OR REPLACE block must be present');
  // The new bucket key is returned and counted.
  assert.match(block, /'offer_retracted_active_divergent'/i, 'must return the offer_retracted_active_divergent bucket');
  assert.match(block, /'offer_retracted_active_count'/i, 'summary must expose offer_retracted_active_count');
  assert.match(block, /jsonb_array_length\(v_offer_retracted_active\)/i,
    'the new bucket length must be part of total_divergent');
});

test('1445: bucket predicate = approved/converted + retracted VEP offer + active member', () => {
  const block = reportBlock(readFileSync(FIX_FILE, 'utf8'));
  // Isolate the bucket-E SELECT (the one populating v_offer_retracted_active), from the
  // SELECT ... jsonb_build_object (which carries member_id) through its terminating `;`.
  const bucket = block.match(/SELECT\s+COALESCE\(jsonb_agg[\s\S]*?INTO\s+v_offer_retracted_active[\s\S]*?m\.is_active\s*=\s*true[\s\S]*?;/i)?.[0] || '';
  assert.ok(bucket, 'v_offer_retracted_active SELECT must be present');
  assert.match(bucket, /a\.status\s+IN\s*\(\s*'approved'\s*,\s*'converted'\s*\)/i,
    'must scope to approved/converted Núcleo status');
  assert.match(bucket, /vep_status_raw\s+IN\s*\(\s*'OfferNotExtended'\s*,\s*'Withdrawn'\s*,\s*'Declined'\s*\)/i,
    'must scope to a retracted VEP offer');
  assert.match(bucket, /m\.is_active\s*=\s*true/i, 'must require the linked member to still be active');
  assert.match(bucket, /'member_id'\s*,\s*m\.id/i, 'each row must carry member_id (for the offboard action)');
});

function subsequentMigrations() {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = all.indexOf(FIX);
  assert.ok(idx >= 0, 'fix migration must be in the registry');
  return all.slice(idx + 1).map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

test('1445: no later migration drops the offer_retracted_active bucket', () => {
  const offenders = [];
  for (const m of subsequentMigrations()) {
    const block = reportBlock(m.body);
    if (block && !/offer_retracted_active_divergent/i.test(block)) {
      offenders.push(m.name);
    }
  }
  assert.equal(offenders.length, 0,
    `get_vep_divergence_report must keep the offer_retracted_active bucket. Offenders: ${offenders.join(', ')}`);
});
