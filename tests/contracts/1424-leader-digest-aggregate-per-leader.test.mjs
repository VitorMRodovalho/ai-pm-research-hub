/**
 * #1424 Fase C contract — leader digest aggregates per LEADER, not per pair.
 *
 * WHY this gate exists (the defect it locks out):
 *   generate_weekly_leader_digest_cron used to INSERT one notification per
 *   (initiative, leader). Fase A of #1424 then deduped rich digests down to the
 *   newest row per (type, recipient) in send-notification-email — so a leader of
 *   8 initiatives received 1 email and silently LOST 7 summaries. Measured
 *   2026-07-25: 20 leaders, 40 pairs, 9 leaders multi-initiative, max 8.
 *
 *   The fix aggregates at the producer: 1 row per leader, payload v2 carrying
 *   every initiative. Regressing the producer back to per-pair INSERTs would
 *   silently re-open the data loss (the email count would not change, so no
 *   quota alert would fire) — hence a contract test rather than a metric.
 *
 * Offline by design: asserts the shipped SQL + edge-function source. It does NOT
 * invoke the cron, because that function INSERTs notifications with SECURITY
 * DEFINER and a test transaction rollback does not undo it (it would email real
 * leaders — see reference-tx-rollback-not-honored-secdef-pollutes-prod).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const EF_PATH = resolve(ROOT, 'supabase/functions/send-notification-email/index.ts');

function loadAllMigrationsConcat() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');
}

// Latest CREATE OR REPLACE FUNCTION public.<name> body across all migrations.
// Dollar-quote tag is captured and backreferenced so the body closes on the tag
// it opened with ($$, $function$, …). Same helper shape as adr-0022 contract.
function findLatestFunctionBody(name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${escaped}\\s*\\([\\s\\S]*?\\)[\\s\\S]*?AS\\s+(\\$[a-zA-Z_]*\\$)([\\s\\S]*?)\\1`,
    'gi',
  );
  let last = null;
  for (const m of allSQL.matchAll(re)) last = m;
  return last ? last[2] : null;
}

const allSQL = loadAllMigrationsConcat();
const efSource = readFileSync(EF_PATH, 'utf8');
const cronBody = findLatestFunctionBody('generate_weekly_leader_digest_cron');

test('#1424 Fase C: leader digest cron is declared and aggregates by leader', () => {
  assert.ok(cronBody, 'generate_weekly_leader_digest_cron must be declared in a migration.');

  // The aggregation itself: group the pairs by leader and roll the per-initiative
  // digests into ONE json array.
  assert.match(cronBody, /GROUP\s+BY\s+c\.leader_id/i,
    'Producer must GROUP BY leader_id — one payload per leader.');
  assert.match(cronBody, /jsonb_agg\s*\(\s*c\.digest/i,
    'Producer must roll per-initiative digests into a json array (jsonb_agg).');
  assert.match(cronBody, /'initiatives'\s*,\s*t\.initiatives/i,
    "Aggregated payload must expose the array under the 'initiatives' key.");
  assert.match(cronBody, /'version'\s*,\s*2/i,
    'Aggregated payload must be tagged version 2 so the renderer can branch.');
});

test('#1424 Fase C: cron preserves ADR-0022 semantics while aggregating', () => {
  // Guards the p173 refactor + ADR-0022 W3 invariants survive the rewrite.
  assert.ok(cronBody.includes('get_weekly_initiative_digest'),
    'Must still call get_weekly_initiative_digest (p173 initiative-aware).');
  assert.ok(cronBody.includes('weekly_tribe_digest_leader'),
    'Notification type must stay weekly_tribe_digest_leader (email handler back-compat).');
  assert.ok(cronBody.includes('suppress_all'),
    'Must still honour the suppress_all delivery preference.');
  assert.ok(cronBody.includes('transactional_immediate'),
    'Rows must stay transactional_immediate so send-notification-email picks them up.');
  // Report rows for initiatives with no active leader engagement must survive.
  assert.ok(cronBody.includes('no_active_v4_leader_engagement'),
    'Must still report initiatives with no active leader engagement.');
});

test('#1424 Fase C: digest RPC is evaluated once per initiative, not once per pair', () => {
  // Without MATERIALIZED the planner may inline the CTE and re-evaluate the
  // (expensive) digest RPC for every leader of an initiative — 40 calls where 26
  // suffice, at the exact moment the Saturday burst is already tight.
  assert.match(cronBody, /digests\s+AS\s+MATERIALIZED/i,
    'The digests CTE must be MATERIALIZED to pin one RPC call per initiative.');
});

test('#1424 Fase C: renderer handles aggregated payload and keeps the legacy path', () => {
  // v2 detection.
  assert.match(efSource, /Array\.isArray\(payload\?\.initiatives\)/,
    'Renderer must detect the v2 aggregated payload via payload.initiatives.');
  // Per-initiative body is factored out so N initiatives render N section groups.
  assert.match(efSource, /function\s+buildLeaderInitiativeBodyHtml\s*\(/,
    'Per-initiative section renderer must exist (buildLeaderInitiativeBodyHtml).');
  assert.match(efSource, /function\s+leaderDigestFrame\s*\(/,
    'Shared page frame must exist so CTA/footer render once per email.');
  // v1 rows queued before the migration must still render: with no initiatives
  // array, the payload itself is treated as the single initiative.
  assert.match(efSource, /list\.length\s*===\s*0\s*\?\s*payload/,
    'Renderer must keep the legacy single-initiative path for rows queued pre-Fase C.');
});

test('#1424 Fase C item 2: leader digest is staggered off the Saturday collision', () => {
  // The two weekly digests used to fire 30 min apart on the same day, which put
  // ~91 emails against DAILY_SEND_CAP=90. Measured 2026-07-25: Saturday carries
  // no traffic other than the digests themselves (18/07 = 71 member + 37 leader,
  // nothing else), so the SMALLER one moves and the member digest keeps Saturday.
  const staggerSQL = readFileSync(
    resolve(MIGRATIONS_DIR, '20260805000491_1424_fasec_item2_stagger_leader_digest_monday.sql'), 'utf8');

  // '0 12 * * 1' = Monday 12:00 UTC (09:00 America/Sao_Paulo).
  assert.match(staggerSQL, /schedule\s*:=\s*'0 12 \* \* 1'/,
    'Leader digest must be rescheduled to Monday 12:00 UTC.');
  // Resolved by NAME, never by a hardcoded jobid: job ids are not stable across
  // environments, and altering the wrong job would silently retime something else.
  assert.match(staggerSQL, /WHERE\s+jobname\s*=\s*'send-weekly-leader-digest'/,
    'Job must be resolved by jobname, not a hardcoded jobid.');
  assert.match(staggerSQL, /RAISE\s+EXCEPTION/,
    'Migration must fail loudly if the job name does not resolve.');
  // Saturday must not reappear for this job in the same migration.
  assert.doesNotMatch(staggerSQL, /schedule\s*:=\s*'[^']*\* \* 6'/,
    'Leader digest must not stay on Saturday (day-of-week 6).');
});

test('#1424 Fase C: leader digest stays a rich/individual type in the email lane', () => {
  // The email lane must NOT fold the leader digest into the generic coalesced
  // list — it has its own full-page renderer. Fase A put it in both sets; the
  // aggregation does not change that.
  assert.match(efSource, /const\s+ALWAYS_INDIVIDUAL_TYPES[\s\S]{0,220}WEEKLY_TRIBE_DIGEST_LEADER_TYPE/,
    'weekly_tribe_digest_leader must stay in ALWAYS_INDIVIDUAL_TYPES.');
  assert.match(efSource, /const\s+RICH_DIGEST_TYPES[^\n]*WEEKLY_TRIBE_DIGEST_LEADER_TYPE/,
    'weekly_tribe_digest_leader must stay in RICH_DIGEST_TYPES (dedup safety net).');
});
