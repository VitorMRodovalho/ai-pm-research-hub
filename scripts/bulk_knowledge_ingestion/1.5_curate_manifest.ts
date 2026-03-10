/**
 * PHASE 1.5: Curate Manifest — Triage before upload
 *
 * Reads upload_manifest.json and applies curation rules:
 *
 * 1. MARKDOWN QUARANTINE (AI Safety): .md/.markdown files are removed from
 *    the upload manifest and moved to data/staging-knowledge/quarantine_md/.
 *    Rationale: legacy .md files may contain freeform instructions, prompts,
 *    or notes that could confuse future AI agents reading the repository or
 *    Storage bucket — treating them as authoritative documentation when they
 *    are actually raw drafts. Quarantining prevents "prompt poisoning" of
 *    downstream LLM pipelines.
 *
 * 2. DOCX/DOC EXTRACTION ISOLATION: .doc and .docx files are removed from
 *    the upload manifest and moved to data/staging-knowledge/needs_extraction/.
 *    These contain meeting minutes, drafts, and atas that require human or
 *    Gemini-assisted extraction before being published as structured content.
 *
 * 3. COPYRIGHT FLAG: PDFs larger than 15 MB or whose filename suggests an
 *    external book/guide/standard are flagged with curation_status =
 *    'pending_copyright_review' instead of 'approved'.
 *
 * Output: upload_manifest_curated.json (clean manifest for Phase 2)
 *
 * Usage: npx tsx scripts/bulk_knowledge_ingestion/1.5_curate_manifest.ts
 */

import * as fs from 'node:fs';
import * as path from 'node:path';

const MANIFEST_IN = path.resolve('./scripts/bulk_knowledge_ingestion/upload_manifest.json');
const MANIFEST_OUT = path.resolve('./scripts/bulk_knowledge_ingestion/upload_manifest_curated.json');
const STAGING_DIR = path.resolve('./data/staging-knowledge');
const QUARANTINE_MD = path.join(STAGING_DIR, 'quarantine_md');
const NEEDS_EXTRACTION = path.join(STAGING_DIR, 'needs_extraction');
const LOG_DIR = path.resolve('./data/ingestion-logs');

const COPYRIGHT_SIZE_THRESHOLD = 15 * 1024 * 1024; // 15 MB

const COPYRIGHT_KEYWORDS = [
  'book', 'livro', 'guide', 'guia', 'harvard', 'springer', 'wiley',
  'elsevier', 'mcgraw', 'oreilly', 'o\'reilly', 'pearson', 'isbn',
  'handbook', 'manual', 'edition', 'edicao', 'copyright', 'pmi-code',
  'state-of-ai', 'executive-guide', 'pminext', 'boletim',
];

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
  curation_status?: string;
}

