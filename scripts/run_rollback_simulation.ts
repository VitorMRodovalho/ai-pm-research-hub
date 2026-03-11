import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PLAN_ID = process.argv.find((arg) => arg.startsWith('--plan-id='))?.split('=')[1] ?? '';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
if (!PLAN_ID) throw new Error('Usage: --plan-id=<uuid>');

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_simulate_ingestion_rollback', { p_plan_id: PLAN_ID });
  if (error) throw error;
  console.log('[rollback-simulation] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[rollback-simulation] failed', error);
  process.exit(1);
});
