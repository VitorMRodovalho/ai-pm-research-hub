import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// p280 #411 Wave 1c — bulk cutoff-invite dispatch (F3)
//
// Adds a "📧 Enviar convite (N)" bulk action alongside bulk-approve/reject/waitlist. Loops
// notify_selection_cutoff_approved over the selected applications with per-iteration try/catch
// (one failure never aborts the loop), reports an aggregate {sent, already, errors, skipped}
// toast, and gates dispatch behind a named confirm. Eligibility mirrors the F1 render gate
// (screening / interview_pending) so a stray selection of a rejected/approved row never emails them.
//
// Depends on Wave 1a (reuses notify_selection_cutoff_approved). No migration.

const PAGE = readFileSync('src/pages/admin/selection.astro', 'utf8');
const I18N_PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const I18N_EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const I18N_ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

const I18N_KEYS = [
  "'admin.selection.bulkCutoffInvite'",
  "'admin.selection.bulkCutoffInviteHint'",
];

describe('p280 #411 Wave 1c — bulk cutoff-invite dispatch', () => {
  describe('bulk bar button', () => {
    it('renders #bulk-cutoff-invite alongside the bulk decision buttons', () => {
      assert.match(
        PAGE,
        /id="bulk-cutoff-invite"[^>]*title=\{t\('admin\.selection\.bulkCutoffInviteHint', lang\)\}>\{t\('admin\.selection\.bulkCutoffInvite', lang\)\}</,
        'bulk dispatch button must use the bulkCutoffInvite/Hint i18n keys'
      );
    });

    it('button lives inside the bulk-actions bar (next to waitlist)', () => {
      const barStart = PAGE.indexOf('id="bulk-actions"');
      const waitlistIdx = PAGE.indexOf('data-decision="waitlist"');
      const cutoffIdx = PAGE.indexOf('id="bulk-cutoff-invite"');
      assert.ok(barStart > -1 && cutoffIdx > barStart, 'cutoff button must be within the bulk-actions bar');
      assert.ok(cutoffIdx > waitlistIdx, 'cutoff button rendered after the waitlist decision button');
    });

    it('wires the button to executeBulkCutoffInvite()', () => {
      assert.match(
        PAGE,
        /getElementById\('bulk-cutoff-invite'\)\?\.addEventListener\('click', \(\) => executeBulkCutoffInvite\(\)\)/,
      );
    });
  });

  describe('executeBulkCutoffInvite handler', () => {
    const fn = PAGE.slice(PAGE.indexOf('async function executeBulkCutoffInvite'), PAGE.indexOf('async function executeBulkCutoffInvite') + 2200);

    it('exists', () => {
      assert.ok(PAGE.includes('async function executeBulkCutoffInvite()'), 'handler must be declared');
    });

    it('reads selected ids from .sel-row-check:checked', () => {
      assert.match(fn, /querySelectorAll<HTMLInputElement>\('\.sel-row-check:checked'\)/);
    });

    it('eligibility mirrors the F1 render gate (screening / interview_pending)', () => {
      assert.match(fn, /const ELIGIBLE = \['screening', 'interview_pending'\]/);
      assert.match(fn, /ELIGIBLE\.includes\(r\.status\)/);
    });

    it('gates dispatch behind a confirm() with count + names preview', () => {
      const confirmIdx = fn.indexOf('confirm(');
      const rpcIdx = fn.indexOf("sb.rpc('notify_selection_cutoff_approved'");
      assert.ok(confirmIdx > -1 && rpcIdx > -1, 'both confirm and rpc must be present');
      assert.ok(confirmIdx < rpcIdx, 'confirm must precede the dispatch loop');
      assert.match(fn, /slice\(0, 3\)/, 'preview shows the first 3 names');
    });

    it('loops notify_selection_cutoff_approved per app with per-iteration try/catch', () => {
      assert.match(fn, /for \(const id of eligibleIds\)/);
      assert.match(fn, /sb\.rpc\('notify_selection_cutoff_approved', \{ p_application_id: id \}\)/);
      // try/catch inside the loop so one failure does not abort the rest
      const loopBody = fn.slice(fn.indexOf('for (const id of eligibleIds)'));
      assert.match(loopBody, /try \{[\s\S]*?\} catch \{ errors\+\+; \}/);
    });

    it('surfaces already_sent as a skip (not an error)', () => {
      assert.match(fn, /data\?\.reason === 'already_sent'\) already\+\+;/);
    });

    it('aggregate toast reports sent / already / errors', () => {
      assert.match(fn, /Enviados: \$\{sent\}/);
      assert.match(fn, /Já dispatchados: \$\{already\}/);
      assert.match(fn, /Erros: \$\{errors\}/);
    });

    it('disables the button during the loop (race guard) and restores label', () => {
      assert.match(fn, /btn\.disabled = true; btn\.textContent = '⏳ Enviando…';/);
      assert.match(fn, /btn\.disabled = false; btn\.textContent = orig;/);
    });

    it('refreshes the dashboard after dispatch', () => {
      assert.match(fn, /loadDashboard\(\);/);
    });
  });

  describe('forward-defense — no canonical-bypass', () => {
    it('does NOT write cutoff_approved_email_sent_at directly via supabase.from()', () => {
      const fn = PAGE.slice(PAGE.indexOf('async function executeBulkCutoffInvite'), PAGE.indexOf('async function executeBulkCutoffInvite') + 2200);
      assert.doesNotMatch(fn, /\.from\('selection_applications'\)/);
    });
  });

  describe('i18n parity across 3 dictionaries', () => {
    for (const key of I18N_KEYS) {
      it(`pt-BR has ${key}`, () => assert.ok(I18N_PT.includes(key)));
      it(`en-US has ${key}`, () => assert.ok(I18N_EN.includes(key)));
      it(`es-LATAM has ${key}`, () => assert.ok(I18N_ES.includes(key)));
    }
  });
});
