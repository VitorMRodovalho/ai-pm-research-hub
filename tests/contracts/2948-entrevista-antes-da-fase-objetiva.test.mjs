// tests/contracts/2948-entrevista-antes-da-fase-objetiva.test.mjs
// Hermetic (reads files only). Lands in the structural bucket by content.
//
// #2948: after the opt-out of the 5 pillars, the onboarding portal set the status to
// interview_pending in the client and offered "Schedule now". opt_out_all_pillars does NOT promote
// on purpose (#2004), and request_interview_booking_link_via_token answers NOT_IN_INTERVIEW_STAGE
// before the objective phase, so the candidate saw the generic error.
//
// What this guard binds, each condition to the result it produces:
//   A. the booking button, its link, its error and its hint render only inside {canBookInterview && (<>...</>)};
//   B. canBookInterview reads app.status against a list equal to the server's own stage gate;
//   C. before the objective phase the block shows the "choice registered" text, and the "schedule below" text
//      only in the interview stage;
//   D. the opt-out and the revert take the status from the server's app_status_after, never a literal;
//   E. NOT_IN_INTERVIEW_STAGE updates the status from the server's answer and returns before the error;
//   F. the confirm dialog promises scheduling only in the interview stage;
//   G. the 2 new keys exist in the 3 dictionaries, promise the email after the objective evaluation, do not
//      tell the person to schedule now, and carry no em dash.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { maskJsComments, maskLineComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const PORTAL = maskJsComments(readFileSync(resolve(ROOT, 'src/components/pmi-onboarding/PMIOnboardingPortal.tsx'), 'utf8'));
const DICTS = Object.fromEntries(['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8')]));
const NEW_KEYS = ['pmi.onboarding.interviewRegisteredBody', 'pmi.onboarding.interviewConfirmBodyRegistered'];

