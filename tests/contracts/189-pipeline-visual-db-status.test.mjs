/**
 * Contract: #189 — the curation pipeline visual must mirror the DB curation_status FSM.
 *
 * CardDetail.tsx hardcoded an 8-step aspirational strip
 * (ideation/research/drafting/author_review/.../curation/published) while the DB CHECK
 * allows only {draft, peer_review, leader_review, curation_pending, published}. A
 * curation_pending item got NO highlight (steps.indexOf('curation_pending') = -1).
 * This locks the strip to the 5 real states so indexOf resolves for every live value.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const CARD = resolve(ROOT, 'src/components/board/CardDetail.tsx');
const TYPES = resolve(ROOT, 'src/types/board.ts');
const cardRaw = existsSync(CARD) ? readFileSync(CARD, 'utf8') : '';
const typesRaw = existsSync(TYPES) ? readFileSync(TYPES, 'utf8') : '';

const DB_STATES = ['draft', 'peer_review', 'leader_review', 'curation_pending', 'published'];

test('#189: pipeline steps array equals the 5 DB curation_status states', () => {
  assert.ok(cardRaw, 'CardDetail.tsx readable');
  const expected = `['${DB_STATES.join("', '")}']`;
  assert.ok(cardRaw.includes(expected),
    `CardDetail.tsx must contain the canonical steps array ${expected}`);
});

test('#189: aspirational phantom steps are gone', () => {
  for (const phantom of ['ideation', 'drafting', 'author_review']) {
    assert.ok(!cardRaw.includes(`'${phantom}'`),
      `CardDetail.tsx must not reference the aspirational step '${phantom}'`);
  }
  // the standalone 8-step 'curation' token (vs the real 'curation_pending') must be gone
  assert.doesNotMatch(cardRaw, /'leader_review', 'curation', 'published'/,
    "the old 8-step 'curation' token must be replaced by 'curation_pending'");
});

test('#189: the strip matches the CurationStatus union in board.ts (single source of truth)', () => {
  assert.ok(typesRaw, 'board.ts readable');
  for (const s of DB_STATES) {
    assert.ok(typesRaw.includes(`'${s}'`),
      `CurationStatus union must include '${s}' (drift between visual + type)`);
  }
});
