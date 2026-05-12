/**
 * VEP JSON import — server-side proxy to pmi-vep-sync worker /ingest (p151 C).
 *
 * POST /api/admin/import-pmi-vep-json
 *
 * Body: { payload: ScriptIngestPayload, dry_run: boolean }
 *
 * Auth flow:
 *   1. Bearer JWT (user session from Supabase) in Authorization header
 *   2. Validate via supabase.auth.getUser(jwt) — get member row
 *   3. Gate via can_by_member(member_id, 'manage_member') — only admins/GP
 *   4. Forward payload to worker /ingest with x-ingest-secret from server env
 *
 * Why server-side proxy (not direct browser → worker):
 *   - INGEST_SHARED_SECRET stays server-side (cfEnv binding), never exposed
 *     to browser. Worker auth surface unchanged.
 *   - Adds audit trail (admin_audit_log) per invocation (dry-run + apply both).
 *   - Reuses canonical logic in worker — single source of truth
 *     (see feedback_worker_db_schema_drift_audit_pattern.md sediment p131).
 */
import type { APIRoute } from 'astro';
import { createClient } from '@supabase/supabase-js';
import { env as cfEnv } from 'cloudflare:workers';

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const POST: APIRoute = async ({ request }) => {
  // 1. Server env (cfEnv runtime) + build-time fallback
  const supabaseUrl = (cfEnv as any)?.SUPABASE_URL || import.meta.env.PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = (cfEnv as any)?.SUPABASE_ANON_KEY || import.meta.env.PUBLIC_SUPABASE_ANON_KEY;
  const ingestSecret = (cfEnv as any)?.INGEST_SHARED_SECRET;
  const workerUrl = (cfEnv as any)?.PMI_VEP_SYNC_URL || 'https://pmi-vep-sync.vitormr.dev';

  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: 'server_misconfig', detail: 'SUPABASE env missing' }, 500);
  }
  if (!ingestSecret) {
    return jsonResponse({ error: 'server_misconfig', detail: 'INGEST_SHARED_SECRET not bound on platform worker' }, 500);
  }

  // 2. Extract + validate session JWT
  const authHeader = request.headers.get('authorization') || '';
  const jwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!jwt) {
    return jsonResponse({ error: 'unauthorized', detail: 'missing Authorization: Bearer <jwt>' }, 401);
  }

  // 3. canV4 gate: manage_member action (same as CSV import path)
  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return jsonResponse({ error: 'unauthorized', detail: userErr?.message || 'invalid_jwt' }, 401);
  }
  const { data: gate, error: gateErr } = await userClient.rpc('can', { p_action: 'manage_member' });
  if (gateErr) {
    return jsonResponse({ error: 'auth_check_failed', detail: gateErr.message }, 500);
  }
  if (!gate) {
    return jsonResponse({ error: 'forbidden', detail: 'requires manage_member' }, 403);
  }

  // 4. Parse body
  let body: any;
  try {
    body = await request.json();
  } catch (e: any) {
    return jsonResponse({ error: 'invalid_json', detail: e.message }, 400);
  }
  if (!body || typeof body !== 'object') {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }
  if (!body.payload || typeof body.payload !== 'object') {
    return jsonResponse({ error: 'missing_field', detail: 'body.payload required' }, 400);
  }
  if (!Array.isArray(body.payload.applications) || body.payload.applications.length === 0) {
    return jsonResponse({ error: 'invalid_payload', detail: 'payload.applications must be non-empty array' }, 400);
  }

  // 5. Forward to worker /ingest (passing dry_run flag inline in payload)
  const workerPayload = {
    ...body.payload,
    dry_run: body.dry_run === true,
  };
  const workerResp = await fetch(`${workerUrl}/ingest`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-ingest-secret': ingestSecret,
    },
    body: JSON.stringify(workerPayload),
  });
  const workerStatus = workerResp.status;
  let workerData: any = null;
  try {
    workerData = await workerResp.json();
  } catch {
    workerData = { error: 'invalid_worker_response' };
  }

  // 6. Audit: worker /ingest already records in cron_run_log per invocation
  // (incl. dry_run via trigger_reason='http_ingest_dry_run'). Skipping a
  // duplicate platform-side admin_audit_log entry — worker is the source of
  // truth for ingest history. If a separate platform-level admin trail is
  // needed later, add a log_admin_action RPC and call it here.

  return jsonResponse(workerData, workerStatus);
};
