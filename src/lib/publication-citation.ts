// #2613 — Citação pronta (ABNT, APA, BibTeX) e licença de uma obra da biblioteca de publicações.
// Funções puras: a página por obra (SSR) e a lista de /publications usam as mesmas.

export const PUBLISHER = 'Núcleo IA & GP';

export interface CitablePublication {
  title: string;
  authors: string[];
  publication_date?: string | null; // coluna `date` (YYYY-MM-DD)
  publication_type?: string | null;
  doi?: string | null;
  external_url?: string | null;
  slug?: string | null;
  collection?: { title: string; position?: number | null } | null;
}

// Partículas de sobrenome em português e espanhol: não viram o sobrenome de entrada.
const PARTICLES = new Set(['da', 'das', 'de', 'del', 'di', 'do', 'dos', 'du', 'e', 'la', 'van', 'von', 'y']);
const SUFFIXES = new Set(['junior', 'júnior', 'jr', 'jr.', 'filho', 'neto', 'sobrinho']);

/** "Maria da Silva Santos Jr." → { given: "Maria da Silva", family: "Santos Jr." }.
 *  Partículas ficam no prenome ("SOUZA, Ana de" na ABNT) e saem das iniciais na APA. */
export function splitName(full: string): { given: string; family: string } {
  const parts = full.trim().split(/\s+/).filter(Boolean);
  if (parts.length <= 1) return { given: '', family: parts[0] ?? '' };
  let familyStart = parts.length - 1;
  if (SUFFIXES.has(parts[familyStart].toLowerCase()) && familyStart > 1) familyStart -= 1;
  return { given: parts.slice(0, familyStart).join(' '), family: parts.slice(familyStart).join(' ') };
}

export function publicationYear(date?: string | null): string {
  const m = /^(\d{4})-\d{2}-\d{2}/.exec(date ?? '');
  return m ? m[1] : 's.d.';
}

export function doiUrl(doi?: string | null): string {
  return doi ? `https://doi.org/${doi.replace(/^https?:\/\/(dx\.)?doi\.org\//i, '')}` : '';
}

/** URL a citar: o DOI quando existe; senão a página permanente da obra. */
export function citationUrl(pub: CitablePublication, origin: string): string {
  return doiUrl(pub.doi) || (pub.slug ? `${origin}/publications/${pub.slug}` : pub.external_url ?? '');
}

const MONTHS_PT = ['jan.', 'fev.', 'mar.', 'abr.', 'maio', 'jun.', 'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.'];

/** ABNT NBR 6023:2018. `accessed` é a data de acesso exigida para documento online. */
export function formatAbnt(pub: CitablePublication, origin: string, accessed: Date): string {
  const authors = pub.authors.map(a => {
    const { given, family } = splitName(a);
    return given ? `${family.toUpperCase()}, ${given}` : family.toUpperCase();
  }).join('; ');
  const year = publicationYear(pub.publication_date);
  const work = pub.collection
    ? `${pub.title}. In: ${PUBLISHER.toUpperCase()}. ${pub.collection.title}. [S. l.]: ${PUBLISHER}, ${year}.`
    : `${pub.title}. [S. l.]: ${PUBLISHER}, ${year}.`;
  const doi = pub.doi ? ` DOI: ${doiUrl(pub.doi).replace('https://doi.org/', '')}.` : '';
  const url = citationUrl(pub, origin);
  const acesso = `${accessed.getDate()} ${MONTHS_PT[accessed.getMonth()]} ${accessed.getFullYear()}`;
  return `${authors ? authors + '. ' : ''}${work}${doi}${url ? ` Disponível em: ${url}. Acesso em: ${acesso}.` : ''}`;
}

