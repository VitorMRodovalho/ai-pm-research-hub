/**
 * Shared server-side OAuth refresh helpers for the MCP Worker proxies.
 *
 * Consumed by `src/pages/mcp.ts` and `src/pages/mcp/semantic.ts` (and the JWT
 * decode + TTL constant by `src/pages/oauth/token.ts`). Extracted in #580 so the
 * MEDIUM "always re-store the rotated refresh token" fix lives in ONE place and
 * BOTH proxy surfaces inherit it — previously `decodeJwtPayload` + `tryAutoRefresh`
 * + the 5-minute window were copy-pasted verbatim across the two files, and a fix
 * applied to one but not the other would silently diverge behaviour.
 *
 * The broader full-proxy extraction (header gate, rate limit, tools/list strip,
 * CORS, SSE pass-through) into `mcp-proxy.ts` remains the #280 follow-up; #580
 * scopes the shared module to the refresh concern only.
 *
 * Module is pure and dependency-injected (KV + fetch + anon key passed in,
 * mirroring `mcp-rate-limit.ts`) so it is unit-testable under `node --test`.
 */

/**
 * KV TTL (seconds) for the server-side refresh token entry `mcp_refresh:{sub}`.
 *
 * INVARIANT: this MUST stay ≤ the Supabase project's refresh-token lifetime
 * (Dashboard → Authentication → Sessions → refresh-token reuse interval /
 * inactivity timeout). Supabase rotates the refresh token on every successful
 * exchange and echoes a new one; `tryAutoRefresh` re-stores it with a fresh TTL,
 * so a session that refreshes at least once per window never lets KV outlive the
 * token. If the dashboard lifetime is ever lowered BELOW this value, KV can hold
 * a refresh token Supabase has already expired → the next auto-refresh 400s → the
 * entry is purged → the connector drops to a clean re-auth. Default 30 days
 * matches Supabase's default refresh-token inactivity timeout.
 */
export const MCP_REFRESH_TTL_SECONDS = 2592000; // 30 days

const DEFAULT_SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';

/** Minimal KV surface used by the refresh helpers (Cloudflare KVNamespace subset). */
export interface RefreshKV {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, opts?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

export interface AutoRefreshConfig {
  /** Supabase anon key (apikey header for the Auth token endpoint). */
  anonKey: string;
  /** Override the Supabase base URL (defaults to the project URL). */
  supabaseUrl?: string;
  /** Override the fetch implementation (for tests). Defaults to global fetch. */
  fetchImpl?: typeof fetch;
}

export interface SupabaseAuthConfig {
  url: string;
  anonKey: string;
}

export function resolveSupabaseAuthConfig(
  runtimeEnv?: Record<string, unknown> | null,
  buildEnv?: Record<string, unknown> | null,
): SupabaseAuthConfig {
  const pick = (...values: unknown[]) => {
    for (const value of values) {
      if (typeof value === 'string' && value.trim()) return value.trim();
    }
    return '';
  };

  return {
    url: pick(
      runtimeEnv?.SUPABASE_URL,
      runtimeEnv?.PUBLIC_SUPABASE_URL,
      buildEnv?.PUBLIC_SUPABASE_URL,
      DEFAULT_SUPABASE_URL,
    ),
    anonKey: pick(
      runtimeEnv?.SUPABASE_ANON_KEY,
      runtimeEnv?.PUBLIC_SUPABASE_ANON_KEY,
      buildEnv?.PUBLIC_SUPABASE_ANON_KEY,
    ),
  };
}

/**
 * Decode a JWT payload WITHOUT verifying the signature. Safe only for reading
 * `sub` / `exp` from our own Supabase-issued tokens — NEVER trust this for
 * authorization decisions. Returns null on any malformed input.
 */
export function decodeJwtPayload(token: string): { sub?: string; exp?: number } | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    return JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
  } catch {
    return null;
  }
}

