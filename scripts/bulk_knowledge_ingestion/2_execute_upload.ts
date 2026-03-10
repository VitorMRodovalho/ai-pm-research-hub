/**
 * PHASE 2: Bulk Upload to Supabase Storage + hub_resources INSERT
 *
 * Reads upload_manifest.json from Phase 1, uploads each file to the
 * Supabase Storage `documents` bucket, then inserts a record into
 * hub_resources with source='bulk-drive-import' and curation_status='approved'.
 *
 * Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env or environment.
 *
 * Usage: npx tsx scripts/bulk_knowledge_ingestion/2_execute_upload.ts [--dry-run]
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { createClient } from '@supabase/supabase-js';

// ── Configuration ──────────────────────────────────────────────────────────

// Support --manifest flag to use curated manifest
const manifestArg = process.argv.find(a => a.startsWith('--manifest'));
const manifestFile = manifestArg
  ? manifestArg.includes('=') ? manifestArg.split('=')[1] : process.argv[process.argv.indexOf(manifestArg) + 1]
  : 'upload_manifest.json';
const MANIFEST_PATH = path.resolve('./scripts/bulk_knowledge_ingestion/' + manifestFile);
const STAGING_DIR = path.resolve('./data/staging-knowledge');
const LOG_DIR = path.resolve('./data/ingestion-logs');
const BUCKET = 'documents';
const CONCURRENCY_DELAY_MS = 500; // 2 files/second to respect API limits
const BATCH_LOG_INTERVAL = 10;

// ── Environment ────────────────────────────────────────────────────────────

function loadEnv() {
  const envPath = path.resolve('.env');
  if (fs.existsSync(envPath)) {
    const lines = fs.readFileSync(envPath, 'utf-8').split('\n');
    for (const line of lines) {
      const match = line.match(/^([A-Z_]+)=(.+)$/);
      if (match) process.env[match[1]] = match[2].replace(/^["']|["']$/g, '');
    }
  }
}

loadEnv();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '';
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!SUPABASE_URL || !SUPABASE_SRK) {
  console.error('ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.');
  console.error('Set them in .env or export them before running.');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_SRK);

// ── Types ──────────────────────────────────────────────────────────────────

interface ManifestEntry {
  sha256: string;
  originalPaths: string[];
  stagingFilename: string;
  storagePath: string;
  title: string;
  assetType: string;
  suggestedTags: string[];
  category: 'geral' | 'adm';
  sizeBytes: number;
  extension: string;
}

interface UploadResult {
  sha256: string;
  filename: string;
  status: 'uploaded' | 'skipped' | 'failed';
  storageUrl?: string;
  resourceId?: string;
  error?: string;
}

// ── MIME type mapping ──────────────────────────────────────────────────────

function getMimeType(ext: string): string {
  const map: Record<string, string> = {
    '.pdf': 'application/pdf',
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.doc': 'application/msword',
    '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.csv': 'text/csv',
    '.txt': 'text/plain',
    '.markdown': 'text/markdown',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.mp4': 'video/mp4',
    '.mp3': 'audio/mpeg',
    '.webm': 'video/webm',
  };
  return map[ext] || 'application/octet-stream';
}

// ── Sleep utility ──────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ── Main ───────────────────────────────────────────────────────────────────

async function main() {
  const dryRun = process.argv.includes('--dry-run');

  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log(`║  PHASE 2: Bulk Upload ${dryRun ? '(DRY RUN)' : '(LIVE)'}`.padEnd(63) + '║');
  console.log('╚══════════════════════════════════════════════════════════════╝');

  if (!fs.existsSync(MANIFEST_PATH)) {
    console.error('ERROR: upload_manifest.json not found. Run Phase 1 first.');
    process.exit(1);
  }

  const manifest: ManifestEntry[] = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf-8'));
  console.log(`\n📋 Manifest loaded: ${manifest.length} files`);

  fs.mkdirSync(LOG_DIR, { recursive: true });
  const results: UploadResult[] = [];
  let uploaded = 0;
  let skipped = 0;
  let failed = 0;

  for (let i = 0; i < manifest.length; i++) {
    const entry = manifest[i];
    const localPath = path.join(STAGING_DIR, entry.stagingFilename);

    if (!fs.existsSync(localPath)) {
      console.warn(`   ⚠ Missing staging file: ${entry.stagingFilename}`);
      results.push({ sha256: entry.sha256, filename: entry.stagingFilename, status: 'failed', error: 'File not in staging' });
      failed++;
      continue;
    }

    if (dryRun) {
      console.log(`   [DRY] Would upload: ${entry.storagePath} (${(entry.sizeBytes / 1024).toFixed(1)} KB, tags: ${entry.suggestedTags.join(', ')})`);
      results.push({ sha256: entry.sha256, filename: entry.stagingFilename, status: 'skipped' });
      skipped++;
      continue;
    }

    try {
      // 1. Upload to Storage
      const fileBuffer = fs.readFileSync(localPath);
      const { data: uploadData, error: uploadError } = await sb.storage
        .from(BUCKET)
        .upload(entry.storagePath, fileBuffer, {
          contentType: getMimeType(entry.extension),
          upsert: true,
        });

      if (uploadError) {
        console.error(`   ✗ Upload failed: ${entry.stagingFilename} — ${uploadError.message}`);
        results.push({ sha256: entry.sha256, filename: entry.stagingFilename, status: 'failed', error: uploadError.message });
        failed++;
        await sleep(CONCURRENCY_DELAY_MS);
        continue;
      }

      const { data: urlData } = sb.storage.from(BUCKET).getPublicUrl(entry.storagePath);
      const publicUrl = urlData?.publicUrl || '';

      // 2. INSERT into hub_resources
      const tribeId = inferTribeId(entry.suggestedTags);
      const { data: insertData, error: insertError } = await sb.from('hub_resources').insert({
        title: entry.title,
        asset_type: entry.assetType,
        url: publicUrl,
        description: `Imported from Drive (${entry.category}). Original: ${path.basename(entry.originalPaths[0])}`,
        tribe_id: tribeId,
        source: 'bulk-drive-import',
        curation_status: 'approved',
        tags: entry.suggestedTags,
        is_active: true,
      }).select('id').single();

      if (insertError) {
        console.error(`   ✗ DB insert failed: ${entry.stagingFilename} — ${insertError.message}`);
        results.push({ sha256: entry.sha256, filename: entry.stagingFilename, status: 'failed', error: insertError.message, storageUrl: publicUrl });
        failed++;
      } else {
        uploaded++;
        results.push({
          sha256: entry.sha256,
          filename: entry.stagingFilename,
          status: 'uploaded',
          storageUrl: publicUrl,
          resourceId: insertData?.id,
        });
      }

      if ((i + 1) % BATCH_LOG_INTERVAL === 0) {
        console.log(`   📤 ${i + 1}/${manifest.length} processed (${uploaded} ok, ${failed} err)`);
      }

      await sleep(CONCURRENCY_DELAY_MS);

    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`   ✗ Exception: ${entry.stagingFilename} — ${msg}`);
      results.push({ sha256: entry.sha256, filename: entry.stagingFilename, status: 'failed', error: msg });
      failed++;
    }
  }

  // Log to broadcast_log for audit trail
  if (!dryRun && uploaded > 0) {
    try {
      await sb.from('broadcast_log').insert({
        tribe_id: null,
        sender_id: null,
        subject: 'Bulk Knowledge Ingestion — Phase 2',
        body: `${uploaded} files uploaded to Storage and inserted into hub_resources. ${failed} failures.`,
        recipient_count: uploaded,
        status: failed === 0 ? 'sent' : 'failed',
        error_detail: failed > 0 ? `${failed} files failed` : null,
      });
    } catch (_) { /* non-critical */ }
  }

  // Write detailed log
  const logFile = path.join(LOG_DIR, `phase2_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(logFile, JSON.stringify({
    timestamp: new Date().toISOString(),
    dryRun,
    totalManifest: manifest.length,
    uploaded,
    skipped,
    failed,
    results,
  }, null, 2), 'utf-8');

  // Summary
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log(`║  PHASE 2 ${dryRun ? 'DRY RUN' : 'COMPLETE'}`.padEnd(63) + '║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Total in manifest:      ${String(manifest.length).padStart(6)}`);
  console.log(`║  Uploaded successfully:   ${String(uploaded).padStart(6)}`);
  console.log(`║  Skipped (dry run):       ${String(skipped).padStart(6)}`);
  console.log(`║  Failed:                  ${String(failed).padStart(6)}`);
  console.log(`║  Log:                     ${logFile}`);
  console.log('╚══════════════════════════════════════════════════════════════╝');
}

function inferTribeId(tags: string[]): number | null {
  for (const tag of tags) {
    const match = tag.match(/^tribo-(\d{1,2})$/);
    if (match) return parseInt(match[1], 10);
  }
  return null;
}

main().catch(err => {
  console.error('FATAL:', err);
  process.exit(1);
});
