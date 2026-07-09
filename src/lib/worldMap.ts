// World reach map — Atlantic-centered equirectangular projection helpers + centroids.
// Backdrop asset: public/assets/maps/world-equirect.svg (Wikimedia BlankMap-Equirectangular,
// CC0 / Natural Earth public domain) — plate carrée, λ0=0, cropped to the Atlantic window
// viewBox="45 12 180 136" (lon -135..45, lat 78..-58). The SAME crop window drives pin math:
// a point (lat,lon) lands at viewBox (lon+180, 90-lat); as a % of the cropped window:
//   leftPct = (lon + 135) / 180 * 100      topPct = (78 - lat) / 136 * 100
// So a positioned overlay over the masked land aligns 1:1 with the geography. (Ciclo 4 PD-MAP-WORLD.)

export const ATLANTIC_WINDOW = { lonMin: -135, lonMax: 45, latTop: 78, latBottom: -58 } as const;

/** Project geographic (lat, lon) to {leftPct, topPct} within the Atlantic crop window. */
export function projectToWindow(lat: number, lon: number): { leftPct: number; topPct: number } {
  return {
    leftPct: ((lon - ATLANTIC_WINDOW.lonMin) / (ATLANTIC_WINDOW.lonMax - ATLANTIC_WINDOW.lonMin)) * 100,
    topPct: ((ATLANTIC_WINDOW.latTop - lat) / (ATLANTIC_WINDOW.latTop - ATLANTIC_WINDOW.latBottom)) * 100,
  };
}

/** Is a centroid inside the rendered Atlantic window? (off-window pins are skipped). */
export function isInWindow(lat: number, lon: number): boolean {
  return lon >= ATLANTIC_WINDOW.lonMin && lon <= ATLANTIC_WINDOW.lonMax
    && lat <= ATLANTIC_WINDOW.latTop && lat >= ATLANTIC_WINDOW.latBottom;
}

// Country centroids (lat, lon) — ISO-3166-1 alpha-2 (matches get_public_country_reach codes).
// 'ZZ'/'XX' (k-anon "Internacional" bucket) intentionally absent → rendered as a legend chip,
// never a map pin (no single location, preserves k-anonymity).
export const COUNTRY_CENTROIDS: Record<string, [number, number]> = {
  BR: [-10.5, -52.5], US: [39.5, -98.5], PT: [39.5, -8.0], ES: [40.2, -3.6],
  IT: [42.8, 12.5], FR: [46.5, 2.5], DE: [51.0, 10.5], GB: [54.0, -2.5],
  CA: [56.5, -98.0], AR: [-38.0, -63.0],
};

// US state centroids (lat, lon), keyed by 2-letter code (matches get_public_state_reach_v2).
export const US_STATE_CENTROIDS: Record<string, [number, number]> = {
  AL: [32.8, -86.8], AK: [64.0, -152.0], AZ: [34.3, -111.7], AR: [34.9, -92.4], CA: [37.2, -119.4],
  CO: [39.0, -105.5], CT: [41.6, -72.7], DE: [39.0, -75.5], DC: [38.9, -77.0], FL: [28.6, -82.4],
  GA: [32.6, -83.4], HI: [20.3, -156.4], ID: [44.4, -114.6], IL: [40.0, -89.2], IN: [39.9, -86.3],
  IA: [42.0, -93.5], KS: [38.5, -98.4], KY: [37.5, -85.3], LA: [31.0, -92.0], ME: [45.4, -69.2],
  MD: [39.0, -76.8], MA: [42.3, -71.8], MI: [44.3, -85.6], MN: [46.3, -94.3], MS: [32.7, -89.7],
  MO: [38.4, -92.5], MT: [47.0, -109.6], NE: [41.5, -99.8], NV: [39.3, -116.6], NH: [43.7, -71.6],
  NJ: [40.1, -74.7], NM: [34.4, -106.1], NY: [42.9, -75.6], NC: [35.5, -79.4], ND: [47.4, -100.3],
  OH: [40.3, -82.8], OK: [35.6, -97.5], OR: [44.0, -120.6], PA: [40.9, -77.8], RI: [41.7, -71.6],
  SC: [33.9, -80.9], SD: [44.4, -100.2], TN: [35.9, -86.4], TX: [31.5, -99.3], UT: [39.3, -111.7],
  VT: [44.1, -72.7], VA: [37.5, -78.8], WA: [47.4, -120.4], WV: [38.6, -80.6], WI: [44.6, -90.0],
  WY: [43.0, -107.6],
};

