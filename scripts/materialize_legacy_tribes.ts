/**
 * Materialize legacy tribes for cycle 1 / cycle 2.
 *
 * Uses admin RPCs to register legacy tribe entities and optionally link boards
 * by keyword. Safe-by-default with --dry-run.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/materialize_legacy_tribes.ts --dry-run
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/materialize_legacy_tribes.ts
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

type LegacySeed = {
  legacyKey: string;
  cycleCode: string;
  cycleLabel: string;
  displayName: string;
  quadrant?: number;
  chapter?: string;
  notes?: string;
  boardKeywords: string[];
};

const LEGACY_SEEDS: LegacySeed[] = [
  {
    legacyKey: 'c1-tribe-04-riscos-ia',
    cycleCode: 'cycle_1',
    cycleLabel: 'Ciclo 1',
    displayName: 'Tribo 04 - Previsao de Riscos em Projetos com IA',
    quadrant: 3,
    notes: 'Materializacao de legado (arquivo historico).',
    boardKeywords: ['riscos', 'risk'],
  },
  {
    legacyKey: 'c1-tribe-05-ferramentas-metodos',
    cycleCode: 'cycle_1',
    cycleLabel: 'Ciclo 1',
    displayName: 'Tribo 05 - Ferramentas e Metodos de IA para GP',
    quadrant: 3,
    notes: 'Materializacao de legado (arquivo historico).',
    boardKeywords: ['ferramentas', 'metodos', 'methods', 'tools'],
  },
  {
    legacyKey: 'c2-tribe-communication',
    cycleCode: 'cycle_2',
    cycleLabel: 'Ciclo 2',
    displayName: 'Tribo Comunicacao - Ciclo 2',
    quadrant: 2,
    notes: 'Materializacao de legado da frente de comunicacao.',
    boardKeywords: ['comunic', 'midias', 'media'],
  },
  {
    legacyKey: 'c2-tribe-06-roi-portfolio',
    cycleCode: 'cycle_2',
    cycleLabel: 'Ciclo 2',
    displayName: 'Tribo 06 - ROI e Portfolio IA',
    quadrant: 3,
    notes: 'Continuidade para mapeamento de renumeracao no ciclo 3.',
    boardKeywords: ['roi', 'portfolio', 'priorizacao'],
  },
];

async function upsertLegacy(seed: LegacySeed): Promise<number | null> {
  if (DRY_RUN) {
    console.log('[dry-run] legacy seed', seed.legacyKey, seed.displayName);
    return null;
  }
  const { data, error } = await sb.rpc('admin_upsert_legacy_tribe', {
    p_legacy_key: seed.legacyKey,
    p_cycle_code: seed.cycleCode,
    p_cycle_label: seed.cycleLabel,
    p_display_name: seed.displayName,
    p_quadrant: seed.quadrant ?? null,
    p_chapter: seed.chapter ?? null,
    p_status: 'inactive',
    p_notes: seed.notes ?? null,
    p_metadata: { seeded_by: 'materialize_legacy_tribes.ts' },
  });
  if (error) {
    console.warn('[legacy] upsert failed', seed.legacyKey, error.message);
    return null;
  }
  return Number(data?.legacy_tribe_id || 0) || null;
}

async function linkBoards(legacyTribeId: number, keywords: string[]) {
  const { data: boards, error } = await sb
    .from('project_boards')
    .select('id, board_name')
    .eq('is_active', true)
    .limit(400);
  if (error || !boards?.length) {
    if (error) console.warn('[legacy] board scan failed', error.message);
    return;
  }

  const matches = boards.filter((board) => {
    const name = String(board.board_name || '').toLowerCase();
    return keywords.some((k) => name.includes(k.toLowerCase()));
  });

  for (const board of matches) {
    if (DRY_RUN) {
      console.log('[dry-run] board link', legacyTribeId, board.id, board.board_name);
      continue;
    }
    const { error: linkErr } = await sb.rpc('admin_link_board_to_legacy_tribe', {
      p_legacy_tribe_id: legacyTribeId,
      p_board_id: board.id,
      p_relation_type: 'legacy_snapshot',
      p_confidence_score: 0.8,
      p_notes: 'Auto-linked by keyword matcher',
      p_metadata: { keywords },
    });
    if (linkErr) {
      console.warn('[legacy] link failed', board.id, linkErr.message);
    }
  }
}

async function main() {
  console.log(`[legacy] materialization start (${DRY_RUN ? 'dry_run' : 'apply'})`);
  for (const seed of LEGACY_SEEDS) {
    const legacyTribeId = await upsertLegacy(seed);
    if (legacyTribeId) {
      await linkBoards(legacyTribeId, seed.boardKeywords);
    } else if (DRY_RUN) {
      await linkBoards(0, seed.boardKeywords);
    }
  }
  console.log('[legacy] done');
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
