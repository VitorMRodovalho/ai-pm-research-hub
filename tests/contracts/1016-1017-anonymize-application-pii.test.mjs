/**
 * #1016 + #1017 — the two remaining anonymizers must erase selection-application child PII
 * via the shared _erase_application_pii helper (#946), not a light scrub / no scrub.
 *
 * Also guards the latent constraint bug surfaced during QA: all three anonymizers set
 * members.member_status='archived', which members_member_status_check must allow.
 *
 * Static (parse the migration) — the destructive runtime path was verified live with a
 * rolled-back impersonated QA (before=5 -> after=0 video screenings).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

function migrationsDefining(token) {
  const dir = 'supabase/migrations';
  return readdirSync(join(REPO_ROOT, dir))
    .filter((f) => f.endsWith('.sql'))
    .map((f) => read(join(dir, f)))
    .filter((s) => s.includes(token));
}

// Slice a single function body out of a migration source (last definition wins).
function funcBody(src, fnName) {
  const start = src.lastIndexOf(`FUNCTION public.${fnName}(`);
  if (start === -1) return null;
  const end = src.indexOf('$function$;', start);
  return end === -1 ? src.slice(start) : src.slice(start, end);
}

test('admin_anonymize_member (#1017) routes applications through _erase_application_pii', () => {
  const src = migrationsDefining('FUNCTION public.admin_anonymize_member').pop();
  assert.ok(src, 'a migration must redefine admin_anonymize_member');
  const body = funcBody(src, 'admin_anonymize_member');
  assert.match(body, /_erase_application_pii\(/, 'must call the shared helper');
  assert.match(body, /selection_applications\s+WHERE\s+email\s*=/i, 'must resolve app ids by email');
});

test('anonymize_by_engagement_kind (#1016) routes applications through _erase_application_pii', () => {
  const src = migrationsDefining('FUNCTION public.anonymize_by_engagement_kind').pop();
  assert.ok(src, 'a migration must redefine anonymize_by_engagement_kind');
  const body = funcBody(src, 'anonymize_by_engagement_kind');
  assert.match(body, /_erase_application_pii\(/, 'must call the shared helper');
  // person-anchored: resolves via person email (+ optional member email)
  assert.match(body, /person_email/, 'must snapshot the person email for app resolution');
  assert.match(body, /email\s*=\s*ANY\(v_emails\)/i, 'must resolve app ids by the collected emails');
});

test('members_member_status_check allows the anonymizer status "archived"', () => {
  const src = migrationsDefining("members_member_status_check").pop();
  assert.ok(src, 'a migration must (re)define members_member_status_check');
  const addBlock = src.slice(src.lastIndexOf('ADD CONSTRAINT members_member_status_check'));
  assert.match(addBlock, /'archived'/, "the constraint must include 'archived' (anonymizers set it)");
});
