import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BATCH_ID = process.argv.find((arg) => arg.startsWith('--batch-id='))?.split('=')[1] ?? null;
const CAPTURE_SNAPSHOT = (process.argv.find((arg) => arg.startsWith('--capture-snapshot='))?.split('=')[1] ?? 'true') !== 'false';
const GATE_MODE = process.argv.find((arg) => arg.startsWith('--gate-mode='))?.split('=')[1] ?? null;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_run_post_ingestion_chain', {
    p_batch_id: BATCH_ID,
    p_capture_snapshot: CAPTURE_SNAPSHOT,
    p_gate_mode: GATE_MODE,
  });

  if (error) throw error;
  console.log('[post-ingestion-chain] completed');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[post-ingestion-chain] failed', error);
  process.exit(1);
});
