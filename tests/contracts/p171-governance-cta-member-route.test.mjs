/**
 * Contract: #171 — governance ratification CTA routes non-admin signer gates to the member
 * review-chain route (/governance/documents/<chain>), not the /admin/ shell.
 *
 * Root cause: _ip_ratify_cta_link sent only {volunteers_in_role_active, member_ratification,
 * external_signer} to a member route and dumped every other gate — incl. leader_awareness
 * (tribe leaders), curator, chapter_witness, president_go/president_others — to /admin/, which
 * non-admin signers read as "I can't access this" (Ana Carla, leader_awareness gate). Frontend
 * co-symptoms: my-pending linked its sign CTA to /admin/, and ReviewChainIsland showed a
 * "signing restricted" banner even to eligible signers.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000100_issue_171_governance_cta_member_route_for_signer_gates.sql');
const MYPENDING = resolve(ROOT, 'src/pages/governance/my-pending.astro');
const ISLAND = resolve(ROOT, 'src/components/governance/ReviewChainIsland.tsx');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mp = existsSync(MYPENDING) ? readFileSync(MYPENDING, 'utf8') : '';
const island = existsSync(ISLAND) ? readFileSync(ISLAND, 'utf8') : '';

test('#171: migration routes the 5 non-admin signer gates to /governance/documents', () => {
  assert.ok(mig.length > 0, 'migration file present');
  const idx = mig.indexOf("THEN '/governance/documents/");
  assert.ok(idx > 0, 'member-documents branch present');
  const whenClause = mig.slice(mig.lastIndexOf('WHEN', idx), idx);
  for (const g of ['curator', 'leader_awareness', 'chapter_witness', 'president_go', 'president_others']) {
    assert.ok(whenClause.includes(`'${g}'`), `member-route branch includes ${g}`);
  }
});

test('#171: ratification gates keep ip-agreement; submitter_acceptance + unknown stay /admin (ELSE)', () => {
  const ipIdx = mig.indexOf("THEN '/governance/ip-agreement");
  assert.ok(ipIdx > 0, 'ip-agreement branch present');
  const ipWhen = mig.slice(mig.lastIndexOf('WHEN', ipIdx), ipIdx);
  for (const g of ['volunteers_in_role_active', 'member_ratification', 'external_signer']) {
    assert.ok(ipWhen.includes(`'${g}'`), `ip-agreement branch includes ${g}`);
  }
  assert.match(mig, /ELSE '\/admin\/governance\/documents\//, 'ELSE → /admin/ (submitter_acceptance + unknown)');
  // submitter_acceptance must not be hardcoded into either member-route branch
  assert.ok(!mig.includes("'submitter_acceptance'"), 'submitter_acceptance is not routed to a member branch (falls to ELSE)');
});

test('#171: my-pending sign CTA links to the member route, not /admin/', () => {
  assert.match(mp, /\/governance\/documents\/' \+ esc\(r\.chain_id\)/, 'links to /governance/documents/<chain>');
  assert.doesNotMatch(mp, /\/admin\/governance\/documents\/' \+ esc\(r\.chain_id\)/, 'no /admin/ link for the sign CTA');
});

test('#171: external-review banner is suppressed when the member has eligible sign gates', () => {
  assert.match(
    island,
    /\(isCommentOnlyMode \|\| externalReviewMode\) && eligibleGates\.length === 0 &&/,
    'banner gated on eligibleGates.length === 0 (signers see sign buttons, not a false "restricted" banner)'
  );
});
