/**
 * #902 — VEP application/offer deadline capture + "approved-then-VEP-expired" surfacing.
 *
 * Guards the chain that lets admin/selection show a deadline countdown BEFORE a VEP
 * expiry and a distinct "aprovado → oferta VEP expirada" state AFTER, instead of the
 * silent approved→rejected flip (root cause: the extract script emits expiryDateUtc /
 * offerExpiredDateUtc / applicationExpiredDateUtc but the worker dropped them, and no
 * column stored a deadline).
 *
 * Static source-parse only (no DB / network) — safe to run anywhere; catches drift
 * before deploy. Mirrors the worker-mapper-db-update-coverage approach.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

test('script-mapper captures the deadline + expiry fields the extract script emits', () => {
  const src = read('cloudflare-workers/pmi-vep-sync/src/script-mapper.ts');
  // forward-looking deadline → vep_offer_expires_at
  assert.match(src, /vep_offer_expires_at:\s*safeTimestamp\(app\.expiryDateUtc\)/,
    'script-mapper must map app.expiryDateUtc → vep_offer_expires_at');
  // actual expiry → vep_expired_at (offer first, then application)
  assert.match(src, /vep_expired_at:\s*safeTimestamp\(app\.offerExpiredDateUtc\s*\?\?\s*app\.applicationExpiredDateUtc\)/,
    'script-mapper must map offerExpiredDateUtc ?? applicationExpiredDateUtc → vep_expired_at');
  // safeTimestamp must degrade malformed/absent dates to null (never throw → never fail the upsert)
  assert.match(src, /export function safeTimestamp\b/, 'safeTimestamp helper must exist + be exported (testable)');
  assert.match(src, /Number\.isNaN\([\s\S]*?\?\s*null/, 'safeTimestamp must return null for unparseable input');
});

test('worker db.ts persists the captured deadline fields on UPDATE (commonRefresh)', () => {
  const src = read('cloudflare-workers/pmi-vep-sync/src/db.ts');
  const cr = src.match(/const\s+commonRefresh\s*=\s*\{([\s\S]*?)\};/);
  assert.ok(cr, 'commonRefresh block must exist');
  assert.match(cr[1], /vep_offer_expires_at:/, 'commonRefresh must include vep_offer_expires_at (else silently dropped on re-ingest)');
  assert.match(cr[1], /vep_expired_at:/, 'commonRefresh must include vep_expired_at');
});

test('worker db.ts audits the VEP-driven terminal clobber (no longer silent/untraced)', () => {
  const src = read('cloudflare-workers/pmi-vep-sync/src/db.ts');
  assert.match(src, /auditVepTerminalClobber/, 'audit helper must exist + be called');
  assert.match(src, /action:\s*'selection\.vep_terminal_clobber'/, 'audit must write a distinct action');
  assert.match(src, /vep_expired_after_cutoff_approval/,
    'audit must tag the approved-then-expired case distinctly from a plain evaluation rejection');
});

test('SelectionApplicationUpsert type declares the deadline fields', () => {
  const src = read('cloudflare-workers/pmi-vep-sync/src/types.ts');
  assert.match(src, /vep_offer_expires_at\?:\s*string\s*\|\s*null/, 'type must declare vep_offer_expires_at');
  assert.match(src, /vep_expired_at\?:\s*string\s*\|\s*null/, 'type must declare vep_expired_at');
});

test('migration adds the two columns + get_selection_dashboard surfaces them in vep_recon', () => {
  const dir = join(REPO_ROOT, 'supabase/migrations');
  const file = readdirSync(dir).find((f) => f.includes('902_vep_offer_deadline_capture'));
  assert.ok(file, 'the #902 migration file must exist');
  const sql = readFileSync(join(dir, file), 'utf8');
  assert.match(sql, /ADD COLUMN IF NOT EXISTS vep_offer_expires_at\s+timestamptz/i);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS vep_expired_at\s+timestamptz/i);
  // the dashboard RPC must expose both inside vep_recon so the FE row can render them
  assert.match(sql, /'offer_expires_at',\s*a\.vep_offer_expires_at/);
  assert.match(sql, /'expired_at',\s*a\.vep_expired_at/);
});

test('admin/selection vepBadge covers the previously-unmapped statuses + the new badges', () => {
  const src = read('src/pages/admin/selection.astro');
  // statuses that previously fell through to the gray "unknown" badge
  for (const status of ['OfferExtended', 'Expired', 'OfferExpired', 'Complete']) {
    assert.match(src, new RegExp(`${status}:\\s*\\{ short:`), `vepBadge labelMap must cover ${status}`);
  }
  // distinct approved→expired badge + proactive countdown chip
  assert.match(src, /cutoff_approved_email_sent_at && isExpiryFamily/, 'approved→expired badge must gate on cutoff approval + expiry family');
  assert.match(src, /offer_expires_at/, 'vepBadge must read the forward-looking deadline');
  assert.match(src, /deadlineToday|deadlineDays/, 'vepBadge must render a deadline countdown');
});

test('the new comp.vepBadge i18n keys exist with full 3-dictionary parity', () => {
  const NEW_KEYS = [
    'expired', 'statusExpired', 'offerExpired', 'statusOfferExpired',
    'offerExtended', 'statusOfferExtended', 'complete', 'statusComplete',
    'approvedExpiredShort', 'approvedExpiredTooltip',
    'deadlineDays', 'deadlineToday', 'deadlineTomorrow', 'deadlineTooltip',
  ];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = read(`src/i18n/${dict}.ts`);
    for (const k of NEW_KEYS) {
      assert.match(src, new RegExp(`'comp\\.vepBadge\\.${k}'\\s*:`), `${dict} missing comp.vepBadge.${k}`);
    }
  }
});
