/**
 * W130 Contract Tests: Contextual Onboarding + Help Rewrite
 * Static analysis — validates migration, help page, lead capture, i18n.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

function readFile(relPath) {
  return readFileSync(resolve(ROOT, relPath), 'utf8');
}

function findFunctionBody(sql, funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'i'
  );
  const match = sql.match(regex);
  return match ? match[2] : '';
}

// ═══════════════════════════════════════════════════
// Migration
// ═══════════════════════════════════════════════════

test('W130 migration exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'supabase/migrations/20260319100033_w130_contextual_onboarding.sql')),
    'W130 migration must exist'
  );
});

test('W130 creates help_journeys table', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS public.help_journeys'), 'Must create help_journeys');
  assert.ok(sql.includes('persona_key text NOT NULL UNIQUE'), 'Must have persona_key UNIQUE');
  assert.ok(sql.includes('title jsonb'), 'Must have title jsonb');
  assert.ok(sql.includes('steps jsonb'), 'Must have steps jsonb');
});

test('W130 seeds 7 persona journeys', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  const personas = ['researcher', 'tribe_leader', 'curator', 'communicator', 'sponsor', 'liaison', 'gp'];
  for (const p of personas) {
    assert.ok(sql.includes(`'${p}'`), `Must seed persona: ${p}`);
  }
});

test('each journey has at least 3 steps with i18n', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  // Check that each persona insert has steps with pt, en, es keys
  const personas = ['researcher', 'tribe_leader', 'curator', 'communicator', 'sponsor', 'liaison', 'gp'];
  for (const p of personas) {
    // Find the persona insert block
    const pIdx = sql.indexOf(`'${p}'`);
    assert.ok(pIdx > 0, `Must find persona ${p} in migration`);
    // Check that there are "key" entries (steps) after it
    const afterP = sql.substring(pIdx, pIdx + 5000);
    const keyMatches = afterP.match(/"key":/g);
    assert.ok(keyMatches && keyMatches.length >= 3, `Persona ${p} must have at least 3 steps, found ${keyMatches?.length || 0}`);
  }
});

test('all step titles have pt, en, es translations', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  // Check for presence of all 3 language keys in title objects
  const titleMatches = sql.match(/"title":\{"pt":"[^"]+","en":"[^"]+","es":"[^"]+"\}/g);
  assert.ok(titleMatches && titleMatches.length >= 20, `Must have at least 20 i18n title objects, found ${titleMatches?.length || 0}`);
});

test('all step action_urls are valid routes', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  const urlMatches = sql.match(/"action_url":"([^"]+)"/g);
  assert.ok(urlMatches, 'Must have action_url entries');
  const validPrefixes = ['/', '/admin', '/profile', '/workspace', '/attendance', '/gamification', '/publications', '/help'];
  for (const m of urlMatches) {
    const url = m.match(/"action_url":"([^"]+)"/)[1];
    const isValid = validPrefixes.some(p => url.startsWith(p));
    assert.ok(isValid, `action_url ${url} must start with a valid route prefix`);
  }
});

// ═══════════════════════════════════════════════════
// Visitor Leads
// ═══════════════════════════════════════════════════

test('W130 creates visitor_leads table', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS public.visitor_leads'), 'Must create visitor_leads');
  assert.ok(sql.includes('lgpd_consent boolean NOT NULL'), 'Must have lgpd_consent');
  assert.ok(sql.includes("status text DEFAULT 'new'"), 'Must have status with default new');
});

test('visitor_leads has public insert + admin read RLS', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  assert.ok(sql.includes('Anyone can submit lead'), 'Must have public insert policy');
  assert.ok(sql.includes('Admin reads leads'), 'Must have admin read policy');
});

test('data_retention_policy has 90-day entry for visitor_leads', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  assert.ok(sql.includes("'visitor_leads', 90, 'delete'"), 'Must add 90-day delete retention for visitor_leads');
});

// ═══════════════════════════════════════════════════
// WhatsApp Fix
// ═══════════════════════════════════════════════════

test('get_gp_whatsapp RPC exists in migration', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  const body = findFunctionBody(sql, 'get_gp_whatsapp');
  assert.ok(body, 'get_gp_whatsapp must exist');
  assert.ok(body.includes("operational_role = 'manager'"), 'Must derive phone from members WHERE operational_role = manager');
  assert.ok(body.includes("site_config"), 'Must fallback to site_config');
});

test('help page uses dynamic WhatsApp (not hardcoded)', () => {
  const content = readFile('src/pages/help.astro');
  assert.ok(!content.includes('5562999999999'), 'Must NOT have hardcoded fake number');
  assert.ok(content.includes('get_gp_whatsapp'), 'Must call get_gp_whatsapp RPC');
  assert.ok(content.includes('wa.me'), 'Must generate wa.me link');
});

// ═══════════════════════════════════════════════════
// Help Page — Role-Aware
// ═══════════════════════════════════════════════════

test('help page loads journeys from DB', () => {
  const content = readFile('src/pages/help.astro');
  assert.ok(content.includes('get_help_journeys'), 'Must call get_help_journeys RPC');
});

test('help page has visitor banner', () => {
  const content = readFile('src/pages/help.astro');
  assert.ok(content.includes('help-visitor-banner'), 'Must have visitor banner element');
  assert.ok(content.includes('help.visitorWelcome'), 'Must use visitorWelcome i18n key');
});

test('help page resolves user personas for role-aware display', () => {
  const content = readFile('src/pages/help.astro');
  assert.ok(content.includes('resolvePersonas'), 'Must have resolvePersonas function');
  assert.ok(content.includes('ROLE_TO_PERSONA'), 'Must map roles to personas');
  assert.ok(content.includes('DESIGNATION_TO_PERSONA'), 'Must map designations to personas');
});

test('help page has onboarding modal', () => {
  const content = readFile('src/pages/help.astro');
  assert.ok(content.includes('onb-modal-backdrop'), 'Must have onboarding modal');
  assert.ok(content.includes('profile_completed_at'), 'Must check profile_completed_at');
  assert.ok(content.includes('onboarding_dismissed_at'), 'Must check onboarding_dismissed_at from DB');
});

// ═══════════════════════════════════════════════════
// Profile completed_at
// ═══════════════════════════════════════════════════

test('migration adds profile_completed_at to members', () => {
  const sql = readFile('supabase/migrations/20260319100033_w130_contextual_onboarding.sql');
  assert.ok(sql.includes('profile_completed_at'), 'Must add profile_completed_at column');
});

// ═══════════════════════════════════════════════════
// Lead Capture on /about
// ═══════════════════════════════════════════════════

test('ImpactPageIsland has lead capture form', () => {
  const content = readFile('src/components/islands/ImpactPageIsland.tsx');
  assert.ok(content.includes('LeadCaptureForm'), 'Must include LeadCaptureForm component');
  // ARM-1 (ADR-0072): migrated from direct visitor_leads.insert() to capture_visitor_lead RPC
  assert.ok(content.includes('capture_visitor_lead'), 'Must call capture_visitor_lead RPC');
  assert.ok(content.includes('lgpd_consent'), 'Must include lgpd_consent field');
  assert.ok(content.includes('utm_'), 'Must capture UTM params from URL');
});

test('lead form has LGPD consent checkbox', () => {
  const content = readFile('src/components/islands/ImpactPageIsland.tsx');
  assert.ok(content.includes('leadConsent'), 'Must have consent label');
  assert.ok(content.includes('/privacy'), 'Must link to privacy policy');
  assert.ok(content.includes('leadConsentRequired'), 'Must have consent required error');
});

test('lead form has chapter and role selection', () => {
  const content = readFile('src/components/islands/ImpactPageIsland.tsx');
  assert.ok(content.includes('chapter_interest'), 'Must have chapter_interest field');
  assert.ok(content.includes('role_interest'), 'Must have role_interest field');
  // p83 — chapter list now loaded dynamically from chapter_registry via loadChapters() helper.
  // Previously asserted hardcoded 'PMI-GO'/'PMI-CE' strings; superseded by data-driven approach.
  assert.ok(content.includes('loadChapters'), 'Must load chapters dynamically from registry');
  assert.ok(content.includes('chapters.map'), 'Must render chapter options from loaded list');
});

// ═══════════════════════════════════════════════════
// i18n
// ═══════════════════════════════════════════════════

test('PT-BR has all W130 help keys', () => {
  const content = readFile('src/i18n/pt-BR.ts');
  const keys = ['help.meta', 'help.title', 'help.subtitle', 'help.visitorWelcome',
    'help.contactBtn', 'lead.title', 'lead.submit', 'lead.consent',
    'onb.modalWelcome', 'onb.modalCta', 'onb.modalDismiss'];
  for (const k of keys) {
    assert.ok(content.includes(`'${k}'`), `PT-BR must have key ${k}`);
  }
});

test('EN-US has all W130 help keys', () => {
  const content = readFile('src/i18n/en-US.ts');
  const keys = ['help.meta', 'help.title', 'lead.title', 'lead.submit', 'onb.modalWelcome'];
  for (const k of keys) {
    assert.ok(content.includes(`'${k}'`), `EN-US must have key ${k}`);
  }
});

test('ES-LATAM has all W130 help keys', () => {
  const content = readFile('src/i18n/es-LATAM.ts');
  const keys = ['help.meta', 'help.title', 'lead.title', 'lead.submit', 'onb.modalWelcome'];
  for (const k of keys) {
    assert.ok(content.includes(`'${k}'`), `ES-LATAM must have key ${k}`);
  }
});

test('i18n key count stays in sync (±5%)', () => {
  function countKeys(filePath) {
    const content = readFileSync(resolve(ROOT, filePath), 'utf8');
    const matches = content.match(/'[^']+'\\s*:/g);
    return matches ? matches.length : 0;
  }
  const ptCount = countKeys('src/i18n/pt-BR.ts');
  const enCount = countKeys('src/i18n/en-US.ts');
  const esCount = countKeys('src/i18n/es-LATAM.ts');
  const tolerance = Math.ceil(ptCount * 0.05);
  assert.ok(Math.abs(ptCount - enCount) <= tolerance, `EN (${enCount}) must be within ±5% of PT (${ptCount})`);
  assert.ok(Math.abs(ptCount - esCount) <= tolerance, `ES (${esCount}) must be within ±5% of PT (${ptCount})`);
});
