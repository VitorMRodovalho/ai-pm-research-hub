import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// p272 #365d — renderTable() must NOT silently override the upstream column sort
//
// Bug context (PM-observed post-#407 deploy):
// User clicked "Pesquisa" header → arrow updated to ↓, but visible rows stayed
// in their previous order. Root cause: renderTable() at L1558 did
// `const displayRows = [...filteredRows].sort((a, b) => track-rank-asc)`,
// which re-sorted the array AFTER applyFilters() had already sorted it by
// sortCol/sortAsc. The internal sort was leftover from a pre-column-sort era
// (when row order was a fixed track-rank interleave). Once column sorting
// exists, this second sort silently undid every user click.
//
// Fix: drop the internal sort. displayRows = filteredRows directly. Upstream
// applyFilters() is the single source of truth for row order.

const PAGE = readFileSync('src/pages/admin/selection.astro', 'utf8');

describe('p272 #365d renderTable must not override upstream sort', () => {
  it('renderTable has NO internal sort that overrides applyFilters() (regression lock)', () => {
    assert.doesNotMatch(
      PAGE,
      /\[\.\.\.filteredRows\]\.sort\(/,
      'renderTable must NEVER spread-copy + re-sort filteredRows — that silently overrode column-click sorting (PM-observed regression class).'
    );
  });

  it('renderTable assigns displayRows = filteredRows directly (single source of truth)', () => {
    assert.match(
      PAGE,
      /const displayRows = filteredRows;/,
      'renderTable must use filteredRows directly so applyFilters().sort() result reaches the DOM unmodified.'
    );
  });

  it('useLeaderRank + useResearcherRank still derived for track-aware rankDisplay', () => {
    assert.match(
      PAGE,
      /const useLeaderRank = filterRole === 'leader';\s*const useResearcherRank = filterRole === 'researcher';/,
      'track-aware booleans must remain — the row template uses them to build rankDisplay ("L#N" / "P#N" / interleaved).'
    );
  });

  it('applyFilters() retains canonical sort against sortCol (no other place handles row order)', () => {
    assert.match(
      PAGE,
      /filteredRows\.sort\(\(a, b\) => \{[\s\S]*?let va = a\[sortCol\]/,
      'upstream sort in applyFilters() must remain — single source of row order; if this is removed, no sort happens at all.'
    );
  });

  it('forward-defense: filteredRows is sorted exactly once as a function call (not counting comment references)', () => {
    // Match the actual call pattern `filteredRows.sort((` — comments referencing
    // the bug history may include the bare token but won't include the arrow-fn
    // open-paren. Tightens regex vs naive `\.sort\(` count which double-counts
    // documentation lines.
    const callMatches = PAGE.match(/filteredRows\.sort\(\(/g) || [];
    assert.equal(
      callMatches.length,
      1,
      `exactly 1 filteredRows.sort(( call expected (the upstream one in applyFilters); found ${callMatches.length}. A second call would re-introduce the #365d override bug.`
    );
  });
});
