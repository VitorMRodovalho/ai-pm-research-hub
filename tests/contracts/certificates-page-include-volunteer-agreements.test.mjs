/**
 * Forward-defense: /certificates page must call get_my_certificates with
 * p_include_volunteer_agreements=true so member-facing view shows all certs
 * including their volunteer_agreement (Termo de Voluntariado).
 *
 * Origin: p217 bug report 2026-05-21 — PM clicked notification → /volunteer-agreement
 * (showed "already signed" via get_my_certificates with p_include=true) → CTA to
 * /certificates → page returned EMPTY because /certificates called the RPC without
 * the flag, defaulting to p_include_volunteer_agreements=false which filters out
 * exactly the cert the user was just shown. Broken journey: "you already signed
 * this thing you have no record of". User-visible regression.
 *
 * Root cause: src/pages/certificates.astro line 53 called sb.rpc('get_my_certificates')
 * with no params; the RPC default `p_include_volunteer_agreements boolean DEFAULT false`
 * filters out volunteer_agreement type certs (admin-context default). Member view
 * should NEVER hide certs the member owns.
 *
 * Fix: pass p_include_volunteer_agreements: true explicitly.
 *
 * Cross-ref:
 *   - src/pages/certificates.astro (member-facing certificates list)
 *   - src/pages/volunteer-agreement.astro:212 (the upstream "already signed" detector
 *     that correctly uses include=true)
 *   - get_my_certificates RPC (admin context preserves include=false default)
 *   - P162 RESOLVED-217.A
 *
 * Scope: static analysis. No DB env required.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const CERT_PAGE = resolve(ROOT, 'src/pages/certificates.astro');

test('certificates.astro calls get_my_certificates with p_include_volunteer_agreements=true', () => {
  const body = readFileSync(CERT_PAGE, 'utf8');

  // The legitimate call site — must include the param. Pattern-agnostic for whitespace + ordering.
  const correctCallPattern = /sb\.rpc\(\s*['"]get_my_certificates['"]\s*,\s*\{[^}]*p_include_volunteer_agreements\s*:\s*true[^}]*\}\s*\)/;
  assert.match(body, correctCallPattern,
    'src/pages/certificates.astro must pass p_include_volunteer_agreements: true to get_my_certificates RPC ' +
    '— otherwise the RPC default (false) filters out volunteer_agreement type certs and member-facing list returns empty');

  // Forward defense: no naked call without the param. The RPC default filters volunteer_agreement,
  // which is wrong for a member-facing list. Member should always see their own certs.
  const nakedCallPattern = /sb\.rpc\(\s*['"]get_my_certificates['"]\s*\)/;
  assert.doesNotMatch(body, nakedCallPattern,
    'src/pages/certificates.astro must NOT call get_my_certificates without arguments ' +
    '— that uses p_include_volunteer_agreements=false default which hides Termo de Voluntariado from member view');
});

test('certificates.astro does not pass p_include_volunteer_agreements=false (would re-introduce the bug)', () => {
  const body = readFileSync(CERT_PAGE, 'utf8');
  const wrongCallPattern = /sb\.rpc\(\s*['"]get_my_certificates['"]\s*,\s*\{[^}]*p_include_volunteer_agreements\s*:\s*false[^}]*\}\s*\)/;
  assert.doesNotMatch(body, wrongCallPattern,
    'src/pages/certificates.astro must not explicitly pass p_include_volunteer_agreements: false');
});
