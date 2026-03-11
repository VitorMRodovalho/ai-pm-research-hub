/**
 * Miro CSV → board_items Importer
 *
 * Reads the Miro board CSV export and inserts stickies/text items
 * as board_items in the active tribe boards. Uses heuristics to
 * map items to tribe_ids based on section headers in the CSV.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/import_miro_csv.mjs [--dry-run]
 */

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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

const SENSITIVE_ROOT = (process.env.SENSITIVE_ROOT || '').trim()
  || resolve(process.cwd(), 'Sensitive');

const MIRO_CSV_PATH = resolve(SENSITIVE_ROOT, 'Miro board - Núcleo IA - Geral.csv');

const SECTION_TO_TRIBE = {
  'tribo 1': 1,
  'tribo 2': 2,
  'tribo 3': 3,
  'tribo 4': 4,
  'tribo 5': 5,
  'tribo 6': 6,
  'tribo 7': 7,
  'tribo 8': 8,
  'tribe 1': 1,
  'tribe 2': 2,
  'tribe 3': 3,
  'tribe 4': 4,
  'tribe 5': 5,
  'tribe 6': 6,
  'tribe 7': 7,
  'tribe 8': 8,
  'artigo (ciclo 2)': 4,
  'prefeitura': null,
  'cronograma': null,
  'info do projeto': null,
};

const SECTION_STATUS = {
  'backlog': 'backlog',
  'ideação': 'backlog',
  'referências': 'backlog',
  'referencias': 'backlog',
  'biblioteca': 'backlog',
  'pesquisa': 'todo',
  'em andamento': 'in_progress',
  'revisão': 'review',
  'concluído': 'done',
  'publicado': 'done',
};

