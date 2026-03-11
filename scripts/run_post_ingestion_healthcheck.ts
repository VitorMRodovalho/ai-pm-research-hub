/**
 * Executes post-ingestion healthcheck and prints the alert summary.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/run_post_ingestion_healthcheck.ts
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/run_post_ingestion_healthcheck.ts --batch=<uuid>
 */

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const batchArg = process.argv.find((arg) => arg.startsWith('--batch='));
const batchId = batchArg ? batchArg.slice('--batch='.length) : null;

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function main() {
  const { data, error } = await sb.rpc('admin_run_post_ingestion_healthcheck', {
    p_batch_id: batchId,
  });
  if (error) {
    console.error('[healthcheck] failed:', error.message);
    process.exit(1);
  }
  console.log(JSON.stringify(data || {}, null, 2));
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
