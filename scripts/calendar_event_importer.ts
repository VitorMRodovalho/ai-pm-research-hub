/**
 * Wave 7 -- Google Calendar ICS Event Importer
 *
 * Parses a Google Calendar .ics export and imports Nucleo/PMI-relevant
 * events into the `events` table with dedup via calendar_event_id.
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/calendar_event_importer.ts [--dry-run]
 */

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { resolveSensitivePath } from './shared/paths';

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

const ICS_PATH = resolveSensitivePath('Google Clalendar', 'vitorodovalho@gmail.com.ics');

const NUCLEO_KEYWORDS = [
  'nucleo', 'núcleo', 'tribo', 'tribe',
  'pmi-go', 'pmi go', 'pmi goiás', 'pmi goias',
  'pmi-ce', 'pmi ceará', 'pmi ceara',
  'nucleo ia', 'núcleo ia',
];

const EXCLUDE_PATTERNS = [
  'pmi® annual', 'pmi in portuñol', 'ted@pmi',
  'pmi 4.0', 'pmbok', 'pmp', 'pmi certification',
];

interface ICSEvent {
  uid: string;
  summary: string;
  dtstart: string;
  dtend?: string;
  description?: string;
  location?: string;
}

function parseICS(content: string): ICSEvent[] {
  const events: ICSEvent[] = [];
  const lines = content.replace(/\r\n /g, '').replace(/\r\n\t/g, '').split(/\r?\n/);

  let current: Partial<ICSEvent> | null = null;

  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') {
      current = {};
    } else if (line === 'END:VEVENT' && current) {
      if (current.uid && current.summary && current.dtstart) {
        events.push(current as ICSEvent);
      }
      current = null;
    } else if (current) {
      const colonIdx = line.indexOf(':');
      if (colonIdx === -1) continue;

      const keyPart = line.substring(0, colonIdx);
      const value = line.substring(colonIdx + 1);
      const baseKey = keyPart.split(';')[0];

      switch (baseKey) {
        case 'UID': current.uid = value; break;
        case 'SUMMARY': current.summary = unescapeICS(value); break;
        case 'DTSTART': current.dtstart = value; break;
        case 'DTEND': current.dtend = value; break;
        case 'DESCRIPTION': current.description = unescapeICS(value); break;
        case 'LOCATION': current.location = unescapeICS(value); break;
      }
    }
  }

  return events;
}

function unescapeICS(s: string): string {
  return s.replace(/\\n/g, '\n').replace(/\\,/g, ',').replace(/\\\\/g, '\\').replace(/\\;/g, ';');
}

function isNucleoRelevant(summary: string): boolean {
  const lower = summary.toLowerCase();
  if (EXCLUDE_PATTERNS.some(p => lower.includes(p))) return false;
  return NUCLEO_KEYWORDS.some(k => lower.includes(k));
}

function parseICSDate(d: string): string {
  if (d.length === 8) {
    return `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`;
  }
  const cleaned = d.replace('Z', '');
  return `${cleaned.slice(0, 4)}-${cleaned.slice(4, 6)}-${cleaned.slice(6, 8)}T${cleaned.slice(9, 11)}:${cleaned.slice(11, 13)}:${cleaned.slice(13, 15)}`;
}

function computeDuration(start: string, end?: string): number {
  if (!end) return 60;
  try {
    const s = new Date(parseICSDate(start));
    const e = new Date(parseICSDate(end));
    const mins = Math.round((e.getTime() - s.getTime()) / 60000);
    return mins > 0 ? mins : 60;
  } catch { return 60; }
}

function inferEventType(summary: string): string {
  const lower = summary.toLowerCase();
  if (lower.includes('webinar') || lower.includes('seminário') || lower.includes('seminario')) return 'webinar';
  if (lower.includes('entrevista')) return 'other';
  if (lower.includes('ligação') || lower.includes('ligaçao') || lower.includes('whatsapp')) return 'other';
  if (lower.includes('tribo') || lower.includes('tribe')) return 'tribe_meeting';
  if (lower.includes('reunião') || lower.includes('reuniao') || lower.includes('meeting')) return 'general_meeting';
  if (lower.includes('planejamento')) return 'general_meeting';
  return 'other';
}

function inferTribeId(summary: string): number | null {
  const lower = summary.toLowerCase();
  if (lower.includes('tribo 1') || lower.includes('tribo 01') || lower.includes('quadrante 1')) return 1;
  if (lower.includes('tribo 2') || lower.includes('tribo 02') || lower.includes('quadrante 2')) return 2;
  if (lower.includes('tribo 3') || lower.includes('tribo 03') || lower.includes('quadrante 3')) return 3;
  if (lower.includes('tribo 4') || lower.includes('tribo 04') || lower.includes('quadrante 4')) return 4;
  if (lower.includes('tribo 5') || lower.includes('tribo 05') || lower.includes('quadrante 5')) return 5;
  if (lower.includes('tribo 6') || lower.includes('tribo 06') || lower.includes('quadrante 6')) return 6;
  if (lower.includes('tribo 7') || lower.includes('tribo 07') || lower.includes('quadrante 7')) return 7;
  return null;
}

async function main() {
  console.log(`Calendar Event Importer${DRY_RUN ? ' (DRY RUN)' : ''}`);
  console.log(`========================================`);

  const icsContent = readFileSync(ICS_PATH, 'utf-8');
  const allEvents = parseICS(icsContent);
  console.log(`Total ICS events parsed: ${allEvents.length}`);

  const relevant = allEvents.filter(e => isNucleoRelevant(e.summary));
  console.log(`Nucleo/PMI-relevant events: ${relevant.length}`);

  let imported = 0, skipped = 0;

  for (const evt of relevant) {
    const date = parseICSDate(evt.dtstart);
    const duration = computeDuration(evt.dtstart, evt.dtend);
    const type = inferEventType(evt.summary);
    const tribeId = inferTribeId(evt.summary);

    if (DRY_RUN) {
      console.log(`  [DRY] ${date} | ${evt.summary.substring(0, 60)} | type=${type} | tribe=${tribeId}`);
      imported++;
      continue;
    }

    const { data: existing } = await sb
      .from('events')
      .select('id')
      .eq('calendar_event_id', evt.uid)
      .maybeSingle();

    if (existing) { skipped++; continue; }

    const { error } = await sb.from('events').insert({
      title: evt.summary,
      date: date.split('T')[0],
      type,
      duration_minutes: duration,
      tribe_id: tribeId,
      source: 'calendar_import',
      calendar_event_id: evt.uid,
      is_recorded: false,
    });

    if (error) {
      console.error(`  ERROR: ${evt.summary.substring(0, 40)}: ${error.message}`);
      skipped++;
    } else {
      imported++;
    }
  }

  console.log(`\n========================================`);
  console.log(`Result: ${imported} imported, ${skipped} skipped (of ${relevant.length} relevant)`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
