import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const RUN_CONTEXT = process.argv.find((arg) => arg.startsWith('--context='))?.split('=')[1] ?? 'manual';
const RUN_LABEL = process.argv.find((arg) => arg.startsWith('--label='))?.split('=')[1] ?? null;
const SOURCE_BATCH_ID = process.argv.find((arg) => arg.startsWith('--batch-id='))?.split('=')[1] ?? null;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_capture_data_quality_snapshot', {
    p_run_context: RUN_CONTEXT,
    p_run_label: RUN_LABEL,
    p_source_batch_id: SOURCE_BATCH_ID,
  });

  if (error) throw error;
  console.log('[audit-snapshot] captured');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[audit-snapshot] failed', error);
  process.exit(1);
});
