import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * Returns true iff `token` is a cryptographically valid `service_role` credential.
 *
 * Why this exists (#738): the previous EF auth fallback decoded the JWT with
 * `atob` and trusted `payload.role === "service_role"` WITHOUT verifying the
 * signature, so a forged token would pass. We cannot simply compare against the
 * injected `SUPABASE_SERVICE_ROLE_KEY` env var either: every `pg_net` dispatcher
 * sends the vault-stored `service_role_key`, which is a DIFFERENT (but equally
 * valid, same-secret-signed) JWT than the env var Supabase injects into the
 * function runtime. A literal-only compare therefore rejects legitimate callers.
 *
 * Resolution:
 *   1. Fast path — exact match against the injected env key (covers EF→EF calls).
 *   2. Otherwise delegate signature verification to PostgREST: call
 *      `current_caller_role()` using the presented token. PostgREST validates the
 *      JWT signature (forged/invalid tokens get 401 before the function runs) and
 *      `auth.role()` returns `service_role` only for a genuine service credential.
 *
 * No secret is duplicated or returned over the wire; the probe reports only the
 * caller's own role claim.
 */
/**
 * Extracts the bearer token from an incoming request's `Authorization` header.
 *
 * Canonical home (#1513): this is caller-auth, not Drive. It was first written
 * in `drive-sa.ts` because the Drive EFs needed it first; `drive-sa.ts` now
 * re-exports this same function, so its existing importers are unaffected and
 * a non-Drive EF can gate itself without pulling the Drive module in.
 */
export function bearerFrom(req: Request): string | null {
  const h = req.headers.get("Authorization") ?? req.headers.get("authorization") ?? "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}

export async function isServiceRoleToken(
  supabaseUrl: string,
  token: string | null | undefined,
): Promise<boolean> {
  if (!token) return false;

  const injected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (injected && token === injected) return true;

  try {
    const probe = createClient<any, "public", any>(supabaseUrl, token, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await probe.rpc("current_caller_role");
    if (error) return false;
    return data === "service_role";
  } catch {
    return false;
  }
}
