import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const CONTEXT = process.argv.find((arg) => arg.startsWith('--context='))?.split('=')[1] ?? 'dry_rehearsal';
const GATE_MODE = process.argv.find((arg) => arg.startsWith('--gate-mode='))?.split('=')[1] ?? 'advisory';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_run_dry_rehearsal_chain', {
    p_context_label: CONTEXT,
    p_gate_mode: GATE_MODE,
  });

  if (error) throw error;
  console.log('[dry-rehearsal-chain] result');
  console.log(JSON.stringify(data, null, 2));
}

main().catch((error) => {
  console.error('[dry-rehearsal-chain] failed', error);
  process.exit(1);
});
