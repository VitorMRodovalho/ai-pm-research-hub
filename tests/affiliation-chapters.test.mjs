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
import { brChapters, soonestBrExpiry, unifiedBrChapters, soonestChapterExpiry } from '../src/lib/affiliation-chapters.ts';

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

// ── #1192 unifiedBrChapters — SSOT read-through first, raw parse as fallback only ──
// Index case (grounded live 2026-07-08): "PMI Amazônia Chapter" carries no "Brazil Chapter"
// suffix, so the raw parser returns [] and the row fell to the amber "verificar manualmente"
// branch even though member_chapter_affiliations held the verified AM row (source pmi_vep).
const JOAO_AFFILIATIONS = [{
  chapter_code: 'AM',
  chapter_label: 'Amazonas',
  source: 'pmi_vep',
  verified_at: '2026-07-08T03:59:39.578858+00:00',
  is_primary: true,
  raw_name: 'Amazônia Chapter',
  expiry: '28 Feb 2027',
}];
const JOAO_RAW = ['PMI Global', { chapterName: 'Amazônia Chapter', expiryDate: '28 Feb 2027' }];

test('#1192 SSOT affiliation wins even when the raw name has no "Brazil Chapter" suffix (the bug)', () => {
  // Pre-fix behaviour: the island called brChapters(raw) → [] → amber warning.
  assert.deepEqual(brChapters(JOAO_RAW, NOW), [], 'raw parser alone cannot resolve the alias (why the SSOT must win)');
  const r = unifiedBrChapters(JOAO_AFFILIATIONS, JOAO_RAW, NOW);
  assert.equal(r.length, 1, 'non-empty ⇒ the cell never falls to the manual-verify branch');
  assert.equal(r[0].name, 'Amazonas', 'display label comes from chapter_registry.state');
  assert.equal(r[0].code, 'AM', 'registry code drives the chapter filter');
  assert.equal(r[0].verified, true, 'SSOT row with verified_at is marked verified');
  assert.equal(r[0].expiry, '28 Feb 2027', 'expiry paired from the raw membership server-side');
  assert.equal(r[0].raw, 'Amazônia Chapter', 'original PMI name kept for the modal prefill');
});

test('#1192 raw parse is the fallback when there is no SSOT row', () => {
  const r = unifiedBrChapters([], ['Pernambuco, Brazil Chapter'], NOW);
  assert.equal(r.length, 1);
  assert.equal(r[0].name, 'Pernambuco');
  assert.equal(r[0].code, undefined, 'fallback entries carry no registry code');
  const rNull = unifiedBrChapters(null, ['Pernambuco, Brazil Chapter'], NOW);
  assert.equal(rNull.length, 1, 'null affiliations (pre-#1192 payload) behaves like []');
});

test('#1192 warning branch only when NEITHER side has data', () => {
  assert.deepEqual(unifiedBrChapters([], ['PMI Global'], NOW), [], 'non-BR raw only → empty → warning');
  assert.deepEqual(unifiedBrChapters(null, null, NOW), [], 'nothing at all → empty → warning');
});

test('#1192 provisional vep_raw entries are not marked verified', () => {
  const r = unifiedBrChapters([{
    chapter_code: 'GO', chapter_label: 'Goiás', source: 'vep_raw',
    verified_at: null, is_primary: false, raw_name: 'Goiás, Brazil Chapter', expiry: null,
  }], [], NOW);
  assert.equal(r[0].verified, false);
  assert.equal(r[0].code, 'GO', 'still filterable by registry code');
});

test('#1192 soonestChapterExpiry feeds Vencimento/farol from the SSOT list (alias case)', () => {
  const s = soonestChapterExpiry(JOAO_AFFILIATIONS, JOAO_RAW, NOW);
  assert.equal(s.expiry, '28 Feb 2027');
  assert.equal(s.status, 'ok');
  // Fallback parity: without affiliations it behaves exactly like soonestBrExpiry.
  const rawOnly = [{ chapterName: 'Goiás, Brazil Chapter', expiryDate: '15 Jul 2026' }];
  assert.equal(soonestChapterExpiry(null, rawOnly, NOW).status, soonestBrExpiry(rawOnly, NOW).status);
});