// Brazilian UF centroids (lat, lon), keyed by 2-letter UF (matches get_public_state_reach_v2).
export const BR_UF_CENTROIDS: Record<string, [number, number]> = {
  AC: [-9.0, -70.5], AL: [-9.6, -36.6], AP: [1.4, -51.8], AM: [-4.0, -64.0], BA: [-12.5, -41.7],
  CE: [-5.0, -39.6], DF: [-15.8, -47.8], ES: [-19.6, -40.6], GO: [-16.0, -49.6], MA: [-5.0, -45.3],
  MT: [-12.7, -55.9], MS: [-20.5, -54.6], MG: [-18.5, -44.5], PA: [-4.0, -52.5], PB: [-7.1, -36.6],
  PR: [-24.5, -51.5], PE: [-8.4, -37.9], PI: [-7.7, -42.7], RJ: [-22.2, -42.6], RN: [-5.8, -36.6],
  RS: [-30.0, -53.5], RO: [-10.9, -62.8], RR: [2.0, -61.4], SC: [-27.3, -50.5], SP: [-22.0, -48.6],
  SE: [-10.6, -37.4], TO: [-10.2, -48.3],
};

// Region display names (proper nouns; pt-BR forms, recognizable across locales). Used in pin
// tooltips alongside the i18n'd country name. Kept out of the i18n dicts (78 geographic names).
export const REGION_NAMES: Record<string, string> = {
  // US states (pt-BR where idiomatic)
  AL: 'Alabama', AK: 'Alasca', AZ: 'Arizona', AR: 'Arkansas', CA: 'Califórnia', CO: 'Colorado',
  CT: 'Connecticut', DE: 'Delaware', DC: 'Washington, D.C.', FL: 'Flórida', GA: 'Geórgia',
  HI: 'Havaí', ID: 'Idaho', IL: 'Illinois', IN: 'Indiana', IA: 'Iowa', KS: 'Kansas', KY: 'Kentucky',
  LA: 'Luisiana', ME: 'Maine', MD: 'Maryland', MA: 'Massachusetts', MI: 'Michigan', MN: 'Minnesota',
  MO: 'Missouri', MS: 'Mississippi', MT: 'Montana', NE: 'Nebraska', NV: 'Nevada', NH: 'New Hampshire', NJ: 'New Jersey',
  NM: 'Novo México', NY: 'Nova York', NC: 'Carolina do Norte', ND: 'Dakota do Norte', OH: 'Ohio',
  OK: 'Oklahoma', OR: 'Oregon', PA: 'Pensilvânia', RI: 'Rhode Island', SC: 'Carolina do Sul', SD: 'Dakota do Sul',
  TN: 'Tennessee', TX: 'Texas', UT: 'Utah', VT: 'Vermont', VA: 'Virgínia', WA: 'Washington',
  WV: 'Virgínia Ocidental', WI: 'Wisconsin', WY: 'Wyoming',
  // Brazilian UFs (collide with some US codes — resolved by country before lookup)
  _AC: 'Acre', _AP: 'Amapá', _AM: 'Amazonas', _BA: 'Bahia', _CE: 'Ceará', _DF: 'Distrito Federal',
  _ES: 'Espírito Santo', _GO: 'Goiás', _MA: 'Maranhão', _MT: 'Mato Grosso', _MS: 'Mato Grosso do Sul',
  _MG: 'Minas Gerais', _PA: 'Pará', _PB: 'Paraíba', _PR: 'Paraná', _PE: 'Pernambuco', _PI: 'Piauí',
  _RJ: 'Rio de Janeiro', _RN: 'Rio Grande do Norte', _RS: 'Rio Grande do Sul', _RO: 'Rondônia',
  _RR: 'Roraima', _SC: 'Santa Catarina', _SP: 'São Paulo', _SE: 'Sergipe', _TO: 'Tocantins',
  _AL: 'Alagoas',
};

// Continent centroids (lat, lon) for the residual continent pins (k>=3 per continent, from
// get_public_continent_reach). 'ZZ' (Internacional) has no single location → legend chip only,
// never a pin. Codes match the SQL continent mapping (EU/SA/NA + AF reserved for the future).
export const CONTINENT_CENTROIDS: Record<string, [number, number]> = {
  EU: [50.0, 10.0],   // central Europe
  SA: [-15.0, -60.0], // central South America
  NA: [58.0, -100.0], // central Canada (residual NA is non-US/BR → sits north of the US country pin)
  AF: [2.0, 20.0],    // central Africa (reserved)
};

// Continent display names (pt-BR proper nouns; recognizable across locales), mirroring REGION_NAMES.
// Kept out of the i18n dicts. 'ZZ' = the Internacional bucket label for the legend chip.
export const CONTINENT_NAMES: Record<string, string> = {
  EU: 'Europa', SA: 'América do Sul', NA: 'América do Norte', AF: 'África', ZZ: 'Internacional',
};

export interface GeoPin {
  kind: 'country' | 'state' | 'continent';
  code: string;            // 'BR' / 'US-VA' / 'BR-SP' / 'EU'
  countryCode: string;     // 'BR' / 'US' (continent pins: the continent code)
  regionName?: string;     // 'Virgínia' (state pins) / 'Europa' (continent pins)
  count: number;
  leftPct: number;
  topPct: number;
}

