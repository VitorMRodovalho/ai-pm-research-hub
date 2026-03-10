/**
 * Wave 7 -- Miro Board Links Importer
 *
 * Parses the Miro board CSV export (section headers + links),
 * extracts URL resources, and inserts into `hub_resources`
 * with source='miro_import'. Deduplicates by URL.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/miro_links_importer.ts [--dry-run]
 */

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

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

const MIRO_CSV_PATH = '/home/vitormrodovalho/Downloads/data/raw-drive-exports/Sensitive/Miro board - Núcleo IA - Geral.csv';

const SECTION_ASSET_TYPE: Record<string, string> = {
  'videos': 'reference',
  'assistentes': 'other',
  'artigos': 'reference',
  'livros': 'reference',
  'cursos': 'course',
  'notícias': 'reference',
  'noticias': 'reference',
  'centro de eventos': 'webinar',
  'retrospectivas': 'webinar',
  'referencias': 'reference',
  'plataforma': 'other',
};

const SECTION_TAGS: Record<string, string[]> = {
  'videos': ['video', 'miro_library'],
  'assistentes': ['ai_tool', 'miro_library'],
  'artigos': ['article', 'miro_library'],
  'livros': ['book', 'miro_library'],
  'cursos': ['course', 'miro_library'],
  'notícias': ['news', 'miro_library'],
  'noticias': ['news', 'miro_library'],
  'centro de eventos': ['event', 'miro_library'],
  'retrospectivas': ['retrospective', 'miro_library'],
  'referencias': ['reference', 'miro_library'],
  'plataforma': ['platform', 'miro_library'],
};

interface MiroItem {
  title: string;
  url: string;
  section: string;
  assetType: string;
  tags: string[];
}

function parseMiroCSV(content: string): MiroItem[] {
  const lines = content.split(/\r?\n/);
  const items: MiroItem[] = [];
  let currentSection = 'other';

  const knownSections = new Set([
    'biblioteca', 'videos', 'assistentes', 'artigos', 'livros',
    'cursos', 'notícias', 'noticias', 'centro de eventos',
    'retrospectivas', 'prefeitura', 'tribo 3', 'plataforma',
    'referencias', 'info do projeto', 'cronograma',
    'artigo (ciclo 2)',
  ]);

  for (const rawLine of lines) {
    const line = rawLine.replace(/^"|"$/g, '').trim();
    if (!line) continue;

    const lowerLine = line.toLowerCase();
    if (knownSections.has(lowerLine)) {
      currentSection = lowerLine;
      continue;
    }

    const urlMatch = line.match(/https?:\/\/[^\s,"]+/);
    if (!urlMatch) continue;

    const url = urlMatch[0].replace(/[,\s]+$/, '');

    let title = line;
    const csvParts = rawLine.split('","');
    if (csvParts.length >= 2) {
      title = csvParts[0].replace(/^"/, '').trim();
    }
    if (title === url || title.startsWith('http')) {
      try {
        const u = new URL(url);
        title = u.hostname.replace('www.', '') + u.pathname.split('/').filter(Boolean).slice(0, 2).join(' - ');
      } catch {
        title = url.substring(0, 80);
      }
    }
    title = title.substring(0, 200);

    const assetType = SECTION_ASSET_TYPE[currentSection] || 'other';
    const tags = SECTION_TAGS[currentSection] || ['miro_library'];

    items.push({ title, url, section: currentSection, assetType, tags });
  }

  return items;
}

function dedup(items: MiroItem[]): MiroItem[] {
  const seen = new Set<string>();
  return items.filter(item => {
    const key = item.url.split('?')[0].split('#')[0].replace(/\/+$/, '');
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function main() {
  console.log(`Miro Links Importer${DRY_RUN ? ' (DRY RUN)' : ''}`);
  console.log(`========================================`);

  const content = readFileSync(MIRO_CSV_PATH, 'utf-8');
  const allItems = parseMiroCSV(content);
  console.log(`Parsed ${allItems.length} items with URLs`);

  const items = dedup(allItems);
  console.log(`After dedup: ${items.length} unique URLs`);

  const sectionCounts: Record<string, number> = {};
  for (const item of items) {
    sectionCounts[item.section] = (sectionCounts[item.section] || 0) + 1;
  }
  console.log('By section:', JSON.stringify(sectionCounts, null, 2));

  let imported = 0, skipped = 0;

  for (const item of items) {
    if (DRY_RUN) {
      console.log(`  [DRY] ${item.title.substring(0, 60)} | ${item.assetType} | ${item.section}`);
      imported++;
      continue;
    }

    const { data: existing } = await sb
      .from('hub_resources')
      .select('id')
      .eq('url', item.url)
      .maybeSingle();

    if (existing) {
      skipped++;
      continue;
    }

    const { error } = await sb.from('hub_resources').insert({
      asset_type: item.assetType,
      title: item.title,
      description: `Imported from Miro board (${item.section})`,
      url: item.url,
      is_active: true,
      source: 'miro_import',
      tags: item.tags,
    });

    if (error) {
      console.error(`  ERROR: ${item.title.substring(0, 40)}: ${error.message}`);
      skipped++;
    } else {
      imported++;
    }
  }

  console.log(`\n========================================`);
  console.log(`Result: ${imported} imported, ${skipped} skipped (of ${items.length} unique items)`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
