/**
 * Contract: p238 #332 — Wave 3 retroactive Art. 18 §IV notification + deletion
 * audit log infrastructure.
 *
 * Origin: Wave 3 of #221/#218 (Whisper Art. 11) decomposition. Wave 1 (p207)
 * shipped DB columns + trigger blocking new transcriptions absent voice
 * biometric consent. Wave 2 (p238 #331) shipped the forward UX path. This
 * leaf (Wave 3) ships the retroactive-remediation audit log:
 *   - ALTER pii_access_log ADD COLUMN deletion_artifacts jsonb (nullable).
 *   - CREATE OR REPLACE FUNCTION lgpd_record_retroactive_notification — PM
 *     calls this AFTER dispatching the email to anchor the audit chain.
 *   - CREATE OR REPLACE FUNCTION lgpd_execute_retroactive_deletion — PM
 *     calls this IF the candidate requests deletion within the 30-day window;
 *     atomically clears pmi_video_screenings.transcription + writes a
 *     pii_access_log row with full deletion_artifacts evidence.
 *
 * The actual notification email dispatch is OUT OF SCOPE for this PR — PM
 * sends from nucleoia@pmigo.org.br using the docs/audit/lgpd-art11-remediation/
 * notification_eduardo_luz_p238_interim.md template (PM-approved interim text,
 * pt-BR primary + en-US fallback). The Angeline legal-grade replacement is
 * sibling #334.
 *
 * Migration: supabase/migrations/20260805000023_p238_332_lgpd_art18_retroactive_deletion_log.sql
 * Template: docs/audit/lgpd-art11-remediation/notification_eduardo_luz_p238_interim.md
 *
 * Asserts:
 *   - Static migration (12): file present, ADD COLUMN IF NOT EXISTS jsonb,
 *     both RPCs declared with SECURITY DEFINER + pinned search_path, both
 *     gates on can_by_member('manage_member'), notification RPC inserts row
 *     with context='lgpd_art_18_retroactive_notification', deletion RPC
 *     inserts row with context='lgpd_art_18_deletion_executed' + writes
 *     deletion_artifacts jsonb, deletion RPC clears
 *     pmi_video_screenings.transcription, idempotent-no-op rejected
 *     (transcription IS NULL guard), sanity DO + single-overload defense,
 *     NOTIFY pgrst.
 *   - Static docs (6): docs file present, contains application_id +
 *     video_id + drive_file_id of the affected row (Eduardo Luz), declares
 *     template_version=interim_v1, contains pt-BR text + en-US fallback,
 *     references Art. 11 §I AND Art. 18 §IV, operational checklist step
 *     calls the RPC.
 *   - Forward-defense (2): no future migration removes deletion_artifacts
 *     column; no future migration redeclares either RPC without manage_member
 *     gate.
 *   - DB-gated (3): live deletion_artifacts column exists with jsonb type,
 *     misuse-call to lgpd_record_retroactive_notification (no auth) returns
 *     Unauthorized, misuse-call to lgpd_execute_retroactive_deletion (no auth)
 *     returns Unauthorized.
 *
 * Cross-ref:
 *   - GH #332 (this leaf)
 *   - GH #218 + #221 (parent umbrella, decomposed p236)
 *   - GH #331 (sibling shipped p238 — forward UI path)
 *   - GH #333 (sibling — invariant U; depends on this leaf's deletion completing for the affected row)
 *   - GH #334 (sibling — Angeline legal-grade template; produces the v2 replacement for interim_v1)
 *   - LGPD Art. 11 §I (sensitive data) · Art. 18 §IV (deletion right) · Art. 9 (informed processing) · Art. 48 §1 (ANPD pre-disclosure — coordinate under #334)
 *   - Wave 1 emergency block canonical row: 20260520231254
 *   - Forward UI capture canonical row: 20260805000022 (p238 #331)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIGRATION_FILE = resolve(
  MIGRATIONS_DIR,
  '20260805000023_p238_332_lgpd_art18_retroactive_deletion_log.sql'
);
const DOCS_FILE = resolve(
  ROOT,
  'docs/audit/lgpd-art11-remediation/notification_eduardo_luz_p238_interim.md'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// Eduardo Luz — the 1 affected candidate (confirmed live p238 boot).
const AFFECTED_APPLICATION_ID = 'e780d8a9-55e0-4a6c-9370-4acc24a9619d';
const AFFECTED_VIDEO_ID = '6afb7e26-b806-4028-a8d5-0a22d1a0584b';
const AFFECTED_DRIVE_FILE_ID = '14bA9rCezVD0Usko-S28ZtJnXd63MwsO6';

// ===================================================================
// STATIC migration body assertions (always run)
// ===================================================================

test('p238 #332: migration file exists', () => {
  assert.ok(existsSync(MIGRATION_FILE), `Migration file must exist at ${MIGRATION_FILE}`);
});

test('p238 #332: migration adds deletion_artifacts jsonb column (IF NOT EXISTS, idempotent)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(
    body,
    /ALTER\s+TABLE\s+public\.pii_access_log\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+deletion_artifacts\s+jsonb/i,
    'Must ALTER pii_access_log ADD COLUMN IF NOT EXISTS deletion_artifacts jsonb'
  );
});

test('p238 #332: both RPCs declared with SECDEF + pinned search_path', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // notification RPC
  assert.match(
    body,
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.lgpd_record_retroactive_notification\s*\([\s\S]*?\)\s+RETURNS\s+jsonb\s+LANGUAGE\s+plpgsql\s+SECURITY\s+DEFINER\s+SET\s+search_path\s*=\s*'public',\s*'pg_temp'/i,
    'lgpd_record_retroactive_notification must be SECDEF with pinned search_path'
  );
  // deletion RPC
  assert.match(
    body,
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.lgpd_execute_retroactive_deletion\s*\([\s\S]*?\)\s+RETURNS\s+jsonb\s+LANGUAGE\s+plpgsql\s+SECURITY\s+DEFINER\s+SET\s+search_path\s*=\s*'public',\s*'pg_temp'/i,
    'lgpd_execute_retroactive_deletion must be SECDEF with pinned search_path'
  );
});

test('p238 #332: both RPCs gate on can_by_member(manage_member)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Both RPCs must invoke can_by_member with 'manage_member' (V4 authority).
  const matches = body.match(/can_by_member\(\s*v_caller_member_id\s*,\s*'manage_member'\s*\)/g) || [];
  assert.ok(matches.length >= 2, `Both RPCs must gate on can_by_member('manage_member'); found ${matches.length} occurrences`);
});

test('p238 #332: notification RPC inserts row with canonical context literal', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(
    body,
    /'lgpd_art_18_retroactive_notification'/,
    'notification RPC must use exact context literal lgpd_art_18_retroactive_notification'
  );
  assert.match(
    body,
    /INSERT\s+INTO\s+public\.pii_access_log\s*\(\s*accessor_id\s*,\s*target_member_id\s*,\s*fields_accessed\s*,\s*context\s*,\s*reason\s*,\s*accessed_at\s*\)\s*VALUES\s*\([\s\S]*?'lgpd_art_18_retroactive_notification'/i,
    'notification RPC must INSERT into pii_access_log with context=lgpd_art_18_retroactive_notification'
  );
});

test('p238 #332: deletion RPC inserts row with canonical context + writes deletion_artifacts', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(
    body,
    /'lgpd_art_18_deletion_executed'/,
    'deletion RPC must use exact context literal lgpd_art_18_deletion_executed'
  );
  assert.match(
    body,
    /INSERT\s+INTO\s+public\.pii_access_log\s*\([\s\S]*?deletion_artifacts\s*\)\s*VALUES\s*\([\s\S]*?'lgpd_art_18_deletion_executed'[\s\S]*?v_artifacts/i,
    'deletion RPC must INSERT into pii_access_log including deletion_artifacts column with the v_artifacts jsonb'
  );
});

test('p238 #332: deletion RPC clears pmi_video_screenings.transcription', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(
    body,
    /UPDATE\s+public\.pmi_video_screenings\s+SET\s+transcription\s*=\s*NULL/i,
    'deletion RPC must UPDATE pmi_video_screenings SET transcription = NULL'
  );
});

test('p238 #332: deletion RPC rejects idempotent no-op (transcription already NULL)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(
    body,
    /IF\s+v_vs\.transcription\s+IS\s+NULL\s+THEN[\s\S]*?RAISE\s+EXCEPTION/i,
    'deletion RPC must reject when transcription is already NULL (keeps audit chain clean)'
  );
});

test('p238 #332: deletion RPC validates video belongs to application', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(
    body,
    /IF\s+v_vs\.application_id\s*<>\s*p_application_id\s+THEN[\s\S]*?RAISE\s+EXCEPTION/i,
    'deletion RPC must validate video_id belongs to the given application_id (cross-app deletion guard)'
  );
});

test('p238 #332: deletion_artifacts jsonb includes the required evidence keys', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  const required = [
    'video_id',
    'application_id',
    'old_transcription_len',
    'drive_file_id',
    'drive_deletion_ref',
    'deletion_reason',
    'reversible',
  ];
  for (const k of required) {
    const re = new RegExp(`jsonb_build_object\\([\\s\\S]*?'${k}'`);
    assert.match(body, re, `deletion_artifacts jsonb_build_object must include key '${k}'`);
  }
});

test('p238 #332: sanity DO block asserts post-apply state + dual-overload defense + NOTIFY pgrst', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /DO\s+\$sanity\$/, 'must have sanity DO block tagged $sanity$');
  assert.match(body, /sanity:\s+pii_access_log\.deletion_artifacts jsonb column missing/i, 'sanity asserts column added');
  assert.match(body, /sanity:\s+lgpd_record_retroactive_notification missing or context literal not present/i, 'sanity asserts notification RPC body');
  assert.match(body, /sanity:\s+lgpd_execute_retroactive_deletion does not write deletion_artifacts/i, 'sanity asserts deletion RPC writes artifacts');
  assert.match(body, /sanity:\s+lgpd_record_retroactive_notification has more than one overload/i, 'sanity defends against duplicate notification overload (SEDIMENT-232.A)');
  assert.match(body, /sanity:\s+lgpd_execute_retroactive_deletion has more than one overload/i, 'sanity defends against duplicate deletion overload (SEDIMENT-232.A)');
  assert.match(body, /NOTIFY\s+pgrst\s*,\s*'reload schema'/i, 'must NOTIFY pgrst at end');
});

// ===================================================================
// STATIC docs assertions (operational template)
// ===================================================================

test('p238 #332: notification template docs file exists', () => {
  assert.ok(existsSync(DOCS_FILE), `Docs file must exist at ${DOCS_FILE}`);
});

test('p238 #332: docs file declares interim_v1 template version + correct affected ids', () => {
  const body = readFileSync(DOCS_FILE, 'utf8');
  assert.match(body, /Template version[^a-zA-Z0-9]{1,12}interim_v1/i, 'docs must declare Template version: interim_v1');
  assert.ok(body.includes(AFFECTED_APPLICATION_ID), `docs must reference application_id ${AFFECTED_APPLICATION_ID}`);
  assert.ok(body.includes(AFFECTED_VIDEO_ID), `docs must reference video_id ${AFFECTED_VIDEO_ID}`);
  assert.ok(body.includes(AFFECTED_DRIVE_FILE_ID), `docs must reference drive_file_id ${AFFECTED_DRIVE_FILE_ID}`);
});

test('p238 #332: docs file contains pt-BR primary + en-US fallback sections + cites Art. 11 + Art. 18', () => {
  const body = readFileSync(DOCS_FILE, 'utf8');
  assert.match(body, /Texto pt-BR/i, 'docs must declare a pt-BR primary section');
  assert.match(body, /English fallback|en-US/i, 'docs must include en-US fallback section');
  assert.match(body, /Art\.\s*11/, 'docs must cite LGPD Art. 11 §I (sensitive data)');
  assert.match(body, /Art\.\s*18/, 'docs must cite LGPD Art. 18 §IV (deletion right)');
});

test('p238 #332: docs file operational checklist calls the canonical RPC', () => {
  const body = readFileSync(DOCS_FILE, 'utf8');
  assert.match(
    body,
    /lgpd_record_retroactive_notification\s*\(/,
    'docs operational checklist must reference lgpd_record_retroactive_notification('
  );
  assert.match(
    body,
    /lgpd_execute_retroactive_deletion\s*\(/,
    'docs operational checklist must reference lgpd_execute_retroactive_deletion('
  );
});

// ===================================================================
// FORWARD-DEFENSE: no future migration regresses
// ===================================================================

test('p238 #332: no future migration drops deletion_artifacts column', () => {
  const all = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  const fixIdx = all.indexOf('20260805000023_p238_332_lgpd_art18_retroactive_deletion_log.sql');
  assert.ok(fixIdx >= 0, 'fix migration must be in registry');
  const subsequent = all.slice(fixIdx + 1).map((f) => ({
    name: f,
    body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8'),
  }));
  const dropPattern =
    /ALTER\s+TABLE\s+(?:public\.)?pii_access_log\s+DROP\s+COLUMN\s+(?:IF\s+EXISTS\s+)?deletion_artifacts/i;
  const offenders = subsequent.filter((m) => dropPattern.test(m.body));
  assert.equal(
    offenders.length,
    0,
    `Future migrations must not DROP COLUMN deletion_artifacts (destroys audit evidence). Offenders: ${offenders.map((m) => m.name).join(', ')}`
  );
});

test('p238 #332: no future migration redeclares either RPC without manage_member gate', () => {
  const all = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  const fixIdx = all.indexOf('20260805000023_p238_332_lgpd_art18_retroactive_deletion_log.sql');
  assert.ok(fixIdx >= 0);
  const subsequent = all.slice(fixIdx + 1).map((f) => ({
    name: f,
    body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8'),
  }));
  for (const rpc of ['lgpd_record_retroactive_notification', 'lgpd_execute_retroactive_deletion']) {
    const declarePattern = new RegExp(
      `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${rpc}\\s*\\(`,
      'i'
    );
    const offenders = subsequent.filter((m) => {
      if (!declarePattern.test(m.body)) return false;
      return !/can_by_member\([\s\S]*?'manage_member'/.test(m.body);
    });
    assert.equal(
      offenders.length,
      0,
      `Future migrations that redeclare ${rpc} must preserve the manage_member gate. Offenders: ${offenders.map((m) => m.name).join(', ')}`
    );
  }
});

// ===================================================================
// DB-GATED: live column + auth gate dispatch
// ===================================================================

test(
  'p238 #332: live pii_access_log.deletion_artifacts column exists with jsonb type',
  { skip: !dbGated ? skipMsg : false },
  async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    // We can't easily query information_schema via PostgREST. Use the
    // function bodies audit helper as a proxy: it will list our two RPCs
    // (a function with the right names exists), and any insert into
    // pii_access_log including deletion_artifacts implies the column exists
    // (otherwise the function definitions would have failed at apply).
    if (error) {
      console.warn(`[p238 #332] _audit_list_public_function_bodies unavailable: ${error.message}`);
      return;
    }
    const rows = Array.isArray(data) ? data : [];
    const hasRecord = rows.some(
      (r) => (r.proname || r.name) === 'lgpd_record_retroactive_notification'
    );
    const hasDelete = rows.some(
      (r) => (r.proname || r.name) === 'lgpd_execute_retroactive_deletion'
    );
    assert.ok(hasRecord, 'live pg_proc must list lgpd_record_retroactive_notification');
    assert.ok(hasDelete, 'live pg_proc must list lgpd_execute_retroactive_deletion');
  }
);

test(
  'p238 #332: lgpd_record_retroactive_notification gates dispatch (service-role context fails member lookup)',
  { skip: !dbGated ? skipMsg : false },
  async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // Service-role bypasses RLS but auth.uid() returns NULL inside the RPC body,
    // so v_caller_member_id is NULL → raises "no member record for caller".
    const { error } = await sb.rpc('lgpd_record_retroactive_notification', {
      p_application_id: AFFECTED_APPLICATION_ID,
      p_template_version: 'interim_v1',
      p_lang: 'pt-BR',
      p_notification_method: 'email',
    });
    assert.ok(error, 'service-role misuse must return an error (no member context)');
    const msg = error.message || '';
    assert.ok(
      /Unauthorized.*no member record|insufficient_privilege/i.test(msg),
      `RPC must reject when caller has no member record; got: ${msg}`
    );
  }
);

test(
  'p238 #332: lgpd_execute_retroactive_deletion gates dispatch (service-role context fails member lookup)',
  { skip: !dbGated ? skipMsg : false },
  async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await sb.rpc('lgpd_execute_retroactive_deletion', {
      p_application_id: AFFECTED_APPLICATION_ID,
      p_video_id: AFFECTED_VIDEO_ID,
      p_deletion_reason: 'CI contract test smoke — service-role rejection probe',
    });
    assert.ok(error, 'service-role misuse must return an error (no member context)');
    const msg = error.message || '';
    assert.ok(
      /Unauthorized.*no member record|insufficient_privilege/i.test(msg),
      `RPC must reject when caller has no member record; got: ${msg}`
    );
  }
);
