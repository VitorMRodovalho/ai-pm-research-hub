/**
 * #517 contract test — recurring-event modal carries no hardcoded meeting link.
 *
 * Bug: RecurringModal.astro prefilled #rec-link with a hardcoded
 *   value="https://meet.google.com/dzo-phoj-tid" — a stale link that re-propagated
 *   into every new recurring series and diverged from the canonical
 *   site_config.general_meeting_link (and the active "Ciclo 3" banner). Reported by
 *   Rodolfo/PMI-MG (two different Meet links surfaced on /attendance).
 *
 * Fix: remove the hardcoded value (placeholder only); the active banner row was
 *   data-corrected to the canonical jgu link. The standing link lives in
 *   site_config.general_meeting_link.
 *
 * (A) static: the modal source has no hardcoded meet.google.com link value.
 * (B) DB-gated: no ACTIVE announcement still points at the retired dzo-phoj-tid link.
 *
 * Cross-ref: #517 (relates #248/#249/#485 tribe day/time drift — handled separately).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MODAL = resolve(ROOT, 'src/components/attendance/RecurringModal.astro');
// strip html comments so the explanatory note (which names the retired link) is ignored
const code = readFileSync(MODAL, 'utf8').replace(/<!--[\s\S]*?-->/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#517: recurring modal has no hardcoded meet.google.com link value', () => {
  // a placeholder ("https://meet.google.com/...") is allowed; a concrete room value is not.
  assert.ok(!/value=["']https:\/\/meet\.google\.com\/[A-Za-z0-9-]+["']/.test(code),
    'recurring link input must not hardcode a meeting-room value (it re-propagates a stale link)');
  assert.ok(!/dzo-phoj-tid/.test(code),
    'the retired dzo-phoj-tid link must not appear in the component');
});

test('DB: no active announcement still points at the retired dzo-phoj-tid link', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('announcements')
    .select('id,link_url,is_active')
    .eq('is_active', true)
    .ilike('link_url', '%dzo-phoj-tid%');
  assert.ok(!error, error?.message);
  assert.equal((data || []).length, 0,
    'no active announcement should link to the retired dzo-phoj-tid room');
});
