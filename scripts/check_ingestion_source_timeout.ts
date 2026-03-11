import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SOURCE = process.argv.find((arg) => arg.startsWith('--source='))?.split('=')[1] ?? 'mixed';
const STARTED_AT = process.argv.find((arg) => arg.startsWith('--started-at='))?.split('=')[1] ?? '';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (!STARTED_AT) {
  throw new Error('Usage: --source=<source> --started-at=<ISO_TIMESTAMP>');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_check_ingestion_source_timeout', {
    p_source: SOURCE,
    p_started_at: STARTED_AT,
  });

  if (error) throw error;
  console.log('[ingestion-timeout-check] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[ingestion-timeout-check] failed', error);
  process.exit(1);
});
