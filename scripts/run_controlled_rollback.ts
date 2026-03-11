import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PLAN_ID = process.argv.find((arg) => arg.startsWith('--plan-id='))?.split('=')[1] ?? '';
const EXECUTE = (process.argv.find((arg) => arg.startsWith('--execute='))?.split('=')[1] ?? 'false') === 'true';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (!PLAN_ID) {
  throw new Error('Usage: --plan-id=<uuid> [--execute=true]');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_execute_ingestion_rollback', {
    p_plan_id: PLAN_ID,
    p_approve_and_execute: EXECUTE,
  });

  if (error) throw error;
  console.log('[controlled-rollback] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[controlled-rollback] failed', error);
  process.exit(1);
});
