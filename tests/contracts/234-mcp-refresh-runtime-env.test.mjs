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

test('#234 / #1053: token endpoint is the sole server-side refresher and uses the runtime resolver', () => {
  // #1053 removed the proxy-side refreshers (dual-refresher collision → ~1h re-login),
  // so /oauth/token is the ONLY server-side refresh path. It must still read Worker
  // runtime env; the proxies must no longer resolve auth config at all.
  const tokenSrc = read('src/pages/oauth/token.ts');
  assert.match(tokenSrc, /resolveSupabaseAuthConfig\(env as any, import\.meta\.env\)/, 'token.ts must read Worker runtime env');
  assert.doesNotMatch(tokenSrc, /anonKey:\s*import\.meta\.env\.PUBLIC_SUPABASE_ANON_KEY\s*\|\|\s*''/, 'token.ts must not pass empty anonKey');

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
