/**
 * #1153 F3 (#1156) — residency-conditional clause rendering for the signed volunteer term.
 *
 * The approved chain-version body (Direção 1, #1153) is the single source of truth and is
 * snapshotted VERBATIM at signing (byte-identical to the .docx V2 that governance approved,
 * INV-2). Clause 14 ("Transferência Internacional de Dados") is, per that .docx, a CONDITIONAL
 * clause: its GDPR/UK-GDPR Art. 49(1)(a) explicit-consent mechanism applies ONLY to volunteers
 * resident in the European Economic Area (EEA/EEE) or the United Kingdom. So the conditional is
 * a RENDER-TIME presentation decision, NOT a mutation of the approved/snapshotted text:
 *   - the immutable snapshot always keeps the full superset body;
 *   - a non-EEE/UK volunteer's rendered instrument omits the clause (fidelity to the .docx);
 *   - an EEE/UK volunteer's instrument keeps it.
 *
 * This module is intentionally self-contained (no imports) so it is importable both by the
 * renderer (pdf.ts) and by the contract test runner (node --experimental-strip-types cannot
 * resolve pdf.ts's extensionless `../canonical` import; a leaf module sidesteps that).
 */

/** Strip diacritics + lowercase + trim, so "França"/"franca"/"FRANÇA" all compare equal. */
function normalizeCountry(s: string | undefined): string {
  if (!s) return '';
  return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
}

/**
 * EEA (EU-27 + Iceland, Liechtenstein, Norway) + United Kingdom, keyed by normalized
 * country identifier. Reference data (a jurisdiction classification), centralized here as the
 * single list rather than sprinkled through the renderer. Covers English and Portuguese names
 * plus ISO 3166-1 alpha-2/alpha-3 codes, because `member_country` is a free-form field.
 */
const EEA_UK_TOKENS: ReadonlySet<string> = new Set(
  [
    // EU-27 — English
    'austria', 'belgium', 'bulgaria', 'croatia', 'cyprus', 'czechia', 'czech republic',
    'denmark', 'estonia', 'finland', 'france', 'germany', 'greece', 'hungary', 'ireland',
    'republic of ireland', 'italy', 'latvia', 'lithuania', 'luxembourg', 'malta',
    'netherlands', 'the netherlands', 'poland', 'portugal', 'romania', 'slovakia', 'slovenia',
    'spain', 'sweden',
    // EEA non-EU
    'iceland', 'liechtenstein', 'norway',
    // United Kingdom + constituent nations / synonyms
    'united kingdom', 'great britain', 'britain', 'england', 'scotland', 'wales',
    'northern ireland',
    // EU-27 — Portuguese
    'austria', 'belgica', 'bulgaria', 'croacia', 'chipre', 'republica tcheca', 'tchequia',
    'chequia', 'dinamarca', 'estonia', 'finlandia', 'franca', 'alemanha', 'grecia', 'hungria',
    'irlanda', 'italia', 'letonia', 'lituania', 'luxemburgo', 'malta', 'paises baixos',
    'holanda', 'polonia', 'portugal', 'romenia', 'eslovaquia', 'eslovenia', 'espanha',
    'suecia',
    // EEA non-EU — Portuguese
    'islandia', 'noruega',
    // United Kingdom — Portuguese
    'reino unido', 'gra-bretanha', 'gra bretanha', 'inglaterra', 'escocia', 'pais de gales',
    'irlanda do norte',
    // ISO 3166-1 alpha-2
    'at', 'be', 'bg', 'hr', 'cy', 'cz', 'dk', 'ee', 'fi', 'fr', 'de', 'gr', 'hu', 'ie', 'it',
    'lv', 'lt', 'lu', 'mt', 'nl', 'pl', 'pt', 'ro', 'sk', 'si', 'es', 'se', 'is', 'li', 'no',
    'gb', 'uk',
    // ISO 3166-1 alpha-3 (common)
    'aut', 'bel', 'bgr', 'hrv', 'cyp', 'cze', 'dnk', 'est', 'fin', 'fra', 'deu', 'grc', 'hun',
    'irl', 'ita', 'lva', 'ltu', 'lux', 'mlt', 'nld', 'pol', 'prt', 'rou', 'svk', 'svn', 'esp',
    'swe', 'isl', 'lie', 'nor', 'gbr',
  ].map(normalizeCountry),
);

/**
 * Does the given (free-form) country string indicate residency in the EEA or the UK?
 *
 * Default for an EMPTY/unknown country is FALSE (omit the clause). Rationale: Clause 14 is the
 * GDPR/UK-GDPR Art. 49(1)(a) EXPLICIT-consent mechanism, which is only validly captured from a
 * volunteer known to be EEE/UK-resident; when residency is undeclared it cannot be validly
 * consented anyway, and the general data-protection provisions (Clause 9) still apply. C4 is
 * majority-BR, and the clause is auto-scoped, so a mistaken omission is legally harmless.
 */
export function isEeaOrUkResidence(country: string | undefined): boolean {
  return EEA_UK_TOKENS.has(normalizeCountry(country));
}

/**
 * Remove the residency-conditional international-transfer clause (Clause 14) from an approved
 * HTML body when the volunteer does NOT reside in the EEA/UK. Idempotent and safe on bodies
 * that do not contain the clause (returns the input unchanged).
 *
 * Detection prefers an explicit governance marker and falls back to a semantic anchor:
 *   1. `data-conditional="eee-uk"` — an element governance may wrap the clause in on a future
 *      chain version (forward-compatible; the whole marked element is removed).
 *   2. Semantic anchor — the clause heading `<p><strong>Cláusula N.</strong> … Transferência
 *      Internacional de Dados …`, spanning up to the NEXT numbered `Cláusula N.` heading (or
 *      the end of the body). Anchoring on the heading TEXT (not the number) survives clause
 *      renumbering; the boundary matches only clause HEADINGS, never inline cross-references
 *      or the "14.3 Cláusulas Contratuais" sub-item.
 */
export function stripEeaUkClause(html: string, country: string | undefined): string {
  if (!html) return html;
  if (isEeaOrUkResidence(country)) return html; // in scope → keep the clause verbatim

  // Path 1 — explicit governance marker (forward-compat).
  const markerRe = /<([a-z][a-z0-9]*)\b[^>]*\bdata-conditional\s*=\s*("|')eee-uk\2[^>]*>[\s\S]*?<\/\1>/gi;
  const marked = html.replace(markerRe, '');
  if (marked !== html) return marked;

  // Path 2 — semantic anchor on the clause heading.
  const headingRe = /<p>\s*<strong>\s*Cláusula\s*\d+\.\s*<\/strong>[^<]*Transfer[êe]ncia\s+Internacional\s+de\s+Dados/i;
  const m = headingRe.exec(html);
  if (!m) return html; // clause not present in this body

  const start = m.index;
  const nextHeadingRe = /<p>\s*<strong>\s*Cláusula\s*\d+\./gi;
  nextHeadingRe.lastIndex = start + m[0].length;
  const next = nextHeadingRe.exec(html);
  const end = next ? next.index : html.length;
  return html.slice(0, start) + html.slice(end);
}

/**
 * Apply all residency conditionals to an approved body. Kept as the single public entry the
 * renderer calls, so future residency-scoped clauses can be added here without touching pdf.ts.
 */
export function applyResidencyConditionals(html: string, country: string | undefined): string {
  return stripEeaUkClause(html, country);
}
