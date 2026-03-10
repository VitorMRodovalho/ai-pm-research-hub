/**
 * PHASE 1: Prepare, Deduplicate & Map files from Drive exports
 *
 * Reads ONLY geral/ and adm/ folders. NEVER touches sensitive/.
 * Generates SHA-256 hashes, deduplicates, sanitizes names, copies
 * unique files to staging, and produces upload_manifest.json.
 *
 * Usage: npx tsx scripts/bulk_knowledge_ingestion/1_prepare_files.ts
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';

// ── Configuration ──────────────────────────────────────────────────────────

const RAW_BASE = path.resolve('./data/raw-drive-exports');
const STAGING_DIR = path.resolve('./data/staging-knowledge');
const MANIFEST_PATH = path.resolve('./scripts/bulk_knowledge_ingestion/upload_manifest.json');
const LOG_DIR = path.resolve('./data/ingestion-logs');

const SOURCE_DIRS: { dir: string; category: 'geral' | 'adm' }[] = [
  { dir: path.join(RAW_BASE, 'Núcleo IA & GP'), category: 'geral' },
  { dir: path.join(RAW_BASE, 'Nucleo IA PMI-GO-CE - Adm'), category: 'adm' },
];

const ALLOWED_EXTENSIONS = new Set([
  '.pdf', '.docx', '.pptx', '.xlsx', '.png', '.jpg', '.jpeg',
  '.txt', '.csv', '.markdown', '.doc', '.mp4', '.mp3', '.webm',
]);

const BLOCKED_EXTENSIONS = new Set([
  '.vcf', '.zip', '.exe', '.bat', '.sh', '.env', '.json', '.mpp',
  '.vsdx', '.heic', '.drawio', '.sbv', '.wav',
]);

// ── Utilities ──────────────────────────────────────────────────────────────

function sha256(filePath: string): string {
  const buf = fs.readFileSync(filePath);
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function sanitizeName(name: string): string {
  return name
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // strip accents
    .replace(/[^a-zA-Z0-9.\-_]/g, '-')               // non-alnum → dash
    .replace(/-{2,}/g, '-')                            // collapse dashes
    .replace(/^-|-$/g, '')                             // trim dashes
    .toLowerCase();
}

function inferTags(filePath: string, category: 'geral' | 'adm'): string[] {
  const tags: string[] = [];
  const lower = filePath.toLowerCase();

  if (category === 'adm') tags.push('governance');

  // Tribe detection
  const tribeMatch = lower.match(/tribo[\s_-]*(\d{1,2})/);
  if (tribeMatch) tags.push(`tribo-${tribeMatch[1].padStart(2, '0')}`);

  // Cycle detection
  if (lower.includes('ciclo 1') || lower.includes('ciclo-1')) tags.push('ciclo-1');
  if (lower.includes('ciclo 2') || lower.includes('ciclo-2')) tags.push('ciclo-2');
  if (lower.includes('ciclo 3') || lower.includes('ciclo-3')) tags.push('ciclo-3');

  // Content type detection
  if (lower.includes('referencia') || lower.includes('referencias')) tags.push('referencias');
  if (lower.includes('artigo') || lower.includes('article')) tags.push('article');
  if (lower.includes('ata') || lower.includes('minuta') || lower.includes('minutes')) tags.push('meeting_minutes');
  if (lower.includes('relatorio') || lower.includes('report')) tags.push('report');
  if (lower.includes('acordo') || lower.includes('cooperacao')) tags.push('cooperation');
  if (lower.includes('modelo') || lower.includes('template')) tags.push('framework');
  if (lower.includes('webinar')) tags.push('webinar');
  if (lower.includes('apresenta') || lower.includes('presentation')) tags.push('presentation');
  if (lower.includes('pausada') || lower.includes('archive')) tags.push('archived');

  // Folder-based context
  const parts = filePath.split(path.sep);
  for (const p of parts) {
    const pl = p.toLowerCase();
    if (pl.includes('quadrante')) {
      const qm = pl.match(/quadrante[\s_-]*(\d)/);
      if (qm) tags.push(`quadrante-${qm[1]}`);
    }
  }

  return [...new Set(tags)];
}

function inferAssetType(ext: string): string {
  if (['.pdf', '.docx', '.doc', '.txt', '.markdown'].includes(ext)) return 'reference';
  if (['.pptx'].includes(ext)) return 'other';
  if (['.xlsx', '.csv'].includes(ext)) return 'other';
  if (['.png', '.jpg', '.jpeg'].includes(ext)) return 'other';
  if (['.mp4', '.mp3', '.webm'].includes(ext)) return 'other';
  return 'other';
}

function walkDir(dir: string): string[] {
  const results: string[] = [];
  if (!fs.existsSync(dir)) return results;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkDir(full));
    } else if (entry.isFile()) {
      results.push(full);
    }
  }
  return results;
}

// ── Manifest entry type ────────────────────────────────────────────────────

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

// ── Main ───────────────────────────────────────────────────────────────────

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  PHASE 1: Prepare, Deduplicate & Map                       ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');

  // Ensure directories
  fs.mkdirSync(STAGING_DIR, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });

  const hashMap = new Map<string, ManifestEntry>();
  let totalFiles = 0;
  let skippedExt = 0;
  let duplicates = 0;

  for (const { dir, category } of SOURCE_DIRS) {
    if (!fs.existsSync(dir)) {
      console.warn(`⚠ Source directory not found: ${dir}`);
      continue;
    }

    console.log(`\n📂 Scanning: ${dir} [${category}]`);
    const files = walkDir(dir);
    console.log(`   Found ${files.length} files`);

    for (const filePath of files) {
      totalFiles++;
      const ext = path.extname(filePath).toLowerCase();

      if (BLOCKED_EXTENSIONS.has(ext)) {
        skippedExt++;
        continue;
      }
      if (!ALLOWED_EXTENSIONS.has(ext)) {
        skippedExt++;
        console.log(`   ⏭ Skipped (ext): ${path.basename(filePath)}`);
        continue;
      }

      const hash = sha256(filePath);
      const tags = inferTags(filePath, category);

      if (hashMap.has(hash)) {
        // Duplicate: merge tags
        const existing = hashMap.get(hash)!;
        existing.originalPaths.push(filePath);
        existing.suggestedTags = [...new Set([...existing.suggestedTags, ...tags])];
        duplicates++;
        continue;
      }

      // New unique file
      const baseName = path.basename(filePath, ext);
      let sanitized = sanitizeName(baseName) + ext;

      // Handle name collisions for different hashes
      let counter = 1;
      const existingNames = new Set([...hashMap.values()].map(e => e.stagingFilename));
      while (existingNames.has(sanitized)) {
        sanitized = sanitizeName(baseName) + `-${counter}` + ext;
        counter++;
      }

      const title = baseName
        .replace(/^copy-of-/i, '')
        .replace(/-/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();

      hashMap.set(hash, {
        sha256: hash,
        originalPaths: [filePath],
        stagingFilename: sanitized,
        storagePath: `knowledge-bulk/${category}/${sanitized}`,
        title,
        assetType: inferAssetType(ext),
        suggestedTags: tags,
        category,
        sizeBytes: fs.statSync(filePath).size,
        extension: ext,
      });
    }
  }

  // Copy unique files to staging
  console.log(`\n📦 Copying ${hashMap.size} unique files to staging...`);
  let copied = 0;
  for (const entry of hashMap.values()) {
    const dest = path.join(STAGING_DIR, entry.stagingFilename);
    fs.copyFileSync(entry.originalPaths[0], dest);
    copied++;
    if (copied % 50 === 0) console.log(`   ${copied}/${hashMap.size} copied...`);
  }

  // Write manifest
  const manifest = [...hashMap.values()];
  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2), 'utf-8');

  // Write log
  const logFile = path.join(LOG_DIR, `phase1_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(logFile, JSON.stringify({
    timestamp: new Date().toISOString(),
    totalFilesScanned: totalFiles,
    skippedByExtension: skippedExt,
    duplicatesFound: duplicates,
    uniqueFilesCopied: hashMap.size,
    totalSizeBytes: manifest.reduce((s, e) => s + e.sizeBytes, 0),
    extensionBreakdown: manifest.reduce((acc, e) => {
      acc[e.extension] = (acc[e.extension] || 0) + 1;
      return acc;
    }, {} as Record<string, number>),
    categoryBreakdown: manifest.reduce((acc, e) => {
      acc[e.category] = (acc[e.category] || 0) + 1;
      return acc;
    }, {} as Record<string, number>),
  }, null, 2), 'utf-8');

  // Summary
  const totalSize = manifest.reduce((s, e) => s + e.sizeBytes, 0);
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  PHASE 1 COMPLETE                                          ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Total files scanned:    ${String(totalFiles).padStart(6)}`);
  console.log(`║  Skipped (blocked ext):  ${String(skippedExt).padStart(6)}`);
  console.log(`║  Duplicates merged:      ${String(duplicates).padStart(6)}`);
  console.log(`║  Unique files staged:    ${String(hashMap.size).padStart(6)}`);
  console.log(`║  Total size:             ${(totalSize / 1024 / 1024).toFixed(1)} MB`);
  console.log(`║  Manifest:               ${MANIFEST_PATH}`);
  console.log(`║  Staging:                ${STAGING_DIR}`);
  console.log(`║  Log:                    ${logFile}`);
  console.log('╚══════════════════════════════════════════════════════════════╝');
}

main().catch(err => {
  console.error('FATAL:', err);
  process.exit(1);
});
