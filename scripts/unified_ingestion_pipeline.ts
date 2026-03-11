/**
 * Unified ingestion pipeline orchestrator.
 *
 * Scans local Sensitive exports, builds a manifest, and registers ingestion
 * batches/files in Supabase for auditable execution.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/unified_ingestion_pipeline.ts --mode=dry_run
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/unified_ingestion_pipeline.ts --mode=apply
 */

import 'dotenv/config';
import { createHash } from 'crypto';
import { readdirSync, readFileSync, statSync } from 'fs';
import { basename, extname, join, relative } from 'path';
import { createClient } from '@supabase/supabase-js';
import { getSensitiveRoot } from './shared/paths';

type IngestionMode = 'dry_run' | 'apply';

type ManifestItem = {
  sourceKind: 'trello' | 'miro' | 'calendar' | 'volunteer_csv' | 'notion' | 'whatsapp' | 'other';
  filePath: string;
  fileSizeBytes: number;
  fileHash: string;
  shouldIngest: boolean;
  reason: string;
};

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const MODE = (process.argv.find((arg) => arg.startsWith('--mode='))?.split('=')[1] || 'dry_run') as IngestionMode;

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

if (!['dry_run', 'apply'].includes(MODE)) {
  console.error(`Invalid mode: ${MODE}. Use --mode=dry_run or --mode=apply`);
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function walkFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walkFiles(full));
    else out.push(full);
  }
  return out;
}

function hashFile(path: string): string {
  const hash = createHash('sha256');
  hash.update(readFileSync(path));
  return hash.digest('hex');
}

function inferSourceKind(filePath: string): ManifestItem['sourceKind'] {
  const low = filePath.toLowerCase();
  if (low.includes('/trello/')) return 'trello';
  if (low.includes('/whatsapp groups/')) return 'whatsapp';
  if (low.endsWith('.ics')) return 'calendar';
  if (low.endsWith('.csv') && low.includes('export voluntarios inscritos')) return 'volunteer_csv';
  if (low.includes('/notion')) return 'notion';
  if (low.includes('miro') && low.endsWith('.csv')) return 'miro';
  return 'other';
}

function ingestionRule(kind: ManifestItem['sourceKind'], filePath: string): Pick<ManifestItem, 'shouldIngest' | 'reason'> {
  if (kind === 'whatsapp') {
    return {
      shouldIngest: false,
      reason: 'blocked_by_policy_whatsapp_manual_only',
    };
  }
  if (kind === 'other') {
    return {
      shouldIngest: false,
      reason: 'unknown_source_kind',
    };
  }
  if (basename(filePath).startsWith('.')) {
    return {
      shouldIngest: false,
      reason: 'hidden_file',
    };
  }
  return { shouldIngest: true, reason: 'eligible' };
}

function buildManifest(sensitiveRoot: string): ManifestItem[] {
  const files = walkFiles(sensitiveRoot);
  return files.map((filePath) => {
    const sourceKind = inferSourceKind(filePath);
    const { shouldIngest, reason } = ingestionRule(sourceKind, filePath);
    const st = statSync(filePath);
    return {
      sourceKind,
      filePath,
      fileSizeBytes: st.size,
      fileHash: hashFile(filePath),
      shouldIngest,
      reason,
    };
  });
}

async function main() {
  const sensitiveRoot = getSensitiveRoot();
  const manifest = buildManifest(sensitiveRoot);

  const stats = manifest.reduce((acc, item) => {
    acc.total += 1;
    acc.byKind[item.sourceKind] = (acc.byKind[item.sourceKind] || 0) + 1;
    if (item.shouldIngest) acc.eligible += 1;
    else acc.blocked += 1;
    return acc;
  }, { total: 0, eligible: 0, blocked: 0, byKind: {} as Record<string, number> });

  const summary = {
    sensitiveRoot,
    mode: MODE,
    totalFiles: stats.total,
    eligibleFiles: stats.eligible,
    blockedFiles: stats.blocked,
    byKind: stats.byKind,
  };

  console.log('[ingestion] summary', JSON.stringify(summary, null, 2));

  const { data: batchId, error: batchErr } = await sb.rpc('admin_start_ingestion_batch', {
    p_source: 'mixed',
    p_mode: MODE,
    p_notes: 'Unified ingestion pipeline run',
  });

  if (batchErr || !batchId) {
    console.error('[ingestion] failed to start batch', batchErr?.message || 'unknown_error');
    process.exit(1);
  }

  for (const item of manifest) {
    const payload = {
      batch_id: batchId,
      source_kind: item.sourceKind,
      file_path: relative(sensitiveRoot, item.filePath),
      file_hash: item.fileHash,
      file_size_bytes: item.fileSizeBytes,
      status: item.shouldIngest ? (MODE === 'apply' ? 'processed' : 'queued') : 'skipped',
      result: {
        mode: MODE,
        shouldIngest: item.shouldIngest,
        reason: item.reason,
        extension: extname(item.filePath),
      },
    };

    const { error } = await sb.from('ingestion_batch_files').upsert(payload, {
      onConflict: 'batch_id,file_path',
      ignoreDuplicates: false,
    });
    if (error) {
      console.warn('[ingestion] file log failed', payload.file_path, error.message);
    }
  }

  const { error: doneErr } = await sb.rpc('admin_finalize_ingestion_batch', {
    p_batch_id: batchId,
    p_status: 'completed',
    p_summary: summary,
  });

  if (doneErr) {
    console.error('[ingestion] failed to finalize batch', doneErr.message);
    process.exit(1);
  }

  console.log(`[ingestion] batch completed: ${batchId}`);
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
