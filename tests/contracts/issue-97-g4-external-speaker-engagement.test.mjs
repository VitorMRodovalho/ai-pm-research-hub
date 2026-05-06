/**
 * Issue #97 W3 G4 — create_external_speaker_engagement orchestrator contract
 *
 * Static analysis test for the Partnership→Initiative atomic orchestrator (p95).
 * Validates:
 *   1. Migration declares the function with the documented signature
 *   2. Function is SECURITY DEFINER (gates auth via auth.uid() → persons.id)
 *   3. Auth gate uses can() with manage_partner OR manage_member
 *   4. Speaker engagements use lead_presenter/co_presenter roles + metadata.presenter_role
 *      per W1 LATAM LIM precedent + G2 CHECK constraint
 *   5. Board items declare source_type='external_partner' + source_partner_id (G3)
 *   6. Initiative declares origin_partner_entity_id (G1)
 *   7. partner_interactions uses 'note' type (constraint: only email|whatsapp|linkedin|call|meeting|note|status_change)
 *   8. MCP wrapper exists in nucleo-mcp/index.ts with the expected param surface
 *   9. MCP wrapper gates on canV4(manage_partner) OR canV4(manage_member)
 *
 * The full happy-path and error-path runtime smokes ran in p106 against synthetic
 * data + cleanup (see commit notes). This file is the static contract that catches
 * regressions across migrations + EF refactors.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MCP_INDEX = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');

function loadAllMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql'))
    .sort()
    .map(f => readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8'))
    .join('\n');
}

const allSQL = loadAllMigrations();
const mcpIndex = readFileSync(MCP_INDEX, 'utf8');

test('#97 G4: create_external_speaker_engagement migration exists', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes('p95_97_w3_g4_create_external_speaker_engagement'));
  assert.ok(files.length > 0, 'Migration with name pattern p95_97_w3_g4_create_external_speaker_engagement must exist');
});

test('#97 G4: function declared with SECURITY DEFINER + parameter signature', () => {
  // Function created with the 12-param signature
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_external_speaker_engagement\s*\(([\s\S]*?)\)\s*RETURNS\s+jsonb[\s\S]*?LANGUAGE\s+plpgsql[\s\S]*?SECURITY\s+DEFINER/i;
  const m = allSQL.match(re);
  assert.ok(m, 'create_external_speaker_engagement must be declared as plpgsql SECURITY DEFINER returning jsonb');
  // Required params present
  const params = m[1];
  for (const p of [
    'p_partner_entity_id', 'p_lead_person_id', 'p_initiative_title',
    'p_co_person_id', 'p_initiative_kind', 'p_deadlines',
    'p_whatsapp_url', 'p_meeting_link', 'p_drive_folder_url',
    'p_board_domain_key', 'p_org_id'
  ]) {
    assert.ok(params.includes(p), `Function signature must include ${p}`);
  }
});

test('#97 G4: auth gate uses can() with manage_partner OR manage_member', () => {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_external_speaker_engagement[\s\S]*?AS\s+\$function\$([\s\S]*?)\$function\$/i;
  const body = allSQL.match(re)?.[1];
  assert.ok(body, 'Function body must be locatable via $function$ delimiters');
  assert.ok(/can\([^)]*'manage_partner'/i.test(body),
    'Function body must call can(...) with manage_partner');
  assert.ok(/can\([^)]*'manage_member'/i.test(body),
    'Function body must call can(...) with manage_member as alternative auth path');
});

test('#97 G4: speaker conventions match W1 LATAM precedent (role + metadata.presenter_role)', () => {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_external_speaker_engagement[\s\S]*?AS\s+\$function\$([\s\S]*?)\$function\$/i;
  const body = allSQL.match(re)?.[1];
  assert.ok(body);
  // Lead must use role='lead_presenter' + presenter_role='lead'
  assert.ok(/role.*'lead_presenter'/i.test(body) || /'lead_presenter'/.test(body),
    'Lead speaker must use role=lead_presenter');
  assert.ok(/'presenter_role',\s*'lead'/i.test(body),
    'Lead metadata must set presenter_role=lead (G2 CHECK constraint)');
  // Co must use role='co_presenter' + presenter_role='co'
  assert.ok(/'co_presenter'/i.test(body),
    'Co speaker must use role=co_presenter');
  assert.ok(/'presenter_role',\s*'co'/i.test(body),
    'Co metadata must set presenter_role=co (G2 CHECK constraint)');
});

test('#97 G4: board_items ship source_type=external_partner + source_partner_id (G3)', () => {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_external_speaker_engagement[\s\S]*?AS\s+\$function\$([\s\S]*?)\$function\$/i;
  const body = allSQL.match(re)?.[1];
  assert.ok(body);
  assert.ok(/'external_partner'/i.test(body),
    'board_items must be created with source_type=external_partner per G3');
  assert.ok(/source_partner_id/i.test(body),
    'board_items must populate source_partner_id (G3 FK to partner_entities)');
});

test('#97 G4: initiative ships origin_partner_entity_id (G1)', () => {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_external_speaker_engagement[\s\S]*?AS\s+\$function\$([\s\S]*?)\$function\$/i;
  const body = allSQL.match(re)?.[1];
  assert.ok(body);
  assert.ok(/origin_partner_entity_id/i.test(body),
    'initiative INSERT must populate origin_partner_entity_id (G1 FK)');
});

test('#97 G4: partner_interactions uses note type (CHECK constraint compliance)', () => {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_external_speaker_engagement[\s\S]*?AS\s+\$function\$([\s\S]*?)\$function\$/i;
  const body = allSQL.match(re)?.[1];
  assert.ok(body);
  // Must NOT use 'initiative_created' (would violate CHECK)
  // INSERT block uses 'note' as interaction_type literal
  const insertBlock = body.match(/INSERT\s+INTO\s+public\.partner_interactions[\s\S]{0,800}/i)?.[0];
  assert.ok(insertBlock, 'partner_interactions INSERT block must exist');
  assert.ok(/'note'/.test(insertBlock),
    'partner_interactions INSERT must use type=note (only email|whatsapp|linkedin|call|meeting|note|status_change allowed)');
  assert.ok(!/'initiative_created'/.test(insertBlock),
    'partner_interactions must NOT use custom type "initiative_created" (violates CHECK constraint)');
});

test('#97 G4: GRANT EXECUTE to authenticated; REVOKE from anon/PUBLIC', () => {
  assert.ok(
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.create_external_speaker_engagement[^;]*\s+TO\s+authenticated/i.test(allSQL),
    'GRANT EXECUTE TO authenticated must be declared'
  );
  assert.ok(
    /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.create_external_speaker_engagement[^;]*\s+FROM[^;]*(?:PUBLIC|anon)/i.test(allSQL),
    'REVOKE EXECUTE FROM PUBLIC + anon must be declared (defense-in-depth)'
  );
});

test('#97 G4: MCP wrapper exists with expected param surface', () => {
  assert.ok(
    /mcp\.tool\(\s*"create_external_speaker_engagement"/.test(mcpIndex),
    'MCP tool create_external_speaker_engagement must be declared'
  );
  // Expected Zod params
  for (const p of [
    'partner_entity_id', 'lead_person_id', 'initiative_title',
    'co_person_id', 'initiative_kind', 'deadlines',
    'whatsapp_url', 'meeting_link', 'drive_folder_url'
  ]) {
    assert.ok(new RegExp(`${p}:\\s*z\\.string\\(`).test(mcpIndex),
      `MCP wrapper must declare zod string param ${p}`);
  }
});

test('#97 G4: MCP wrapper auth gates on canV4(manage_partner) OR canV4(manage_member)', () => {
  const wrapperRegex = /mcp\.tool\(\s*"create_external_speaker_engagement"[\s\S]*?\}\s*\)\s*;/;
  const wrapper = mcpIndex.match(wrapperRegex)?.[0];
  assert.ok(wrapper, 'MCP wrapper block must be locatable');
  assert.ok(/canV4\([^)]*'manage_partner'/i.test(wrapper),
    'MCP wrapper must check canV4(manage_partner)');
  assert.ok(/canV4\([^)]*'manage_member'/i.test(wrapper),
    'MCP wrapper must check canV4(manage_member) as alternative path');
});
