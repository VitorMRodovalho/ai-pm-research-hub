import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PLAN_ID = process.argv.find((arg) => arg.startsWith('--plan-id='))?.split('=')[1] ?? '';
const WINDOW_START = process.argv.find((arg) => arg.startsWith('--window-start='))?.split('=')[1] ?? null;
const WINDOW_END = process.argv.find((arg) => arg.startsWith('--window-end='))?.split('=')[1] ?? null;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
if (!PLAN_ID) throw new Error('Usage: --plan-id=<uuid> [--window-start=ISO] [--window-end=ISO]');

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_approve_ingestion_rollback', {
    p_plan_id: PLAN_ID,
    p_execution_window_start: WINDOW_START,
    p_execution_window_end: WINDOW_END,
  });
  if (error) throw error;
  console.log('[controlled-rollback-approve] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[controlled-rollback-approve] failed', error);
  process.exit(1);
});
