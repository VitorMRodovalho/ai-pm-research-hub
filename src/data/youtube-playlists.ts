/**
 * youtube-playlists.ts — SSOT for the Núcleo YouTube channel playlist links.
 *
 * WHY: playlist ids were hardcoded in BaseLayout (footer) and TribesSection.
 * A wrong id was copied into the footer once (the "Webinars" link pointed at
 * the leaders-intro playlist). Resolving links by SEMANTIC TITLE instead of a
 * literal id removes that failure mode and auto-advances cycle-scoped playlists
 * (e.g. "Introdução dos Líderes de Tribo") when a new cycle's playlist appears.
 *
 * DO NOT hardcode `youtube.com/playlist?list=<id>` in components — use
 * getPlaylistUrl(key). Guarded by tests/contracts/youtube-playlists-ssot.test.mjs.
 *
 * The list below is generated from the channel. Refresh it with:
 *   YOUTUBE_API_KEY=<key> node scripts/refresh-youtube-playlists.mjs
 * (see that script's header for the OAuth alternative for unlisted playlists).
 */

export interface YtPlaylist {
  id: string;
  title: string;
}

export const YOUTUBE_CHANNEL_ID = 'UCIEiHte8f_AVwCXP2wZ7DjQ';

// GENERATED:START — do not edit by hand; run scripts/refresh-youtube-playlists.mjs
export const YOUTUBE_PLAYLISTS: YtPlaylist[] = [
  { id: 'PLRexyUb8O7bo', title: 'Ciclo 4 (2026/2) - Introdução dos Líderes de Tribo' },
  { id: 'PLQJVKrw1fcry8eG_bAGShCYb7wx3oDBSS', title: 'Ciclo 3 - Conteúdo das Tribos' },
  { id: 'PLQJVKrw1fcryCMIFyLnXY9ZNoBRyo3ZiZ', title: 'Iniciativa Grupo de Estudos CPMAI (Operação)' },
  { id: 'PLQJVKrw1fcryAoeIaJ3YJii5INCdsgiPD', title: 'Grupo de Estudos PMI-CPMAI' },
  { id: 'PLQJVKrw1fcrwqDt5zvX6OvI_S_7rsuZNq', title: 'Comite de Curadoria' },
  { id: 'PLQJVKrw1fcryo4W1spdR8kkIW5brizS3Q', title: 'Q2: Gestão de Projetos de IA & Equipes Híbridas (Débora Moura)' },
  { id: 'PLQJVKrw1fcrzK46BqO_EjgieOHnWCAoLR', title: 'Ciclo 3 (2026/1) - Reunião de Liderança' },
  { id: 'PLQJVKrw1fcrzHRUMGH6P4uEwEZFG7Qx8E', title: 'Submissões a Eventos (PMI / LIM LATAM)' },
  { id: 'PLQJVKrw1fcrymIpRMT4efnR0G1TJRaMWI', title: 'Ciclo 3 (2026/1) - Reuniões Gerais' },
  { id: 'PLQJVKrw1fcrx3fD2ug1hnps6TklcMT1dc', title: 'Ciclo 3 (2026/1) - Introdução dos Líderes de Tribo' },
  { id: 'PLQJVKrw1fcryz7GGgOleIwbdx1zMQPX6f', title: 'Ciclo 2 (2025/2) - Introdução dos Líderes de Tribo' },
  { id: 'PLQJVKrw1fcryumj-vbZYK7Q-zoeAGQCos', title: 'Webinars' },
  { id: 'PLQJVKrw1fcrwyNQMyWuGK0pe8kxA50qQi', title: 'Ciclo 2 (2025/2) - Reuniões Gerais' },
  { id: 'PLQJVKrw1fcrzPs9NfNawKrMU9GitykEv3', title: 'Núcleo IA - Pílulas de conhecimento' },
];
// GENERATED:END

const CYCLE_RE = /Ciclo\s+(\d+)/i;

function cycleOf(title: string): number {
  const m = title.match(CYCLE_RE);
  return m ? Number(m[1]) : 0;
}

/** Latest (highest-cycle) playlist whose title matches the pattern. */
function latestByPattern(pattern: RegExp): YtPlaylist | undefined {
  const matches = YOUTUBE_PLAYLISTS.filter((p) => pattern.test(p.title));
  if (matches.length === 0) return undefined;
  return matches.reduce((best, p) => (cycleOf(p.title) >= cycleOf(best.title) ? p : best));
}

/**
 * Semantic playlist keys. Each resolver picks a playlist by title so a Studio
 * rename/new-cycle propagates on the next data refresh without touching components.
 */
export const PLAYLIST_RESOLVERS = {
  webinars: () => YOUTUBE_PLAYLISTS.find((p) => p.title.trim().toLowerCase() === 'webinars'),
  leadersIntro: () => latestByPattern(/Introdu[çc][ãa]o dos L[íi]deres de Tribo/i),
  generalMeetings: () => latestByPattern(/Reuni[õo]es Gerais/i),
} as const;

export type PlaylistKey = keyof typeof PLAYLIST_RESOLVERS;

export function getPlaylistId(key: PlaylistKey): string {
  const p = PLAYLIST_RESOLVERS[key]();
  if (!p) throw new Error(`youtube-playlists: no playlist resolved for key "${key}"`);
  return p.id;
}

export function getPlaylistUrl(key: PlaylistKey): string {
  return `https://www.youtube.com/playlist?list=${getPlaylistId(key)}`;
}
