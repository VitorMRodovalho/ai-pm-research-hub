/**
 * #234 — MCP connector refresh must use Worker runtime env.
 *
 * Regression: Claude.ai connector still dropped around the 1h access-token TTL.
 * The proxy/token refresh path was wired to build-time `import.meta.env` values;
 * if Cloudflare did not inject those into SSR, auto-refresh became a silent no-op.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { resolveSupabaseAuthConfig } from '../../src/lib/mcp-refresh.ts';

const ROOT = process.cwd();
const read = (rel) => readFileSync(resolve(ROOT, rel), 'utf8');

test('#234: Supabase auth config prefers Cloudflare runtime env over build env', () => {
  const cfg = resolveSupabaseAuthConfig(
    { SUPABASE_URL: 'https://runtime.supabase.co', SUPABASE_ANON_KEY: 'runtime-anon' },
    { PUBLIC_SUPABASE_URL: 'https://build.supabase.co', PUBLIC_SUPABASE_ANON_KEY: 'build-anon' },
  );

  assert.equal(cfg.url, 'https://runtime.supabase.co');
  assert.equal(cfg.anonKey, 'runtime-anon');
});

test('#234: Supabase auth config falls back to PUBLIC runtime env before build env', () => {
  const cfg = resolveSupabaseAuthConfig(
    { PUBLIC_SUPABASE_URL: 'https://runtime-public.supabase.co', PUBLIC_SUPABASE_ANON_KEY: 'runtime-public-anon' },
    { PUBLIC_SUPABASE_URL: 'https://build.supabase.co', PUBLIC_SUPABASE_ANON_KEY: 'build-anon' },
  );

  assert.equal(cfg.url, 'https://runtime-public.supabase.co');
  assert.equal(cfg.anonKey, 'runtime-public-anon');
});

test('#234: fallback config supplies URL but requires anon key binding', () => {
  const cfg = resolveSupabaseAuthConfig(null, null);

  assert.match(cfg.url, /^https:\/\/ldrfrvwhxsmgaabwmaik\.supabase\.co$/);
  assert.equal(cfg.anonKey, '');
});

test('#234 / #1053 / #1210: discovery + authorize passthrough use the runtime resolver; no server-side refresher remains', () => {
  // #1053 removed the proxy-side refreshers (dual-refresher collision → ~1h re-login).
  // #1210 retired the Worker token endpoint entirely (token issuance = Supabase
  // native OAuth server). The runtime-env resolver invariant now lives in the
  // routes that must know the Supabase URL: the AS metadata + the authorize
  // compat passthrough.
  for (const rel of ['src/pages/.well-known/oauth-authorization-server.ts', 'src/pages/oauth/authorize.ts']) {
    const src = read(rel);
    assert.match(src, /resolveSupabaseAuthConfig\(env as any, import\.meta\.env\)/, `${rel} must read Worker runtime env`);
  }

  const tokenSrc = read('src/pages/oauth/token.ts');
  assert.doesNotMatch(tokenSrc, /resolveSupabaseAuthConfig/, 'token.ts stub must not resolve auth config (#1210 — no server-side token work)');

  for (const rel of ['src/pages/mcp.ts', 'src/pages/mcp/semantic.ts']) {
    const src = read(rel);
    assert.doesNotMatch(src, /resolveSupabaseAuthConfig/, `${rel} must not resolve auth config — single-refresher model (#1053)`);
  }
});

test('#234: wrangler publishes Supabase public URL without full anon JWT literals', () => {
  const wrangler = read('wrangler.toml');

  assert.match(wrangler, /\[vars\][\s\S]*SUPABASE_URL\s*=\s*"https:\/\/ldrfrvwhxsmgaabwmaik\.supabase\.co"/);
  assert.match(wrangler, /\[vars\][\s\S]*PUBLIC_SUPABASE_URL\s*=\s*"https:\/\/ldrfrvwhxsmgaabwmaik\.supabase\.co"/);
  assert.doesNotMatch(wrangler, /SUPABASE_ANON_KEY\s*=\s*"eyJ/);
  assert.doesNotMatch(wrangler, /PUBLIC_SUPABASE_ANON_KEY\s*=\s*"eyJ/);
});
