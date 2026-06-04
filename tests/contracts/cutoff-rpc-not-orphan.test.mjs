import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// #411 SPEC Wave 3 sediment guard — cutoff-rpc-not-orphan
//
// notify_selection_cutoff_approved was shipped p228 (2026-05-21) but had ZERO UI call sites
// until p270/p271. Seven above-band researchers sat with welcome-email-only for 21 days because
// no surface invoked it. This test locks that regression class: it fails CI the moment the RPC
// stops being invoked from the frontend, forcing whoever removes the call site to either restore
// it or consciously delete this guard.
//
// Wave 1c+1d added two MORE invocation surfaces (bulk dispatch + the rescue RPC's internal call),
// and Wave 2a added the daily cron — but the canonical, user-visible surface that closed the
// original regression is the modal/bulk wiring in src/pages/admin/selection.astro.

const PAGE = readFileSync('src/pages/admin/selection.astro', 'utf8');

describe('#411 cutoff-rpc-not-orphan — notify_selection_cutoff_approved keeps a live UI surface', () => {
  it('admin/selection.astro invokes notify_selection_cutoff_approved (single-dispatch F1 + bulk F3)', () => {
    const hits = (PAGE.match(/sb\.rpc\('notify_selection_cutoff_approved'/g) || []).length;
    assert.ok(
      hits >= 1,
      'notify_selection_cutoff_approved lost its frontend call site — the original orphan-RPC ' +
      'regression (#411) is back. Restore the modal/bulk wiring or consciously remove this guard.'
    );
  });

  it('the rescue path keeps the RPC reachable too (selection_rescue_stuck_interview wired)', () => {
    assert.ok(
      PAGE.includes("sb.rpc('selection_rescue_stuck_interview'"),
      'the F4 rescue surface (which re-dispatches via notify) must stay wired'
    );
  });
});
