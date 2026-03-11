/**
 * Seed explicit continuity overrides for leadership-requested renumbering paths.
 *
 * Current scope:
 * - Fabricio continuity stream
 * - Debora continuity stream
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/seed_continuity_overrides.ts --dry-run
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/seed_continuity_overrides.ts
 */

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const DRY_RUN = process.argv.includes('--dry-run');

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

type OverrideSeed = {
  continuityKey: string;
  leaderName: string;
  legacyCycleCode: string;
  currentCycleCode: string;
  continuityType: 'renumbered_continuity' | 'same_stream_new_id' | 'same_stream_same_id';
  notes: string;
  matchLegacy: string[];
  matchCurrent: string[];
};

const SEEDS: OverrideSeed[] = [
  {
    continuityKey: 'fabricio-stream-renumbering',
    leaderName: 'Fabricio',
    legacyCycleCode: 'cycle_2',
    currentCycleCode: 'cycle_3',
    continuityType: 'same_stream_new_id',
    notes: 'Continuity override requested for Fabricio stream across cycle renumbering.',
    matchLegacy: ['fabricio', 'roi', 'portfolio'],
    matchCurrent: ['fabricio', 'roi', 'portfolio'],
  },
  {
    continuityKey: 'debora-stream-renumbering',
    leaderName: 'Debora',
    legacyCycleCode: 'cycle_2',
    currentCycleCode: 'cycle_3',
    continuityType: 'same_stream_new_id',
    notes: 'Continuity override requested for Debora stream across cycle renumbering.',
    matchLegacy: ['debora', 'agentes', 'equipes hibridas'],
    matchCurrent: ['debora', 'agentes', 'equipes hibridas'],
  },
];

async function findTribeId(keywords: string[]): Promise<number | null> {
  const { data, error } = await sb.from('tribes').select('id,name').order('id');
  if (error || !data?.length) return null;
  const match = data.find((tribe) => {
    const name = String(tribe.name || '').toLowerCase();
    return keywords.some((k) => name.includes(k.toLowerCase()));
  });
  return match ? Number(match.id) : null;
}

async function main() {
  console.log(`[continuity] start ${DRY_RUN ? '(dry-run)' : '(apply)'}`);
  for (const seed of SEEDS) {
    const legacyTribeId = await findTribeId(seed.matchLegacy);
    const currentTribeId = await findTribeId(seed.matchCurrent);
    const payload = {
      p_continuity_key: seed.continuityKey,
      p_legacy_cycle_code: seed.legacyCycleCode,
      p_legacy_tribe_id: legacyTribeId,
      p_current_cycle_code: seed.currentCycleCode,
      p_current_tribe_id: currentTribeId,
      p_leader_name: seed.leaderName,
      p_continuity_type: seed.continuityType,
      p_is_active: true,
      p_notes: seed.notes,
      p_metadata: {
        seeded_by: 'seed_continuity_overrides.ts',
        match_legacy: seed.matchLegacy,
        match_current: seed.matchCurrent,
      },
    };
    if (DRY_RUN) {
      console.log('[dry-run] override', payload);
      continue;
    }
    const { error } = await sb.rpc('admin_upsert_tribe_continuity_override', payload);
    if (error) {
      console.warn('[continuity] failed', seed.continuityKey, error.message);
      continue;
    }
    console.log('[continuity] upserted', seed.continuityKey);
  }
  console.log('[continuity] done');
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
