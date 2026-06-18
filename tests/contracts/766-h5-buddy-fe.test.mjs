/**
 * Contract: #766 H5 buddy/padrinho — PR2 (FE social pointer).
 *
 * PR2 is the front-end half of H5 (the closing item of #766). PR1 shipped the DB layer
 * (table buddy_pairings + RPCs offer_buddy/respond_to_buddy_offer/revoke_buddy_offer/get_my_buddy,
 * migration 20260805000207). PR2 surfaces it:
 *   (a)+(b) a canonical BuddyBlock island inline on /workspace (afilhado: silent | offer | pointer
 *           + padrino confirmations / pending offers), and
 *   (c) a volunteer "offer to be their buddy" pull on the Members tab of /tribe/[id].
 *
 * Design anchors (SPEC_766_H5_BUDDY.md §6, ux-leader GO-with-changes):
 *  - NOT routed through the global MilestoneCelebration island (offer = decision, pointer persists).
 *  - WhatsApp is double-gated server-side (share_whatsapp AND accepted) — the FE only ever renders
 *    a wa.me link from a non-null phone get_my_buddy chose to expose; otherwise the tribe-group
 *    fallback. The FE adds no new exposure path.
 *  - i18n: all buddy.* keys live in the 3 dicts (no inline hardcoded copy in the component).
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const BLOCK = read('src/components/buddy/BuddyBlock.tsx');
const WK = read('src/pages/workspace.astro');
const TRIBE = read('src/pages/tribe/[id].astro');
const PT = read('src/i18n/pt-BR.ts');
const EN = read('src/i18n/en-US.ts');
const ES = read('src/i18n/es-LATAM.ts');

// ── Component exists & reads the canonical RPC ──────────────────────────────────
test('BuddyBlock: component exists and reads get_my_buddy (canonical PR1 read)', () => {
  assert.ok(BLOCK, 'BuddyBlock.tsx exists');
  assert.match(BLOCK, /rpc\(['"]get_my_buddy['"]\)/);
});

test('BuddyBlock: drives the loop via the PR1 mutation RPCs', () => {
  assert.match(BLOCK, /rpc\(['"]respond_to_buddy_offer['"],\s*\{[^}]*p_pairing_id[^}]*p_response/s);
  assert.match(BLOCK, /rpc\(['"]revoke_buddy_offer['"],\s*\{[^}]*p_pairing_id/s);
});

// ── Three afilhado states (SPEC §6 a/b) ─────────────────────────────────────────
test('BuddyBlock: silent when nothing to show (returns null)', () => {
  // both the no-data guard and the all-empty guard return null
  assert.match(BLOCK, /if \(!data\) return null/);
  assert.match(BLOCK, /padrinoAccepted\.length === 0 && padrinoPending\.length === 0\) return null/);
});

test('BuddyBlock: pending-offer state renders accept/decline decision card', () => {
  assert.match(BLOCK, /status === ['"]offered['"]/);
  assert.match(BLOCK, /offerAccept/);
  assert.match(BLOCK, /offerDecline/);
});

test('BuddyBlock: accepted state renders the pointer (whatsapp OR tribe-group fallback)', () => {
  assert.match(BLOCK, /status === ['"]accepted['"]/);
  // wa.me link only when phone present; fallback otherwise
  assert.match(BLOCK, /padrino_whatsapp \? waLink\(af\.padrino_whatsapp\) : fallbackHref/);
  assert.match(BLOCK, /pointerWhatsapp/);
  assert.match(BLOCK, /pointerFallback/);
});

// ── WhatsApp handling mirrors resolve_whatsapp_link (digits-only wa.me) ──────────
test('BuddyBlock: waLink keeps digits only, mirroring resolve_whatsapp_link', () => {
  assert.match(BLOCK, /wa\.me\/['"] \+ phone\.replace\(\/\\D\/g, ['"]['"]\)/);
});

test('BuddyBlock: never invents a WhatsApp link — only renders one from a non-null exposed phone', () => {
  // the accepted-pointer link, the padrino-confirmed link both guard on *_whatsapp truthiness
  assert.match(BLOCK, /p\.afilhado_whatsapp &&/);
  assert.doesNotMatch(BLOCK, /rpc\(['"]resolve_whatsapp_link/); // double-gate stays in get_my_buddy
});

// ── a11y: mirror the milestone island ───────────────────────────────────────────
test('BuddyBlock: a11y — labelled region, focus the primary action on offer, guarded Escape declines', () => {
  // persistent decision surface → role=region with a label (not role=status, which is for ephemera)
  assert.match(BLOCK, /role="region" aria-label=\{copy\.pointerTitle\}/);
  assert.match(BLOCK, /acceptRef\.current\?\.focus\(\)/);
  // Escape declines ONLY when focus is inside the offer card, and stops propagation (no bubble decline)
  assert.match(BLOCK, /offerCardRef\.current\?\.contains\(document\.activeElement\)/);
  assert.match(BLOCK, /e\.stopPropagation\(\)/);
  assert.match(BLOCK, /respond\(pid, ['"]decline['"]\)/);
  // touch targets + wrap on mobile
  assert.match(BLOCK, /min-h-\[44px\]/);
  assert.match(BLOCK, /flex-wrap/);
});

// ── Mounted inline on /workspace, NOT via MilestoneCelebration ───────────────────
test('workspace: mounts BuddyBlock inline with copy + lang (canonical, not the milestone island)', () => {
  assert.match(WK, /import BuddyBlock from ['"]\.\.\/components\/buddy\/BuddyBlock['"]/);
  assert.match(WK, /<BuddyBlock client:load lang=\{lang\} copy=\{BUDDY_COPY\}/);
  assert.match(WK, /BUDDY_COPY = \{/);
});

// ── (c) tribe Members-tab volunteer pull ────────────────────────────────────────
test('tribe: volunteer pool is own-tribe scoped and offers via offer_buddy', () => {
  assert.match(TRIBE, /canVolunteerSet/);
  assert.match(TRIBE, /currentMember\.tribe_id === TRIBE_ID/);
  assert.match(TRIBE, /rpc\(['"]get_my_buddy['"]\)/);
  assert.match(TRIBE, /can_volunteer_for/);
  assert.match(TRIBE, /data-action="offer-buddy"/);
  assert.match(TRIBE, /rpc\(['"]offer_buddy['"],\s*\{\s*p_afilhado_member_id/);
});

// ── i18n parity: every buddy.* key in all 3 dicts ───────────────────────────────
// Note: copy delivery is intentionally split — BuddyBlock (workspace) consumes the offer/pointer/
// padrino/toast-accepted/declined/revoked keys; the pool.* and toast.offered keys are consumed by
// the tribe/[id].astro Members-tab inline script. Both surfaces resolve from the same 3 dicts.
const BUDDY_KEYS = [
  'buddy.offer.title', 'buddy.offer.body', 'buddy.offer.accept', 'buddy.offer.decline',
  'buddy.pointer.title', 'buddy.pointer.body', 'buddy.pointer.whatsapp', 'buddy.pointer.fallback',
  'buddy.padrino.confirmed', 'buddy.padrino.pending', 'buddy.padrino.revoke',
  'buddy.toast.accepted', 'buddy.toast.declined', 'buddy.toast.offered', 'buddy.toast.revoked',
  'buddy.toast.error',
  'buddy.pool.noPadrino', 'buddy.pool.offerCta', 'buddy.pool.offered',
];

for (const [name, dict] of [['pt-BR', PT], ['en-US', EN], ['es-LATAM', ES]]) {
  test(`i18n parity: all buddy.* keys present in ${name}`, () => {
    for (const k of BUDDY_KEYS) {
      assert.ok(dict.includes(`'${k}'`), `${name} missing ${k}`);
    }
  });
}

test('i18n: {name} placeholder present in the interpolated keys (all 3 dicts)', () => {
  for (const dict of [PT, EN, ES]) {
    for (const k of ['buddy.offer.title', 'buddy.pointer.body', 'buddy.padrino.confirmed', 'buddy.padrino.pending']) {
      const line = dict.split('\n').find((l) => l.includes(`'${k}'`));
      assert.ok(line && line.includes('{name}'), `${k} must carry {name}`);
    }
  }
});
