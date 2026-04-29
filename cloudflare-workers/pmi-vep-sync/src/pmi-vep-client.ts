/**
 * PMI VEP API client wrapper.
 *
 * AUTH (Plano B per p81 review): refresh_token-based via Cloudflare Workers KV.
 *
 * Flow:
 *   1. PM faz login interativo no PMI VEP UMA VEZ via browser, captura
 *      refresh_token + access_token do response do OAuth flow do PMI
 *   2. Seed o KV: `wrangler kv key put --binding=PMI_OAUTH_KV pmi_oauth:tokens '<json>'`
 *      onde <json> = {"access_token":"...","refresh_token":"...","expires_at":1234567890000,"refreshed_at":1234567890000}
 *   3. Worker: a cada execução, lê do KV. Se access_token válido → reusa.
 *      Senão → POST /token com grant_type=refresh_token, atualiza KV.
 *   4. Se PMI rotaciona refresh_token (resposta inclui novo), KV pega o novo.
 *      Se não rotaciona, mantém o atual (alguns providers só rotacionam após N usos).
 *
 * IMPORTANT: Cron diário 1x/day = race-free. Para multi-trigger no futuro,
 * adicionar KV mutex (e.g., compare-and-set via metadata.versionId).
 *
 * Se KV vazio (primeira deploy sem seed), worker FALHA com mensagem clara
 * apontando para o README. Não tenta client_credentials por segurança
 * (auditável: você sempre sabe quem inicializou os tokens).
 */

import type { Env, VepApplicationListItem, VepApplicationDetail, PmiOAuthTokens } from './types';

const BUCKETS = {
  submitted: 'submitted',
  qualified: 'qualified',
  rejected: 'rejected'
} as const;

export type Bucket = typeof BUCKETS[keyof typeof BUCKETS];

const KV_KEY = 'pmi_oauth:tokens';

/**
 * In-memory cache para reduzir KV reads dentro do mesmo isolate.
 * Cloudflare Workers reusam isolates em cold-warm. Cache válido até expires_at.
 */
let _isolateCache: PmiOAuthTokens | null = null;

async function readTokensFromKV(env: Env): Promise<PmiOAuthTokens | null> {
  if (_isolateCache && _isolateCache.expires_at > Date.now() + 30_000) {
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
 * Refresh access_token via OAuth refresh_token grant.
 * Updates KV with new tokens (handles rotation).
 */
async function refreshAccessToken(env: Env, current: PmiOAuthTokens): Promise<PmiOAuthTokens> {
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: current.refresh_token,
    client_id: env.PMI_VEP_OAUTH_CLIENT_ID,
    client_secret: env.PMI_VEP_OAUTH_CLIENT_SECRET
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
    token_type?: string;
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

async function getAccessToken(env: Env): Promise<string> {
  const tokens = await readTokensFromKV(env);

  if (!tokens) {
    throw new Error(
      'PMI OAuth not initialized — KV key "pmi_oauth:tokens" empty. ' +
      'PM precisa seed-ar via wrangler kv key put. Ver README seção "PMI OAuth KV Setup".'
    );
  }

  // Token still valid (with 30s buffer)
  if (tokens.expires_at > Date.now() + 30_000) {
    return tokens.access_token;
  }

  // Refresh
  const refreshed = await refreshAccessToken(env, tokens);
  return refreshed.access_token;
}

async function vepFetch(path: string, env: Env, init?: RequestInit): Promise<Response> {
  const token = await getAccessToken(env);
  const url = path.startsWith('http') ? path : `${env.PMI_VEP_BASE_URL}${path}`;
  const resp = await fetch(url, {
    ...init,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...(init?.headers ?? {})
    }
  });

  // If 401, try one refresh + retry (token expired between read and use)
  if (resp.status === 401) {
    const tokens = await readTokensFromKV(env);
    if (tokens) {
      const refreshed = await refreshAccessToken(env, tokens);
      return fetch(url, {
        ...init,
        headers: {
          'Authorization': `Bearer ${refreshed.access_token}`,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...(init?.headers ?? {})
        }
      });
    }
  }

  return resp;
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
