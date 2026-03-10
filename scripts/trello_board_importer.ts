/**
 * Wave 7 -- Trello Board Importer
 *
 * Parses 5 Trello JSON exports and ingests them into:
 *   - project_boards / board_items (workflow cards)
 *   - trello_import_log (audit trail)
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/trello_board_importer.ts [--dry-run]
 */

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';
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

const SENSITIVE_DIR = '/home/vitormrodovalho/Downloads/data/raw-drive-exports/Sensitive/Trello';

interface BoardConfig {
  file: string;
  boardSource: string;
  tribeId: number | null;
  cycle: number;
}

const BOARDS: BoardConfig[] = [
  { file: '8DSPL6eu - comunicacao-ciclo-3-nucleo-ia-gp.json', boardSource: 'comunicacao_ciclo3', tribeId: null, cycle: 3 },
  { file: 'controle de artigos cPgV9etE - articles.json', boardSource: 'controle_artigos', tribeId: null, cycle: 3 },
  { file: 'Dynna3IA - nucleo-ia-artigos-projectmanagementcom.json', boardSource: 'artigos_pmcom', tribeId: null, cycle: 3 },
  { file: 'OWzME1Ss - nucleo-ai-tribo-3-priorizacao-e-selecao-de-projeto.json', boardSource: 'tribo3_priorizacao', tribeId: 3, cycle: 3 },
  { file: 'zH82r9ai - midias-sociais-nucleo-ia-gestao-de-projetos.json', boardSource: 'midias_sociais', tribeId: null, cycle: 3 },
];

const LIST_STATUS_MAP: Record<string, string> = {
  'materiais de apoio': 'backlog',
  'estratégico | materiais de apoio': 'backlog',
  'ideação': 'backlog',
  'ideação': 'backlog',
  'new article ideas': 'backlog',
  'backlog': 'backlog',
  'article ideas / backlog': 'backlog',
  'membros da equipe': 'backlog',
  'pauta de reunião': 'backlog',
  'início e organização': 'todo',
  'planejados': 'todo',
  'research': 'todo',
  'pesquisa e coleta de informações': 'todo',
  'research & outline': 'todo',
  'outline': 'todo',
  'design': 'in_progress',
  'redação': 'in_progress',
  'redação': 'in_progress',
  'edição': 'in_progress',
  'draft 1': 'in_progress',
  'drafting in progress': 'in_progress',
  'estruturação do conteúdo': 'in_progress',
  'conteúdo elaborado': 'in_progress',
  'revisão estratégica': 'review',
  'validação gp': 'review',
  'validação': 'review',
  'internal review (author & peer)': 'review',
  'tribe leader review': 'review',
  'curation committee review': 'review',
  'curation': 'review',
  'validação e ajustes': 'review',
  'submit': 'review',
  'submitted for publication': 'review',
  'revisions required (external feedback)': 'review',
  'publicação': 'done',
  'publicação conteúdo': 'done',
  'publish': 'done',
  'published': 'done',
  'concluído': 'done',
  'concluido': 'done',
  'finalização e apresentação': 'done',
  'social media marketing': 'done',
  'done': 'done',
  'monitoramento & análise': 'done',
  'monitoring impact': 'done',
};

function mapListToStatus(listName: string): string {
  const key = listName.toLowerCase().trim();
  return LIST_STATUS_MAP[key] || 'backlog';
}

function mapLabelsToTags(labels: Array<{ name: string; color: string }>): string[] {
  return labels
    .filter(l => l.name && l.name.trim())
    .map(l => l.name.toLowerCase().trim().replace(/\s+/g, '_'));
}

async function loadMembers(): Promise<Map<string, string>> {
  const { data } = await sb.from('members').select('id, name, email');
  const map = new Map<string, string>();
  if (data) {
    for (const m of data) {
      if (m.email) map.set(m.email.toLowerCase(), m.id);
      if (m.name) map.set(m.name.toLowerCase(), m.id);
    }
  }
  return map;
}

function tryMatchMember(
  trelloMembers: Array<{ fullName: string; username: string }>,
  cardMemberIds: string[],
  allTrelloMembers: Array<{ id: string; fullName: string; username: string }>,
  dbMembers: Map<string, string>
): string | null {
  for (const tmId of cardMemberIds) {
    const tm = allTrelloMembers.find(m => m.id === tmId);
    if (!tm) continue;
    const byName = dbMembers.get(tm.fullName.toLowerCase());
    if (byName) return byName;
  }
  return null;
}

