/**
 * Wave 7 -- Volunteer CSV Importer
 *
 * Parses PMI volunteer application CSV exports (Ciclos 1-3),
 * stores them in `volunteer_applications`, and cross-references
 * with `members` via email match.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/volunteer_csv_importer.ts [--dry-run]
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

const BASE_DIR = '/home/vitormrodovalho/Downloads/data/raw-drive-exports/Sensitive/Export voluntarios inscritos plataforma PMI';

interface CsvConfig {
  path: string;
  cycle: number;
  opportunityId: string;
  snapshotDate: string;
}

const CSV_FILES: CsvConfig[] = [
  {
    path: `${BASE_DIR}/Ciclo 1 (GO e CE)/Opportunity62106_Applications_20250822153520.csv`,
    cycle: 1, opportunityId: '62106', snapshotDate: '2025-08-22',
  },
  {
    path: `${BASE_DIR}/Ciclo 2 (GO e CE)/Opportunity64967_Applications_20251222181533.csv`,
    cycle: 2, opportunityId: '64967', snapshotDate: '2025-12-22',
  },
  {
    path: `${BASE_DIR}/Ciclo 3 (pelo Go para os 5 capitulos, Pesqu e Lideres)/Opportunity64966_Applications_20260116155015.csv`,
    cycle: 3, opportunityId: '64966', snapshotDate: '2026-01-16',
  },
  {
    path: `${BASE_DIR}/Ciclo 3 (pelo Go para os 5 capitulos, Pesqu e Lideres)/Opportunity64966_Applications_20260309212026.csv`,
    cycle: 3, opportunityId: '64966', snapshotDate: '2026-03-09',
  },
  {
    path: `${BASE_DIR}/Ciclo 3 (pelo Go para os 5 capitulos, Pesqu e Lideres)/Opportunity64967_Applications_20260116163615.csv`,
    cycle: 3, opportunityId: '64967', snapshotDate: '2026-01-16',
  },
  {
    path: `${BASE_DIR}/Ciclo 3 (pelo Go para os 5 capitulos, Pesqu e Lideres)/Opportunity64967_Applications_20260309212143.csv`,
    cycle: 3, opportunityId: '64967', snapshotDate: '2026-03-09',
  },
];

function parseCSV(content: string): string[][] {
  const rows: string[][] = [];
  let current: string[] = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < content.length; i++) {
    const ch = content[i];
    const next = content[i + 1];

    if (inQuotes) {
      if (ch === '"' && next === '"') {
        field += '"';
        i++;
      } else if (ch === '"') {
        inQuotes = false;
      } else {
        field += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === ',') {
        current.push(field.trim());
        field = '';
      } else if (ch === '\n' || (ch === '\r' && next === '\n')) {
        current.push(field.trim());
        field = '';
        if (current.some(c => c)) rows.push(current);
        current = [];
        if (ch === '\r') i++;
      } else {
        field += ch;
      }
    }
  }
  if (field || current.length) {
    current.push(field.trim());
    if (current.some(c => c)) rows.push(current);
  }
  return rows;
}

function findColumnIndex(headers: string[], ...names: string[]): number {
  for (const name of names) {
    const idx = headers.findIndex(h => h.toLowerCase().trim() === name.toLowerCase().trim());
    if (idx >= 0) return idx;
  }
  return -1;
}

async function loadMemberEmails(): Promise<Map<string, string>> {
  const { data } = await sb.from('members').select('id, email');
  const map = new Map<string, string>();
  if (data) {
    for (const m of data) {
      if (m.email) map.set(m.email.toLowerCase().trim(), m.id);
    }
  }
  return map;
}

async function importCSV(config: CsvConfig, memberEmails: Map<string, string>) {
  console.log(`\n=== ${config.path.split('/').pop()} (Cycle ${config.cycle}, Opp ${config.opportunityId}, Snapshot ${config.snapshotDate}) ===`);

  const content = readFileSync(config.path, 'utf-8');
  const rows = parseCSV(content);
  if (rows.length < 2) {
    console.log('  No data rows found');
    return { total: 0, imported: 0, skipped: 0 };
  }

  const headers = rows[0].map(h => h.trim());

  const colAppId = findColumnIndex(headers, 'Application ID');
  const colPmiId = findColumnIndex(headers, 'PMI ID');
  const colFirst = findColumnIndex(headers, 'First Name');
  const colLast = findColumnIndex(headers, 'Last Name');
  const colEmail = findColumnIndex(headers, 'Email');
  const colMembership = findColumnIndex(headers, 'Membership status');
  const colCerts = findColumnIndex(headers, 'Certifications');
  const colCity = findColumnIndex(headers, 'City');
  const colState = findColumnIndex(headers, 'State');
  const colCountry = findColumnIndex(headers, 'Country');
  const colAppStatus = findColumnIndex(headers, 'App Status');
  const colReason = findColumnIndex(headers, 'Reason for Applying');
  const colResumeUrl = findColumnIndex(headers, 'Resume Url');
  const colAreas = findColumnIndex(headers, 'Areas of Interest');
  const colLabel = findColumnIndex(headers, 'Label');
  const colIndustry = findColumnIndex(headers, 'Industry');
  const colSpecialty = findColumnIndex(headers, 'Specialty');

  const essayIndices: number[] = [];
  headers.forEach((h, i) => {
    if (/essay question/i.test(h)) essayIndices.push(i);
  });

  let imported = 0, skipped = 0;

  for (let r = 1; r < rows.length; r++) {
    const row = rows[r];
    const get = (idx: number) => (idx >= 0 && idx < row.length ? row[idx]?.trim() : '') || '';

    const email = get(colEmail).toLowerCase();
    const appId = get(colAppId);
    if (!email || !appId) { skipped++; continue; }

    const certs = get(colCerts).split(',').map(c => c.trim()).filter(Boolean);
    const essays: Record<string, string> = {};
    essayIndices.forEach((idx, i) => {
      const val = get(idx);
      if (val) essays[`essay_${i + 1}`] = val;
    });

    const memberId = memberEmails.get(email) || null;
    const isExistingMember = !!memberId;

    if (DRY_RUN) {
      console.log(`  [DRY] ${get(colFirst)} ${get(colLast)} <${email}> | Cycle ${config.cycle} | Status: ${get(colAppStatus)} | Member: ${isExistingMember}`);
      imported++;
      continue;
    }

    const { error } = await sb.from('volunteer_applications').upsert({
      application_id: appId,
      pmi_id: get(colPmiId) || null,
      first_name: get(colFirst),
      last_name: get(colLast),
      email,
      membership_status: get(colMembership) || null,
      certifications: certs,
      city: get(colCity) || null,
      state: get(colState) || null,
      country: get(colCountry) || null,
      app_status: get(colAppStatus) || null,
      reason_for_applying: get(colReason) || null,
      essay_answers: essays,
      areas_of_interest: get(colAreas) || null,
      label: get(colLabel) || null,
      industry: get(colIndustry) || null,
      specialty: get(colSpecialty) || null,
      resume_url: get(colResumeUrl) || null,
      cycle: config.cycle,
      opportunity_id: config.opportunityId,
      snapshot_date: config.snapshotDate,
      member_id: memberId,
      is_existing_member: isExistingMember,
    }, {
      onConflict: 'application_id,opportunity_id,snapshot_date',
    });

    if (error) {
      console.error(`  ERROR row ${r}: ${error.message}`);
      skipped++;
    } else {
      imported++;
    }
  }

  console.log(`  Result: ${imported} imported, ${skipped} skipped (of ${rows.length - 1} data rows)`);
  return { total: rows.length - 1, imported, skipped };
}

async function main() {
  console.log(`Volunteer CSV Importer${DRY_RUN ? ' (DRY RUN)' : ''}`);
  console.log(`========================================`);

  const memberEmails = await loadMemberEmails();
  console.log(`Loaded ${memberEmails.size} member emails for matching`);

  let grandTotal = 0, grandImported = 0, grandSkipped = 0;

  for (const config of CSV_FILES) {
    const result = await importCSV(config, memberEmails);
    grandTotal += result.total;
    grandImported += result.imported;
    grandSkipped += result.skipped;
  }

  console.log(`\n========================================`);
  console.log(`GRAND TOTAL: ${grandImported} imported, ${grandSkipped} skipped (of ${grandTotal} rows across ${CSV_FILES.length} files)`);

  if (!DRY_RUN) {
    const { data: stats } = await sb.rpc('volunteer_funnel_summary');
    if (stats) {
      console.log(`\nFunnel Summary:`);
      console.log(JSON.stringify(stats, null, 2));
    }
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
