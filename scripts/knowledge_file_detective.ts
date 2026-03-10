/**
 * Knowledge File Detective
 * Scans data/staging-knowledge/ for presentation files (.pdf/.pptx) not yet
 * registered in the artifacts table and outputs a report JSON.
 *
 * Usage: npx tsx scripts/knowledge_file_detective.ts [--ingest]
 *   --ingest  Also insert discovered orphans into artifacts with status='review'
 */
import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { readdirSync, writeFileSync, mkdirSync } from 'fs';
import { join, extname, basename } from 'path';

const STAGING_DIR = join(__dirname, '..', 'data', 'staging-knowledge');
const OUTPUT_DIR = join(__dirname, '..', 'data', 'ingestion-logs');
const OUTPUT_FILE = join(OUTPUT_DIR, 'file_detective_report.json');

const PRESENTATION_KEYWORDS = [
  'apresenta', 'presentation', 'nucleo-ia', 'pmrank', 'pmi_ai_hub',
  'palestrante', 'tribo', 'webinar', 'slide',
];

const ALLOWED_EXTENSIONS = ['.pdf', '.pptx', '.ppt'];

const sb = createClient(
  process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '',
  process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY || '',
);

interface FileRecord {
  filename: string;
  path: string;
  extension: string;
  matchedKeywords: string[];
  suggestedType: string;
  suggestedCycle: string;
  suggestedTribeId: number | null;
  registeredInArtifacts: boolean;
  artifactId: string | null;
}

function inferTribeFromFilename(name: string): number | null {
  const triboMatch = name.match(/tribo[- _]?(\d+)/i);
  if (triboMatch) return parseInt(triboMatch[1]);
  if (/quadrante[- _]?1/i.test(name)) return 1;
  if (/quadrante[- _]?2/i.test(name)) return 2;
  if (/quadrante[- _]?3/i.test(name)) return 6;
  if (/quadrante[- _]?4/i.test(name)) return 7;
  return null;
}

function inferCycleFromFilename(name: string): string {
  if (/2024|ciclo[- _]?1/i.test(name)) return 'cycle_1';
  if (/2025-0[1-6]|ciclo[- _]?2/i.test(name)) return 'cycle_2';
  return 'cycle_3';
}

async function main() {
  const shouldIngest = process.argv.includes('--ingest');
  console.log(`📁 Scanning ${STAGING_DIR}...`);

  let files: string[];
  try {
    files = readdirSync(STAGING_DIR);
  } catch {
    console.error(`❌ Cannot read directory: ${STAGING_DIR}`);
    process.exit(1);
  }

  const candidates = files.filter(f => {
    const ext = extname(f).toLowerCase();
    if (!ALLOWED_EXTENSIONS.includes(ext)) return false;
    const lower = f.toLowerCase();
    return PRESENTATION_KEYWORDS.some(kw => lower.includes(kw));
  });

  console.log(`🔍 Found ${candidates.length} presentation candidates out of ${files.length} total files`);

  const { data: existingArtifacts } = await sb
    .from('artifacts')
    .select('id, title, url, type')
    .in('type', ['presentation', 'other']);

  const existingTitles = new Set(
    (existingArtifacts || []).map((a: any) => a.title?.toLowerCase().trim())
  );
  const existingUrls = new Set(
    (existingArtifacts || []).flatMap((a: any) => a.url ? [a.url] : [])
  );

  const report: FileRecord[] = [];

  for (const filename of candidates) {
    const ext = extname(filename).toLowerCase();
    const name = basename(filename, ext);
    const lower = name.toLowerCase();

    const matchedKeywords = PRESENTATION_KEYWORDS.filter(kw => lower.includes(kw));
    const tribeId = inferTribeFromFilename(lower);
    const cycle = inferCycleFromFilename(filename);

    const titleNormalized = name.replace(/[-_]/g, ' ').toLowerCase().trim();
    const isRegistered = existingTitles.has(titleNormalized)
      || [...existingUrls].some(u => u.includes(filename));

    const matchingArtifact = (existingArtifacts || []).find((a: any) =>
      a.title?.toLowerCase().trim() === titleNormalized
      || (a.url && a.url.includes(filename))
    );

    report.push({
      filename,
      path: join(STAGING_DIR, filename),
      extension: ext,
      matchedKeywords,
      suggestedType: 'presentation',
      suggestedCycle: cycle,
      suggestedTribeId: tribeId,
      registeredInArtifacts: isRegistered,
      artifactId: matchingArtifact?.id || null,
    });
  }

  const orphans = report.filter(r => !r.registeredInArtifacts);
  const registered = report.filter(r => r.registeredInArtifacts);

  console.log(`\n📊 Results:`);
  console.log(`   Total candidates: ${report.length}`);
  console.log(`   Already registered: ${registered.length}`);
  console.log(`   Orphans (not in DB): ${orphans.length}`);

  if (orphans.length) {
    console.log(`\n🔎 Orphaned files:`);
    orphans.forEach(o => {
      console.log(`   - ${o.filename} (tribe=${o.suggestedTribeId || '?'}, cycle=${o.suggestedCycle})`);
    });
  }

  if (shouldIngest && orphans.length) {
    console.log(`\n📥 Ingesting ${orphans.length} orphans into artifacts table...`);
    for (const orphan of orphans) {
      const { error } = await sb.from('artifacts').insert({
        title: orphan.filename.replace(/[-_]/g, ' ').replace(/\.\w+$/, ''),
        type: orphan.suggestedType,
        tribe_id: orphan.suggestedTribeId,
        cycle: orphan.suggestedCycle,
        status: 'review',
        submitted_at: new Date().toISOString(),
      });
      if (error) {
        console.error(`   ❌ Failed to insert ${orphan.filename}: ${error.message}`);
      } else {
        console.log(`   ✅ Inserted: ${orphan.filename}`);
      }
    }
  }

  mkdirSync(OUTPUT_DIR, { recursive: true });
  const output = {
    generatedAt: new Date().toISOString(),
    stagingDir: STAGING_DIR,
    totalFilesScanned: files.length,
    presentationCandidates: report.length,
    orphans: orphans.length,
    registered: registered.length,
    ingested: shouldIngest ? orphans.length : 0,
    files: report,
  };

  writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2));
  console.log(`\n💾 Report saved to: ${OUTPUT_FILE}`);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
