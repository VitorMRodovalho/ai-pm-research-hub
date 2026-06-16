import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

// WS-A (governance): tribe WhatsApp GROUP links (tribes.whatsapp_url) must never be
// served to anon/pre-onboarding. These client-side surfaces use the anon key, so the
// column must not be in their `.from('tribes').select(...)` — neither by name nor via
// `select('*')`. The link is served only via the gated get_tribe_group_link RPC (A1).
//
// Scope: the genuinely public surfaces (PR-A0). The tribe page (tribe/[id].astro) is
// rewired to the gated RPC in PR-A1 and locked there.
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const ANON_SURFACES = [
  'src/components/sections/TribesSection.astro',
  'src/components/nav/Nav.astro',
];

// Match `.from('tribes')` followed (within a small window) by `.select('...')`.
const TRIBES_SELECT_RE = /\.from\(\s*['"]tribes['"]\s*\)[\s\S]{0,120}?\.select\(\s*(['"`])([\s\S]*?)\1\s*\)/g;

for (const rel of ANON_SURFACES) {
  test(`WS-A static: ${rel} does not select tribes.whatsapp_url with the anon key`, () => {
    const body = read(rel);
    assert.ok(body, `${rel} present`);

    let m;
    let found = false;
    TRIBES_SELECT_RE.lastIndex = 0;
    while ((m = TRIBES_SELECT_RE.exec(body)) !== null) {
      found = true;
      const cols = m[2];
      assert.ok(
        !/whatsapp_url/.test(cols),
        `${rel}: tribes select must not include whatsapp_url (anon leak) — got: ${cols}`,
      );
      assert.ok(
        !/^\s*\*\s*$/.test(cols),
        `${rel}: tribes select('*') leaks whatsapp_url to anon — list explicit columns`,
      );
    }
    assert.ok(found, `${rel}: expected at least one .from('tribes').select(...) to validate`);
  });
}
