/**
 * Contract test for issue #181 (p203) — signature evidence persistence.
 *
 * Verifies via static migration analysis that:
 *   - certificates.counter_signature_hash column exists.
 *   - counter_sign_certificate() RPC accepts (uuid, text, text) signature.
 *   - counter_sign_certificate() persists counter_signature_hash in UPDATE.
 *   - counter_sign_certificate() includes the hash in admin_audit_log changes.
 *   - sign_volunteer_agreement() RPC accepts (text, text, text) signature.
 *   - sign_volunteer_agreement() INSERT writes signed_ip + signed_user_agent.
 *
 * Pattern: matches selection-interview-decision.test.mjs (read-all SQL, regex).
 * Hard-fails offline (no DB env required).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
}

const allSQL = loadAllMigrations().join('\n');

function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

function latestFunctionSignature(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\(([^)]*)\\)`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][1] : null;
}

test('certificates.counter_signature_hash column is added by some migration', () => {
  const re = /ALTER\s+TABLE\s+(?:public\.)?certificates\s+ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?counter_signature_hash\s+text/i;
  assert.ok(re.test(allSQL), 'expected ALTER TABLE certificates ADD COLUMN counter_signature_hash text');
});

test('counter_sign_certificate accepts p_signed_ip + p_signed_user_agent', () => {
  const sig = latestFunctionSignature('counter_sign_certificate');
  assert.ok(sig, 'counter_sign_certificate signature not found');
  assert.match(sig, /p_certificate_id\s+uuid/i, 'p_certificate_id must remain');
  assert.match(sig, /p_signed_ip\s+text\s+DEFAULT\s+NULL/i, 'p_signed_ip text DEFAULT NULL required');
  assert.match(sig, /p_signed_user_agent\s+text\s+DEFAULT\s+NULL/i, 'p_signed_user_agent text DEFAULT NULL required');
});

test('counter_sign_certificate persists counter_signature_hash in UPDATE', () => {
  const body = latestFunctionBody('counter_sign_certificate');
  assert.ok(body, 'counter_sign_certificate body not found');
  assert.match(
    body,
    /UPDATE\s+public\.certificates[\s\S]*?counter_signature_hash\s*=\s*v_hash/i,
    'UPDATE must persist counter_signature_hash'
  );
});

test('counter_sign_certificate writes hash to admin_audit_log changes', () => {
  const body = latestFunctionBody('counter_sign_certificate');
  assert.match(
    body,
    /admin_audit_log[\s\S]*?counter_signature_hash[\s\S]*?v_hash/i,
    'admin_audit_log changes payload must include counter_signature_hash'
  );
});

test('counter_sign_certificate safely parses signer IP via inet cast', () => {
  const body = latestFunctionBody('counter_sign_certificate');
  assert.match(body, /v_ip\s+inet\s*:=\s*NULL/i, 'v_ip should be declared as NULL inet');
  assert.match(body, /p_signed_ip::inet/i, 'should attempt p_signed_ip::inet cast');
  // Tighter regex per code-reviewer LOW: no [\s\S]*? gap between EXCEPTION and v_ip := NULL.
  assert.match(
    body,
    /EXCEPTION\s+WHEN\s+OTHERS\s+THEN\s+v_ip\s*:=\s*NULL/i,
    'should swallow inet-cast failure to NULL (do not break counter-sign on malformed IP)'
  );
});

test('both RPCs cap p_signed_user_agent to 500 chars server-side (defense vs direct PostgREST/MCP)', () => {
  // Frontend already trims via navigator.userAgent.substring(0, 500), but a direct
  // RPC call (PostgREST or MCP) can bypass that cap. Per code-reviewer GAP-181.B HIGH,
  // both RPC bodies enforce the cap as `p_signed_user_agent := left(p_signed_user_agent, 500)`.
  const counterBody = latestFunctionBody('counter_sign_certificate');
  assert.match(
    counterBody,
    /p_signed_user_agent\s*:=\s*left\(\s*p_signed_user_agent\s*,\s*500\s*\)/i,
    'counter_sign_certificate must cap p_signed_user_agent to 500 chars'
  );
  const signBody = latestFunctionBody('sign_volunteer_agreement');
  assert.match(
    signBody,
    /p_signed_user_agent\s*:=\s*left\(\s*p_signed_user_agent\s*,\s*500\s*\)/i,
    'sign_volunteer_agreement must cap p_signed_user_agent to 500 chars'
  );
});

test('sign_volunteer_agreement accepts p_signed_ip + p_signed_user_agent', () => {
  const sig = latestFunctionSignature('sign_volunteer_agreement');
  assert.ok(sig, 'sign_volunteer_agreement signature not found');
  assert.match(sig, /p_language\s+text\s+DEFAULT/i, 'p_language must remain');
  assert.match(sig, /p_signed_ip\s+text\s+DEFAULT\s+NULL/i, 'p_signed_ip text DEFAULT NULL required');
  assert.match(sig, /p_signed_user_agent\s+text\s+DEFAULT\s+NULL/i, 'p_signed_user_agent text DEFAULT NULL required');
});

test('sign_volunteer_agreement INSERT writes signed_ip + signed_user_agent into certificates', () => {
  const body = latestFunctionBody('sign_volunteer_agreement');
  assert.ok(body, 'sign_volunteer_agreement body not found');
  const insertRe = /INSERT\s+INTO\s+certificates\s*\(([\s\S]*?)\)\s*VALUES/i;
  const match = body.match(insertRe);
  assert.ok(match, 'INSERT INTO certificates not found');
  const cols = match[1].toLowerCase();
  assert.ok(cols.includes('signed_ip'), 'signed_ip must be in INSERT column list');
  assert.ok(cols.includes('signed_user_agent'), 'signed_user_agent must be in INSERT column list');
});

test('sign_volunteer_agreement audit log includes signed_ip + signed_user_agent', () => {
  const body = latestFunctionBody('sign_volunteer_agreement');
  assert.match(
    body,
    /admin_audit_log[\s\S]*?'signed_ip'[\s\S]*?'signed_user_agent'/i,
    'admin_audit_log changes payload must include signed_ip + signed_user_agent'
  );
});
