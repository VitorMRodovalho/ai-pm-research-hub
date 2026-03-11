/**
 * Notion normalization importer for local Sensitive exports.
 *
 * Reads local files from Sensitive/Notion*, normalizes records, and stores them
 * in notion_import_staging for controlled board mapping.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/notion_normalize_import.ts --mode=dry_run
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/notion_normalize_import.ts --mode=apply
 */

import 'dotenv/config';
import { readdirSync, statSync } from 'fs';
import { basename, join } from 'path';
import { createClient } from '@supabase/supabase-js';
import { getSensitiveRoot } from './shared/paths';

type Mode = 'dry_run' | 'apply';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const MODE = (process.argv.find((arg) => arg.startsWith('--mode='))?.split('=')[1] || 'dry_run') as Mode;

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function findNotionFiles(root: string): string[] {
  const entries = readdirSync(root, { withFileTypes: true });
  const notionDirs = entries
    .filter((e) => e.isDirectory() && e.name.toLowerCase().startsWith('notion'))
    .map((e) => join(root, e.name));
  const out: string[] = [];
  for (const dir of notionDirs) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (!entry.isFile()) continue;
      const full = join(dir, entry.name);
      const size = statSync(full).size;
      if (size <= 0) continue;
      out.push(full);
    }
  }
  return out;
}

function normalizeTitle(name: string): string {
  return name.replace(/\.(csv|md|markdown|txt|json)$/i, '').replace(/[_-]+/g, ' ').trim();
}

async function main() {
  const sensitiveRoot = getSensitiveRoot();
  const files = findNotionFiles(sensitiveRoot);
  console.log(`[notion] files detected: ${files.length}`);

  let batchId: string | null = null;
  if (MODE === 'apply') {
    const { data, error } = await sb.rpc('admin_start_ingestion_batch', {
      p_source: 'notion',
      p_mode: MODE,
      p_notes: 'Notion normalization staging import',
    });
    if (error || !data) {
      console.error('[notion] failed to open batch', error?.message || 'unknown');
      process.exit(1);
    }
    batchId = data;
  }

  let inserted = 0;
  for (const filePath of files) {
    const title = normalizeTitle(basename(filePath));
    const payload = {
      batch_id: batchId,
      source_file: filePath.replace(`${sensitiveRoot}/`, ''),
      source_page: title,
      external_item_id: null,
      title,
      description: `Imported from Notion export file: ${basename(filePath)}`,
      status_raw: null,
      assignee_name: null,
      tags: ['notion_import'],
      due_date: null,
      tribe_hint: null,
      chapter_hint: null,
      confidence_score: 0.4,
      normalized: { mode: MODE, filename: basename(filePath) },
    };

    if (MODE === 'dry_run') {
      console.log('[dry-run] stage', payload.source_file);
      continue;
    }

    const { error } = await sb.from('notion_import_staging').insert(payload);
    if (error) {
      if (error.code === '23505') continue;
      console.warn('[notion] stage failed', payload.source_file, error.message);
      continue;
    }
    inserted += 1;
  }

  if (MODE === 'apply' && batchId) {
    await sb.rpc('admin_finalize_ingestion_batch', {
      p_batch_id: batchId,
      p_status: 'completed',
      p_summary: {
        source: 'notion',
        files_detected: files.length,
        rows_staged: inserted,
      },
    });
  }
  console.log(`[notion] done (${MODE})`);
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
