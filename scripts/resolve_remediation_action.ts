import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ALERT_ID = Number(process.argv.find((arg) => arg.startsWith('--alert-id='))?.split('=')[1] ?? '0');

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (!ALERT_ID) {
  throw new Error('Usage: --alert-id=<id>');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_resolve_remediation_action', {
    p_alert_id: ALERT_ID,
  });
  if (error) throw error;
  console.log('[remediation-escalation] action');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[remediation-escalation] failed', error);
  process.exit(1);
});
