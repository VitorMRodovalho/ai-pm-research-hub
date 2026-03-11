import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const WINDOW_DAYS = Number(process.argv.find((arg) => arg.startsWith('--window-days='))?.split('=')[1] ?? '30');

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('exec_readiness_slo_by_source', { p_window_days: WINDOW_DAYS });
  if (error) throw error;
  console.log('[readiness-slo-by-source] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[readiness-slo-by-source] failed', error);
  process.exit(1);
});