async function importBoard(config: BoardConfig, dbMembers: Map<string, string>) {
  const filePath = resolve(SENSITIVE_DIR, config.file);
  const raw = readFileSync(filePath, 'utf-8');
  const board = JSON.parse(raw);

  const boardName = board.name || config.file;
  const lists: Record<string, string> = {};
  for (const l of board.lists || []) {
    lists[l.id] = l.name;
  }

  console.log(`\n=== Importing: ${boardName} (${config.boardSource}) ===`);
  console.log(`  Lists: ${Object.values(lists).join(', ')}`);
  console.log(`  Cards: ${(board.cards || []).length}`);
  console.log(`  Members: ${(board.members || []).length}`);

  const columnNames = (board.lists || []).map((l: any) => mapListToStatus(l.name));
  const uniqueColumns = [...new Set(columnNames)];

  let projectBoardId: string | null = null;

  if (!DRY_RUN) {
    const { data: existingBoard } = await sb
      .from('project_boards')
      .select('id')
      .eq('board_name', boardName)
      .eq('source', 'trello')
      .maybeSingle();

    if (existingBoard) {
      projectBoardId = existingBoard.id;
      console.log(`  Board already exists: ${projectBoardId} (skipping create)`);
    } else {
      const { data: newBoard, error: boardErr } = await sb
        .from('project_boards')
        .insert({
          board_name: boardName,
          tribe_id: config.tribeId,
          source: 'trello',
          columns: JSON.stringify(uniqueColumns),
          is_active: true,
        })
        .select('id')
        .single();

      if (boardErr) {
        console.error(`  ERROR creating board: ${boardErr.message}`);
        return { total: 0, mapped: 0, skipped: 0 };
      }
      projectBoardId = newBoard.id;
      console.log(`  Created board: ${projectBoardId}`);
    }
  }

  let mapped = 0, skipped = 0;
  const cards = board.cards || [];

  for (let i = 0; i < cards.length; i++) {
    const card = cards[i];
    if (card.closed) { skipped++; continue; }

    const listName = lists[card.idList] || 'Unknown';
    const status = mapListToStatus(listName);
    const tags = mapLabelsToTags(card.labels || []);
    const assigneeId = tryMatchMember(
      board.members || [],
      card.idMembers || [],
      board.members || [],
      dbMembers
    );

    const labels = (card.labels || []).map((l: any) => ({
      name: l.name,
      color: l.color,
    }));

    const attachments = (card.attachments || []).map((a: any) => ({
      name: a.name,
      url: a.url,
    }));

    const checklists: any[] = [];
    for (const clId of (card.idChecklists || [])) {
      const cl = (board.checklists || []).find((c: any) => c.id === clId);
      if (cl) {
        checklists.push({
          name: cl.name,
          items: (cl.checkItems || []).map((ci: any) => ({
            name: ci.name,
            complete: ci.state === 'complete',
          })),
        });
      }
    }

    if (DRY_RUN) {
      console.log(`  [DRY] ${card.name?.substring(0, 60)} | ${listName} -> ${status} | tags: ${tags.join(',')}`);
      mapped++;
      continue;
    }

    const { data: existing } = await sb
      .from('board_items')
      .select('id')
      .eq('source_card_id', card.id)
      .eq('source_board', config.boardSource)
      .maybeSingle();

    if (existing) { skipped++; continue; }

    const { error: insertErr } = await sb.from('board_items').insert({
      board_id: projectBoardId,
      title: card.name || 'Untitled',
      description: card.desc || null,
      status,
      assignee_id: assigneeId,
      tags,
      labels: JSON.stringify(labels),
      due_date: card.due ? card.due.split('T')[0] : null,
      position: i,
      source_card_id: card.id,
      source_board: config.boardSource,
      cycle: config.cycle,
      attachments: JSON.stringify(attachments),
      checklist: JSON.stringify(checklists),
    });

    if (insertErr) {
      console.error(`  ERROR inserting card "${card.name?.substring(0, 40)}": ${insertErr.message}`);
      skipped++;
    } else {
      mapped++;
    }
  }

  if (!DRY_RUN) {
    await sb.from('trello_import_log').insert({
      board_name: boardName,
      board_source: config.boardSource,
      cards_total: cards.length,
      cards_mapped: mapped,
      cards_skipped: skipped,
      target_table: 'board_items',
      notes: `Imported via trello_board_importer.ts. Board ID: ${projectBoardId}`,
    });
  }

  console.log(`  Result: ${mapped} mapped, ${skipped} skipped (of ${cards.length} total)`);
  return { total: cards.length, mapped, skipped };
}

async function main() {
  console.log(`Trello Board Importer${DRY_RUN ? ' (DRY RUN)' : ''}`);
  console.log(`========================================`);

  const dbMembers = await loadMembers();
  console.log(`Loaded ${dbMembers.size} member name/email entries for matching`);

  let grandTotal = 0, grandMapped = 0, grandSkipped = 0;

  for (const config of BOARDS) {
    const result = await importBoard(config, dbMembers);
    grandTotal += result.total;
    grandMapped += result.mapped;
    grandSkipped += result.skipped;
  }

  console.log(`\n========================================`);
  console.log(`GRAND TOTAL: ${grandMapped} mapped, ${grandSkipped} skipped (of ${grandTotal} cards across ${BOARDS.length} boards)`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