function regionCentroid(countryCode: string, region: string): [number, number] | undefined {
  return countryCode === 'BR' ? BR_UF_CENTROIDS[region] : US_STATE_CENTROIDS[region];
}
function regionName(countryCode: string, region: string): string {
  return (countryCode === 'BR' ? REGION_NAMES['_' + region] : REGION_NAMES[region]) || region;
}

/**
 * Build the placeable pin list from the zero-PII RPC payloads (unified geo opt-in model,
 * legal-counsel parecer 2026-06-25). Four layers, painted in order:
 *  - countryReach (get_public_country_reach): named countries k>=3 (BR/US + any >=3) → country pins;
 *    'ZZ'/'XX' excluded (the Internacional bucket is a legend chip, surfaced via continentReach).
 *  - preciseCountryReach (get_public_precise_country_reach): non-BR/US countries with >=1 member who
 *    consented to precise (k=1) display → country pins; deduped against named countries.
 *  - stateReach (get_public_state_reach_v3): BR/US states, dual-population (k=1 precise + k>=3 aggregate).
 *  - continentReach (get_public_continent_reach): the residual grouped by continent (k>=3) → continent
 *    pins; the 'ZZ' row carries no centroid and is returned to the caller as the Internacional chip.
 * Off-window or unknown-centroid rows are returned as pins-skipped; their members still count in a
 * coarser layer, so no member is dropped from a total.
 */
export function buildGeoPins(
  countryReach: Array<{ country_code: string; member_count: number | string }>,
  stateReach: Array<{ country_code: string; region_code: string; member_count: number | string }>,
  preciseCountryReach: Array<{ country_code: string; member_count: number | string }> = [],
  continentReach: Array<{ continent_code: string; member_count: number | string }> = [],
): { pins: GeoPin[]; skippedCountries: string[]; skippedStates: string[]; skippedContinents: string[] } {
  const pins: GeoPin[] = [];
  const skippedCountries: string[] = [];
  const skippedStates: string[] = [];
  const skippedContinents: string[] = [];
  const seenCountry = new Set<string>();

  const pushCountry = (code: string, count: number) => {
    if (seenCountry.has(code)) return;
    const centroid = COUNTRY_CENTROIDS[code];
    if (!centroid || !isInWindow(centroid[0], centroid[1])) { skippedCountries.push(code); return; }
    const { leftPct, topPct } = projectToWindow(centroid[0], centroid[1]);
    pins.push({ kind: 'country', code, countryCode: code, count, leftPct, topPct });
    seenCountry.add(code);
  };

  for (const c of countryReach) {
    if (c.country_code === 'ZZ' || c.country_code === 'XX') continue; // intl bucket → continentReach/chip
    pushCountry(c.country_code, Number(c.member_count || 0));
  }
  // Precise (k=1) consented countries — un-bucket the member from ZZ into a named country pin.
  for (const c of preciseCountryReach) {
    if (c.country_code === 'ZZ' || c.country_code === 'XX') continue;
    pushCountry(c.country_code, Number(c.member_count || 0));
  }

  for (const s of stateReach) {
    const centroid = regionCentroid(s.country_code, s.region_code);
    if (!centroid || !isInWindow(centroid[0], centroid[1])) { skippedStates.push(`${s.country_code}-${s.region_code}`); continue; }
    const { leftPct, topPct } = projectToWindow(centroid[0], centroid[1]);
    pins.push({
      kind: 'state', code: `${s.country_code}-${s.region_code}`, countryCode: s.country_code,
      regionName: regionName(s.country_code, s.region_code), count: Number(s.member_count || 0), leftPct, topPct,
    });
  }

  for (const ct of continentReach) {
    const code = ct.continent_code;
    if (code === 'ZZ' || code === 'XX') continue; // Internacional → legend chip, not a pin
    const centroid = CONTINENT_CENTROIDS[code];
    if (!centroid || !isInWindow(centroid[0], centroid[1])) { skippedContinents.push(code); continue; }
    const { leftPct, topPct } = projectToWindow(centroid[0], centroid[1]);
    pins.push({
      kind: 'continent', code, countryCode: code,
      regionName: CONTINENT_NAMES[code] || code, count: Number(ct.member_count || 0), leftPct, topPct,
    });
  }

  return { pins, skippedCountries, skippedStates, skippedContinents };
}

/** Pin diameter in px from member count (sqrt scale; country/continent pins larger than state pins). */
export function pinDiameter(kind: 'country' | 'state' | 'continent', count: number): number {
  const base = kind === 'state' ? 15 : 20;
  const k = kind === 'state' ? 2.6 : 4.2;
  // #1239: the count is rendered INSIDE the pin, so magnitude does not need to be
  // encoded by area too. Cap the diameter so a large cohort (e.g. Brazil) stays a
  // subtle hierarchy cue instead of ballooning and covering neighbouring pins.
  const cap = kind === 'state' ? 30 : 38;
  return Math.min(Math.round(base + k * Math.sqrt(Math.max(count, 1))), cap);
}
