import { describe, it, expect } from 'vitest';
import { buildBrChapterMatcher, parseBrChapterCode, type ChapterMatcherRow } from './mapper';

/**
 * #1175 F2 — chapter-name resolution is chapter_registry-driven. The fixture mirrors
 * the live registry shape (bare codes, state names, vep_name_aliases); the matcher must
 * mirror resolve_br_chapter_code() (migration 20260805000364). Index case: the VEP name
 * "Amazônia Chapter" (no ", Brazil Chapter" suffix; registry state "Amazonas") resolved
 * to null under the old suffix-gated parser, leaving the member with 0 affiliations.
 */

const REGISTRY: ChapterMatcherRow[] = [
  { chapter_code: 'GO', state: 'Goiás', vep_name_aliases: [] },
  { chapter_code: 'MG', state: 'Minas Gerais', vep_name_aliases: [] },
  { chapter_code: 'RS', state: 'Rio Grande do Sul', vep_name_aliases: [] },
  { chapter_code: 'RJ', state: 'Rio de Janeiro', vep_name_aliases: [] },
  { chapter_code: 'SE', state: 'Sergipe', vep_name_aliases: null },
  { chapter_code: 'AM', state: 'Amazonas', vep_name_aliases: ['Amazônia Chapter', 'Amazonia Chapter'] },
];

const match = buildBrChapterMatcher(REGISTRY);

describe('#1175 F2 buildBrChapterMatcher', () => {
  it('resolves the canonical "<State>, Brazil Chapter" form from registry state names', () => {
    expect(match('Goiás, Brazil Chapter')).toBe('GO');
    expect(match('Minas Gerais, Brazil Chapter')).toBe('MG');
    expect(match('Rio Grande do Sul, Brazil Chapter')).toBe('RS');
    expect(match('Sergipe, Brazil Chapter')).toBe('SE');
  });

  it('resolves vep_name_aliases without the ", Brazil Chapter" suffix (index case AM)', () => {
    expect(match('Amazônia Chapter')).toBe('AM');
    expect(match('Amazonia Chapter')).toBe('AM');
  });

  it('is case- and diacritic-insensitive', () => {
    expect(match('amazônia chapter')).toBe('AM');
    expect(match('AMAZONIA CHAPTER')).toBe('AM');
    expect(match('goias, brazil chapter')).toBe('GO');
  });

  it('returns null for non-BR chapters (BR-only FACT table, ADR-0104)', () => {
    expect(match('PMI Global')).toBeNull();
    expect(match('Washington, DC Chapter')).toBeNull();
    expect(match('Angola Chapter')).toBeNull();
    expect(match('Honduras Chapter')).toBeNull();
    expect(match('Central Italy Chapter')).toBeNull();
  });

  it('returns null for empty / nullish input', () => {
    expect(match(null)).toBeNull();
    expect(match(undefined)).toBeNull();
    expect(match('')).toBeNull();
  });

  it('does not let a state substring match without the Brazil Chapter suffix', () => {
    // Only an explicit alias may skip the suffix gate.
    expect(match('Sergipe')).toBeNull();
    expect(match('Rio de Janeiro Chapter')).toBeNull();
  });
});

describe('#1175 F2 static fallback parity (parseBrChapterCode)', () => {
  it('fallback still resolves the canonical suffix form', () => {
    expect(parseBrChapterCode('Minas Gerais, Brazil Chapter')).toBe('MG');
    expect(parseBrChapterCode('Sergipe, Brazil Chapter')).toBe('SE');
  });

  it('fallback misses aliases by construction (registry is the fix, not this map)', () => {
    expect(parseBrChapterCode('Amazônia Chapter')).toBeNull();
  });
});