function parseMiroCSV(content) {
  const lines = content.split(/\r?\n/);
  const items = [];
  let currentSection = 'geral';
  let currentTribeId = null;

  const sectionKeys = new Set([
    ...Object.keys(SECTION_TO_TRIBE),
    'biblioteca', 'videos', 'assistentes', 'artigos', 'livros',
    'cursos', 'notícias', 'noticias', 'centro de eventos',
    'retrospectivas', 'plataforma', 'referencias', 'referências',
    'backlog', 'ideação', 'pesquisa', 'em andamento', 'revisão',
    'concluído', 'publicado',
  ]);

  for (const rawLine of lines) {
    const line = rawLine.replace(/^"|"$/g, '').trim();
    if (!line) continue;

    const lower = line.toLowerCase();

    if (sectionKeys.has(lower)) {
      currentSection = lower;
      if (SECTION_TO_TRIBE[lower] !== undefined) {
        currentTribeId = SECTION_TO_TRIBE[lower];
      }
      continue;
    }

    const tribeMatch = lower.match(/tribo?\s*(\d+)/);
    if (tribeMatch) {
      const tId = parseInt(tribeMatch[1], 10);
      if (tId >= 1 && tId <= 8) {
        currentTribeId = tId;
        currentSection = lower;
        continue;
      }
    }

    if (line.startsWith('http') && line.length < 10) continue;
    if (line.length < 3) continue;

    const hasUrl = /https?:\/\//.test(line);
    let title = line;
    let description = null;

    const csvParts = rawLine.split('","');
    if (csvParts.length >= 2) {
      title = csvParts[0].replace(/^"/, '').trim();
      const rest = csvParts.slice(1).join(' ').replace(/"$/g, '').trim();
      if (rest && rest !== title) description = rest;
    }

    if (title.length > 200) title = title.substring(0, 197) + '...';

    const status = SECTION_STATUS[currentSection] || 'backlog';

    items.push({
      title,
      description,
      tribeId: currentTribeId,
      section: currentSection,
      status,
      hasUrl,
      tags: ['miro_import', `miro_section_${currentSection.replace(/\s+/g, '_')}`],
    });
  }

  return items;
}

async function getOrCreateBoard(tribeId) {
  const { data: existing } = await sb
    .from('project_boards')
    .select('id')
    .eq('tribe_id', tribeId)
    .eq('is_active', true)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing) return existing.id;

  const { data: newBoard, error } = await sb
    .from('project_boards')
    .insert({
      board_name: `Tribo ${tribeId} — Board`,
      tribe_id: tribeId,
      source: 'miro_import',
      columns: JSON.stringify(['backlog', 'todo', 'in_progress', 'review', 'done']),
      is_active: true,
    })
    .select('id')
    .single();

  if (error) {
    console.error(`  ERROR creating board for tribe ${tribeId}: ${error.message}`);
    return null;
  }
  console.log(`  Created board ${newBoard.id} for tribe ${tribeId}`);
  return newBoard.id;
}

async function main() {
  console.log(`Miro CSV → board_items Importer${DRY_RUN ? ' (DRY RUN)' : ''}`);
  console.log('========================================');

  if (!existsSync(MIRO_CSV_PATH)) {
    console.error(`CSV not found: ${MIRO_CSV_PATH}`);
    console.error('Set SENSITIVE_ROOT or ensure Sensitive/ exists with the Miro CSV.');
    process.exit(1);
  }

  const content = readFileSync(MIRO_CSV_PATH, 'utf-8');
  const allItems = parseMiroCSV(content);
  console.log(`Parsed ${allItems.length} items from CSV`);

  const withTribe = allItems.filter(i => i.tribeId !== null);
  const withoutTribe = allItems.filter(i => i.tribeId === null);
  console.log(`  With tribe mapping: ${withTribe.length}`);
  console.log(`  Without tribe (skipped): ${withoutTribe.length}`);

  const byTribe = {};
  for (const item of withTribe) {
    if (!byTribe[item.tribeId]) byTribe[item.tribeId] = [];
    byTribe[item.tribeId].push(item);
  }

  console.log('\nDistribution:');
  for (const [tid, items] of Object.entries(byTribe)) {
    console.log(`  Tribe ${tid}: ${items.length} items`);
  }

  const boardCache = {};
  let imported = 0;
  let skipped = 0;

  for (const [tribeIdStr, items] of Object.entries(byTribe)) {
    const tribeId = parseInt(tribeIdStr, 10);
    console.log(`\n--- Tribe ${tribeId} (${items.length} items) ---`);

    if (DRY_RUN) {
      for (const item of items) {
        console.log(`  [DRY] ${item.title.substring(0, 70)} | ${item.status} | ${item.section}`);
        imported++;
      }
      continue;
    }

    if (!boardCache[tribeId]) {
      boardCache[tribeId] = await getOrCreateBoard(tribeId);
    }
    const boardId = boardCache[tribeId];
    if (!boardId) {
      console.error(`  Skipping tribe ${tribeId}: no board`);
      skipped += items.length;
      continue;
    }

    for (let i = 0; i < items.length; i++) {
      const item = items[i];

      const { data: dup } = await sb
        .from('board_items')
        .select('id')
        .eq('board_id', boardId)
        .eq('title', item.title)
        .eq('source_board', 'miro_import')
        .maybeSingle();

      if (dup) {
        skipped++;
        continue;
      }

      const { error: insertErr } = await sb.from('board_items').insert({
        board_id: boardId,
        title: item.title,
        description: item.description,
        status: item.status,
        curation_status: 'draft',
        tags: item.tags,
        position: i,
        source_board: 'miro_import',
        source_card_id: `miro_${tribeId}_${i}`,
        cycle: 2,
      });

      if (insertErr) {
        console.error(`  ERROR: ${item.title.substring(0, 40)}: ${insertErr.message}`);
        skipped++;
      } else {
        imported++;
      }
    }
  }

  console.log('\n========================================');
  console.log(`Result: ${imported} imported, ${skipped} skipped (of ${withTribe.length} tribe-mapped items)`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
