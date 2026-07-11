/**
 * #1052 — public_members must not leak PII (signature_url) to anon.
 *
 * public_members is anon-readable. Its signature_url column carried a member-signatures
 * storage path that embeds the member's email in the filename, so anon could harvest emails
 * by listing the view. The column was removed; cert rendering resolves the issuer/counter-signer
 * signature via the gated RPC get_signer_signature_url (signer-scoped). This locks both sides.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

function migrationDefiningView() {
  const dir = 'supabase/migrations';
  return readdirSync(join(REPO_ROOT, dir))
    .filter((f) => f.endsWith('.sql'))
    .map((f) => read(join(dir, f)))
    .filter((s) => s.includes('CREATE VIEW public.public_members'))
    .pop();
}

test('migration recreates public_members without signature_url, SELECT-only to anon', () => {
  const src = migrationDefiningView();
  assert.ok(src, 'a migration must (re)create public_members');
  const viewBlock = src.slice(src.indexOf('CREATE VIEW public.public_members'), src.indexOf('FROM public.members'));
  assert.doesNotMatch(viewBlock, /signature_url/, 'public_members view must not select signature_url');
  assert.match(src, /GRANT SELECT ON public\.public_members TO anon/, 'anon must get SELECT only');
  assert.doesNotMatch(src, /GRANT (ALL|INSERT|UPDATE|DELETE)[^\n]*public_members[^\n]*anon/i,
    'anon must not get write grants on public_members');
});

test('migration adds the signer-scoped RPC get_signer_signature_url', () => {
  const dir = 'supabase/migrations';
  const src = readdirSync(join(REPO_ROOT, dir)).filter((f) => f.endsWith('.sql'))
    .map((f) => read(join(dir, f)))
    .filter((s) => s.includes('FUNCTION public.get_signer_signature_url')).pop();
  assert.ok(src, 'a migration must define get_signer_signature_url');
  assert.match(src, /c\.issued_by\s*=\s*m\.id\s+OR\s+c\.counter_signed_by\s*=\s*m\.id/,
    'RPC must scope to cert signers (issued_by / counter_signed_by)');
});

test('no source reads signature_url from public_members (rerouted to the RPC)', () => {
  const files = ['src/lib/certificates/pdf.ts', 'src/pages/gamification.astro'];
  for (const f of files) {
    const src = read(f);
    assert.doesNotMatch(src, /from\(['"]public_members['"]\)\s*\.\s*select\(\s*['"]signature_url/,
      `${f} must not select signature_url from public_members`);
    assert.match(src, /get_signer_signature_url/, `${f} must resolve signatures via the gated RPC`);
  }
});

test('DB: public_members.signature_url is gone (skipped without creds)', async (t) => {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return t.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
  const res = await fetch(`${url}/rest/v1/public_members?select=signature_url&limit=1`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  assert.equal(res.ok, false, 'selecting public_members.signature_url must fail (column removed)');
});

test('DB: get_signer_signature_url exists and returns null for a non-signer (skipped without creds)', async (t) => {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return t.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
  const res = await fetch(`${url}/rest/v1/rpc/get_signer_signature_url`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_signer_id: '00000000-0000-0000-0000-000000000000' }),
  });
  if (!res.ok) assert.fail(`RPC call failed: ${res.status} ${await res.text()}`);
  const v = await res.json();
  assert.equal(v, null, 'random id must resolve to null (no signature)');
});
