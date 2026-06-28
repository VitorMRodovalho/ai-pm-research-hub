/**
 * Issue #806 — create_external_speaker_engagement partner-reuse guard + initiative
 * metadata parity; admin_manage_partner_entity 'pmi_global' enum; Detroit data-fix.
 *
 * Static contract: reads the #806 migration SQL + the MCP index.ts. The FK
 * origin_partner_entity_id already existed and was persisted — the gap is the
 * missing fail-closed reuse guard, the missing metadata.partner_entity_id on the
 * initiative, the rejected 'pmi_global' entity_type, and the live Detroit residue.
 *
 * No DB env required.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');

const migFile = readdirSync(MIG_DIR).find(f => f.includes('806_partner_reuse_guard'));
const mig = migFile ? readFileSync(join(MIG_DIR, migFile), 'utf8') : '';
const mcp = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

test('#806: migration file exists', () => {
  assert.ok(migFile, 'expected a *_806_partner_reuse_guard*.sql migration');
});

test('#806: create_external_speaker_engagement gains p_allow_partner_reuse (DROP+CREATE)', () => {
  assert.match(mig, /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.create_external_speaker_engagement\(/i,
    'drops the old signature (param count change requires DROP+CREATE)');
  assert.match(mig, /p_allow_partner_reuse\s+boolean\s+DEFAULT\s+false/i,
    'adds the override param, defaulting to false (fail-closed)');
});

test('#806: fail-closed reuse guard on active initiatives', () => {
  assert.match(mig, /NOT\s+p_allow_partner_reuse\s+AND\s+EXISTS/i, 'guard gates on NOT override AND EXISTS');
  assert.match(mig, /origin_partner_entity_id\s*=\s*p_partner_entity_id[\s\S]*?status\s*=\s*'active'/i,
    'guard checks the partner against ACTIVE initiatives');
  assert.match(mig, /partner_already_linked/, 'returns a structured partner_already_linked code');
  assert.match(mig, /existing_initiatives/, 'surfaces the conflicting initiatives');
});

test('#806: initiative metadata now carries partner_entity_id (parity with engagements)', () => {
  // The Step 1 initiative INSERT uses jsonb_strip_nulls(jsonb_build_object(...)).
  assert.match(
    mig,
    /jsonb_strip_nulls\(jsonb_build_object\([\s\S]*?'partner_entity_id',\s*p_partner_entity_id::text/i,
    'initiative metadata includes partner_entity_id',
  );
});

test('#806: grants restored on the new 13-arg signature', () => {
  assert.match(mig, /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.create_external_speaker_engagement\([^)]*boolean\)\s+FROM\s+PUBLIC,\s*anon/i);
  assert.match(mig, /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.create_external_speaker_engagement\([^)]*boolean\)\s+TO\s+authenticated,\s*service_role/i);
});

test('#806: admin_manage_partner_entity accepts pmi_global + surfaces allowed list', () => {
  assert.match(mig, /'pmi_global'/, "adds 'pmi_global' to the entity_type allow-list");
  assert.match(mig, /'invalid_entity_type'[\s\S]*?'allowed'/i, 'returns the allowed values in the error');
});

test('#806: Detroit origin-FK data-fix is embedded (auditable)', () => {
  assert.match(mig, /UPDATE\s+public\.initiatives[\s\S]*?origin_partner_entity_id\s*=\s*'a57ce406-37ae-42b4-836c-91a446febaf8'/i,
    'corrects Detroit origin FK to the right partner');
  assert.match(mig, /WHERE\s+id\s*=\s*'0b7cbe35-5d7f-4d40-b9f5-0a8eaa486f0d'/i, 'scoped to the Detroit initiative');
  assert.match(mig, /origin_partner_entity_id\s*=\s*'8bb97295-4e8e-4e19-98a4-37b72d3305b8'/i,
    'guarded on the wrong (LIM) partner so it is idempotent');
});

test('#806: duplicate partial index dropped (keep ix_, drop idx_)', () => {
  assert.match(mig, /DROP\s+INDEX\s+IF\s+EXISTS\s+public\.idx_initiatives_origin_partner/i);
  assert.doesNotMatch(mig, /DROP\s+INDEX\s+IF\s+EXISTS\s+public\.ix_initiatives_origin_partner/i,
    'must NOT drop the index we keep');
});

test('#806: MCP tool exposes allow_partner_reuse + passes it through', () => {
  assert.match(mcp, /allow_partner_reuse:\s*z\.boolean\(\)\.optional\(\)/,
    'tool schema has the optional override flag');
  assert.match(mcp, /p_allow_partner_reuse:\s*params\.allow_partner_reuse\s*\?\?\s*false/,
    'handler passes the flag (default false) to the RPC');
});

test('#806: MCP manage_partner entity_type describe includes pmi_global', () => {
  assert.match(mcp, /entity_type:\s*z\.string\(\)\.optional\(\)\.describe\("[^"]*pmi_global[^"]*"\)/,
    'manage_partner entity_type doc lists pmi_global');
});