/** APA 7. */
export function formatApa(pub: CitablePublication, origin: string): string {
  const names = pub.authors.map(a => {
    const { given, family } = splitName(a);
    const initials = given.split(/\s+/).filter(p => p && !PARTICLES.has(p.toLowerCase()))
      .map(p => `${p[0].toUpperCase()}.`).join(' ');
    return initials ? `${family}, ${initials}` : family;
  });
  const authors = names.length <= 1 ? (names[0] ?? '')
    : names.length === 2 ? `${names[0]}, & ${names[1]}`
    : `${names.slice(0, -1).join(', ')}, & ${names[names.length - 1]}`;
  const year = publicationYear(pub.publication_date);
  const work = pub.collection
    ? `${pub.title}. In ${pub.collection.title}. ${PUBLISHER}.`
    : `${pub.title}. ${PUBLISHER}.`;
  const url = citationUrl(pub, origin);
  return `${authors ? authors + ' ' : ''}(${year === 's.d.' ? 'n.d.' : year}). ${work}${url ? ' ' + url : ''}`;
}

function bibEscape(s: string): string {
  return s.replace(/\\/g, '\\textbackslash{}').replace(/([&%$#_{}])/g, '\\$1');
}

export function bibtexKey(pub: CitablePublication): string {
  const first = pub.authors[0] ? splitName(pub.authors[0]).family : 'nucleo';
  const word = pub.title.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().match(/[a-z0-9]{4,}/)?.[0] ?? 'obra';
  const base = first.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
  return `${base || 'nucleo'}${publicationYear(pub.publication_date).replace('s.d.', 'nd')}${word}`;
}

export function formatBibtex(pub: CitablePublication, origin: string): string {
  const type = pub.collection ? 'incollection' : pub.publication_type === 'article' ? 'article' : 'misc';
  const fields: [string, string][] = [
    ['title', `{${bibEscape(pub.title)}}`],
    ['author', `{${pub.authors.map(a => {
      const { given, family } = splitName(a);
      return bibEscape(given ? `${family}, ${given}` : family);
    }).join(' and ')}}`],
    ['year', `{${publicationYear(pub.publication_date).replace('s.d.', 'n.d.')}}`],
    ['publisher', `{${bibEscape(PUBLISHER)}}`],
  ];
  if (pub.collection) fields.push(['booktitle', `{${bibEscape(pub.collection.title)}}`]);
  if (pub.doi) fields.push(['doi', `{${doiUrl(pub.doi).replace('https://doi.org/', '')}}`]);
  const url = citationUrl(pub, origin);
  if (url) fields.push(['url', `{${url}}`]);
  return `@${type}{${bibtexKey(pub)},\n${fields.map(([k, v]) => `  ${k} = ${v}`).join(',\n')}\n}`;
}

const LICENSES: Record<string, { label: string; url: string }> = {
  'CC-BY-4.0': { label: 'CC BY 4.0', url: 'https://creativecommons.org/licenses/by/4.0/' },
  'CC-BY-SA-4.0': { label: 'CC BY-SA 4.0', url: 'https://creativecommons.org/licenses/by-sa/4.0/' },
  'CC-BY-NC-4.0': { label: 'CC BY-NC 4.0', url: 'https://creativecommons.org/licenses/by-nc/4.0/' },
  'CC-BY-NC-SA-4.0': { label: 'CC BY-NC-SA 4.0', url: 'https://creativecommons.org/licenses/by-nc-sa/4.0/' },
  'CC-BY-ND-4.0': { label: 'CC BY-ND 4.0', url: 'https://creativecommons.org/licenses/by-nd/4.0/' },
  'CC0-1.0': { label: 'CC0 1.0', url: 'https://creativecommons.org/publicdomain/zero/1.0/' },
  'MIT': { label: 'MIT', url: 'https://opensource.org/license/mit' },
};

/** Identificador SPDX → rótulo e URL. Licença desconhecida mostra o identificador, sem link. */
export function licenseInfo(spdx?: string | null): { label: string; url: string } | null {
  if (!spdx) return null;
  return LICENSES[spdx] ?? { label: spdx, url: '' };
}
