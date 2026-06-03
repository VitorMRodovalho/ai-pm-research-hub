/**
 * Contract: #170 — create_meeting_notes must not comma-split prose into bogus bullets.
 *
 * Root cause: the tool built fullContent by String(params.decisions).split(",") and
 * String(params.action_items).split(","), one markdown bullet per comma-segment. Portuguese
 * meeting notes use commas inside clauses and responsible-party lists ("Fabrício, Fernando e
 * Sávio"), so single decisions/actions were shredded into fragment bullets — corrupting 7 rows
 * of stored minutes (Fabricio's WhatsApp report). Fix: split on NEWLINE only (never bare ","),
 * plus a pre-write quarantine gate that rejects serialization-corruption markers before the DB
 * write so a bad payload never reaches events.minutes_text.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const EF = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const raw = existsSync(EF) ? readFileSync(EF, 'utf8') : '';

// Isolate the create_meeting_notes tool body (its registration → start of the next tool),
// so assertions don't false-match on other tools that legitimately .split(",") (e.g. tags).
function toolBlock(src, name) {
  const start = src.indexOf(`mcp.tool("${name}"`);
  if (start < 0) return '';
  const after = src.indexOf('mcp.tool("', start + 1);
  return src.slice(start, after < 0 ? undefined : after);
}
const block = toolBlock(raw, 'create_meeting_notes');

test('#170: create_meeting_notes tool block is present', () => {
  assert.ok(block.length > 0, 'create_meeting_notes registration found');
});

test('#170: decisions/action_items are split on NEWLINE, never on bare comma', () => {
  assert.match(block, /split\(\/\\r\?\\n\/\)/, 'splits list params on /\\r?\\n/ (newline)');
  assert.doesNotMatch(block, /\.split\(","\)/, 'no .split(",") anywhere in create_meeting_notes');
});

test('#170: a pre-write corruption-marker quarantine gate fires BEFORE the DB write', () => {
  assert.match(block, /hasReplacementChar|hasObjectArtifact/, 'has a corruption-marker guard');
  assert.match(block, /\[object Object\]/, 'rejects the "[object Object]" serialization artifact (whole-line)');
  assert.match(block, /U\+FFFD|replacement character/i, 'guards the U+FFFD replacement character');
  // the gate must sit before the DB write (fail-before-write)
  const gateIdx = block.indexOf('hasObjectArtifact');
  const upsertIdx = block.indexOf('upsert_event_minutes');
  assert.ok(gateIdx > 0 && upsertIdx > gateIdx, 'corruption gate precedes upsert_event_minutes');
});

test('#170: param guidance is one-per-line for BOTH fields (no leftover "(comma-separated)")', () => {
  // both decisions AND action_items must carry the one-per-line guidance, not just one of them
  assert.ok((block.match(/one per line/g) ?? []).length >= 2, 'both params described as one-per-line');
  assert.doesNotMatch(block, /\(comma-separated\)/, 'no leftover "(comma-separated)" guidance');
});
