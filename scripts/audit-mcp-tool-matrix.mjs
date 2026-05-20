#!/usr/bin/env node
// scripts/audit-mcp-tool-matrix.mjs
// Generates the MCP contract matrix (issue #162 close, p202).
//
// Static parser: extracts per-tool name, description, RPC calls, table touches,
// canV4 gates, external fetches, return shape hints from supabase/functions/nucleo-mcp/index.ts.
//
// Optional runtime cross-check: fetches tools/list via nucleoia.vitormr.dev/mcp,
// flags drift between static parser and runtime tools/list.
//
// Outputs:
//   docs/reference/MCP_TOOL_MATRIX.md    (markdown table)
//   docs/reference/mcp-tool-matrix.json  (structured)
//
// Run:
//   node scripts/audit-mcp-tool-matrix.mjs            (static-only)
//   node scripts/audit-mcp-tool-matrix.mjs --runtime  (cross-check with prod)

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";

const SOURCE_PATH = "supabase/functions/nucleo-mcp/index.ts";
const MATRIX_MD_PATH = "docs/reference/MCP_TOOL_MATRIX.md";
const MATRIX_JSON_PATH = "docs/reference/mcp-tool-matrix.json";
const RUNTIME_URL = "https://nucleoia.vitormr.dev/mcp";

const DOMAIN_RULES = [
  [/^(get_my_|set_my_)/, "personal"],
  [/governance|manual_section|ratification|^sign_|chain|certificate|version|signature/, "governance"],
  [/partner/, "partners"],
  [/comms|campaign|broadcast|webinar|newsletter/, "comms"],
  [/board|card|checklist|curat|portfolio/, "board"],
  [/event|attendance|meeting|near_event|upcoming/, "events"],
  [/xp|ranking|leaderboard|champion|gamification|showcase|streak/, "gamification"],
  [/selection|application|interview|onboarding|evaluat/, "selection"],
  [/wiki|knowledge|hub_resource/, "knowledge"],
  [/health|audit|invitation|digest|anomaly|drift|lgpd/, "health"],
  [/(^|_)admin_|manage_member|manage_platform|offboard|promote|inactivate|chain_audit/, "admin"],
  [/tribe|initiative|engagement/, "tribe"],
];

function classifyDomain(name) {
  for (const [pattern, domain] of DOMAIN_RULES) {
    if (pattern.test(name)) return domain;
  }
  return "tribe";
}

