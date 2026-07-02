// tests/affiliation-chapters.test.mjs
// #995 — the Filiação queue must recognize the STRING form of pmi_memberships
// ("<State>, Brazil Chapter"), not only the enriched-object form. Before the fix,
// brChapters() filtered on m?.chapterName and returned [] for string[] input, so every
// enriched member fell through to the "verificar manualmente" warning (45/82 live).
//
// The string-form test below encodes exactly the bug: against the pre-fix parser it
// returned [] (→ warning); post-fix it returns the chapter. Non-no-op.
import test from 'node:test';
import assert from 'node:assert/strict';
import { brChapters, soonestBrExpiry } from '../src/lib/affiliation-chapters.ts';

// Fixed clock so expired/soon windows are deterministic.
const NOW = Date.parse('2026-07-01T00:00:00Z');

test('#995 string form ("<State>, Brazil Chapter") is recognized (the bug: fell through to warning)', () => {
  const r = brChapters(['PMI Global', 'Pernambuco, Brazil Chapter'], NOW);
  assert.equal(r.length, 1, 'exactly the BR chapter, PMI Global filtered out');
  assert.equal(r[0].name, 'Pernambuco');
  assert.equal(r[0].expiry, null, 'string form carries no expiry');
  assert.equal(r[0].expired, false);
  assert.equal(r[0].soon, false);
});

test('#995 enriched object form { chapterName, expiryDate } still works, with expiry window', () => {
  const soonISO = new Date(NOW + 10 * 86400000).toISOString();
  const r = brChapters([{ chapterName: 'São Paulo, Brazil Chapter', expiryDate: soonISO }], NOW);
  assert.equal(r.length, 1);
  assert.equal(r[0].name, 'São Paulo');
  assert.equal(r[0].soon, true, 'expiry within 30d → soon');
  assert.equal(r[0].expired, false);
});

test('#995 mixed string + object array; non-BR entries filtered out', () => {
  const r = brChapters(
    ['PMI Global', 'Rio de Janeiro, Brazil Chapter', { chapterName: 'Minas Gerais, Brazil Chapter' }],
    NOW,
  );
  assert.deepEqual(r.map((c) => c.name).sort(), ['Minas Gerais', 'Rio de Janeiro']);
});

test('#995 expired object chapter is flagged expired', () => {
  const pastISO = new Date(NOW - 5 * 86400000).toISOString();
  const r = brChapters([{ chapterName: 'Bahia, Brazil Chapter', expiryDate: pastISO }], NOW);
  assert.equal(r.length, 1);
  assert.equal(r[0].expired, true);
  assert.equal(r[0].soon, false);
});

test('#995 null / undefined / empty / non-array → []', () => {
  assert.deepEqual(brChapters(null), []);
  assert.deepEqual(brChapters(undefined), []);
  assert.deepEqual(brChapters([]), []);
  assert.deepEqual(brChapters('not-an-array'), []);
});

test('#995 a membership with no BR chapter at all → [] (legitimate warning case preserved)', () => {
  const r = brChapters(['PMI Global', 'Some Other, USA Chapter'], NOW);
  assert.deepEqual(r, [], 'genuinely-non-BR memberships still yield the manual-verify warning');
});

// ── #1041 soonestBrExpiry — the sortable "Vencimento" column + provisional farol ──
test('#1041 soonestBrExpiry picks the earliest-expiring BR chapter (most urgent)', () => {
  const s = soonestBrExpiry([
    { chapterName: 'PMI Global', expiryDate: '31 Dec 2027' },            // non-BR, ignored
    { chapterName: 'Goiás, Brazil Chapter', expiryDate: '30 Nov 2026' }, // later
    { chapterName: 'Ceará, Brazil Chapter', expiryDate: '31 Aug 2026' }, // SOONEST
  ], NOW);
  assert.equal(s.expiry, '31 Aug 2026', 'the earliest-expiring BR chapter wins');
  assert.equal(s.status, 'ok');
  assert.ok(s.days > 30, 'far enough out to be ok');
});

test('#1041 soonestBrExpiry classifies expired / soon / ok / none', () => {
  assert.equal(soonestBrExpiry([{ chapterName: 'Goiás, Brazil Chapter', expiryDate: '01 Jun 2026' }], NOW).status, 'expired');
  assert.equal(soonestBrExpiry([{ chapterName: 'Goiás, Brazil Chapter', expiryDate: '15 Jul 2026' }], NOW).status, 'soon'); // within 30d of 2026-07-01
  assert.equal(soonestBrExpiry([{ chapterName: 'Goiás, Brazil Chapter', expiryDate: '31 Dec 2026' }], NOW).status, 'ok');
  // no dated BR chapter → 'none' (string form has no expiry; drives the "—" cell)
  assert.equal(soonestBrExpiry(['Goiás, Brazil Chapter'], NOW).status, 'none');
  assert.equal(soonestBrExpiry(null, NOW).status, 'none');
  assert.equal(soonestBrExpiry([{ chapterName: 'PMI Global', expiryDate: '31 Aug 2026' }], NOW).status, 'none', 'non-BR chapters do not count');
});

test('#1041 soonestBrExpiry days sign: negative when expired', () => {
  const s = soonestBrExpiry([{ chapterName: 'Goiás, Brazil Chapter', expiryDate: '01 Jun 2026' }], NOW);
  assert.ok(s.expired && s.days < 0, 'expired chapter has negative days');
});
