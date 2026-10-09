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

/** Só http(s): valor de coluna livre (linkedin_url, pdf_url, external_url) nunca vira href `javascript:`. */
export function safeHttpUrl(u?: string | null): string | null {
  if (!u) return null;
  try {
    const url = new URL(u.trim());
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : null;
  } catch {
    return null;
  }
}

export function doiUrl(doi?: string | null): string {
  return doi ? `https://doi.org/${doi.replace(/^https?:\/\/(dx\.)?doi\.org\//i, '')}` : '';
}

/** URL a citar: o DOI quando existe; senão a página permanente da obra. */
export function citationUrl(pub: CitablePublication, origin: string): string {
  return doiUrl(pub.doi) || (pub.slug ? `${origin}/publications/${pub.slug}` : safeHttpUrl(pub.external_url) ?? '');
}

const MONTHS_PT = ['jan.', 'fev.', 'mar.', 'abr.', 'maio', 'jun.', 'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.'];

/** Data de acesso no fuso de Brasília: o Worker roda em UTC, e perto da meia-noite o dia mudaria. */
function accessDateBr(accessed: Date): string {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: 'numeric', day: 'numeric' })
    .formatToParts(accessed);
  const get = (type: string) => Number(parts.find(p => p.type === type)?.value);
  return `${get('day')} ${MONTHS_PT[get('month') - 1]} ${get('year')}`;
}

/** Sem autor, a entrada da ABNT é o título, com a primeira palavra em maiúsculas. */
function titleEntry(title: string): string {
  const [first, ...rest] = title.split(' ');
  return [first.toUpperCase(), ...rest].join(' ');
}

/** ABNT NBR 6023:2018. Com DOI, cita só o DOI; sem DOI, a URL e a data de acesso. */
export function formatAbnt(pub: CitablePublication, origin: string, accessed: Date): string {
  const authors = pub.authors.map(a => {
    const { given, family } = splitName(a);
    return given ? `${family.toUpperCase()}, ${given}` : family.toUpperCase();
  }).join('; ');
  const year = publicationYear(pub.publication_date);
  const ano = year === 's.d.' ? '[s.d.]' : year;
  const title = authors ? pub.title : titleEntry(pub.title);
  const work = pub.collection
    ? `${title}. In: ${PUBLISHER.toUpperCase()}. ${pub.collection.title}. [S. l.]: ${PUBLISHER}, ${ano}.`
    : `${title}. [S. l.]: ${PUBLISHER}, ${ano}.`;
  const head = `${authors ? authors + '. ' : ''}${work}`;
  if (pub.doi) return `${head} DOI: ${doiUrl(pub.doi).replace('https://doi.org/', '')}.`;
  const url = citationUrl(pub, origin);
  return url ? `${head} Disponível em: ${url}. Acesso em: ${accessDateBr(accessed)}.` : head;
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
  const date = `(${year === 's.d.' ? 'n.d.' : year}).`;
  const source = pub.collection ? `In ${pub.collection.title}. ${PUBLISHER}.` : `${PUBLISHER}.`;
  const url = citationUrl(pub, origin);
  // Sem autor, o título ocupa a posição do autor (APA 7, 9.12).
  const body = authors ? `${authors} ${date} ${pub.title}. ${source}` : `${pub.title}. ${date} ${source}`;
  return `${body}${url ? ' ' + url : ''}`;
}

const BIB_ESCAPES: Record<string, string> = {
  '\\': '\\textbackslash{}', '&': '\\&', '%': '\\%', '$': '\\$', '#': '\\#', '_': '\\_',
  '{': '\\{', '}': '\\}', '~': '\\textasciitilde{}', '^': '\\textasciicircum{}',
};

/** Uma passada só: escapar `\\` e depois `{}` escaparia as chaves do próprio `\\textbackslash{}`. */
function bibEscape(s: string): string {
  return s.replace(/[\\&%$#_{}~^]/g, c => BIB_ESCAPES[c]);
}

export function bibtexKey(pub: CitablePublication): string {
  const first = pub.authors[0] ? splitName(pub.authors[0]).family : 'nucleo';
  const word = pub.title.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().match(/[a-z0-9]{4,}/)?.[0] ?? 'obra';
  const base = first.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
  return `${base || 'nucleo'}${publicationYear(pub.publication_date).replace('s.d.', 'nd')}${word}`;
}

export function formatBibtex(pub: CitablePublication, origin: string): string {
  // @article exigiria `journal`, que não temos: obra avulsa sai como @misc.
  const type = pub.collection ? 'incollection' : 'misc';
  const fields: [string, string][] = [['title', `{${bibEscape(pub.title)}}`]];
  if (pub.authors.length > 0) {
    fields.push(['author', `{${pub.authors.map(a => {
      const { given, family } = splitName(a);
      return bibEscape(given ? `${family}, ${given}` : family);
    }).join(' and ')}}`]);
  }
  fields.push(
    ['year', `{${publicationYear(pub.publication_date).replace('s.d.', 'n.d.')}}`],
    ['publisher', `{${bibEscape(PUBLISHER)}}`],
  );
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
