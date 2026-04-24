// ADR-0018 W2 — Rate limit for the /mcp Cloudflare Worker proxy.
//
// Two counters per member (JWT sub), keyed by 1-minute bucket:
//   rl:{sub}:1m:{bucket}        general       — 100 req/min
//   rl:{sub}:dest:1m:{bucket}   destructive   —  10 req/min
//
// When a counter exceeds its threshold, the request is denied with 429
// before reaching the Supabase Edge Function. Counters have TTL of 70s
// (slightly longer than the window) so they self-expire.
//
// KV read-increment-write is racy (two concurrent requests can miss a
// tick). Acceptable for rate limiting at this scale — slippage is at
// most a few extra requests per member per minute. If tighter bounds
// are ever needed, migrate to Durable Objects.
//
// Fail-open on KV errors: we never block a legitimate caller because
// the counter store hiccupped. Primary authority enforcement stays in
// the RPC layer (canV4 gate). This proxy rate limit is defense-in-depth
// against stolen-token abuse and cross-MCP injection bursts.

export const DESTRUCTIVE_TOOLS = new Set<string>([
  "drop_event_instance",
  "delete_card",
  "archive_card",
  "offboard_member",
  "manage_initiative_engagement",
]);

export const GENERAL_LIMIT_PER_MIN = 100;
export const DESTRUCTIVE_LIMIT_PER_MIN = 10;
const KEY_TTL_SECONDS = 70;

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfter?: number;
  reason?: string;
  /** 'general' | 'destructive' | undefined */
  limitKind?: "general" | "destructive";
}

export interface KVNamespaceLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

/** Extract the MCP tool name from a JSON-RPC request body, if present. */
export function extractToolName(body: string | null): string | null {
  if (!body) return null;
  try {
    const parsed = JSON.parse(body);
    if (parsed?.method === "tools/call" && typeof parsed?.params?.name === "string") {
      return parsed.params.name;
    }
    return null;
  } catch {
    return null;
  }
}

export function isDestructive(toolName: string | null): boolean {
  return !!toolName && DESTRUCTIVE_TOOLS.has(toolName);
}

/**
 * Check and increment per-minute rate counters for this caller.
 * Returns allowed=false when either counter has already reached its limit.
 * Fail-open if `kv` is missing or throws.
 */
export async function checkRateLimit(
  kv: KVNamespaceLike | null | undefined,
  sub: string,
  toolName: string | null,
  nowMs: number = Date.now()
): Promise<RateLimitResult> {
  if (!kv || !sub) return { allowed: true, remaining: -1 };

  const minuteBucket = Math.floor(nowMs / 60000);
  const generalKey = `rl:${sub}:1m:${minuteBucket}`;
  const destructive = isDestructive(toolName);
  const destKey = destructive ? `rl:${sub}:dest:1m:${minuteBucket}` : null;

  try {
    const generalCount = parseInt((await kv.get(generalKey)) || "0", 10);
    if (generalCount >= GENERAL_LIMIT_PER_MIN) {
      return {
        allowed: false,
        remaining: 0,
        retryAfter: 60,
        reason: `Rate limit: ${GENERAL_LIMIT_PER_MIN} requests/minute per member (current: ${generalCount})`,
        limitKind: "general",
      };
    }

    let destCount = 0;
    if (destKey) {
      destCount = parseInt((await kv.get(destKey)) || "0", 10);
      if (destCount >= DESTRUCTIVE_LIMIT_PER_MIN) {
        return {
          allowed: false,
          remaining: 0,
          retryAfter: 60,
          reason: `Destructive rate limit: ${DESTRUCTIVE_LIMIT_PER_MIN} destructive calls/minute per member (current: ${destCount}, tool: ${toolName})`,
          limitKind: "destructive",
        };
      }
    }

    // Increment both counters. Race-condition slippage is acceptable.
    await kv.put(generalKey, String(generalCount + 1), { expirationTtl: KEY_TTL_SECONDS });
    if (destKey) {
      await kv.put(destKey, String(destCount + 1), { expirationTtl: KEY_TTL_SECONDS });
    }

    return {
      allowed: true,
      remaining: GENERAL_LIMIT_PER_MIN - generalCount - 1,
    };
  } catch (e) {
    // Fail-open: better to let a few extra requests through than block the platform.
    return { allowed: true, remaining: -1, reason: "kv_error_fail_open" };
  }
}