function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  PHASE 1.5: Curate Manifest (Triage)                       ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');

  if (!fs.existsSync(MANIFEST_IN)) {
    console.error('ERROR: upload_manifest.json not found. Run Phase 1 first.');
    process.exit(1);
  }

  const manifest: ManifestEntry[] = JSON.parse(fs.readFileSync(MANIFEST_IN, 'utf-8'));
  console.log(`\n📋 Loaded manifest: ${manifest.length} entries`);

  fs.mkdirSync(QUARANTINE_MD, { recursive: true });
  fs.mkdirSync(NEEDS_EXTRACTION, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });

  const curated: ManifestEntry[] = [];
  const quarantinedMd: ManifestEntry[] = [];
  const extractionQueue: ManifestEntry[] = [];
  let copyrightFlagged = 0;

  for (const entry of manifest) {
    const ext = entry.extension.toLowerCase();
    const srcPath = path.join(STAGING_DIR, entry.stagingFilename);
    const fileExists = fs.existsSync(srcPath);

    // ── Rule 1: Markdown quarantine ──
    if (ext === '.md' || ext === '.markdown') {
      entry.suggestedTags = [...new Set([...entry.suggestedTags, 'raw_notes'])];
      entry.curation_status = 'quarantined_ai_safety';
      quarantinedMd.push(entry);

      if (fileExists) {
        const dest = path.join(QUARANTINE_MD, entry.stagingFilename);
        fs.renameSync(srcPath, dest);
      }
      console.log(`   🔒 Quarantined (MD):  ${entry.stagingFilename}`);
      continue;
    }

    // ── Rule 2: DOCX/DOC extraction isolation ──
    if (ext === '.docx' || ext === '.doc') {
      entry.curation_status = 'needs_extraction';
      extractionQueue.push(entry);

      if (fileExists) {
        const dest = path.join(NEEDS_EXTRACTION, entry.stagingFilename);
        fs.renameSync(srcPath, dest);
      }
      console.log(`   📝 Extraction queue:  ${entry.stagingFilename}`);
      continue;
    }

    // ── Rule 3: Copyright flag for PDFs ──
    if (ext === '.pdf') {
      const nameLower = entry.stagingFilename.toLowerCase();
      const sizeFlag = entry.sizeBytes > COPYRIGHT_SIZE_THRESHOLD;
      const nameFlag = COPYRIGHT_KEYWORDS.some(kw => nameLower.includes(kw));

      if (sizeFlag || nameFlag) {
        entry.curation_status = 'pending_copyright_review';
        copyrightFlagged++;
        const reason = sizeFlag ? `${(entry.sizeBytes / 1024 / 1024).toFixed(1)} MB` : 'keyword match';
        console.log(`   ⚠️  Copyright flag:   ${entry.stagingFilename} (${reason})`);
      } else {
        entry.curation_status = 'approved';
      }
    } else {
      entry.curation_status = 'approved';
    }

    curated.push(entry);
  }

  // Write curated manifest
  fs.writeFileSync(MANIFEST_OUT, JSON.stringify(curated, null, 2), 'utf-8');

  // Write triage log
  const logFile = path.join(LOG_DIR, `phase1.5_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(logFile, JSON.stringify({
    timestamp: new Date().toISOString(),
    inputEntries: manifest.length,
    outputEntries: curated.length,
    quarantinedMarkdown: quarantinedMd.length,
    docxExtractionQueue: extractionQueue.length,
    copyrightFlagged,
    approvedForUpload: curated.filter(e => e.curation_status === 'approved').length,
    quarantinedFiles: quarantinedMd.map(e => e.stagingFilename),
    extractionFiles: extractionQueue.map(e => e.stagingFilename),
    copyrightFiles: curated.filter(e => e.curation_status === 'pending_copyright_review').map(e => ({
      file: e.stagingFilename,
      sizeMB: (e.sizeBytes / 1024 / 1024).toFixed(1),
    })),
  }, null, 2), 'utf-8');

  // Summary
  const approved = curated.filter(e => e.curation_status === 'approved').length;
  const pending = curated.filter(e => e.curation_status === 'pending_copyright_review').length;

  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  PHASE 1.5 COMPLETE — TRIAGE SUMMARY                       ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Input (from Phase 1):     ${String(manifest.length).padStart(6)}`);
  console.log(`║  ─────────────────────────────────`);
  console.log(`║  🔒 Quarantined (.md):     ${String(quarantinedMd.length).padStart(6)}  → quarantine_md/`);
  console.log(`║  📝 Extraction (.docx):    ${String(extractionQueue.length).padStart(6)}  → needs_extraction/`);
  console.log(`║  ⚠️  Copyright review:      ${String(copyrightFlagged).padStart(6)}  (kept in manifest, flagged)`);
  console.log(`║  ✅ Approved for upload:    ${String(approved).padStart(6)}`);
  console.log(`║  ─────────────────────────────────`);
  console.log(`║  Output manifest:          ${String(curated.length).padStart(6)}  entries`);
  console.log(`║  Manifest file:            ${MANIFEST_OUT}`);
  console.log(`║  Log:                      ${logFile}`);
  console.log('╚══════════════════════════════════════════════════════════════╝');

  console.log('\n📌 Next steps:');
  console.log('   1. Review copyright-flagged PDFs manually');
  console.log('   2. Use Gemini agent on needs_extraction/ for atas');
  console.log('   3. Run Phase 2 with curated manifest:');
  console.log('      npx tsx scripts/bulk_knowledge_ingestion/2_execute_upload.ts --manifest upload_manifest_curated.json');
}

main();
