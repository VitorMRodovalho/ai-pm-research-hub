// ─── PMI Chapter data ───

export interface Chapter {
  code: string;
  name: string;
  logo: string;
}

export const CHAPTERS: Chapter[] = [
  { code: 'PMI-GO', name: 'PMI Goiás',        logo: '/assets/logos/pmigo.png' },
  { code: 'PMI-CE', name: 'PMI Ceará',         logo: '/assets/logos/pmice.jpg' },
  { code: 'PMI-DF', name: 'PMI Distrito Federal', logo: '/assets/logos/pmidf.png' },
  { code: 'PMI-MG', name: 'PMI Minas Gerais',  logo: '/assets/logos/pmimg.png' },
  { code: 'PMI-RS', name: 'PMI Rio Grande do Sul', logo: '/assets/logos/pmirs.png' },
];

export const CHAPTER_CODES = CHAPTERS.map((c) => c.code);
