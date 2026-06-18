/**
 * Contract: #106 PR3 — chapter selection pipeline (Bloco 3).
 *
 * Per SPEC_106_CHAPTER_DASHBOARD.md: a SEPARATE lazy-loaded RPC get_chapter_selection_summary
 * (data-architect: do NOT inflate the get_chapter_dashboard monolith), same V4 own-chapter gate,
 * filtered by selection_cycles.contracting_chapter (NOT selection_applications.chapter). Returns the
 * open cycle (live) + a 'last' fallback for the graceful empty-state (ux R2).
 *
 * Offline source assertions; no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG = read('supabase/migrations/20260805000215_106_pr3_chapter_selection_summary.sql');
const FE = read('src/components/chapter/ChapterDashboard.tsx');

test('migration 20260805000215 exists', () => {
  assert.ok(MIG, 'PR3 migration file exists');
});

test('RPC is a SEPARATE SECDEF function with the own-chapter gate', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_chapter_selection_summary\(p_chapter text/);
  assert.match(MIG, /SECURITY DEFINER/);
  assert.match(MIG, /SET search_path TO ''/);
  // mirrors get_chapter_dashboard gate
  assert.match(MIG, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/);
  assert.match(MIG, /p_chapter = v_caller_chapter/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_chapter_selection_summary\(text\) TO authenticated/);
});

test('RPC filters by contracting_chapter (not selection_applications.chapter)', () => {
  assert.match(MIG, /sc\.contracting_chapter = v_chapter/);
  assert.ok(!/sa\.chapter = v_chapter/.test(MIG), 'must not filter apps by the arbitrary selection_applications.chapter');
  // open cycle + last fallback for empty-state
  assert.match(MIG, /sc\.status = 'open'/);
  assert.match(MIG, /'open'/);
  assert.match(MIG, /'last'/);
});

test('FE renders the pipeline block with a graceful empty-state', () => {
  assert.match(FE, /rpc\(['"]get_chapter_selection_summary['"]/);
  assert.match(FE, /pipeline\.open/);
  // empty-state path uses the i18n empty + last-cycle strings
  assert.match(FE, /pipelineEmpty/);
  assert.match(FE, /pipelineLast/);
  // open-state shows app count + deadline
  assert.match(FE, /open_apps/);
});

test('FE pipeline does not inflate get_chapter_dashboard (separate rpc call)', () => {
  // both rpcs are called independently in the component (each with their own args)
  assert.match(FE, /rpc\(['"]get_chapter_dashboard['"]/);
  assert.match(FE, /rpc\(['"]get_chapter_selection_summary['"]/);
});
