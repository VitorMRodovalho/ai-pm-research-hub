import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const LIMIT = Number(process.argv.find((arg) => arg.startsWith('--limit='))?.split('=')[1] ?? '100');
const ONLY_UNMAPPED = (process.argv.find((arg) => arg.startsWith('--only-unmapped='))?.split('=')[1] ?? 'true') !== 'false';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function main() {
  const { data, error } = await sb.rpc('admin_suggest_notion_board_mappings', {
    p_limit: LIMIT,
    p_only_unmapped: ONLY_UNMAPPED,
  });

  if (error) throw error;

  const rows = data ?? [];
  console.log(`[notion-suggestions] rows=${rows.length} onlyUnmapped=${ONLY_UNMAPPED}`);
  console.log(JSON.stringify(rows, null, 2));
}

main().catch((error) => {
  console.error('[notion-suggestions] failed', error);
  process.exit(1);
});
