/**
 * Executes admin_data_quality_audit() and prints JSON output.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/run_data_quality_audit.ts
 */

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function main() {
  const { data, error } = await sb.rpc('admin_data_quality_audit');
  if (error) {
    console.error('[audit] failed:', error.message);
    process.exit(1);
  }
  console.log(JSON.stringify(data || {}, null, 2));
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
