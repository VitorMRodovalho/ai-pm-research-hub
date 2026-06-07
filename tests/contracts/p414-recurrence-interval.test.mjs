/**
 * #414 contract test — recurrence generator with a parametrizable interval (semanal/quinzenal/mensal).
 *
 * Background: create_recurring_weekly_events only stepped weekly (v_date := start + (v_week-1)*7), so a
 * biweekly leadership cadence ("quinzenal", qui 19:30) was self-serve-impossible via the UI — the C3
 * series had to be hand-seeded by SQL (see #414 / p276 handoff).
 *
 * Fix (migration 20260805000124): two trailing optional params on the RPC —
 *   p_interval_days   int DEFAULT 7  (semanal=7, quinzenal=14)
 *   p_interval_months int DEFAULT 0  (mensal=1; true calendar month, anchored to the start day)
 * combined into a single interval expression. Defaults (7/0) reproduce the prior weekly step exactly
 * (backward compatible). Frontend: RecurringModal gains a #rec-frequency select; createRecurring maps
 * the cadence to the two params + makes the "Repetir até" occurrence count cadence-aware.
 *
 * Live-verified at ship time (impersonated admin): days=14 → gap 14d; months=1 → 01-15/02-15/03-15;
 * defaults → gap 7d; one recurrence_group per series.
 *
 * (A) static  — migration body + modal + handler + i18n wiring (always run).
 * (B) DB-gated — the live 12-arg signature is reachable via PostgREST and fail-closed (service-role
 *     cannot impersonate a member, so auth.uid() is null → {success:false, Unauthorized}; the house
 *     pattern for auth.uid()-gated RPCs — see p511). Proves deployment of the new arity, both with and
 *     without the new params (default-arg back-compat).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000124_p414_recurrence_interval_param.sql');
const MODAL = resolve(ROOT, 'src/components/attendance/RecurringModal.astro');
const ATT = resolve(ROOT, 'src/pages/attendance.astro');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const modalRaw = existsSync(MODAL) ? readFileSync(MODAL, 'utf8') : '';
const attRaw = existsSync(ATT) ? readFileSync(ATT, 'utf8') : '';

// ── (A) static ─────────────────────────────────────────────────────────────
test('#414 static: migration adds p_interval_days + p_interval_months and steps by an interval', () => {
  assert.ok(migRaw, 'migration 20260805000124 is present');
  assert.match(migRaw, /p_interval_days\s+integer\s+DEFAULT\s+7/i, 'p_interval_days int DEFAULT 7');
  assert.match(migRaw, /p_interval_months\s+integer\s+DEFAULT\s+0/i, 'p_interval_months int DEFAULT 0');
  // the per-occurrence date must use the interval expression, not the old hardcoded weekly step
  assert.match(migRaw, /INTERVAL\s+'1 day'/i, "date math uses INTERVAL '1 day'");
  assert.match(migRaw, /INTERVAL\s+'1 month'/i, "date math uses INTERVAL '1 month'");
  assert.ok(!/v_date\s*:=\s*p_start_date\s*\+\s*\(\(v_week\s*-\s*1\)\s*\*\s*7\)\s*;/.test(migRaw),
    'the old hardcoded weekly step (\\* 7) must be gone');
  // signature change => DROP + CREATE (GC-097), not a 2nd overload
  assert.match(migRaw, /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.create_recurring_weekly_events/i,
    'DROP FUNCTION precedes the recreate (param-count change → DROP+CREATE per GC-097)');
});

test('#414 static: RecurringModal offers a frequency select (weekly/biweekly/monthly)', () => {
  assert.ok(modalRaw, 'RecurringModal.astro readable');
  assert.match(modalRaw, /id="rec-frequency"/, 'rec-frequency select exists');
  assert.match(modalRaw, /<option value="weekly"/, 'weekly option');
  assert.match(modalRaw, /<option value="biweekly"/, 'biweekly option');
  assert.match(modalRaw, /<option value="monthly"/, 'monthly option');
});

test('#414 static: createRecurring reads the cadence and passes both interval params', () => {
  assert.ok(attRaw, 'attendance.astro readable');
  assert.match(attRaw, /rec-frequency/, 'createRecurring reads rec-frequency');
  assert.match(attRaw, /p_interval_days:\s*intervalDays/, 'passes p_interval_days');
  assert.match(attRaw, /p_interval_months:\s*intervalMonths/, 'passes p_interval_months');
  // monthly → 1 calendar month; biweekly → 14 days
  assert.match(attRaw, /freq === 'monthly'\s*\?\s*1\s*:\s*0/, 'monthly maps to intervalMonths=1');
  assert.match(attRaw, /freq === 'biweekly'\s*\?\s*14/, 'biweekly maps to intervalDays=14');
});

test('#414 static: the 4 cadence i18n keys exist in all 3 dictionaries', () => {
  const keys = ['attendance.modal.frequency', 'attendance.modal.freqWeekly',
                'attendance.modal.freqBiweekly', 'attendance.modal.freqMonthly'];
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(resolve(ROOT, `src/i18n/${loc}.ts`), 'utf8');
    for (const k of keys) {
      assert.ok(dict.includes(`'${k}'`), `${loc} is missing ${k}`);
    }
  }
});

// ── (B) DB-gated ────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#414 DB: the 12-arg signature (with the new params) is live + fail-closed', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service-role has no auth.uid() → the gated RPC returns a structured {success:false, Unauthorized}.
  // A PostgREST "could not find function ... with parameter" error here would mean the new arity is NOT
  // deployed — that is the failure this guards against. Far-future date + the call is rejected pre-INSERT.
  const { data, error } = await sb.rpc('create_recurring_weekly_events', {
    p_type: 'geral', p_title_template: 'p414-probe {n}', p_start_date: '2031-01-02',
    p_n_weeks: 2, p_interval_days: 14, p_interval_months: 0,
  });
  assert.ok(!error, `RPC must resolve the new signature (got error: ${error?.message})`);
  assert.equal(data?.success, false, 'service-role (no auth.uid()) must be rejected');
  assert.match(String(data?.error || ''), /Unauthorized/i, 'fail-closed with Unauthorized');
});

test('#414 DB: omitting the new params still resolves (default-arg back-compat)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('create_recurring_weekly_events', {
    p_type: 'geral', p_title_template: 'p414-probe-legacy {n}', p_start_date: '2031-01-02', p_n_weeks: 2,
  });
  assert.ok(!error, `legacy arity must still resolve via defaults (got error: ${error?.message})`);
  assert.equal(data?.success, false, 'still fail-closed for service-role');
  assert.match(String(data?.error || ''), /Unauthorized/i, 'fail-closed with Unauthorized');
});