/**
 * True if a token with the given `exp` (epoch seconds) is already expired or will
 * expire within `skewSeconds` (default 300 = 5 min) — the proactive-refresh
 * window. Equivalent to the prior inline `payload.exp - 300 < now` check.
 */
export function isExpiringSoon(exp: number, skewSeconds = 300, nowSeconds?: number): boolean {
  const now = nowSeconds ?? Math.floor(Date.now() / 1000);
  return exp - skewSeconds < now;
}

/**
 * Refresh an expired access token using the refresh_token stored in KV under
 * `mcp_refresh:{sub}`. Returns the new access_token, or null when there is no
 * stored token / the refresh failed.
 *
 * CONTRACT (#580): this function NEVER throws — every KV/network/parse failure
 * resolves to null so the caller (the Worker proxy) falls open to the original
 * token rather than crashing the request into a 500/502. A transient blip must
 * not be louder than a genuinely-expired token.
 *
 * On a successful rotation we ALWAYS re-store the refresh token with a fresh TTL
 * (#580 MEDIUM): use the newly-returned token when present, else re-persist the
 * one we just sent. A partial 200 carrying an access_token but no refresh_token
 * must NOT leave the rotated-invalidated token lingering in KV — that would 400
 * the NEXT auto-refresh, purge the entry, and drop the connector to re-auth
 * mid-session. Behavioural assumption (Supabase Auth): a 200 with an access_token
 * from /auth/v1/token?grant_type=refresh_token guarantees the submitted token was
 * ACCEPTED (the session is live) — Supabase returns non-2xx when a refresh token
 * is revoked/expired — so re-storing the old token here can never mask a
 * revocation. The two failure paths below (non-2xx, 200-without-access_token) are
 * the only ways a token gets purged.
 *
 * On rejection (revoked/expired refresh token → non-2xx, or a 200 with no
 * access_token) we DELETE the KV entry so the stale token is not retried; the
 * next /mcp call then 401s and forces a clean re-auth. We do NOT delete on a
 * transient exception (network/KV blip) — that would mass-purge live sessions.
 */
export async function tryAutoRefresh(
  sub: string,
  kv: RefreshKV,
  config: AutoRefreshConfig,
): Promise<string | null> {
  // #580 — without an anon key the Supabase call can only 401, which would
  // otherwise hit the non-2xx purge path and force a needless re-auth for EVERY
  // session on a misconfigured deploy. Skip entirely → fall open to the original token.
  if (!config.anonKey) return null;

  let refreshToken: string | null;
  try {
    refreshToken = await kv.get(`mcp_refresh:${sub}`);
  } catch {
    return null; // KV read blip — fail-open, do not purge
  }
  if (!refreshToken) return null;

  const supabaseUrl = config.supabaseUrl ?? DEFAULT_SUPABASE_URL;
  const doFetch = config.fetchImpl ?? fetch;

  let res: Awaited<ReturnType<typeof fetch>>;
  try {
    res = await doFetch(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'apikey': config.anonKey },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
  } catch {
    return null; // network blip — fail-open, do not purge (token may still be valid)
  }

  if (!res.ok) {
    // Refresh rejected (revoked/expired) — purge stale KV entry to prevent a retry loop.
    await kv.delete(`mcp_refresh:${sub}`).catch(() => {});
    return null;
  }

  let data: any;
  try {
    data = await res.json();
  } catch {
    return null; // malformed body — fail-open, do not purge
  }
  if (!data.access_token) {
    await kv.delete(`mcp_refresh:${sub}`).catch(() => {});
    return null;
  }

  // #580 MEDIUM — always re-store, falling back to the token we sent when Supabase
  // returns a partial 200 without a rotated refresh_token. Refreshes the 30-day TTL.
  // Best-effort: a KV write failure must NOT discard the fresh access_token we just
  // obtained (it only affects the NEXT refresh cycle).
  const newRefresh = data.refresh_token || refreshToken;
  await kv.put(`mcp_refresh:${sub}`, newRefresh, { expirationTtl: MCP_REFRESH_TTL_SECONDS }).catch(() => {});

  return data.access_token;
}
