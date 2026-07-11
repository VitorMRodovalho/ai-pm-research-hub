/**
 * Contract: #1029 — nudge operacional para webinar past-dated sem status terminal.
 *
 * A meta "Webinares realizados" (get_webinars_count(...,realized) = status='completed', #479) lê 0/N
 * porque NÃO existe mecanismo que avance planned/confirmed → completed depois do evento — só a edição
 * manual (upsert_webinar), que é esquecida.
 *
 * Decisão (owner 2026-07-11, opção B): sem cron de auto-transição (os past-dated presos são placeholders
 * sem event/presença — 0 sinal de que ocorreram; auto-completar re-inflaria a métrica que #479 corrigiu).
 * Em vez disso, um NUDGE: list_webinars_v2 expõe `needs_status_review`
 * (status IN planned|confirmed AND scheduled_at < now()); o admin de webinares badge-a a fila + conta.
 *
 * Travas:
 *  (1) static — a migration de list_webinars_v2 computa needs_status_review; o admin renderiza o
 *      badge/stat; i18n presente nas 3 dicionários.
 *  (2) DB — o RPC devolve o flag e ele bate com o predicado (status planned/confirmed + scheduled_at<now).
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
const WEBINARS_PAGE = resolve(process.cwd(), 'src/pages/admin/webinars.astro');

function latestBodyMatching(re) {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  let body = null;
  for (const f of files) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    if (re.test(sql)) body = sql;
  }
  return body;
}

test('#1029 static: list_webinars_v2 computes the needs_status_review flag', () => {
  const body = latestBodyMatching(/CREATE OR REPLACE FUNCTION public\.list_webinars_v2\s*\(/);
  assert.ok(body, 'a migration must capture CREATE OR REPLACE FUNCTION public.list_webinars_v2(');
  const norm = body.replace(/\s+/g, ' ');
  assert.match(
    norm,
    /w\.status IN \('planned', 'confirmed'\) AND w\.scheduled_at < now\(\)\) AS needs_status_review/,
    'must expose needs_status_review = past-dated planned/confirmed (#1029 nudge)',
  );
});

test('#1029 static: admin webinars page renders the nudge (badge + stat) with i18n', () => {
  const src = readFileSync(WEBINARS_PAGE, 'utf8');
  assert.match(src, /w\.needs_status_review/, 'the page must read the RPC flag');
  assert.match(src, /needsReviewBadge/, 'the page must render a per-row needs-review badge');
  assert.match(src, /statNeedsReview/, 'the page must surface a needs-review stat/count');
  // i18n parity across the 3 dictionaries.
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(process.cwd(), `src/i18n/${dict}.ts`), 'utf8');
    for (const key of ['admin.webinars.statNeedsReview', 'admin.webinars.cardNeedsReview']) {
      assert.ok(d.includes(`'${key}'`), `i18n key '${key}' missing in ${dict}`);
    }
  }
});

test('#1029 DB: list_webinars_v2 returns needs_status_review consistent with the predicate', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('list_webinars_v2', { p_status: null, p_chapter: null, p_tribe_id: null });
  assert.ok(!error, `RPC must not error: ${error?.message}`);
  const rows = Array.isArray(data) ? data : [];
  assert.ok(rows.length > 0, 'expected at least one webinar row');
  const now = Date.now();
  for (const w of rows) {
    assert.ok('needs_status_review' in w, 'every row must carry the needs_status_review flag');
    const expected =
      ['planned', 'confirmed'].includes(w.status) && new Date(w.scheduled_at).getTime() < now;
    assert.equal(
      !!w.needs_status_review,
      expected,
      `needs_status_review mismatch for "${w.title}" (status=${w.status}, scheduled_at=${w.scheduled_at})`,
    );
  }
});
