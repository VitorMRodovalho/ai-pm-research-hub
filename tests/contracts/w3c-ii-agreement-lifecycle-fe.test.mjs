/**
 * Contract: Wave 3c-ii (B8, #740 / ADR-0104) — agreement reject/reissue lifecycle, FRONTEND surface.
 *
 * 3c-i (mig …196) shipped the DB state machine (issued|rejected|superseded + reject_certificate /
 * reissue_agreement). This wave makes the read RPCs lifecycle-aware (mig …197) and wires the admin
 * panel + member screens + verify page to the new states.
 *
 * Static-only (reads migration source + FE files + i18n) → runs without DB env. Live behavior
 * (reject/reissue end-to-end, status-aware compliance, distrato copy) was validated at apply time via
 * rolled-back probes; this guards the wiring so it can't silently regress.
 *
 * Cross-ref: #740 Wave 3 (B8), ADR-0104, ADR-0022 (_delivery_mode_for).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000197_w3c_ii_agreement_lifecycle_fe.sql';
const MIG = readFileSync(MIG_PATH, 'utf8');

const PANEL = readFileSync('src/components/admin/VolunteerAgreementPanel.tsx', 'utf8');
const VA = readFileSync('src/pages/volunteer-agreement.astro', 'utf8');
const CERTS = readFileSync('src/pages/certificates.astro', 'utf8');
const VERIFY = readFileSync('src/pages/verify/[code].astro', 'utf8');
const PROFILE = readFileSync('src/pages/profile.astro', 'utf8');

describe('w3c-ii — DB read surface is lifecycle-aware (mig …197)', () => {
  it('migration exists and replaces the five read/copy RPCs', () => {
    assert.ok(existsSync(MIG_PATH));
    for (const fn of ['verify_certificate', 'get_all_certificates', 'get_my_certificates',
                      'get_volunteer_agreement_status', 'reject_certificate']) {
      assert.match(MIG, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `replaces ${fn}`);
    }
  });

  it('verify_certificate reports rejected + superseded distinctly from revoked', () => {
    assert.match(MIG, /'rejected', cert\.status = 'rejected'/);
    assert.match(MIG, /'superseded', cert\.status = 'superseded'/);
  });

  it('get_all_certificates summary counts the new states', () => {
    assert.match(MIG, /'rejected', count\(\*\) FILTER \(WHERE c\.status = 'rejected'/);
    assert.match(MIG, /'superseded', count\(\*\) FILTER \(WHERE c\.status = 'superseded'/);
  });

  it('get_my_certificates exposes the rejection reason to the member', () => {
    assert.match(MIG, /'revoked_reason', c\.revoked_reason, 'revoked_at', c\.revoked_at/);
  });

  it('get_volunteer_agreement_status adds agreement_cert_id/status and counts only issued as signed', () => {
    assert.match(MIG, /'agreement_cert_id',/);
    assert.match(MIG, /'agreement_status',/);
    assert.match(MIG, /c\.status IN \('issued', 'rejected'\)/);
    // the actionable cert excludes superseded/revoked; "signed" must require status='issued'
    assert.match(MIG, /'signed', EXISTS \(\s*\n\s*SELECT 1 FROM public\.certificates c WHERE c\.member_id = m\.id AND c\.type = 'volunteer_agreement'\s*\n\s*AND c\.status = 'issued'/);
  });

  it('reject_certificate uses formal distrato copy for a counter-signed (bilateral) term — legal R2', () => {
    assert.match(MIG, /v_was_counter_signed := v_cert\.counter_signed_by IS NOT NULL/);
    assert.match(MIG, /IF v_was_counter_signed THEN/);
    assert.match(MIG, /Distrato do seu Termo de Voluntariado/);
  });
});

describe('w3c-ii — admin panel actions (VolunteerAgreementPanel.tsx)', () => {
  it('reads the actionable agreement fields', () => {
    assert.match(PANEL, /agreement_cert_id: string \| null/);
    assert.match(PANEL, /agreement_status: string \| null/);
  });

  it('wires Reject (reject_certificate) and Reissue (reissue_agreement) RPC calls', () => {
    assert.match(PANEL, /rpc\('reject_certificate', \{ p_certificate_id: m\.agreement_cert_id, p_reason:/);
    assert.match(PANEL, /rpc\('reissue_agreement', \{ p_member_id: m\.id, p_reason:/);
  });

  it('Reissue is manager-only (hidden for chapter_board scoped view)', () => {
    assert.match(PANEL, /\{isManager && \(\s*\n\s*<button\s*\n\s*onClick=\{\(\) => reissueAgreement\(m\)\}/);
  });

  it('shows a distinct rejected badge and warns on counter-signed rejection (distrato)', () => {
    assert.match(PANEL, /m\.agreement_status === 'rejected'/);
    assert.match(PANEL, /rejectPromptCountersigned/);
  });
});

describe('w3c-ii — member surfaces', () => {
  it('volunteer-agreement.astro only blocks re-sign on a valid (issued) term, not a rejected one', () => {
    assert.match(VA, /const validCert = vaCerts\.find\(\(c: any\) => c\.status === 'issued' \|\| c\.status == null\)/);
    assert.match(VA, /const rejectedCert = vaCerts\.find\(\(c: any\) => c\.status === 'rejected'\)/);
    assert.match(VA, /renderRejectedBanner/);
  });

  it('certificates.astro shows a rejected badge + reason + re-sign link', () => {
    assert.match(CERTS, /c\.status === 'rejected'/);
    assert.match(CERTS, /certificates\.status\.rejected/);
    assert.match(CERTS, /certificates\.rejectedResign/);
  });

  it('profile.astro swaps the volunteer banner copy when the term was rejected', () => {
    assert.match(PROFILE, /c\.status === 'rejected'/);
    assert.match(PROFILE, /vaRejectedTitle/);
  });
});

describe('w3c-ii + #991 — verify page collapses invalid states (status-oracle-free)', () => {
  // #991 (PM full-collapse, 2026-07-01) reversed the …197 wave on the ANONYMOUS /verify
  // surface: verify_certificate now returns an indistinguishable {valid:false} for any
  // non-issued code, so the page no longer branches on revoked/rejected/superseded.
  // The lifecycle reasons remain MEMBER-facing on /certificates (asserted above).
  // Full no-oracle/no-PII guarantees live in 991-verify-certificate-no-pii-leak.test.mjs.
  it('no longer distinguishes revoked/rejected/superseded (collapsed to one invalid state)', () => {
    assert.doesNotMatch(VERIFY, /if \(data\.rejected\)/);
    assert.doesNotMatch(VERIFY, /if \(data\.superseded\)/);
    assert.doesNotMatch(VERIFY, /if \(data\.revoked\)/);
    assert.match(VERIFY, /data\.valid !== true/);
  });
});

describe('w3c-ii — i18n 3-dict parity', () => {
  const KEYS = [
    // #991 removed verify.rejected/rejectedAt/superseded/supersededHint — the anonymous
    // /verify lifecycle panels were collapsed (status-oracle-free). The member-facing
    // reject/reissue keys below are unchanged by #991 and remain required.
    'certificates.status.rejected', 'certificates.rejectedReason', 'certificates.rejectedResign',
    'volunteer.rejected.title', 'volunteer.rejected.description', 'volunteer.rejected.reasonLabel',
    'profile.volunteerBanner.rejectedTitle', 'profile.volunteerBanner.rejectedDescription',
  ];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    it(`${dict} defines every new key`, () => {
      const src = readFileSync(`src/i18n/${dict}.ts`, 'utf8');
      for (const k of KEYS) {
        assert.ok(src.includes(`'${k}':`), `${dict} missing ${k}`);
      }
    });
  }
});
