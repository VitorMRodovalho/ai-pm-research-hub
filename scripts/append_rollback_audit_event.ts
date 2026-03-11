import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PLAN_ID = process.argv.find((arg) => arg.startsWith('--plan-id='))?.split('=')[1] ?? '';
const EVENT_TYPE = process.argv.find((arg) => arg.startsWith('--event='))?.split('=')[1] ?? '';
const REASON = process.argv.find((arg) => arg.startsWith('--reason='))?.split('=')[1] ?? null;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
if (!PLAN_ID || !EVENT_TYPE) throw new Error('Usage: --plan-id=<uuid> --event=<type> [--reason=...]');

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_append_rollback_audit_event', {
    p_plan_id: PLAN_ID,
    p_event_type: EVENT_TYPE,
    p_reason: REASON,
    p_details: { runner: 'append_rollback_audit_event.ts' },
  });
  if (error) throw error;
  console.log('[rollback-audit-event] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[rollback-audit-event] failed', error);
  process.exit(1);
});
