/**
 * Trello Comms Board Merger
 *
 * Reads two Trello JSON exports for the Communication team:
 *   - 8DSPL6eu - comunicacao-ciclo-3-nucleo-ia-gp.json
 *   - zH82r9ai - midias-sociais-nucleo-ia-gestao-de-projetos.json
 *
 * Merges cards from both boards and inserts them into the Communication
 * tribe's active project_board in Supabase as board_items.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/import_comms_trello.mjs [--dry-run]
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
const TRELLO_DIR = resolve(SENSITIVE_ROOT, 'Trello');

const TRELLO_FILES = [
  {
    file: '8DSPL6eu - comunicacao-ciclo-3-nucleo-ia-gp.json',
    source: 'comunicacao_ciclo3',
    label: 'Comunicação Ciclo 3',
  },
  {
    file: 'zH82r9ai - midias-sociais-nucleo-ia-gestao-de-projetos.json',
    source: 'midias_sociais',
    label: 'Mídias Sociais',
  },
];

const LIST_STATUS_MAP = {
  'materiais de apoio': 'backlog',
  'estratégico | materiais de apoio': 'backlog',
  'ideação': 'backlog',
  'backlog': 'backlog',
  'membros da equipe': 'backlog',
  'pauta de reunião': 'backlog',
  'início e organização': 'todo',
  'planejados': 'todo',
  'design': 'in_progress',
  'redação': 'in_progress',
  'edição': 'in_progress',
  'estruturação do conteúdo': 'in_progress',
  'conteúdo elaborado': 'in_progress',
  'revisão estratégica': 'review',
  'validação gp': 'review',
  'validação': 'review',
  'validação e ajustes': 'review',
  'publicação': 'done',
  'publicação conteúdo': 'done',
  'concluído': 'done',
  'concluido': 'done',
  'social media marketing': 'done',
  'done': 'done',
  'monitoramento & análise': 'done',
};

function mapListToStatus(listName) {
  return LIST_STATUS_MAP[listName.toLowerCase().trim()] || 'backlog';
}

function mapLabelsToTags(labels) {
  return (labels || [])
    .filter(l => l.name && l.name.trim())
    .map(l => l.name.toLowerCase().trim().replace(/\s+/g, '_'));
}

async function loadMembers() {
  const { data } = await sb.from('members').select('id, name, email');
  const map = new Map();
  if (data) {
    for (const m of data) {
      if (m.email) map.set(m.email.toLowerCase(), m.id);
      if (m.name) map.set(m.name.toLowerCase(), m.id);
    }
  }
  return map;
}

function tryMatchMember(cardMemberIds, allTrelloMembers, dbMembers) {
  for (const tmId of cardMemberIds) {
    const tm = allTrelloMembers.find(m => m.id === tmId);
    if (!tm) continue;
    const byName = dbMembers.get(tm.fullName.toLowerCase());
    if (byName) return byName;
  }
  return null;
}

async function findOrCreateCommsBoard() {
  const { data: commsTribe } = await sb
    .from('tribes')
    .select('id, name')
    .or('name.ilike.%comunica%,name.ilike.%comms%,workstream_type.eq.operational')
    .order('id')
    .limit(5);

  let commsTribeId = null;
  if (commsTribe && commsTribe.length > 0) {
    const match = commsTribe.find(t =>
      /comunica|comms/i.test(t.name)
    ) || commsTribe[0];
    commsTribeId = match.id;
    console.log(`Found Communication tribe: id=${match.id}, name="${match.name}"`);
  }

  if (!commsTribeId) {
    console.log('No Communication tribe found. Checking tribe 8 as fallback...');
    const { data: t8 } = await sb.from('tribes').select('id, name').eq('id', 8).maybeSingle();
    if (t8) {
      commsTribeId = 8;
      console.log(`Using tribe 8: "${t8.name}"`);
    }
  }

  if (!commsTribeId) {
    console.error('ERROR: No communication tribe found. Create one first:');
    console.error(`  INSERT INTO tribes (name, is_active, workstream_type) VALUES ('Comunicação', true, 'operational');`);
    process.exit(1);
  }

  const { data: existingBoard } = await sb
    .from('project_boards')
    .select('id, board_name')
    .eq('tribe_id', commsTribeId)
    .eq('is_active', true)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existingBoard) {
    console.log(`Using existing board: ${existingBoard.id} ("${existingBoard.board_name}")`);
    return { boardId: existingBoard.id, tribeId: commsTribeId };
  }

  if (DRY_RUN) {
    console.log('[DRY] Would create new Communication board');
    return { boardId: 'dry-run-id', tribeId: commsTribeId };
  }

  const { data: newBoard, error } = await sb
    .from('project_boards')
    .insert({
      board_name: 'Comunicação — Board Consolidado',
      tribe_id: commsTribeId,
      source: 'trello_merge',
      domain_key: 'comms_consolidated',
      columns: JSON.stringify(['backlog', 'todo', 'in_progress', 'review', 'done']),
      is_active: true,
    })
    .select('id')
    .single();

  if (error) {
    console.error(`ERROR creating board: ${error.message}`);
    process.exit(1);
  }

  console.log(`Created Communication board: ${newBoard.id}`);
  return { boardId: newBoard.id, tribeId: commsTribeId };
}

function parseTrelloBoard(filePath) {
  const raw = readFileSync(filePath, 'utf-8');
  const board = JSON.parse(raw);

  const lists = {};
  for (const l of board.lists || []) {
    lists[l.id] = l.name;
  }

  const cards = (board.cards || [])
    .filter(c => !c.closed)
    .map(card => {
      const listName = lists[card.idList] || 'Unknown';
      const status = mapListToStatus(listName);
      const tags = mapLabelsToTags(card.labels || []);

      const labels = (card.labels || []).map(l => ({
        name: l.name,
        color: l.color,
      }));

      const attachments = (card.attachments || []).map(a => ({
        name: a.name,
        url: a.url,
      }));

      const checklists = [];
      for (const clId of (card.idChecklists || [])) {
        const cl = (board.checklists || []).find(c => c.id === clId);
        if (cl) {
          checklists.push({
            name: cl.name,
            items: (cl.checkItems || []).map(ci => ({
              name: ci.name,
              complete: ci.state === 'complete',
            })),
          });
        }
      }

      return {
        trelloId: card.id,
        title: card.name || 'Untitled',
        description: card.desc || null,
        listName,
        status,
        tags,
        labels,
        dueDate: card.due ? card.due.split('T')[0] : null,
        memberIds: card.idMembers || [],
        attachments,
        checklists,
      };
    });

  return {
    boardName: board.name,
    members: board.members || [],
    cards,
  };
}

async function main() {
  console.log(`Trello Comms Board Merger${DRY_RUN ? ' (DRY RUN)' : ''}`);
  console.log('========================================');

  if (!existsSync(TRELLO_DIR)) {
    console.error(`Trello directory not found: ${TRELLO_DIR}`);
    console.error('Set SENSITIVE_ROOT or ensure Sensitive/Trello/ exists.');
    process.exit(1);
  }

  const dbMembers = await loadMembers();
  console.log(`Loaded ${dbMembers.size} member entries for matching`);

  const { boardId, tribeId } = await findOrCreateCommsBoard();

  let allCards = [];
  let allTrelloMembers = [];

  for (const config of TRELLO_FILES) {
    const filePath = resolve(TRELLO_DIR, config.file);
    if (!existsSync(filePath)) {
      console.warn(`  WARN: File not found, skipping: ${config.file}`);
      continue;
    }

    const parsed = parseTrelloBoard(filePath);
    console.log(`\n${config.label}: "${parsed.boardName}"`);
    console.log(`  Cards: ${parsed.cards.length}, Members: ${parsed.members.length}`);

    for (const card of parsed.cards) {
      card.sourceBoard = config.source;
      card.sourceLabel = config.label;
    }

    allCards.push(...parsed.cards);
    allTrelloMembers.push(...parsed.members);
  }

  const seen = new Set();
  const uniqueMembers = allTrelloMembers.filter(m => {
    if (seen.has(m.id)) return false;
    seen.add(m.id);
    return true;
  });

  const dedupCards = [];
  const titleSeen = new Set();
  for (const card of allCards) {
    const key = card.title.toLowerCase().trim();
    if (titleSeen.has(key)) continue;
    titleSeen.add(key);
    dedupCards.push(card);
  }

  console.log(`\nTotal cards: ${allCards.length}, After dedup: ${dedupCards.length}`);

  let imported = 0;
  let skipped = 0;

  for (let i = 0; i < dedupCards.length; i++) {
    const card = dedupCards[i];
    const assigneeId = tryMatchMember(card.memberIds, uniqueMembers, dbMembers);

    if (DRY_RUN) {
      console.log(`  [DRY] ${card.title.substring(0, 60)} | ${card.listName} -> ${card.status} | from: ${card.sourceLabel}`);
      imported++;
      continue;
    }

    const { data: dup } = await sb
      .from('board_items')
      .select('id')
      .eq('source_card_id', card.trelloId)
      .eq('source_board', card.sourceBoard)
      .maybeSingle();

    if (dup) {
      skipped++;
      continue;
    }

    const { error: insertErr } = await sb.from('board_items').insert({
      board_id: boardId,
      title: card.title,
      description: card.description,
      status: card.status,
      curation_status: 'draft',
      assignee_id: assigneeId,
      tags: [...card.tags, 'comms_import', card.sourceBoard],
      labels: JSON.stringify(card.labels),
      due_date: card.dueDate,
      position: i,
      source_card_id: card.trelloId,
      source_board: card.sourceBoard,
      cycle: 3,
      attachments: JSON.stringify(card.attachments),
      checklist: JSON.stringify(card.checklists),
    });

    if (insertErr) {
      console.error(`  ERROR: ${card.title.substring(0, 40)}: ${insertErr.message}`);
      skipped++;
    } else {
      imported++;
    }
  }

  console.log('\n========================================');
  console.log(`Result: ${imported} imported, ${skipped} skipped (of ${dedupCards.length} unique cards)`);
  console.log(`Target: tribe_id=${tribeId}, board_id=${boardId}`);

  if (!DRY_RUN && boardId !== 'dry-run-id') {
    await sb.from('trello_import_log').insert({
      board_name: 'Comunicação — Merged',
      board_source: 'comms_trello_merge',
      cards_total: dedupCards.length,
      cards_mapped: imported,
      cards_skipped: skipped,
      target_table: 'board_items',
      notes: `Merged from ${TRELLO_FILES.map(f => f.source).join(' + ')}. Board ID: ${boardId}`,
    });
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
