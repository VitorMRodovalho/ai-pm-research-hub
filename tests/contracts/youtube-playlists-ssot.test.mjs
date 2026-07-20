// Guard: YouTube playlist links are a single source of truth resolved by
// semantic key (src/data/youtube-playlists.ts), never a hardcoded id in a
// component. Prevents the class of bug where the footer "Webinars" link was
// mis-pointed at the leaders-intro playlist (2026-07-20).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  getPlaylistId,
  getPlaylistUrl,
  PLAYLIST_RESOLVERS,
  YOUTUBE_PLAYLISTS,
} from '../../src/data/youtube-playlists.ts';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (rel) => readFileSync(path.join(root, rel), 'utf8');
const COMPONENTS = ['src/layouts/BaseLayout.astro', 'src/components/sections/TribesSection.astro'];

test('components resolve playlist links via getPlaylistUrl(), no hardcoded playlist id', () => {
  for (const f of COMPONENTS) {
    const src = read(f);
    assert.ok(!/playlist\?list=/.test(src), `${f} must not hardcode a playlist?list= id — use getPlaylistUrl()`);
    assert.ok(src.includes('getPlaylistUrl('), `${f} must resolve playlist links via getPlaylistUrl()`);
  }
});

test('every semantic key resolves to a valid playlist id + url', () => {
  for (const key of Object.keys(PLAYLIST_RESOLVERS)) {
    const id = getPlaylistId(key);
    assert.match(id, /^PL[A-Za-z0-9_-]{10,}$/, `${key} must resolve to a playlist id`);
    assert.equal(getPlaylistUrl(key), `https://www.youtube.com/playlist?list=${id}`);
  }
});

test('webinars key is the exact "Webinars" playlist (not the leaders-intro one)', () => {
  const p = PLAYLIST_RESOLVERS.webinars();
  assert.ok(p, 'a "Webinars" playlist must exist in the SSOT');
  assert.equal(p.title.trim().toLowerCase(), 'webinars');
});

test('cycle-scoped keys pick the highest cycle (auto-advance across cycles)', () => {
  const cyc = (t) => Number((t.match(/Ciclo\s+(\d+)/i) || [])[1] || 0);
  const cases = [
    ['leadersIntro', /Introdu[çc][ãa]o dos L[íi]deres de Tribo/i],
    ['generalMeetings', /Reuni[õo]es Gerais/i],
  ];
  for (const [key, re] of cases) {
    const resolved = PLAYLIST_RESOLVERS[key]();
    assert.ok(resolved, `${key} must resolve`);
    const maxCycle = Math.max(...YOUTUBE_PLAYLISTS.filter((p) => re.test(p.title)).map((p) => cyc(p.title)));
    assert.equal(cyc(resolved.title), maxCycle, `${key} must be the highest-cycle match`);
  }
});