// The slice from `start` to the first `end` after it. Throws when either is missing: an empty slice would turn
// every doesNotMatch below green.
function slice(src, start, end) {
  const i = src.indexOf(start);
  assert.ok(i >= 0, `start marker not found: ${start}`);
  const j = src.indexOf(end, i + start.length);
  assert.ok(j > i, `end marker not found after ${start}: ${end}`);
  return src.slice(i, j + end.length);
}
const listOf = (src, name) => {
  const m = src.match(new RegExp(`const ${name} = \\[([^\\]]*)\\];`));
  assert.ok(m, `${name} not declared as a literal list`);
  return [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();
};
const keyValue = (dict, key) => {
  const m = dict.match(new RegExp(`^\\s*'${key.replace(/\./g, '\\.')}':\\s*'((?:[^'\\\\]|\\\\.)*)',\\s*$`, 'm'));
  return m ? m[1] : null;
};

// Cut inside each test, so a missing marker fails the test that depends on it and not the whole file.
const interviewBlock = () => slice(PORTAL, '{isInterviewMode && (', '{!isInterviewMode && !hasVoiceConsent && (');

test('A: the booking button, link, error and hint render only inside {canBookInterview && (<>...</>)}', () => {
  const BOOKING_BLOCK = slice(interviewBlock(), '{canBookInterview && (<>', '</>)}');
  assert.equal((PORTAL.match(/onClick=\{requestBookingLink\}/g) || []).length, 1, 'exactly one booking button');
  assert.match(BOOKING_BLOCK, /onClick=\{requestBookingLink\}/);
  assert.match(BOOKING_BLOCK, /\{bookingUrl && \(/);
  assert.match(BOOKING_BLOCK, /\{bookingError && \(/);
  assert.match(BOOKING_BLOCK, /T\('pmi\.onboarding\.interviewScheduleHint'\)/);
  assert.equal((PORTAL.match(/pmi\.onboarding\.interviewScheduleHint/g) || []).length, 1, 'the hint renders in one place');
});

test('B: canBookInterview reads app.status against the same list as the server stage gate', () => {
  assert.match(PORTAL, /const canBookInterview = INTERVIEW_BOOKING_STATUSES\.includes\(app\.status\);/);
  const client = listOf(PORTAL, 'INTERVIEW_BOOKING_STATUSES');
  const fn = latestFunctionCapture(ROOT, 'request_interview_booking_link_via_token');
  const gate = maskLineComments(fn.body).match(/IF v_app\.status NOT IN \(([^)]*)\) THEN\s+RETURN jsonb_build_object\(\s*'success', false,\s*'failure_code', 'NOT_IN_INTERVIEW_STAGE'/);
  assert.ok(gate, `stage gate not found in ${fn.file}`);
  const server = [...gate[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();
  assert.deepEqual(client, server, `client list must equal the gate in ${fn.file}`);
});

test('C: before the objective phase the block says the choice is registered; "schedule below" only in the interview stage', () => {
  assert.match(PORTAL, /const awaitingObjective = BEFORE_OBJECTIVE_STATUSES\.includes\(app\.status\);/);
  assert.deepEqual(listOf(PORTAL, 'BEFORE_OBJECTIVE_STATUSES'), ['objective_eval', 'screening', 'submitted']);
  const INTERVIEW_BLOCK = interviewBlock();
  assert.match(INTERVIEW_BLOCK, /\{awaitingObjective && \(\s*<p data-testid="interview-choice-registered"[^>]*>\s*\{T\('pmi\.onboarding\.interviewRegisteredBody'\)\}/);
  assert.match(INTERVIEW_BLOCK, /\{canBookInterview && \(\s*<p[^>]*>\s*\{T\('pmi\.onboarding\.interviewSelectedBody'\)\}/);
  assert.equal((PORTAL.match(/pmi\.onboarding\.interviewSelectedBody/g) || []).length, 1, 'the "schedule below" text renders in one place');
  assert.equal((PORTAL.match(/pmi\.onboarding\.interviewRegisteredBody/g) || []).length, 1, 'the registered text renders in one place');
});

test('D: the opt-out and the revert take the status from app_status_after, never a literal', () => {
  const optOut = slice(PORTAL, 'const handleOptInterviewAll = async () => {', 'const handleRevertInterview');
  const revert = slice(PORTAL, 'const handleRevertInterview = async () => {', 'const handleReplaceVideo');
  for (const [name, body, rpc] of [['opt-out', optOut, 'opt_out_all_pillars'], ['revert', revert, 'revert_interview_optout']]) {
    assert.match(body, new RegExp(`const \\{ data, error \\} = await sb\\.rpc\\('${rpc}'`), `${name}: reads the RPC answer`);
    assert.match(body, /const statusAfter = \(data as any\)\?\.app_status_after;/, `${name}: takes app_status_after`);
    assert.match(body, /application: \{ \.\.\.app, status: typeof statusAfter === 'string' \? statusAfter : app\.status \}/, `${name}: status from the server`);
    assert.doesNotMatch(body, /status: '(interview_|screening|objective_|submitted)/, `${name}: no status literal`);
    assert.doesNotMatch(body, /app\.status === 'interview_pending'/, `${name}: no client copy of the server rule`);
    // the field the client reads is the one the server returns
    assert.match(maskLineComments(latestFunctionCapture(ROOT, rpc).body), /'app_status_after',/, `${rpc} returns app_status_after`);
  }
});

test('E: NOT_IN_INTERVIEW_STAGE takes the status from the answer and returns before the error', () => {
  const fn = slice(PORTAL, 'const requestBookingLink = async () => {', 'if (!payload) {');
  assert.match(fn, /const serverStatus = \(data as any\)\?\.application_status;\s+if \(\(data as any\)\?\.failure_code === 'NOT_IN_INTERVIEW_STAGE' && payload && typeof serverStatus === 'string'\) \{\s+tab\?\.close\(\);\s+setPayload\(\{ \.\.\.payload, application: \{ \.\.\.payload\.application, status: serverStatus \} \}\);\s+return;\s+\}/);
  const branch = fn.indexOf("'NOT_IN_INTERVIEW_STAGE'");
  const firstError = fn.indexOf("setBookingError(T('pmi.onboarding.interviewScheduleUnavailable'))");
  assert.ok(branch >= 0 && firstError > branch, 'the stage branch comes before the first error');
  const server = maskLineComments(latestFunctionCapture(ROOT, 'request_interview_booking_link_via_token').body);
  assert.match(server, /'failure_code', 'NOT_IN_INTERVIEW_STAGE',\s*'application_status', v_app\.status/, 'the server returns application_status with the code');
});

test('F: the confirm dialog promises scheduling only in the interview stage', () => {
  assert.match(PORTAL, /: canBookInterview\s+\? T\('pmi\.onboarding\.interviewConfirmBody'\)\s+: T\('pmi\.onboarding\.interviewConfirmBodyRegistered'\)\}/);
  assert.equal((PORTAL.match(/T\('pmi\.onboarding\.interviewConfirmBody'\)/g) || []).length, 1, 'the "schedule after confirming" text renders in one place');
});

test('G: the new keys exist in the 3 dictionaries, promise the email after the objective evaluation and do not say to schedule now', () => {
  const promise = { 'pt-BR': [/e-mail/, /avaliação objetiva/], 'en-US': [/email/, /objective evaluation/], 'es-LATAM': [/email/, /evaluación objetiva/] };
  const scheduleNow = /agende|schedule a time|agende el horario|após confirmar|after confirming|después de confirmar/i;
  for (const [lang, dict] of Object.entries(DICTS)) {
    for (const key of NEW_KEYS) {
      const v = keyValue(dict, key);
      assert.ok(v, `${key} missing in ${lang}`);
      for (const re of promise[lang]) assert.match(v, re, `${key} in ${lang} must promise ${re}`);
      assert.doesNotMatch(v, scheduleNow, `${key} in ${lang} must not tell the person to schedule now`);
      assert.doesNotMatch(v, /\u2014/, `${key} in ${lang}: no em dash`);
      if (lang === 'pt-BR') {
        assert.doesNotMatch(v, /\b(convidad|aprovad|selecionad|candidat)[oa]s?\b/i, `${key}: no gendered word for the person`);
      }
    }
  }
});
