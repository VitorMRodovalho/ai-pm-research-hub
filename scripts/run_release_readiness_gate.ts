import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const MAX_OPEN_WARNINGS = Number(process.argv.find((arg) => arg.startsWith('--max-open-warnings='))?.split('=')[1] ?? '5');
const FRESH_SNAPSHOT_HOURS = Number(process.argv.find((arg) => arg.startsWith('--fresh-snapshot-hours='))?.split('=')[1] ?? '24');

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_release_readiness_gate', {
    p_max_open_warnings: MAX_OPEN_WARNINGS,
    p_require_fresh_snapshot_hours: FRESH_SNAPSHOT_HOURS,
  });

  if (error) throw error;
  console.log('[release-readiness] gate result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[release-readiness] failed', error);
  process.exit(1);
});
