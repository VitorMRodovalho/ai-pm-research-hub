import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BATCH_ID = process.argv.find((arg) => arg.startsWith('--batch-id='))?.split('=')[1] ?? '';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
if (!BATCH_ID) throw new Error('Usage: --batch-id=<uuid>');

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_verify_ingestion_provenance_batch', { p_batch_id: BATCH_ID });
  if (error) throw error;
  console.log('[ingestion-provenance-verify] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[ingestion-provenance-verify] failed', error);
  process.exit(1);
});
