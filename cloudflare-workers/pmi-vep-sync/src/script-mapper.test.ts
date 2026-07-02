import { describe, it, expect } from 'vitest';
import { normalizeMemberships, mapScriptToNucleo } from './script-mapper';

/**
 * #1037 — the enriched PMI export carries per-chapter expiry in `profileMemberships`
 * ([{chapterName, expiryDate}]); `profileMembershipChapters` is chapter NAMES only.
 * The mapper must prefer profileMemberships so pmi_memberships keeps the VENCIMENTO
 * that /admin/filiacao surfaces.
 */

describe('#1037 normalizeMemberships', () => {
  it('keeps expiryDate from the enriched object form', () => {
    expect(normalizeMemberships([{ chapterName: 'PMI Global', expiryDate: '31 May 2027' }]))
      .toEqual([{ chapterName: 'PMI Global', expiryDate: '31 May 2027' }]);
  });

  it('maps the names-only form to expiryDate null', () => {
    expect(normalizeMemberships(['PMI Global', 'Espírito Santo, Brazil Chapter']))
      .toEqual([
        { chapterName: 'PMI Global', expiryDate: null },
        { chapterName: 'Espírito Santo, Brazil Chapter', expiryDate: null },
      ]);
  });

  it('drops malformed entries and returns null for empty/absent', () => {
    expect(normalizeMemberships(null)).toBeNull();
    expect(normalizeMemberships([])).toBeNull();
    expect(normalizeMemberships([{}, '', { chapterName: '' }, 42])).toBeNull();
  });
});

describe('#1037 mapScriptToNucleo membership preference', () => {
  const opp = { role_default: 'x', essay_mapping: {} } as any;
  const base = {
    applicationId: '1', _opportunityId: 'o', applicantName: 'N',
    applicantEmail: 'e@x.com', _bucket: 'submitted', status: 'Submitted',
  } as any;

  it('prefers profileMemberships (with expiry) over profileMembershipChapters (names)', () => {
    const app = {
      ...base,
      // both double-encoded (p150), as PMI Community returns them
      profileMemberships: '[{"chapterName":"PMI Global","expiryDate":"31 May 2027"},{"chapterName":"Espírito Santo, Brazil Chapter","expiryDate":"31 May 2027"}]',
      profileMembershipChapters: '["PMI Global","Espírito Santo, Brazil Chapter"]',
    } as any;
    const out = mapScriptToNucleo(app, opp, [], 'cyc');
    expect(out.pmi_memberships).toEqual([
      { chapterName: 'PMI Global', expiryDate: '31 May 2027' },
      { chapterName: 'Espírito Santo, Brazil Chapter', expiryDate: '31 May 2027' },
    ]);
  });

  it('falls back to profileMembershipChapters (names, null expiry) when profileMemberships absent', () => {
    const app = { ...base, profileMembershipChapters: '["PMI Global","Ceará, Brazil Chapter"]' } as any;
    const out = mapScriptToNucleo(app, opp, [], 'cyc');
    expect(out.pmi_memberships).toEqual([
      { chapterName: 'PMI Global', expiryDate: null },
      { chapterName: 'Ceará, Brazil Chapter', expiryDate: null },
    ]);
  });

  it('nulls memberships for phase-B-private profiles (Decision 5)', () => {
    const app = {
      ...base, profilePrivate: true,
      profileMemberships: '[{"chapterName":"PMI Global","expiryDate":"31 May 2027"}]',
    } as any;
    const out = mapScriptToNucleo(app, opp, [], 'cyc');
    expect(out.pmi_memberships).toBeNull();
  });
});
