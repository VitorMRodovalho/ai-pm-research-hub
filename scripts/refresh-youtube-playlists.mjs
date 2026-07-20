#!/usr/bin/env node
/**
 * refresh-youtube-playlists.mjs — regenerate the GENERATED block in
 * src/data/youtube-playlists.ts from the live YouTube channel.
 *
 * Usage:
 *   YOUTUBE_API_KEY=<youtube-data-api-v3-key> \
 *     node --experimental-strip-types scripts/refresh-youtube-playlists.mjs
 *
 * Auth: a plain API key is enough because we list a channel's PUBLIC playlists
 * (channelId query). Unlisted/private playlists are NOT returned by an API-key
 * query — the script MERGES (keeps existing ids not returned), so an unlisted
 * playlist already in the file survives a refresh. To (re)capture unlisted ones,
 * use the OAuth tooling in ~/projects/_pmo/youtube (mine=true) and paste the id.
 *
 * The file is the SSOT; components resolve links by semantic key via
 * getPlaylistUrl(). This script only rewrites the data array, never the logic.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { YOUTUBE_CHANNEL_ID, YOUTUBE_PLAYLISTS } from '../src/data/youtube-playlists.ts';

const KEY = process.env.YOUTUBE_API_KEY;
if (!KEY) {
  console.error('ERROR: set YOUTUBE_API_KEY (a YouTube Data API v3 key).');
  process.exit(1);
}

async function fetchAllPlaylists() {
  const items = [];
  let pageToken = '';
  do {
    const url = new URL('https://www.googleapis.com/youtube/v3/playlists');
    url.searchParams.set('part', 'snippet');
    url.searchParams.set('channelId', YOUTUBE_CHANNEL_ID);
    url.searchParams.set('maxResults', '50');
    url.searchParams.set('key', KEY);
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`YouTube API ${res.status}: ${await res.text()}`);
    const data = await res.json();
    for (const it of data.items) items.push({ id: it.id, title: it.snippet.title });
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return items;
}

function esc(s) {
  return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

const fetched = await fetchAllPlaylists();
if (fetched.length === 0) throw new Error('No playlists returned — aborting (refusing to wipe the file).');

// Merge: fetched (public) wins; keep existing ids not returned (unlisted survive).
const byId = new Map(YOUTUBE_PLAYLISTS.map((p) => [p.id, p]));
for (const p of fetched) byId.set(p.id, p);
const merged = [...byId.values()];

const filePath = path.join(path.dirname(fileURLToPath(import.meta.url)), '../src/data/youtube-playlists.ts');
const src = readFileSync(filePath, 'utf8');
const START = '// GENERATED:START';
const END = '// GENERATED:END';
const s = src.indexOf(START);
const e = src.indexOf(END);
if (s === -1 || e === -1 || e < s) throw new Error('GENERATED markers not found in youtube-playlists.ts');

const startLineEnd = src.indexOf('\n', s) + 1; // keep the START comment line verbatim
const block =
  'export const YOUTUBE_PLAYLISTS: YtPlaylist[] = [\n' +
  merged.map((p) => `  { id: '${esc(p.id)}', title: '${esc(p.title)}' },`).join('\n') +
  '\n];\n';

const next = src.slice(0, startLineEnd) + block + src.slice(e);
writeFileSync(filePath, next);
console.log(`Wrote ${merged.length} playlists (fetched ${fetched.length} public) to src/data/youtube-playlists.ts`);
