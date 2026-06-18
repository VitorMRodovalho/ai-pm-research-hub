/**
 * Contract: #106 PR2 — chapter outreach script (Bloco 4), trilingual + GP-editable.
 *
 * Per SPEC_106_CHAPTER_DASHBOARD.md: a GLOBAL key 'chapter_outreach_script' in platform_settings
 * (JSONB pt-BR/en-US/es-LATAM). GP edits via the EXISTING admin_update_setting RPC on /admin/settings;
 * chapter directors COPY it (read-only) on /admin/chapter. platform_settings is deny-all RLS +
 * get_platform_setting is service-role-only, so a NARROW SECDEF reader exposes ONLY this key to
 * authenticated members (without broadening get_platform_setting).
 *
 * Offline source assertions; no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG = read('supabase/migrations/20260805000214_106_pr2_chapter_outreach_script.sql');
const FE = read('src/components/chapter/ChapterDashboard.tsx');
const SETTINGS = read('src/pages/admin/settings.astro');
const PT = read('src/i18n/pt-BR.ts');
const EN = read('src/i18n/en-US.ts');
const ES = read('src/i18n/es-LATAM.ts');

// ── Migration: seed + narrow reader ─────────────────────────────────────────────
test('migration 20260805000214 exists', () => {
  assert.ok(MIG, 'PR2 migration file exists');
});

test('migration seeds chapter_outreach_script idempotently (ON CONFLICT DO NOTHING)', () => {
  assert.match(MIG, /INSERT INTO public\.platform_settings/);
  assert.match(MIG, /'chapter_outreach_script'/);
  assert.match(MIG, /ON CONFLICT \(key\) DO NOTHING/);
  // trilingual seed
  assert.match(MIG, /'pt-BR'/);
  assert.match(MIG, /'en-US'/);
  assert.match(MIG, /'es-LATAM'/);
});

test('migration creates a NARROW SECDEF reader granted to authenticated', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_chapter_outreach_script\(\)/);
  assert.match(MIG, /SECURITY DEFINER/);
  assert.match(MIG, /SET search_path TO ''/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_chapter_outreach_script\(\) TO authenticated/);
  // only reads the one key — never selects arbitrary settings
  assert.match(MIG, /key = 'chapter_outreach_script'/);
});

test('migration does NOT create a new writer (reuses admin_update_setting)', () => {
  assert.ok(!/CREATE OR REPLACE FUNCTION public\.set_platform_setting/.test(MIG), 'no set_platform_setting');
  assert.ok(!/CREATE OR REPLACE FUNCTION public\.admin_update_setting/.test(MIG), 'does not redefine admin_update_setting');
});

// ── Dashboard: read-only copy surface (persona) ─────────────────────────────────
test('dashboard reads the script (read-only) and never writes it', () => {
  assert.match(FE, /rpc\(['"]get_chapter_outreach_script['"]\)/);
  assert.ok(!/admin_update_setting/.test(FE), 'dashboard never edits the script');
  // copy-to-clipboard + a11y announce
  assert.match(FE, /navigator\.clipboard/);
  assert.match(FE, /aria-live=["']polite["']/);
  assert.match(FE, /scriptTab/);
});

// ── Settings: GP editor writes via admin_update_setting ──────────────────────────
test('settings editor loads via reader and saves via admin_update_setting', () => {
  assert.match(SETTINGS, /loadOutreachScript/);
  assert.match(SETTINGS, /rpc\(['"]get_chapter_outreach_script['"]\)/);
  assert.match(SETTINGS, /p_key: 'chapter_outreach_script'/);
  assert.match(SETTINGS, /rpc\(['"]admin_update_setting['"]/);
  // three language textareas
  assert.match(SETTINGS, /data-outreach-lang/);
});

// ── i18n parity (3 dicts) ───────────────────────────────────────────────────────
test('outreach i18n keys exist in all three dictionaries', () => {
  for (const [name, dict] of [['pt', PT], ['en', EN], ['es', ES]]) {
    assert.match(dict, /'admin\.settings\.outreachTitle'/, `${name} has outreachTitle`);
    assert.match(dict, /'admin\.settings\.outreachHint'/, `${name} has outreachHint`);
  }
});
