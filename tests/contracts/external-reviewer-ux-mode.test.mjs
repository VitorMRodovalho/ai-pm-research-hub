/**
 * Forward-defense: BUG-219.A Phase 3 — UX comment-only mode + external-friendly
 * route /governance/documents/[chainId]/* for external reviewers.
 *
 * Origin: p219 close session — PM smoke discovered advogada Angelina was
 * blocked from /admin/governance/documents/[chainId] via "negativa de acesso"
 * because (a) she had no members row yet (resolved Phase 1) and (b) the read
 * RPCs gated strict on manage_member (resolved Phase 2). This Phase 3 closes
 * the loop on UX:
 *   - new route /governance/documents/[chainId] (no /admin prefix) with
 *     BaseLayout (no admin sidebar)
 *   - ReviewChainIsland exposes externalReviewMode={true} prop that:
 *       • shows top banner explaining comment-only scope
 *       • routes PDF/DOCX/Audit buttons to /governance/* siblings (not /admin/*)
 *   - canComment widened to include the p195 carve-out (any caller with
 *     can_by_member('participate_in_governance_review') gets comment UI)
 *
 * Cross-ref:
 *   - src/pages/governance/documents/[chainId]/{index,export-pdf,export-docx,audit-report}.astro
 *   - src/pages/en/governance/documents/[chainId]/index.astro (locale redirect)
 *   - src/pages/es/governance/documents/[chainId]/index.astro (locale redirect)
 *   - src/components/governance/ReviewChainIsland.tsx (externalReviewMode prop +
 *     canReviewGovernance state + isCommentOnlyMode banner)
 *   - supabase/migrations/20260804000000_p220_bug_219_a_external_reviewer_rpc_carve_out.sql
 *   - P162 BUG-219.A
 *
 * Static-only bundle (no DB env required):
 *   1. New /governance/* routes exist for chain review + 3 sub-actions
 *   2. en/es locale redirect stubs exist (GC-097 i18n parity)
 *   3. ReviewChainIsland accepts externalReviewMode prop with safe default (false)
 *   4. Banner conditional uses isCommentOnlyMode OR explicit externalReviewMode
 *   5. Export/audit links switch to /governance/* path when externalReviewMode=true
 *   6. canComment now includes canReviewGovernance (the p195 carve-out lift)
 *
 * Behavioural smoke is manual (no auth context in node:test) — flagged for PM.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE_DIR = resolve(ROOT, 'src/pages/governance/documents/[chainId]');
const ISLAND_FILE = resolve(ROOT, 'src/components/governance/ReviewChainIsland.tsx');

test('p220 BUG-219.A Phase 3: /governance/documents/[chainId] routes exist (no /admin prefix)', () => {
  for (const sub of ['index.astro', 'export-pdf.astro', 'export-docx.astro', 'audit-report.astro']) {
    const f = resolve(PAGE_DIR, sub);
    assert.ok(existsSync(f),
      `Missing route ${sub} — external reviewer needs /governance/documents/[chainId]/* sibling to /admin/governance/* with BaseLayout (no admin sidebar)`);
  }
});

test('p220 BUG-219.A Phase 3: en/es locale redirect stubs for index page (GC-097 i18n parity)', () => {
  const en = resolve(ROOT, 'src/pages/en/governance/documents/[chainId]/index.astro');
  const es = resolve(ROOT, 'src/pages/es/governance/documents/[chainId]/index.astro');
  assert.ok(existsSync(en), 'EN locale redirect for /governance/documents/[chainId] missing');
  assert.ok(existsSync(es), 'ES locale redirect for /governance/documents/[chainId] missing');
  assert.match(readFileSync(en, 'utf8'), /Astro\.redirect\(['"]\/governance\/documents\//,
    'EN redirect must point to canonical /governance/documents/* path');
  assert.match(readFileSync(es, 'utf8'), /Astro\.redirect\(['"]\/governance\/documents\//,
    'ES redirect must point to canonical /governance/documents/* path');
});

test('p220 BUG-219.A Phase 3: /governance/documents/[chainId]/index.astro uses BaseLayout (no AdminLayout)', () => {
  const body = readFileSync(resolve(PAGE_DIR, 'index.astro'), 'utf8');
  assert.match(body, /import\s+BaseLayout\s+from\s+['"][^'"]*BaseLayout\.astro['"]/,
    'Must import BaseLayout (no admin sidebar). AdminLayout would defeat the purpose of an external-reviewer-friendly URL.');
  assert.doesNotMatch(body, /AdminLayout/,
    'Must NOT use AdminLayout — external reviewer should not see admin sidebar/breadcrumbs.');
  assert.match(body, /<ReviewChainIsland[^>]*externalReviewMode=\{true\}/,
    'Must pass externalReviewMode={true} to ReviewChainIsland so banner renders + export links route to /governance/*');
});

test('p220 BUG-219.A Phase 3: ReviewChainIsland accepts externalReviewMode prop with safe default', () => {
  const body = readFileSync(ISLAND_FILE, 'utf8');
  assert.match(body, /externalReviewMode\s*=\s*false/,
    'externalReviewMode prop must default to false so existing /admin/* callers keep current behavior (backwards-compatible)');
  assert.match(body, /externalReviewMode\?\s*:\s*boolean/,
    'externalReviewMode must be typed as optional boolean in the props interface');
});

test('p220 BUG-219.A Phase 3: ReviewChainIsland probes p195 carve-out via can_by_member', () => {
  const body = readFileSync(ISLAND_FILE, 'utf8');
  assert.match(body, /sb\.rpc\(['"]can_by_member['"],\s*\{[^}]*p_action:\s*['"]participate_in_governance_review['"]/,
    'Island must call can_by_member(p_action=participate_in_governance_review) to detect external reviewers');
  assert.match(body, /canReviewGovernance/,
    'Island must store the probe result in canReviewGovernance state');
});

test('p220 BUG-219.A Phase 3: canComment widened to include carve-out', () => {
  const body = readFileSync(ISLAND_FILE, 'utf8');
  // Must reference canReviewGovernance in the canComment expression — the whole
  // point of Phase 3 is letting external reviewers comment without
  // manage_member/curator/submitter rights.
  const canCommentMatch = body.match(/const\s+canComment\s*=\s*[^;]+;/);
  assert.ok(canCommentMatch, 'canComment derivation must be present');
  assert.match(canCommentMatch[0], /canReviewGovernance/,
    'canComment expression must include canReviewGovernance — otherwise carve-out users (e.g., Angelina) cannot comment despite holding the capability');
});

test('p220 BUG-219.A Phase 3: comment-only banner conditional', () => {
  const body = readFileSync(ISLAND_FILE, 'utf8');
  assert.match(body, /isCommentOnlyMode\s*=\s*canReviewGovernance\s*&&\s*!isCurator\s*&&\s*!isSubmitter\s*&&\s*!isAdmin/,
    'isCommentOnlyMode derivation must require carve-out AND none of the strict caps (curator/submitter/admin)');
  assert.match(body, /Modo de revisão externa/,
    'Banner copy must label the mode as "Modo de revisão externa" — keeps users oriented');
});

test('p220 BUG-219.A Phase 3: export/audit links toggle /governance ↔ /admin based on mode', () => {
  const body = readFileSync(ISLAND_FILE, 'utf8');
  // All three buttons must use the conditional path
  for (const sub of ['export-pdf', 'export-docx', 'audit-report']) {
    const re = new RegExp(`externalReviewMode\\s*\\?\\s*['"]\\/governance['"]\\s*:\\s*['"]\\/admin\\/governance['"][\\s\\S]*?\\/documents\\/\\$\\{detail\\.chain_id\\}\\/${sub}`);
    assert.match(body, re,
      `${sub} link must toggle path prefix via externalReviewMode (no admin chrome for external reviewers)`);
  }
});
