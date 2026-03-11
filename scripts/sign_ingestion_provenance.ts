import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BATCH_ID = process.argv.find((arg) => arg.startsWith('--batch-id='))?.split('=')[1] ?? '';
const FILE_PATH = process.argv.find((arg) => arg.startsWith('--file-path='))?.split('=')[1] ?? '';
const FILE_HASH = process.argv.find((arg) => arg.startsWith('--file-hash='))?.split('=')[1] ?? '';
const SOURCE_KIND = process.argv.find((arg) => arg.startsWith('--source-kind='))?.split('=')[1] ?? 'mixed';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (!BATCH_ID || !FILE_PATH || !FILE_HASH) {
  throw new Error('Usage: --batch-id=<uuid> --file-path=<path> --file-hash=<sha256> [--source-kind=<kind>]');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_sign_ingestion_file_provenance', {
    p_batch_id: BATCH_ID,
    p_file_path: FILE_PATH,
    p_file_hash: FILE_HASH,
    p_source_kind: SOURCE_KIND,
    p_metadata: { runner: 'sign_ingestion_provenance.ts' },
  });

  if (error) throw error;
  console.log('[ingestion-provenance] signed');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[ingestion-provenance] failed', error);
  process.exit(1);
});
