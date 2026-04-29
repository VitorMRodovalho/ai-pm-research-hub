/**
 * PMI VEP API client wrapper.
 *
 * AUTH (Plano B-revised per HAR analysis 2026-04-28):
 *
 * PMI vep_ui app NÃO emite refresh_token (scope `openid profile` only — sem
 * `offline_access`). Token tem TTL de 24h. Worker opera em "access-only mode":
 *
 *   1. PM faz login interativo no PMI VEP, exporta HAR ou copia access_token
 *      do devtools Network response de /connect/token
 *   2. Seed KV: `wrangler kv key put --binding=PMI_OAUTH_KV pmi_oauth:tokens '<json>'`
 *      onde <json> = {"access_token":"<jwt>","expires_at":<ms_epoch>,"refreshed_at":<ms_epoch>,"initialized_by":"<audit>"}
 *   3. Worker lê do KV em cada execução. Verifica expiry.
 *   4. Se token expirou OU expira em < 1h: throw error claro para o run falhar
 *      (vai aparecer em cron_run_log + dispara alert se 3 consecutive failures)
 *   5. Se token expira em < 6h: log WARNING (PM proactive notification via
 *      cron_run_log.metrics.token_expiring_soon = true)
 *
 * SE no futuro PMI conceder offline_access (PM pediu pro PMI IT), código já
 * suporta refresh_token opcional via fallback. Worker tenta refresh apenas
 * se PmiOAuthTokens.refresh_token estiver presente. Caso contrário, mantém
 * access-only mode.
 *
 * IMPORTANT: Cron diário 1x/day. Se PM não re-seedar em 24h, run falha
 * (log_cron_run_complete status=failed). Após 3 falhas consecutivas, alerta
 * GP via campaign_send_one_off slug=cron_failure_alert.
 */

import type { Env, VepApplicationListItem, VepApplicationDetail, PmiOAuthTokens } from './types';

const BUCKETS = {
  submitted: 'submitted',
  qualified: 'qualified',
  rejected: 'rejected'
} as const;

export type Bucket = typeof BUCKETS[keyof typeof BUCKETS];

const KV_KEY = 'pmi_oauth:tokens';
const EXPIRY_BUFFER_MS = 60 * 60 * 1000;          // 1h: throw if expires in less than this
const PROACTIVE_WARN_MS = 6 * 60 * 60 * 1000;     // 6h: log warn (alert PM to re-seed soon)

/**
 * In-memory cache para reduzir KV reads dentro do mesmo isolate.
 */
let _isolateCache: PmiOAuthTokens | null = null;

async function readTokensFromKV(env: Env): Promise<PmiOAuthTokens | null> {
  if (_isolateCache && _isolateCache.expires_at > Date.now() + EXPIRY_BUFFER_MS) {
    return _isolateCache;
  }
  const stored = await env.PMI_OAUTH_KV.get(KV_KEY, 'json') as PmiOAuthTokens | null;
  if (stored) _isolateCache = stored;
  return stored;
}

async function writeTokensToKV(env: Env, tokens: PmiOAuthTokens): Promise<void> {
  await env.PMI_OAUTH_KV.put(KV_KEY, JSON.stringify(tokens));
  _isolateCache = tokens;
}

/**
 * Tenta refresh via grant_type=refresh_token. SÓ chama se tokens.refresh_token
 * estiver presente (PMI atual não emite — fallback para futuro).
 */
async function refreshAccessToken(env: Env, current: PmiOAuthTokens): Promise<PmiOAuthTokens> {
  if (!current.refresh_token) {
    throw new Error('No refresh_token available — PMI vep_ui app does not issue refresh_tokens (no offline_access scope). PM must re-seed manually.');
  }

  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: current.refresh_token,
    client_id: env.PMI_VEP_OAUTH_CLIENT_ID,
    ...(env.PMI_VEP_OAUTH_CLIENT_SECRET ? { client_secret: env.PMI_VEP_OAUTH_CLIENT_SECRET } : {})
  });

  const resp = await fetch(env.PMI_VEP_OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`PMI OAuth refresh failed: ${resp.status} ${text}`);
  }

  const json = await resp.json() as {
    access_token: string;
    refresh_token?: string;
    expires_in: number;
  };

  const updated: PmiOAuthTokens = {
    access_token: json.access_token,
    refresh_token: json.refresh_token ?? current.refresh_token,
    expires_at: Date.now() + (json.expires_in * 1000),
    refreshed_at: Date.now(),
    initialized_by: current.initialized_by
  };

  await writeTokensToKV(env, updated);
  return updated;
}

