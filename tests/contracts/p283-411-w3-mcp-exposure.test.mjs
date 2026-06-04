import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// p283 #411 Wave 3 — MCP exposure + forward-defense
//
// Exposes notify_selection_cutoff_approved + selection_rescue_stuck_interview + the
// get_cutoff_dispatch_health observability tool on the /mcp surface, and locks the
// "RPC with zero call sites" regression class (the original #411 root cause) by asserting
// both write RPCs have call sites in BOTH the frontend (src/) AND the MCP server.

const MCP = readFileSync('supabase/functions/nucleo-mcp/index.ts', 'utf8');
const PAGE = readFileSync('src/pages/admin/selection.astro', 'utf8');

describe('p283 #411 Wave 3 — MCP tool registration', () => {
  it('registers get_cutoff_dispatch_health (params-less health tool)', () => {
    assert.match(MCP, /mcp\.tool\("get_cutoff_dispatch_health"/);
    assert.match(MCP, /sb\.rpc\("get_cutoff_dispatch_health"\)/);
  });
  it('registers notify_selection_cutoff_approved write tool', () => {
    assert.match(MCP, /mcp\.tool\("notify_selection_cutoff_approved"/);
    assert.match(MCP, /sb\.rpc\("notify_selection_cutoff_approved", \{ p_application_id: params\.application_id \}\)/);
  });
  it('registers selection_rescue_stuck_interview write tool', () => {
    assert.match(MCP, /mcp\.tool\("selection_rescue_stuck_interview"/);
    assert.match(MCP, /sb\.rpc\("selection_rescue_stuck_interview", \{ p_application_id: params\.application_id \}\)/);
  });
  it('each new tool registered exactly once (no duplicate-name SDK boot crash)', () => {
    for (const t of ['get_cutoff_dispatch_health', 'notify_selection_cutoff_approved', 'selection_rescue_stuck_interview']) {
      const n = (MCP.match(new RegExp(`mcp\\.tool\\("${t}"`, 'g')) || []).length;
      assert.strictEqual(n, 1, `${t} must be registered exactly once; found ${n}`);
    }
  });
  it('write tools authenticate + UUID-validate before dispatch', () => {
    for (const t of ['notify_selection_cutoff_approved', 'selection_rescue_stuck_interview']) {
      const block = MCP.slice(MCP.indexOf(`mcp.tool("${t}"`), MCP.indexOf(`mcp.tool("${t}"`) + 1400);
      assert.match(block, /const member = await getMember\(sb\)/, `${t} must authenticate`);
      assert.match(block, /isUUID\(params\.application_id\)/, `${t} must validate the UUID`);
    }
  });
});

describe('p283 #411 Wave 3 — forward-defense: no orphan RPCs (locks the original #411 regression)', () => {
  // The original bug: notify_selection_cutoff_approved shipped with ZERO UI call sites, so 7
  // above-band researchers sat un-invited for 21 days. These assertions fail CI if either RPC
  // ever loses its frontend OR its MCP call site.
  it('notify_selection_cutoff_approved has a frontend (src/) call site', () => {
    assert.ok(
      PAGE.includes("sb.rpc('notify_selection_cutoff_approved'"),
      'notify_selection_cutoff_approved must keep at least one src/ call site (admin/selection.astro)'
    );
  });
  it('notify_selection_cutoff_approved has an MCP call site', () => {
    assert.ok(MCP.includes('sb.rpc("notify_selection_cutoff_approved"'));
  });
  it('selection_rescue_stuck_interview has a frontend (src/) call site', () => {
    assert.ok(PAGE.includes("sb.rpc('selection_rescue_stuck_interview'"));
  });
  it('selection_rescue_stuck_interview has an MCP call site', () => {
    assert.ok(MCP.includes('sb.rpc("selection_rescue_stuck_interview"'));
  });
});
