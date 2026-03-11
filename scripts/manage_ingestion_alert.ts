import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const ALERT_ID = Number(process.argv.find((arg) => arg.startsWith('--alert-id='))?.split('=')[1] ?? '0');
const STATUS = process.argv.find((arg) => arg.startsWith('--status='))?.split('=')[1] ?? '';
const REASON = process.argv.find((arg) => arg.startsWith('--reason='))?.split('=')[1] ?? null;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (!ALERT_ID || !STATUS) {
  throw new Error('Usage: --alert-id=<id> --status=<open|acknowledged|closed> [--reason=...]');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_update_ingestion_alert_status', {
    p_alert_id: ALERT_ID,
    p_next_status: STATUS,
    p_reason: REASON,
    p_metadata: { runner: 'manage_ingestion_alert.ts' },
  });

  if (error) throw error;
  console.log('[ingestion-alert] status updated');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[ingestion-alert] failed', error);
  process.exit(1);
});
