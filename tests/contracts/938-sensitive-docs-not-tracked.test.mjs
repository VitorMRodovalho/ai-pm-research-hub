/**
 * #938 Contract Test: CI guard against re-introducing sensitive docs (forward-protection)
 * [gov][#816 split] — https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/938
 *
 * This repo is PUBLIC. The `.gitignore` #816 block (legal/PII/partner/internal-draft docs)
 * only blocks FUTURE untracked adds — it does NOT catch files that are ALREADY tracked, nor
 * a future `git add -f`. This guard closes that gap: it lists tracked files that match the
 * #816 sensitive patterns and FAILS if any appears outside the explicit baseline allowlist.
 *
 * ── Design (grounded 2026-07-11) ────────────────────────────────────────────────────────
 * Patterns are DERIVED from the `.gitignore` #816 block (SSOT — no duplication) and matched
 * with git's OWN ignore engine via `git ls-files -i -c -x <pattern>`. This is path-anchored:
 * a naive substring match of `p277_`/`video_screening` catches 36 tracked files, 35 of which
 * are LEGITIMATE migrations (session-prefix / feature-name) — false positives of the W28
 * "73 events" class. The git-native match catches only the real `docs/`-anchored sensitive
 * files. Do NOT replace this with substring matching.
 *
 * ── Baseline / ratchet ──────────────────────────────────────────────────────────────────
 * The 16 files below are currently tracked AND match the #816 patterns. They are the
 * baseline; each carries a disposition. The guard fails on any NEW match. As #816's history
 * rewrite removes the purge-TODO entries, delete them from this allowlist so it ratchets DOWN
 * (same mechanic as the p175 drift allowlist). A shrinking allowlist is the success signal.
 *
 * Carve-out that MUST stay tracked: `docs/legal/` (public compliance/transparency SSOT under
 * its own contract tests — deliberately excluded from the #816 block, see .gitignore).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();

// ── Baseline allowlist ──────────────────────────────────────────────────────────────────
// Tracked files that match the #816 patterns today. Removal is OUT OF SCOPE here (#938 is
// additive: guard + audit) and deferred to #816's destructive history rewrite. Ratchet DOWN
// as the rewrite lands: delete the corresponding lines below.
const BASELINE = new Set([
  // Group 1 — confirmed PII / legal (known escapees; motivated this guard). TODO: purge in #816 rewrite.
  'docs/drafts/p269_briefing_reuniao_advogada_cr050_frontiers.pdf',
  'docs/drafts/p277_email_desligamento_alumni_malu_andressa.md',
  // Group 2 — internal / legal-draft docs surfaced by the 2nd-pass audit. TODO: purge in #816 rewrite.
  'docs/drafts/v2.7_p153_tap_cpmai_v1.docx',
  'docs/editorial/drafts/FRONTIERS_EDITORIAL_GUIDE_v1_DRAFT.html',
  // Group 3 — commercial pitch-deck build tooling (partner-named: Kruel/CEIA/LATAM). The heavy
  // .pptx/.pdf decks are ALREADY untracked (nested docs/strategy/deck/.gitignore). TODO: purge/untrack in #816.
  'docs/strategy/deck/.gitignore',
  'docs/strategy/deck/build.py',
  'docs/strategy/deck/build_kruel.py',
  'docs/strategy/deck/deck_engine.py',
  'docs/strategy/deck/gen_assets.py',
  'docs/strategy/deck/gen_assets_ceia.py',
  'docs/strategy/deck/gen_assets_kruel.py',
  'docs/strategy/deck/assets/ceia_bridge.png',
  'docs/strategy/deck/assets/hub_spoke.png',
  'docs/strategy/deck/assets/hub_spoke_en.png',
  'docs/strategy/deck/assets/strategy_flow.png',
  'docs/strategy/deck/assets/synergy.png',
]);

/**
 * Extract the path-anchored patterns from the `.gitignore` #816 block, i.e. every non-comment,
 * non-empty line between the `# === #816 ...` header and the `# === END #816 ===` sentinel.
 */
function extractSensitivePatterns() {
  const lines = readFileSync(resolve(ROOT, '.gitignore'), 'utf8').split('\n');
  const start = lines.findIndex((l) => /^# === #816\b/.test(l));
  const end = lines.findIndex((l) => /^# === END #816 ===/.test(l));
  assert.ok(start !== -1, '.gitignore must contain the `# === #816` block header');
  assert.ok(end !== -1 && end > start, '.gitignore must contain the `# === END #816 ===` sentinel after the header');
  return lines
    .slice(start + 1, end)
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith('#'));
}

/** Tracked files that match the given ignore patterns, via git's own (path-anchored) engine. */
function trackedMatchingPatterns(patterns) {
  const xArgs = patterns.flatMap((p) => ['-x', p]);
  const out = execFileSync('git', ['ls-files', '-i', '-c', ...xArgs], {
    cwd: ROOT,
    encoding: 'utf8',
  });
  return out.split('\n').map((l) => l.trim()).filter(Boolean);
}

test('#938 .gitignore #816 block is delimited by header + END sentinel', () => {
  const patterns = extractSensitivePatterns();
  assert.ok(patterns.length >= 10, `expected the #816 block to yield its sensitive patterns, got ${patterns.length}`);
  // Every #816 pattern is docs/-anchored — this is what makes the guard immune to the substring trap.
  const stray = patterns.filter((p) => !p.startsWith('docs/'));
  assert.deepEqual(stray, [], `#816 patterns must be docs/-anchored (path-scoped), found stray: ${stray.join(', ')}`);
});

test('#938 no sensitive doc is tracked outside the baseline allowlist', () => {
  const patterns = extractSensitivePatterns();
  const matched = trackedMatchingPatterns(patterns);
  const offenders = matched.filter((f) => !BASELINE.has(f));
  assert.deepEqual(
    offenders,
    [],
    `Sensitive doc(s) newly tracked (match the .gitignore #816 legal/PII block):\n  ${offenders.join('\n  ')}\n` +
      `If legitimately public, add an explicit carve-out. Otherwise remove from tracking (git rm --cached) ` +
      `and route to the #816 rewrite. NEVER just add to the baseline to silence this.`,
  );
});

test('#938 baseline allowlist does not drift above the real tracked set (ratchet DOWN only)', () => {
  const patterns = extractSensitivePatterns();
  const matched = new Set(trackedMatchingPatterns(patterns));
  // Stale baseline entries (file already removed/renamed) must be pruned so the allowlist keeps shrinking.
  const stale = [...BASELINE].filter((f) => !matched.has(f));
  assert.deepEqual(
    stale,
    [],
    `Baseline allowlist has stale entries no longer tracked — prune them so the guard ratchets down:\n  ${stale.join('\n  ')}`,
  );
});
