#!/usr/bin/env node
// scripts/generate-mcp-manifest.mjs
// Parses supabase/functions/nucleo-mcp/index.ts and emits a JSON manifest of
// all MCP tools, grouped by domain + permission. Output:
//   src/lib/mcp-manifest.json  (consumed by /docs/mcp Astro page)
//
// Run: node scripts/generate-mcp-manifest.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SOURCE_PATH = 'supabase/functions/nucleo-mcp/index.ts';
const OUTPUT_PATH = 'src/lib/mcp-manifest.json';

const DOMAIN_RULES = [
  [/^(get_my_|set_my_)/, 'personal'],
  [/governance|manual_section|ratification|^sign_|chain|certificate|version|signature/, 'governance'],
  [/partner/, 'partners'],
  [/comms|campaign|broadcast|webinar|newsletter/, 'comms'],
  [/board|card|checklist|curat|portfolio/, 'board'],
  [/event|attendance|meeting|near_event|upcoming/, 'events'],
  [/xp|ranking|leaderboard|champion|gamification|showcase|streak/, 'gamification'],
  [/selection|application|interview|onboarding|evaluat/, 'selection'],
  [/wiki|knowledge|hub_resource/, 'knowledge'],
  [/health|audit|invitation|digest|anomaly|drift|lgpd/, 'health'],
  [/(^|_)admin_|manage_member|manage_platform|offboard|promote|inactivate|chain_audit/, 'admin'],
  [/tribe|initiative|engagement/, 'tribe'],
];

const ADMIN_HINTS = /admin_|offboard|manage_member|manage_platform|inactivate|view_pii|audit_log|chain_audit/;
const WRITE_HINTS = /^(create_|update_|delete_|add_|set_|manage_|move_|archive_|register_|propose_|submit_|complete_|approve_|advance_|assign_|cancel_|confirm_|counter_|drop_|duplicate_|edit_|exec_|invite_|issue_|link_|lock_|log_|mark_|offboard_|promote_|recalculate_|record_|resolve_|respond_|restore_|review_|schedule_|unlink_|withdraw_|sign_|dismiss_|detect_|bulk_|convert_)/;

const SAFE_DOMAIN_LIST = [
  'personal', 'tribe', 'board', 'events', 'governance', 'comms',
  'partners', 'gamification', 'selection', 'knowledge', 'admin', 'health',
];

function classifyDomain(name) {
  for (const [pattern, domain] of DOMAIN_RULES) {
    if (pattern.test(name)) return domain;
  }
  return 'tribe';
}

function classifyPermission(name) {
  if (ADMIN_HINTS.test(name)) return 'admin';
  if (WRITE_HINTS.test(name)) return 'write';
  return 'read';
}

function isSensitive(name) {
  return /pii|audit_log|offboard|inactivate|export_audit|chain_audit_report/.test(name);
}

const text = readFileSync(resolve(SOURCE_PATH), 'utf8');
const re = /mcp\.tool\(\s*"([^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,/g;

const tools = [];
const seen = new Set();
let match;
while ((match = re.exec(text)) !== null) {
  const name = match[1];
  if (seen.has(name)) {
    console.warn(`[warn] duplicate tool name: ${name}`);
    continue;
  }
  seen.add(name);
  const description = match[2].replace(/\\"/g, '"').replace(/\\n/g, ' ').trim();
  const domain = classifyDomain(name);
  const permission = classifyPermission(name);
  const sensitive = isSensitive(name);
  tools.push({
    name,
    description: sensitive
      ? 'Internal admin operation — full details available to authorized members on request.'
      : description,
    domain,
    permission,
    is_sensitive: sensitive,
  });
}

const domainOrder = new Map(SAFE_DOMAIN_LIST.map((d, i) => [d, i]));
tools.sort((a, b) => {
  const da = domainOrder.get(a.domain) ?? 99;
  const db = domainOrder.get(b.domain) ?? 99;
  if (da !== db) return da - db;
  const permOrder = { read: 0, write: 1, admin: 2 };
  if (permOrder[a.permission] !== permOrder[b.permission]) {
    return permOrder[a.permission] - permOrder[b.permission];
  }
  return a.name.localeCompare(b.name);
});

const byDomain = {};
const byPermission = {};
for (const t of tools) {
  byDomain[t.domain] = (byDomain[t.domain] || 0) + 1;
  byPermission[t.permission] = (byPermission[t.permission] || 0) + 1;
}

const manifest = {
  generated_at: new Date().toISOString(),
  source: SOURCE_PATH,
  total: tools.length,
  by_domain: byDomain,
  by_permission: byPermission,
  sensitive_count: tools.filter(t => t.is_sensitive).length,
  domain_order: SAFE_DOMAIN_LIST,
  tools,
};

writeFileSync(resolve(OUTPUT_PATH), JSON.stringify(manifest, null, 2) + '\n');
console.log(`[ok] ${tools.length} tools → ${OUTPUT_PATH}`);
console.log('[ok] by_domain:', byDomain);
console.log('[ok] by_permission:', byPermission);
console.log(`[ok] sensitive (sanitized desc): ${manifest.sensitive_count}`);
