import { writeFileSync } from 'fs';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const WINDOW_DAYS = Number(process.argv.find((arg) => arg.startsWith('--window-days='))?.split('=')[1] ?? '30');
const OUT = process.argv.find((arg) => arg.startsWith('--out='))?.split('=')[1] ?? '';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('exec_governance_export_bundle', { p_window_days: WINDOW_DAYS });
  if (error) throw error;
  const payload = JSON.stringify(data, null, 2);
  if (OUT) {
    writeFileSync(OUT, payload, 'utf8');
    console.log(`[governance-export-bundle] saved ${OUT}`);
  } else {
    console.log(payload);
  }
}

main().catch((error) => {
  console.error('[governance-export-bundle] failed', error);
  process.exit(1);
});