/**
 * Get a valid access_token. Throws clear error if KV uninitialized OR
 * token expired and no refresh path available.
 *
 * Side effect: stamps run-time hint for caller (via _isolateCache.expires_at)
 * so caller can check expiry status for proactive warning logging.
 */
async function getAccessToken(env: Env): Promise<string> {
  const tokens = await readTokensFromKV(env);

  if (!tokens) {
    throw new Error(
      'PMI OAuth not initialized — KV key "pmi_oauth:tokens" empty. ' +
      'PM must seed via wrangler kv key put. See README "PMI OAuth KV Setup" section.'
    );
  }

  const now = Date.now();
  const remainingMs = tokens.expires_at - now;

  // Token still valid with safety buffer
  if (remainingMs > EXPIRY_BUFFER_MS) {
    return tokens.access_token;
  }

  // Try refresh (only if refresh_token available — PMI doesn't issue them currently)
  if (tokens.refresh_token) {
    const refreshed = await refreshAccessToken(env, tokens);
    return refreshed.access_token;
  }

  // No refresh path — fail clean with operational guidance
  throw new Error(
    `PMI access_token expires in ${(remainingMs / 60000).toFixed(0)}min (or already expired). ` +
    `No refresh_token in KV (PMI vep_ui app sem offline_access). ` +
    `PM precisa re-seedar via wrangler kv key put. ` +
    `Original seed by: ${tokens.initialized_by ?? 'unknown'}. ` +
    `expires_at: ${new Date(tokens.expires_at).toISOString()}.`
  );
}

/**
 * Returns expiry status hint — to be called by main run loop AFTER first
 * vepFetch (when _isolateCache is populated). Lets index.ts log a proactive
 * warning to cron_run_log.metrics if token expiring soon.
 */
export function getTokenExpiryStatus(): {
  has_token: boolean;
  expires_at_ms?: number;
  remaining_hours?: number;
  expiring_soon?: boolean;
} {
  if (!_isolateCache) return { has_token: false };
  const remainingMs = _isolateCache.expires_at - Date.now();
  return {
    has_token: true,
    expires_at_ms: _isolateCache.expires_at,
    remaining_hours: remainingMs / 3600000,
    expiring_soon: remainingMs < PROACTIVE_WARN_MS
  };
}

async function vepFetch(path: string, env: Env, init?: RequestInit): Promise<Response> {
  const token = await getAccessToken(env);
  const url = path.startsWith('http') ? path : `${env.PMI_VEP_BASE_URL}${path}`;
  return fetch(url, {
    ...init,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...(init?.headers ?? {})
    }
  });
}

export async function listApplications(
  env: Env,
  opportunityId: string,
  bucket: Bucket
): Promise<VepApplicationListItem[]> {
  const path = bucket === 'submitted'
    ? `/api/opportunity/${opportunityId}/applications/status/submitted`
    : bucket === 'qualified'
    ? `/api/opportunity/${opportunityId}/qualifiedapplications`
    : `/api/opportunity/${opportunityId}/RejectedApplications`;

  const resp = await vepFetch(path, env);
  if (!resp.ok) throw new Error(`listApplications ${bucket}: ${resp.status}`);

  const json = await resp.json() as { applications?: VepApplicationListItem[] } | VepApplicationListItem[];
  return Array.isArray(json) ? json : (json.applications ?? []);
}

export async function getApplicationDetail(
  env: Env,
  applicationId: string | number
): Promise<VepApplicationDetail> {
  const resp = await vepFetch(`/api/applications/${applicationId}`, env);
  if (!resp.ok) throw new Error(`getApplicationDetail ${applicationId}: ${resp.status}`);
  return await resp.json() as VepApplicationDetail;
}

export async function listAllApplicationsForOpp(
  env: Env,
  opportunityId: string
): Promise<VepApplicationListItem[]> {
  const [submitted, qualified, rejected] = await Promise.all([
    listApplications(env, opportunityId, BUCKETS.submitted).catch(e => {
      console.error(`bucket submitted failed for opp ${opportunityId}:`, e.message);
      return [];
    }),
    listApplications(env, opportunityId, BUCKETS.qualified).catch(e => {
      console.error(`bucket qualified failed for opp ${opportunityId}:`, e.message);
      return [];
    }),
    listApplications(env, opportunityId, BUCKETS.rejected).catch(e => {
      console.error(`bucket rejected failed for opp ${opportunityId}:`, e.message);
      return [];
    })
  ]);

  const seen = new Set<string>();
  const all: VepApplicationListItem[] = [];
  for (const app of [...submitted, ...qualified, ...rejected]) {
    const id = String(app.applicationId);
    if (seen.has(id)) continue;
    seen.add(id);
    all.push(app);
  }
  return all;
}
