/**
 * #518 contract test — announcement banner dismissal persists across sessions/logins
 *
 * Bug: AnnouncementBanner.astro stored dismissed ids in `sessionStorage`, which is
 *   cleared on every new tab session / browser close / fresh login — so a dismissed
 *   banner re-appeared on the next refresh or login. Reported by PM (WhatsApp).
 *
 * Fix: store in `localStorage` (same key `dismissed_announcements`, same JSON-array
 *   shape). Announcement ids are stable UUIDs, so a new or edited announcement (new id)
 *   still re-appears, while a dismissed one stays gone — option (a)+(c) per the issue.
 *
 * Static-only: the banner is a client `<script>` with no server surface; the storage
 *   choice is asserted against the source (comments stripped so the explanatory
 *   "unlike sessionStorage" note does not trip the regression assertion).
 *
 * Cross-ref: #518.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const FILE = resolve(ROOT, 'src/components/ui/AnnouncementBanner.astro');
const src = readFileSync(FILE, 'utf8');
// strip JS line comments AND html comments so explanatory text mentioning sessionStorage is ignored
const code = src.replace(/\/\/[^\n]*/g, '').replace(/<!--[\s\S]*?-->/g, '');

test('#518: dismissal reads + writes localStorage under dismissed_announcements', () => {
  assert.match(code, /localStorage\.getItem\('dismissed_announcements'\)/,
    'must read the dismissed set from localStorage');
  assert.match(code, /localStorage\.setItem\('dismissed_announcements'/,
    'must persist the dismissed set to localStorage');
});

test('#518: dismissal no longer uses sessionStorage (regression form)', () => {
  assert.ok(!/sessionStorage/.test(code),
    'dismissal must not use sessionStorage — it resets every session/login and re-shows the banner');
});

test('#518: dismissal keyed by the announcement id and deduped', () => {
  // handler pushes the dismissed id (UUID, stable per banner) with a dup guard
  assert.match(code, /dismissed\.includes\(id\)/,
    'dedup guard keeps the persisted set from growing on repeated/cross-tab dismiss');
});
