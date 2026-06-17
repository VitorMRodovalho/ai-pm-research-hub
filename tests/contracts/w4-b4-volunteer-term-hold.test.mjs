/**
 * Contract: Wave 4 B4 (#740) — volunteer term "signature hold" is communicated with dignity.
 *
 * The volunteer term is under a deliberate governance signature hold (action
 * `governance.term_signature_hold`, 2026-06-10): the active template was moved to under_review
 * while the term is revised (new IP/governance version + corrective addendum). With no active
 * template, `sign_volunteer_agreement` returns `template_not_found`. Before this slice the member
 * filled the whole form and hit a cryptic generic error toast at submit. B4 detects the hold on
 * the FRONT and shows a graceful "paused" screen instead — no DB change (the hold is the PM's
 * governance lever; we only communicate it).
 *
 * Static-only (reads the FE file + i18n) → runs without DB env.
 *
 * Cross-ref: #740 Wave 4, ADR-0104.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const VA = readFileSync('src/pages/volunteer-agreement.astro', 'utf8');

describe('w4-b4 — paused screen exists and is wired', () => {
  it('defines a renderPaused(lang) screen', () => {
    assert.match(VA, /function renderPaused\(lang: Lang\): string/);
    // surfaces the paused copy lines + the back CTA + the profile hint
    assert.match(VA, /volunteer\.paused\.title/);
    assert.match(VA, /volunteer\.paused\.description/);
    assert.match(VA, /volunteer\.paused\.addendumNote/);
    assert.match(VA, /volunteer\.paused\.profileHint/);
    assert.match(VA, /volunteer\.paused\.backCta/);
  });

  it('labels the status icon for screen readers (a11y)', () => {
    assert.match(VA, /role="img" aria-label="\$\{esc\(t\('volunteer\.paused\.iconLabel', lang\)\)\}"/);
  });

  it('detects the hold by the ABSENCE of an active template row (not a parse failure)', () => {
    assert.match(VA, /\.select\('id, content'\)/);
    assert.match(VA, /activeTemplateRow = docs\?\.\[0\] \|\| null/);
    assert.match(VA, /if \(!activeTemplateRow\) \{\s*\n\s*app\.innerHTML = renderPaused\(lang\);\s*\n\s*return;\s*\n\s*\}/);
  });

  it('the paused gate runs BEFORE the profile-completeness gate', () => {
    const pausedIdx = VA.indexOf('if (!activeTemplateRow)');
    const missingIdx = VA.indexOf('if (missing.length > 0)');
    assert.ok(pausedIdx > 0 && missingIdx > 0, 'both gates present');
    assert.ok(pausedIdx < missingIdx, 'paused gate must precede the missing-fields gate');
  });

  it('handles a mid-session template_not_found at submit with the same paused screen', () => {
    assert.match(VA, /if \(data\?\.error === 'template_not_found'\) \{ app\.innerHTML = renderPaused\(lang\); return; \}/);
  });

  it('does not reintroduce a second active-template query (template loaded once, before the form)', () => {
    const occurrences = (VA.match(/\.eq\('status', 'active'\)/g) || []).length;
    assert.equal(occurrences, 1, 'exactly one active-template query');
  });
});

describe('w4-b4 — i18n 3-dict parity', () => {
  const KEYS = [
    'volunteer.paused.title',
    'volunteer.paused.iconLabel',
    'volunteer.paused.description',
    'volunteer.paused.addendumNote',
    'volunteer.paused.profileHint',
    'volunteer.paused.backCta',
  ];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    it(`${dict} defines every new key`, () => {
      const src = readFileSync(`src/i18n/${dict}.ts`, 'utf8');
      for (const k of KEYS) {
        assert.ok(src.includes(`'${k}':`), `${dict} missing ${k}`);
      }
    });
  }
});
