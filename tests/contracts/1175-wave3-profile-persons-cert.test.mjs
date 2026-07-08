/**
 * Contract: #1175 Wave 3 (F3 + F4 + F5 + import counter label).
 *
 *  F3 — profile.astro: share_whatsapp binds ONLY to #self-share-whatsapp (the ghost
 *       #self-share-wa binding always read false and clobbered the saved true value);
 *       the CEP field declares it is NOT stored (ViaCEP autofill only, LGPD minimização).
 *  F4 — update_my_profile dual-writes the shared PII fields to persons (ADR-0006);
 *       one-time NULL-fill backfill audited (48 persons, 2026-07-08).
 *  F5 — sign_volunteer_agreement derives function_role + period from the ACTIVE
 *       volunteer engagement (authoritative), never primarily from the operational_role
 *       cache (structurally 'guest' for first-time signers) or the opportunity window.
 *  Label — admin/selection import summary shows the real worker counter
 *       chapter_affiliations_upserted (pmi_chapter_memberships_upserted died in #441).
 *
 * Static source/migration-body guards (offline). Live behavior was verified at apply
 * time via impersonated rolled-back probes (see #1175 session evidence 2026-07-08).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const PROFILE = readFileSync('src/pages/profile.astro', 'utf8');
const SELECTION = readFileSync('src/pages/admin/selection.astro', 'utf8');

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

test('#1175 F3: share_whatsapp has exactly ONE diff-builder binding (#self-share-whatsapp)', () => {
  assert.ok(!PROFILE.includes('self-share-wa\''), 'the ghost #self-share-wa binding must be gone');
  assert.ok(!/getElementById\('self-share-wa'\)/.test(PROFILE), 'no lookup of the nonexistent element');
  const bindings = PROFILE.match(/fields\.share_whatsapp\s*=/g) ?? [];
  assert.equal(bindings.length, 1, `share_whatsapp must be assigned exactly once (got ${bindings.length})`);
  assert.match(PROFILE, /getElementById\('self-share-whatsapp'\)/);
});

test('#1175 F3: the CEP field declares it is not stored', () => {
  assert.match(PROFILE, /o CEP não é armazenado/);
});

test('#1175 F4: update_my_profile dual-writes the shared PII fields to persons', () => {
  const body = latestFunctionBody('update_my_profile');
  assert.ok(body, 'update_my_profile must be captured in a migration');
  assert.match(body, /IF v_caller\.person_id IS NOT NULL THEN/);
  assert.match(body, /UPDATE persons SET/);
  for (const f of ['phone', 'address', 'city', 'state', 'country', 'birth_date', 'share_whatsapp']) {
    assert.ok(
      new RegExp(`UPDATE persons SET[\\s\\S]*?${f} = CASE WHEN p_fields \\? '${f}'`).test(body),
      `persons dual-write must cover ${f}`,
    );
  }
});

test('#1175 F5: certificate role comes from the active engagement, cache is fallback only', () => {
  const body = latestFunctionBody('sign_volunteer_agreement');
  assert.ok(body, 'sign_volunteer_agreement must be captured in a migration');
  // engagement lookup feeds the role...
  assert.match(body, /e\.kind = 'volunteer' AND e\.status = 'active'/);
  assert.match(body, /v_function_role := v_eng\.role/);
  assert.match(body, /v_function_role_source := 'engagement'/);
  // ...and the INSERT/snapshot stamp the derived role, not the raw cache
  assert.ok(
    !/'member_role', v_member\.operational_role/.test(body),
    'content_snapshot.member_role must not stamp the operational_role cache directly',
  );
  assert.match(body, /'member_role', v_function_role/);
  assert.match(body, /'member_role_source', v_function_role_source/);
});

test('#1175 F5: certificate period prefers the engagement vigency over the opportunity window', () => {
  const body = latestFunctionBody('sign_volunteer_agreement');
  assert.ok(body);
  assert.match(body, /IF v_eng\.start_date IS NOT NULL AND v_eng\.end_date IS NOT NULL THEN/);
  assert.match(body, /v_source := 'engagement_vigency'/);
  // the previous fallback chain survives untouched
  for (const src of ["'application_match'", "'application_year_match'", "'founder_role_vep'"]) {
    assert.ok(body.includes(`v_source := ${src}`), `period fallback ${src} must be preserved`);
  }
});

test('#1175: import summary shows the real worker counter (chapter_affiliations_upserted)', () => {
  assert.ok(
    !SELECTION.includes('pmi_chapter_memberships_upserted'),
    'the legacy counter (never emitted by the worker since #441) must be gone',
  );
  assert.match(SELECTION, /chapter_affiliations_upserted/);
});
