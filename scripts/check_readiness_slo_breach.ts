import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const MAX_HOURS = Number(process.argv.find((arg) => arg.startsWith('--max-hours='))?.split('=')[1] ?? '48');
const MAX_STREAK = Number(process.argv.find((arg) => arg.startsWith('--max-not-ready-streak='))?.split('=')[1] ?? '3');

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_check_readiness_slo_breach', {
    p_max_hours_since_last_decision: MAX_HOURS,
    p_max_consecutive_not_ready: MAX_STREAK,
  });
  if (error) throw error;
  console.log('[readiness-slo] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[readiness-slo] failed', error);
  process.exit(1);
});
