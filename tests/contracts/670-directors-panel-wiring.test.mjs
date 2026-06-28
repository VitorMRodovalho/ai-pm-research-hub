import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * #670 — voluntariado_director + certificacao_director are function-anchored in the V4
 * capability map (src/lib/permissions.ts), mirroring filiacao_director (#659). Held alone
 * each office was silently broken on the frontend (no panel permission → fell back to the
 * holder's operational_role tier). This wires the narrow surface and RATCHETS it: each
 * director must hold EXACTLY ['admin.access', '<own panel perm>'] — no member-manage,
 * analytics, curation, or the OTHER office's panel. Server RPCs stay the real boundary.
 *
 * Source-parsing contract (no DB env), same style as 670-chapter-liaison-narrow-permissions.
 */

const ROOT = process.cwd();
const src = readFileSync(resolve(ROOT, 'src/lib/permissions.ts'), 'utf8');

function designationCaps(name) {
  const re = new RegExp(`${name}:\\s*\\[([^\\]]*)\\]`);
  const m = re.exec(src);
  if (!m) return null;
  return m[1]
    .split(',')
    .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
    .filter((s) => s.length > 0 && !s.startsWith('//'));
}

const DIRECTORS = [
  { designation: 'voluntariado_director', panel: 'admin.voluntarios' },
  { designation: 'certificacao_director', panel: 'admin.certificacao' },
];

// Capabilities that would be an escalation beyond a narrow read panel.
const FORBIDDEN = ['admin.members.manage', 'admin.analytics', 'content.curate', 'data.anonymize', 'data.view_members'];

for (const { designation, panel } of DIRECTORS) {
  test(`#670 ${designation} is wired in DESIGNATION_PERMISSIONS`, () => {
    const caps = designationCaps(designation);
    assert.ok(caps, `${designation} missing from DESIGNATION_PERMISSIONS in permissions.ts`);
  });

  test(`#670 ${designation} holds EXACTLY ['admin.access', '${panel}'] (least privilege)`, () => {
    const caps = designationCaps(designation);
    assert.deepEqual([...caps].sort(), ['admin.access', panel].sort(),
      `${designation} must be exactly admin.access + its own panel perm. Got: ${JSON.stringify(caps)}`);
  });

  test(`#670 ${designation} holds no escalation capability`, () => {
    const caps = new Set(designationCaps(designation));
    for (const f of FORBIDDEN) {
      assert.equal(caps.has(f), false, `${designation} must NOT hold ${f}`);
    }
  });

  test(`#670 ${designation} does not hold the other office's panel`, () => {
    const caps = new Set(designationCaps(designation));
    const otherPanel = DIRECTORS.find((d) => d.designation !== designation).panel;
    assert.equal(caps.has(otherPanel), false, `${designation} must NOT hold ${otherPanel}`);
  });

  test(`#670 ${designation} is in the Designation union + has a label`, () => {
    assert.match(src, new RegExp(`\\|\\s*'${designation}'`), `${designation} missing from the Designation union`);
    assert.match(src, new RegExp(`${designation}:\\s*\\{\\s*pt:`), `${designation} missing from DESIGNATION_LABELS`);
  });

  test(`#670 ${panel} exists in the Permission union`, () => {
    assert.match(src, new RegExp(`\\|\\s*'${panel}'`), `${panel} missing from the Permission union`);
  });
}
