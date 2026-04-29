/**
 * PMI VEP API client wrapper.
 *
 * AUTH: PMI VEP usa OIDC. Para um worker server-side, precisamos
 * obter access token via OAuth client_credentials (ou outro grant suportado).
 *
 * TODO_CLAUDE_CODE [CRÍTICO — pre-deploy]: confirmar com Vitor:
 *   - Existe app OAuth registrado no PMI para server-to-server?
 *   - Qual grant type? (client_credentials, password, ou outro?)
 *   - URL exata de token endpoint
 *   - Scopes necessários
 *
 * Plano B se PMI não tiver OAuth server-side:
 *   - Capturar refresh_token via login interativo do Vitor uma vez
 *   - Armazenar em Cloudflare Workers KV
 *   - Worker usa refresh_token para obter access_token a cada execução
 */

import type { Env, VepApplicationListItem, VepApplicationDetail } from './types';

const BUCKETS = {
  submitted: 'submitted',
  qualified: 'qualified',
  rejected: 'rejected'
} as const;

export type Bucket = typeof BUCKETS[keyof typeof BUCKETS];

let _tokenCache: { token: string; expiresAt: number } | null = null;

async function getAccessToken(env: Env): Promise<string> {
  if (_tokenCache && _tokenCache.expiresAt > Date.now() + 30_000) {
    return _tokenCache.token;
  }

  const body = new URLSearchParams({
    grant_type: 'client_credentials',
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
    throw new Error(`PMI OAuth token failed: ${resp.status} ${text}`);
  }

  const json = await resp.json() as { access_token: string; expires_in: number };
  _tokenCache = {
    token: json.access_token,
    expiresAt: Date.now() + (json.expires_in * 1000)
  };
  return json.access_token;
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
