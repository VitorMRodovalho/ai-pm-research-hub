// #1050 — generic per-IP rate limit for anon-facing Cloudflare Worker routes
// (e.g. the OAuth /token endpoint). Mirrors the KV-bucket approach of
// mcp-rate-limit.ts, but keys by client IP (cf-connecting-ip) + action instead of
// member JWT sub — because these routes are hit before/without authentication.
//
// Fail-open on any missing signal or KV error: a throttle store hiccup must never
// block a legitimate caller. This is defense-in-depth (brute-force/flood dampening),
// not the primary authority gate (PKCE + Supabase validation stay in the route).

export interface KVNamespaceLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

export interface IpRateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfter?: number;
}

const KEY_TTL_SECONDS = 70; // slightly longer than the 60s window so keys self-expire

/** Extract the client IP from a Cloudflare-fronted request (cf-connecting-ip first). */
export function clientIpFrom(request: Request): string | null {
  const cf = request.headers.get('cf-connecting-ip');
  if (cf) return cf;
  const xff = request.headers.get('x-forwarded-for');
  if (xff) return xff.split(',')[0].trim();
  return null;
}

/**
 * Check + increment a per-minute counter keyed by (action, ip).
 * Returns allowed=false once the counter has reached limitPerMin for the current
 * minute bucket. Fail-open when kv/ip is missing or KV throws.
 */
export async function checkIpRateLimit(
  kv: KVNamespaceLike | null | undefined,
  ip: string | null,
  action: string,
  limitPerMin: number,
  nowMs: number = Date.now()
): Promise<IpRateLimitResult> {
  if (!kv || !ip) return { allowed: true, remaining: -1 };

  const bucket = Math.floor(nowMs / 60000);
  const key = `iprl:${action}:${ip}:${bucket}`;

  try {
    const count = parseInt((await kv.get(key)) || '0', 10);
    if (count >= limitPerMin) {
      return { allowed: false, remaining: 0, retryAfter: 60 };
    }
    await kv.put(key, String(count + 1), { expirationTtl: KEY_TTL_SECONDS });
    return { allowed: true, remaining: limitPerMin - count - 1 };
  } catch {
    // Fail-open: better a few extra requests than blocking the platform.
    return { allowed: true, remaining: -1 };
  }
}
