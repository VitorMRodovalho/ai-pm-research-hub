/**
 * W122 + W123 Contract Tests: Novello Recognition + Partner Pipeline
 * Static analysis — reads migration files, UI files, and verifies structure.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');

function findFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  if (matches.length === 0) return null;
  return matches[matches.length - 1][2];
}

// ═══════════════════════════════════════════════════
// W122: Carlos Novello Recognition
// ═══════════════════════════════════════════════════

test('get_public_impact_data includes recognitions array', () => {
  const body = findFunctionBody('get_public_impact_data');
  assert.ok(body, 'get_public_impact_data not found');
  assert.ok(body.includes("'recognitions'"), 'Must include recognitions key');
});

test('recognitions has Carlos Novello entry', () => {
  const body = findFunctionBody('get_public_impact_data');
  assert.ok(body);
  assert.ok(body.includes('Carlos Novello'), 'Must include Carlos Novello in recognitions');
  assert.ok(body.includes('Finalista'), 'Must include Finalista designation');
  assert.ok(body.includes('PMI LATAM'), 'Must reference PMI LATAM');
  assert.ok(body.includes('2026-02-26'), 'Must include ceremony date');
});

test('ImpactPageIsland has recognitions section', () => {
  const path = resolve(ROOT, 'src/components/islands/ImpactPageIsland.tsx');
  assert.ok(existsSync(path));
  const content = readFileSync(path, 'utf8');
  assert.ok(content.includes('recognitions'), 'Must reference recognitions data');
  assert.ok(content.includes('recognitionsSection'), 'Must have recognitionsSection label');
});

test('ImpactPageIsland recognitions i18n (pt-BR, en-US, es-LATAM)', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/ImpactPageIsland.tsx'), 'utf8');
  assert.ok(content.includes('Reconhecimentos'), 'pt-BR label');
  assert.ok(content.includes('Recognitions'), 'en-US label');
  assert.ok(content.includes('Reconocimientos'), 'es-LATAM label');
});

test('ImpactData interface includes recognitions', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/ImpactPageIsland.tsx'), 'utf8');
  assert.ok(content.includes('recognitions:'), 'ImpactData must have recognitions field');
});

// ═══════════════════════════════════════════════════
// W123: Partner Pipeline RPCs
// ═══════════════════════════════════════════════════

test('get_partner_pipeline RPC exists', () => {
  const body = findFunctionBody('get_partner_pipeline');
  assert.ok(body, 'get_partner_pipeline not found');
});

test('get_partner_pipeline requires auth', () => {
  const body = findFunctionBody('get_partner_pipeline');
  assert.ok(body);
  assert.ok(/auth\.uid\(\)/i.test(body), 'Must check auth.uid()');
  assert.ok(/RAISE\s+EXCEPTION/i.test(body), 'Must RAISE EXCEPTION on unauthorized');
});

test('get_partner_pipeline returns pipeline data', () => {
  const body = findFunctionBody('get_partner_pipeline');
  assert.ok(body);
  const fields = ['pipeline', 'by_status', 'by_type', 'total', 'active', 'stale'];
  for (const f of fields) {
    assert.ok(body.includes(`'${f}'`), `Must include ${f} in response`);
  }
});

test('get_partner_pipeline includes days_in_stage', () => {
  const body = findFunctionBody('get_partner_pipeline');
  assert.ok(body);
  assert.ok(body.includes('days_in_stage'), 'Must calculate days_in_stage');
});

test('get_partner_pipeline stale detection uses 30 days', () => {
  const body = findFunctionBody('get_partner_pipeline');
  assert.ok(body);
  assert.ok(body.includes('30 days'), 'Stale threshold must be 30 days');
});

test('admin_update_partner_status RPC exists', () => {
  const body = findFunctionBody('admin_update_partner_status');
  assert.ok(body, 'admin_update_partner_status not found');
});

test('admin_update_partner_status requires auth', () => {
  const body = findFunctionBody('admin_update_partner_status');
  assert.ok(body);
  assert.ok(/auth\.uid\(\)/i.test(body), 'Must check auth.uid()');
  assert.ok(/RAISE\s+EXCEPTION/i.test(body), 'Must RAISE EXCEPTION on unauthorized');
});

test('admin_update_partner_status enforces forward-only transitions', () => {
  const body = findFunctionBody('admin_update_partner_status');
  assert.ok(body);
  assert.ok(body.includes('backward_transition_blocked'), 'Must block backward transitions');
});

test('admin_update_partner_status allows inactive/churned from any status', () => {
  const body = findFunctionBody('admin_update_partner_status');
  assert.ok(body);
  assert.ok(body.includes("'inactive'") && body.includes("'churned'"), 'Must allow inactive/churned transitions');
});

test('admin_update_partner_status appends notes with timestamp', () => {
  const body = findFunctionBody('admin_update_partner_status');
  assert.ok(body);
  assert.ok(body.includes('to_char(now()'), 'Must append timestamp to notes');
});

// ═══════════════════════════════════════════════════
// W123: Schema changes
// ═══════════════════════════════════════════════════

test('partner_entities gets notes and updated_at columns', () => {
  assert.ok(allSQL.includes('ADD COLUMN IF NOT EXISTS notes text'), 'Must add notes column');
  assert.ok(allSQL.includes('ADD COLUMN IF NOT EXISTS updated_at'), 'Must add updated_at column');
});

test('partner_entities gets chapter column', () => {
  assert.ok(allSQL.includes('ADD COLUMN IF NOT EXISTS chapter text'), 'Must add chapter column');
});

test('admin_manage_partner_entity accepts expanded status values', () => {
  const body = findFunctionBody('admin_manage_partner_entity');
  assert.ok(body);
  assert.ok(body.includes("'contact'"), 'Must accept contact status');
  assert.ok(body.includes("'negotiation'"), 'Must accept negotiation status');
  assert.ok(body.includes("'churned'"), 'Must accept churned status');
});

test('admin_manage_partner_entity accepts expanded entity types', () => {
  const body = findFunctionBody('admin_manage_partner_entity');
  assert.ok(body);
  assert.ok(body.includes("'community'"), 'Must accept community type');
  assert.ok(body.includes("'research'"), 'Must accept research type');
  assert.ok(body.includes("'association'"), 'Must accept association type');
});

// ═══════════════════════════════════════════════════
// W123: Partner Seeding
// ═══════════════════════════════════════════════════

test('PM AI Revolution seeded as contact', () => {
  assert.ok(allSQL.includes('PM AI Revolution'), 'Must seed PM AI Revolution');
  assert.ok(allSQL.includes("'contact'"), 'PM AI Revolution must be seeded as contact');
});

test('5 prospect partners seeded', () => {
  const prospects = ['IFG', 'FioCruz', 'AI.Brasil', 'CEIA-UFG', 'PMO-GA'];
  for (const name of prospects) {
    assert.ok(allSQL.includes(name), `Must seed ${name}`);
  }
});

// ═══════════════════════════════════════════════════
// W123: UI — Pipeline View
// ═══════════════════════════════════════════════════

test('PartnerPipelineIsland exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx')), 'PartnerPipelineIsland.tsx must exist');
});

test('PartnerPipelineIsland has Kanban columns', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx'), 'utf8');
  assert.ok(content.includes('prospect'), 'Must have prospect column');
  assert.ok(content.includes('contact'), 'Must have contact column');
  assert.ok(content.includes('negotiation'), 'Must have negotiation column');
  assert.ok(content.includes('active'), 'Must have active column');
  assert.ok(content.includes('inactive'), 'Must have inactive column');
});

test('PartnerPipelineIsland calls get_partner_pipeline', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx'), 'utf8');
  assert.ok(content.includes('get_partner_pipeline'), 'Must call get_partner_pipeline RPC');
});

test('PartnerPipelineIsland calls admin_update_partner_status', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx'), 'utf8');
  assert.ok(content.includes('admin_update_partner_status'), 'Must call admin_update_partner_status RPC');
});

test('PartnerPipelineIsland shows stale alerts', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx'), 'utf8');
  assert.ok(content.includes('stale'), 'Must show stale partner alerts');
});

test('PartnerPipelineIsland supports i18n', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx'), 'utf8');
  assert.ok(content.includes('pt-BR'), 'Must support pt-BR');
  assert.ok(content.includes('en-US'), 'Must support en-US');
  assert.ok(content.includes('es-LATAM'), 'Must support es-LATAM');
});

test('/admin/partnerships uses PartnerPipelineIsland', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/admin/partnerships.astro'), 'utf8');
  assert.ok(content.includes('PartnerPipelineIsland'), 'Must use PartnerPipelineIsland');
  assert.ok(content.includes('client:load'), 'Must have client:load');
});

test('/admin/partnerships has pipeline/crud view toggle', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/admin/partnerships.astro'), 'utf8');
  assert.ok(content.includes('pipeline-panel'), 'Must have pipeline panel');
  assert.ok(content.includes('view-toggle'), 'Must have view toggle');
});

test('/admin/partnerships has expanded status options', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/admin/partnerships.astro'), 'utf8');
  assert.ok(content.includes('contact'), 'Must have contact option');
  assert.ok(content.includes('negotiation'), 'Must have negotiation option');
  assert.ok(content.includes('churned'), 'Must have churned option');
});