function parseTools(text) {
  const re = /mcp\.tool\(\s*"([^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,/g;
  const matches = [];
  let m;
  while ((m = re.exec(text)) !== null) {
    matches.push({ start: m.index, name: m[1], description: m[2] });
  }

  const tools = [];
  for (let i = 0; i < matches.length; i++) {
    const chunkEnd = i + 1 < matches.length ? matches[i + 1].start : text.length;
    const chunk = text.slice(matches[i].start, chunkEnd);
    tools.push(analyzeChunk(matches[i].name, matches[i].description, chunk));
  }
  return tools;
}

function uniqSorted(arr) {
  return [...new Set(arr)].sort();
}

function analyzeChunk(name, description, body) {
  const rpcs = uniqSorted([...body.matchAll(/sb\.rpc\(\s*"([^"]+)"/g)].map((m) => m[1]));
  const tables = uniqSorted([...body.matchAll(/sb\.from\(\s*"([^"]+)"/g)].map((m) => m[1]));
  const canV4Calls = uniqSorted([...body.matchAll(/canV4\s*\([^,]+,\s*[^,]+,\s*['"]([^'"]+)['"]/g)].map((m) => m[1]));
  const fetchCount = (body.match(/\bfetch\(/g) || []).length;
  const usesServiceRole = /SUPABASE_SERVICE_ROLE_KEY|service_role/i.test(body);
  // Heuristic return shape: first `return ok(...` substring trimmed.
  const okReturn = body.match(/return\s+ok\(\s*(\{[\s\S]{0,160}?\}|[^)]{0,160})/);
  const returnShape = okReturn
    ? okReturn[1].replace(/\s+/g, " ").slice(0, 90)
    : null;

  return {
    name,
    description: description.replace(/\\"/g, '"').replace(/\\n/g, " ").trim(),
    domain: classifyDomain(name),
    rpcs,
    tables,
    canV4_actions: canV4Calls,
    external_fetch_count: fetchCount,
    uses_service_role: usesServiceRole,
    return_shape_hint: returnShape,
  };
}

async function fetchRuntimeTools() {
  const res = await fetch(RUNTIME_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      Authorization: "Bearer test",
      "User-Agent": "audit-mcp-tool-matrix/1.0",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }),
  });
  const text = await res.text();
  const dataLine = text.split("\n").find((l) => l.startsWith("data: "));
  if (!dataLine) throw new Error("No SSE data line in tools/list response");
  const json = JSON.parse(dataLine.slice(6));
  return json.result?.tools || [];
}

function buildMarkdown(tools, runtimeStatus) {
  const byDomain = {};
  for (const t of tools) byDomain[t.domain] = (byDomain[t.domain] || 0) + 1;
  const directTableCount = tools.filter((t) => t.tables.length).length;
  const rpcOnlyCount = tools.filter((t) => t.tables.length === 0 && t.rpcs.length > 0).length;
  const noBackendCount = tools.filter((t) => t.tables.length === 0 && t.rpcs.length === 0).length;
  const canV4Count = tools.filter((t) => t.canV4_actions.length).length;
  const fetchCount = tools.filter((t) => t.external_fetch_count > 0).length;
  const serviceRoleCount = tools.filter((t) => t.uses_service_role).length;

  const lines = [];
  lines.push("# MCP 293-Tool Contract Matrix");
  lines.push("");
  lines.push(
    "_Auto-generated by `scripts/audit-mcp-tool-matrix.mjs`. Do not edit by hand — re-run the script. Tracks issue #162 (p202, 2026-05-19)._",
  );
  lines.push("");
  lines.push(`**Generated:** ${new Date().toISOString()}`);
  lines.push(`**Source:** \`${SOURCE_PATH}\``);
  lines.push(`**Total tools (static parser):** ${tools.length}`);
  lines.push(`**Runtime cross-check:** ${runtimeStatus}`);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push("| Metric | Count |");
  lines.push("|---|---|");
  lines.push(`| Total tools | ${tools.length} |`);
  for (const [d, c] of Object.entries(byDomain).sort(([, a], [, b]) => b - a)) {
    lines.push(`| Domain: \`${d}\` | ${c} |`);
  }
  lines.push(`| Direct table reads/writes | ${directTableCount} |`);
  lines.push(`| RPC-only (no direct table) | ${rpcOnlyCount} |`);
  lines.push(`| No backend (in-memory/computed only) | ${noBackendCount} |`);
  lines.push(`| canV4-gated (JS layer) | ${canV4Count} |`);
  lines.push(`| External \`fetch(\` calls | ${fetchCount} |`);
  lines.push(`| Uses service_role | ${serviceRoleCount} |`);
  lines.push("");
  lines.push("## Direct-table-access hotspots");
  lines.push("");
  const tableHits = {};
  for (const t of tools) {
    for (const tbl of t.tables) tableHits[tbl] = (tableHits[tbl] || 0) + 1;
  }
  const ranked = Object.entries(tableHits).sort(([, a], [, b]) => b - a);
  lines.push("| Table | Tools touching it |");
  lines.push("|---|---|");
  for (const [tbl, count] of ranked) {
    lines.push(`| \`${tbl}\` | ${count} |`);
  }
  lines.push("");
  lines.push("## Matrix");
  lines.push("");
  lines.push("| Tool | Domain | RPCs | Tables | canV4 gate | Ext. fetch | service_role |");
  lines.push("|---|---|---|---|---|---|---|");
  // Sort tools by domain then name for predictable output
  const domainOrder = [
    "personal",
    "tribe",
    "board",
    "events",
    "governance",
    "comms",
    "partners",
    "gamification",
    "selection",
    "knowledge",
    "admin",
    "health",
  ];
  const order = (d) => {
    const i = domainOrder.indexOf(d);
    return i === -1 ? 99 : i;
  };
  const sorted = [...tools].sort((a, b) => {
    if (a.domain !== b.domain) return order(a.domain) - order(b.domain);
    return a.name.localeCompare(b.name);
  });
  for (const t of sorted) {
    const shortList = (arr) =>
      arr.length === 0
        ? "—"
        : `${arr.length} (${arr
            .slice(0, 2)
            .map((s) => `\`${s}\``)
            .join(", ")}${arr.length > 2 ? "…" : ""})`;
    const gate = t.canV4_actions.length ? t.canV4_actions.map((a) => `\`${a}\``).join("+") : "—";
    const fetchCol = t.external_fetch_count ? `${t.external_fetch_count}×` : "—";
    const sr = t.uses_service_role ? "✓" : "—";
    lines.push(
      `| \`${t.name}\` | ${t.domain} | ${shortList(t.rpcs)} | ${shortList(t.tables)} | ${gate} | ${fetchCol} | ${sr} |`,
    );
  }
  return lines.join("\n") + "\n";
}

const text = readFileSync(resolve(SOURCE_PATH), "utf8");
const tools = parseTools(text);
console.log(`[parser] ${tools.length} tools extracted from index.ts`);

let runtimeStatus = "skipped (--runtime not passed)";
if (process.argv.includes("--runtime")) {
  try {
    const runtimeTools = await fetchRuntimeTools();
    const runtimeNames = new Set(runtimeTools.map((t) => t.name));
    const staticNames = new Set(tools.map((t) => t.name));
    const inStaticOnly = [...staticNames].filter((n) => !runtimeNames.has(n));
    const inRuntimeOnly = [...runtimeNames].filter((n) => !staticNames.has(n));
    if (inStaticOnly.length === 0 && inRuntimeOnly.length === 0) {
      runtimeStatus = `clean (${runtimeTools.length} runtime ≡ ${tools.length} static)`;
    } else {
      runtimeStatus = `drift: ${inStaticOnly.length} static-only [${inStaticOnly.slice(0, 5).join(", ")}], ${inRuntimeOnly.length} runtime-only [${inRuntimeOnly.slice(0, 5).join(", ")}]`;
      for (const t of tools) if (!runtimeNames.has(t.name)) t.drift = "static-only";
    }
    console.log(`[runtime] ${runtimeStatus}`);
  } catch (e) {
    runtimeStatus = `error: ${e.message}`;
    console.warn(`[runtime] failed: ${e.message}`);
  }
}

mkdirSync(resolve(dirname(MATRIX_MD_PATH)), { recursive: true });

const json = {
  generated_at: new Date().toISOString(),
  source: SOURCE_PATH,
  total: tools.length,
  runtime_status: runtimeStatus,
  by_domain: tools.reduce((a, t) => ({ ...a, [t.domain]: (a[t.domain] || 0) + 1 }), {}),
  tools,
};

writeFileSync(resolve(MATRIX_JSON_PATH), JSON.stringify(json, null, 2) + "\n");
writeFileSync(resolve(MATRIX_MD_PATH), buildMarkdown(tools, runtimeStatus));

console.log(`[ok] wrote ${tools.length} rows to ${MATRIX_MD_PATH} + ${MATRIX_JSON_PATH}`);
