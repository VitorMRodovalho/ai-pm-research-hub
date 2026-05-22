/**
 * Forward-defense: MCP /mcp worker proxy strips non-spec `execution.taskSupport`
 * and inputSchema `$schema` fields from tools/list responses for spec-strict clients (Perplexity).
 *
 * Origin: p220 session (2026-05-22) — after fixing the OAuth allowlist
 * (Perplexity subdomain coverage via host endsWith), the connector
 * authenticated successfully but Perplexity UI showed "No tools to display"
 * despite the upstream MCP server returning tools/list with all 299 tools.
 * Diagnosis: each tool definition carries `execution:{taskSupport:"forbidden"}`,
 * an Anthropic-internal extension added by @modelcontextprotocol/sdk@1.29.0
 * (Claude Managed Agents task-scheduling hint). This field is NOT part of the
 * public MCP spec — stricter validators (Perplexity, possibly Cursor) silently
 * drop the entire tools array on unknown top-level fields.
 *
 * Fix: post-process tools/list responses in the Worker proxy at src/pages/mcp.ts.
 * The SDK serializes `execution` with a constant value, and Zod emits a constant
 * draft-07 `$schema` URI; literal regexes avoid JSON parse cost on the hot path.
 *
 * Cross-ref:
 *   - src/pages/mcp.ts (the proxy with the strip)
 *   - PR #275 (Perplexity OAuth allowlist fix that unblocked the auth step)
 *   - https://spec.modelcontextprotocol.io (no `execution` field in spec)
 *
 * Static-only bundle: source-code checks (no SSE parser to run).
 *   1. Detection of tools/list method via regex on request body
 *   2. Strip applied universally (not gated on client User-Agent — defensive)
 *   3. Two regex variants cover leading-comma + trailing-comma positions for execution
 *   4. `$schema` is also stripped from inputSchema payloads for Perplexity compatibility
 *   5. content-length header deleted so client receives correct length
 *   6. Strip happens BEFORE the SSE streaming branch (so SSE tools/list also cleaned)
 *   7. kvLog instrumented to record rawLen/cleanedLen/stripped delta
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(resolve(process.cwd(), 'src/pages/mcp.ts'), 'utf8');

test('mcp proxy: detects tools/list method via request body regex', () => {
  assert.match(SRC, /const\s+isToolsList\s*=\s*[\s\S]*?"method"\s*[\\]*?[\s\S]*?"tools\\?\/list"/,
    'Worker must detect tools/list via regex on reqBody — used to gate the strip behavior');
});

test('mcp proxy: strips execution field with leading-comma variant', () => {
  assert.match(SRC, /\.replace\(\s*\/,\\s\*"execution"\\s\*:\\s\*\\\{\\s\*"taskSupport"\\s\*:\\s\*"forbidden"\\s\*\\\}\/g/,
    'Must strip ",execution:{taskSupport:forbidden}" (field appears mid-object)');
});

test('mcp proxy: strips execution field with trailing-comma variant', () => {
  assert.match(SRC, /\.replace\(\s*\/"execution"\\s\*:\\s\*\\\{\\s\*"taskSupport"\\s\*:\\s\*"forbidden"\\s\*\\\}\\s\*,\?\/g/,
    'Must also strip "execution:{taskSupport:forbidden}" with optional trailing comma (field appears at start of object)');
});

test('mcp proxy: strips inputSchema $schema with both comma-position variants', () => {
  const schemaStripCount = (SRC.match(/json-schema\\.org\\\/draft-07\\\/schema#/g) || []).length;
  assert.ok(schemaStripCount >= 2,
    'Must strip draft-07 $schema in both leading-comma and trailing-comma positions');
  assert.ok(SRC.includes('"\\$schema"'),
    'Strip regex must target the literal $schema key');
});

test('mcp proxy: deletes content-length header after strip (length mismatch prevention)', () => {
  // After mutation, the body is shorter; forwarding original content-length
  // would cause some clients (or CDNs) to truncate. Must drop the header.
  assert.match(SRC, /respHeadersOut\.delete\(['"]content-length['"]\)/,
    'Must delete content-length header on the cleaned response');
});

test('mcp proxy: tools/list strip happens BEFORE SSE streaming branch', () => {
  // Order matters — if SSE branch fires first, tools/list passes through unprocessed
  const isToolsListIdx = SRC.indexOf('isToolsList');
  const sseStreamIdx = SRC.indexOf('For SSE responses');
  assert.ok(isToolsListIdx > 0 && sseStreamIdx > 0,
    'Both markers must be present in src/pages/mcp.ts');
  // Need the isToolsList HANDLING (the `if (isToolsList)` block) to appear before
  // the SSE branch. Find the `if (isToolsList)` line.
  const ifToolsListIdx = SRC.indexOf('if (isToolsList)');
  assert.ok(ifToolsListIdx > 0 && ifToolsListIdx < sseStreamIdx,
    'The `if (isToolsList)` handling block must appear before the SSE streaming branch — otherwise SSE-wrapped tools/list bypasses the cleanup');
});

test('mcp proxy: kvLog instruments raw vs cleaned length delta', () => {
  assert.match(SRC, /kvLog\(["']mcp-upstream-tools-list["'],/,
    'A dedicated kvLog event must be emitted for tools/list (separable from generic mcp-upstream)');
  assert.match(SRC, /rawLen[\s\S]{0,200}cleanedLen[\s\S]{0,200}stripped/,
    'kvLog payload must include rawLen, cleanedLen, stripped (=delta) for observability');
});

test('mcp proxy: rationale comment documents the Perplexity / spec-strict client gap', () => {
  assert.match(SRC, /Perplexity/i,
    'Comment must reference Perplexity as the spec-strict client motivating this strip');
  assert.match(SRC, /spec\.modelcontextprotocol\.io|MCP spec/i,
    'Comment must reference the official MCP spec as the contract being honored');
});

test('mcp proxy: strip applies universally (not gated on User-Agent)', () => {
  // Defensive choice: every client benefits from a spec-compliant payload, and
  // gating on UA would create a "works on Claude.ai but not Perplexity" matrix
  // that future devs would have to maintain. Strip universally.
  const conditionMatch = SRC.match(/if\s*\(\s*isToolsList\s*\)/);
  assert.ok(conditionMatch, 'Strip must be gated only on `isToolsList`, no UA / client-name check');
  const block = SRC.slice(conditionMatch.index, conditionMatch.index + 2000);
  assert.doesNotMatch(block, /user-agent|userAgent/i,
    'Strip block must NOT branch on User-Agent — universal application');
});
