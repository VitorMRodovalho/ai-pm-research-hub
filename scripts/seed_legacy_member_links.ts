import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const DRY_RUN = (process.argv.find((arg) => arg.startsWith('--mode='))?.split('=')[1] ?? 'dry') !== 'apply';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

type LegacyTribe = { id: number; display_name: string; cycle_code: string | null };
type HistoryRow = {
  member_id: string;
  cycle_code: string;
  operational_role: string | null;
  tribe_id: number | null;
};

async function main() {
  const { data: legacyTribes, error: legacyError } = await sb
    .from('legacy_tribes')
    .select('id,display_name,cycle_code');
  if (legacyError) throw legacyError;

  const { data: historyRows, error: historyError } = await sb
    .from('member_cycle_history')
    .select('member_id,cycle_code,operational_role,tribe_id')
    .not('tribe_id', 'is', null);
  if (historyError) throw historyError;

  const legacyByName = new Map<string, LegacyTribe>();
  for (const tribe of (legacyTribes ?? []) as LegacyTribe[]) {
    legacyByName.set(tribe.display_name.toLowerCase().trim(), tribe);
  }

  let linked = 0;
  for (const row of (historyRows ?? []) as HistoryRow[]) {
    const inferredKey = `tribo ${row.tribe_id}`.toLowerCase();
    const legacy = legacyByName.get(inferredKey);
    if (!legacy) continue;

    if (DRY_RUN) {
      console.log(
        '[dry-run] link',
        JSON.stringify({
          legacy_tribe_id: legacy.id,
          member_id: row.member_id,
          cycle_code: row.cycle_code,
          role_snapshot: row.operational_role,
        }),
      );
      linked += 1;
      continue;
    }

    const { error } = await sb.rpc('admin_link_member_to_legacy_tribe', {
      p_legacy_tribe_id: legacy.id,
      p_member_id: row.member_id,
      p_cycle_code: row.cycle_code,
      p_role_snapshot: row.operational_role,
      p_link_type: row.operational_role?.includes('lead') ? 'historical_leader' : 'historical_member',
      p_confidence_score: 0.85,
      p_metadata: { seeded_by: 'seed_legacy_member_links.ts' },
    });
    if (error) throw error;
    linked += 1;
  }

  console.log(`[legacy-member-links] processed=${linked} mode=${DRY_RUN ? 'dry' : 'apply'}`);
}

main().catch((error) => {
  console.error('[legacy-member-links] failed', error);
  process.exit(1);
});
