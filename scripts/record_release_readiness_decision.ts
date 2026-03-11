import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const CONTEXT = process.argv.find((arg) => arg.startsWith('--context='))?.split('=')[1] ?? null;
const MODE = process.argv.find((arg) => arg.startsWith('--mode='))?.split('=')[1] ?? null;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_record_release_readiness_decision', {
    p_context_label: CONTEXT,
    p_mode: MODE,
  });

  if (error) throw error;
  console.log('[readiness-history] recorded');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[readiness-history] failed', error);
  process.exit(1);
});
