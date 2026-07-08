import { describe, it, expect } from 'vitest';
import { normalizeMemberships, mapScriptToNucleo, mapServiceHistory } from './script-mapper';

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

/**
 * #1175 Wave 4 — mapServiceHistory contract.
 * Root cause grounded 2026-07-08: the p131 script emitted history rows keyed by
 * applicantId (with title/roleTitle), while the mapper filtered by applicationId
 * and read roleName only -> 0 silent inserts since 2026-05-12. Wave 4 fixes the
 * script (emits applicationId + roleName) AND adds a legacy fallback here so the
 * archived enriched exports stay importable.
 */
describe('#1175 Wave 4 mapServiceHistory', () => {
  const app = { applicationId: '301400', applicantId: 777 } as any;
  const dbId = 'db-uuid-1';

  it('matches Wave 4 rows by applicationId and maps roleName', () => {
    const rows = mapServiceHistory(app, dbId, [
      { applicationId: 301400, applicantId: 777, chapterName: 'Goiás, Brazil Chapter', roleName: 'Pesquisador', startDate: '2026-01-01T00:00:00Z' },
      { applicationId: 999999, applicantId: 888, chapterName: 'Other Chapter', roleName: 'X' },
    ] as any);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      application_id: dbId,
      chapter_name: 'Goiás, Brazil Chapter',
      role_name: 'Pesquisador',
      start_date: '2026-01-01',
      source: 'pmi_community',
    });
  });

  it('falls back to applicantId matching for pre-Wave-4 exports (no applicationId) and derives role from roleTitle/title', () => {
    const legacy = [
      { applicantId: 777, chapterName: 'Amazônia Chapter', title: 'Voluntário', roleTitle: 'Mentor' },
      { applicantId: 777, chapterName: 'Goiás, Brazil Chapter', title: 'Diretor' },
      { applicantId: 888, chapterName: 'Elsewhere', title: 'Nope' },
    ] as any;
    const rows = mapServiceHistory(app, dbId, legacy);
    expect(rows).toHaveLength(2);
    expect(rows[0].role_name).toBe('Mentor');       // roleTitle wins over title
    expect(rows[1].role_name).toBe('Diretor');      // title as last resort
  });

  it('does NOT cross-match legacy rows onto a different applicant', () => {
    const rows = mapServiceHistory({ applicationId: '5', applicantId: 111 } as any, dbId, [
      { applicantId: 777, chapterName: 'Goiás, Brazil Chapter', title: 'X' },
    ] as any);
    expect(rows).toEqual([]);
  });

  it('returns [] for profilePrivate apps (Decision 5 defense-in-depth)', () => {
    const rows = mapServiceHistory({ ...app, profilePrivate: true } as any, dbId, [
      { applicationId: 301400, chapterName: 'Goiás, Brazil Chapter', roleName: 'X' },
    ] as any);
    expect(rows).toEqual([]);
  });

  it('skips rows with empty chapterName and blanks empty roles to null', () => {
    const rows = mapServiceHistory(app, dbId, [
      { applicationId: 301400, chapterName: '  ', roleName: 'X' },
      { applicationId: 301400, chapterName: 'Ceará, Brazil Chapter', roleName: '   ' },
    ] as any);
    expect(rows).toHaveLength(1);
    expect(rows[0].chapter_name).toBe('Ceará, Brazil Chapter');
    expect(rows[0].role_name).toBeNull();
  });
});
