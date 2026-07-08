/**
 * Contract: #1175 D2 — partner_chapters covers the 15 BR registry chapters with an
 * EXPLICIT partnership_status ('signed' vs 'announced_at_risk') instead of the binary
 * list of 5, and the selection-tag semantics live in ONE helper.
 *
 *  - partner_chapters.partnership_status with CHECK domain; the 10 new rows enter as
 *    announced_at_risk (agreement pending legal review — PM decision 2026-07-08).
 *  - parse_vep_chapters() resolves via resolve_br_chapter_code() (chapter_registry SSOT,
 *    #1175 F2) — no hardcoded ILIKE state chain; STABLE (reads the registry).
 *  - apply_partner_chapter_tags(): no_partner_chapter = no partner AT ALL (not even
 *    announced); partner_chapter_at_risk = partner exists but none signed.
 *  - admin_update_application + finalize_decisions call the helper — the inline
 *    partner block must not survive in their latest captured bodies.
 *
 * Static migration-body guard (offline). Live application was verified at apply time
 * (2026-07-08): 15 active partners (5 signed / 10 at_risk), 2 SC codes normalized,
 * 7 snapshots recomputed, 1 app untagged + 1 tagged at_risk (admin_audit_log
 * 'selection.partner_chapters_d2_semantics').
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIG_PATH = 'supabase/migrations/20260805000365_1175_d2_partner_chapters_15_status.sql';
const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
const allSQL = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.endsWith('.sql')).sort()
  .map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');

function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi',
  );
  const m = [...allSQL.matchAll(regex)];
  return m.length ? m[m.length - 1][2] : null;
}

const MIG = readFileSync(MIG_PATH, 'utf8');

test('#1175 D2: partnership_status column with the signed/announced_at_risk domain', () => {
  assert.ok(existsSync(MIG_PATH));
  assert.match(MIG, /ADD COLUMN IF NOT EXISTS partnership_status text NOT NULL DEFAULT 'signed'/);
  assert.match(MIG, /CHECK \(partnership_status IN \('signed', 'announced_at_risk'\)\)/);
});

test('#1175 D2: the 10 missing registry chapters are seeded as announced_at_risk (not silently signed)', () => {
  // seed derives from chapter_registry (SSOT), never a literal chapter list
  assert.match(MIG, /INSERT INTO public\.partner_chapters[\s\S]*?FROM public\.chapter_registry cr/);
  assert.match(MIG, /'announced_at_risk'[\s\S]*?FROM public\.chapter_registry/);
  assert.match(MIG, /NOT EXISTS \(\s*SELECT 1 FROM public\.partner_chapters pc/);
});

test('#1175 D2: parse_vep_chapters resolves via the registry, not a hardcoded state chain', () => {
  const body = latestFunctionBody('parse_vep_chapters');
  assert.ok(body, 'parse_vep_chapters must be captured in a migration');
  assert.match(body, /resolve_br_chapter_code\(v_match\)/);
  assert.ok(!/ILIKE '%goiás%'/i.test(body), 'the hardcoded ILIKE state chain must be gone');
  // non-BR names keep the legacy visible fallback (cannot match partner codes)
  assert.match(body, /ELSE 'PMI-' \|\| regexp_replace/);
});

test('#1175 D2: apply_partner_chapter_tags encodes both tag semantics in one place', () => {
  const body = latestFunctionBody('apply_partner_chapter_tags');
  assert.ok(body, 'apply_partner_chapter_tags must be captured in a migration');
  // no partner at all -> no_partner_chapter
  assert.match(body, /is_partner_chapter = true[\s\S]*?no_partner_chapter/);
  // partner exists but none signed -> partner_chapter_at_risk
  assert.match(body, /partnership_status = 'signed'/);
  assert.match(body, /partner_chapter_at_risk/);
});

test('#1175 D2: admin_update_application delegates to the helper (no inline partner block)', () => {
  const body = latestFunctionBody('admin_update_application');
  assert.ok(body);
  assert.match(body, /PERFORM public\.apply_partner_chapter_tags\(p_application_id\)/);
  assert.ok(
    !/array_append\(tags, 'no_partner_chapter'\)/.test(body),
    'the inline no_partner_chapter block must be replaced by the helper call',
  );
});

test('#1175 D2: finalize_decisions delegates to the helper (no inline partner block)', () => {
  const body = latestFunctionBody('finalize_decisions');
  assert.ok(body);
  assert.match(body, /PERFORM public\.apply_partner_chapter_tags\(v_app_id\)/);
  assert.ok(
    !/array_append\(tags, 'no_partner_chapter'\)/.test(body),
    'the inline no_partner_chapter block must be replaced by the helper call',
  );
});

test('#1175 D2: retroactive corrections are audited and PostgREST reloaded', () => {
  assert.match(MIG, /selection\.partner_chapters_d2_semantics/);
  assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
});
