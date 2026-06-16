/**
 * Contract: Wave 2 / D1 — "Ação hoje" do GP (Épico D re-escopado).
 *
 * Painel-cockpit na home admin que agrega `get_selection_dashboard` (RPC já
 * existente) e nomeia os candidatos parados no funil, em 5 baldes:
 *   - sem convite (in-band): interview_pending + sem cutoff_approved_email_sent_at
 *     (política PM 2026-06-16 = decisão MANUAL; o cron só despacha strict-above-target).
 *   - convite enviado, sem agendamento: interview_pending + email + !interview_scheduled
 *   - entrevista vencida: meta.interview_stuck
 *   - no-show: status interview_noshow
 *   - oferta VEP não aceita (D7): vep_recon.status_raw === 'OfferExtended'
 *
 * ZERO DB: o painel só lê o RPC existente. Static-only (lê fonte) → roda sem env.
 *
 * Cross-ref: #740 (umbrella pré-onboarding), plano Wave 2, get_selection_dashboard.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const WIDGET_PATH = 'src/components/admin/GpActionTodayWidget.tsx';
const HOME_PATH = 'src/pages/admin/index.astro';
const WIDGET = readFileSync(WIDGET_PATH, 'utf8');
const HOME = readFileSync(HOME_PATH, 'utf8');

const DICTS = {
  'pt-BR': readFileSync('src/i18n/pt-BR.ts', 'utf8'),
  'en-US': readFileSync('src/i18n/en-US.ts', 'utf8'),
  'es-LATAM': readFileSync('src/i18n/es-LATAM.ts', 'utf8'),
};

const I18N_KEYS = [
  'comp.adminDash.actionToday.title',
  'comp.adminDash.actionToday.subtitle',
  'comp.adminDash.actionToday.noInvite',
  'comp.adminDash.actionToday.noInviteHint',
  'comp.adminDash.actionToday.invitedNotScheduled',
  'comp.adminDash.actionToday.invitedNotScheduledHint',
  'comp.adminDash.actionToday.interviewStuck',
  'comp.adminDash.actionToday.interviewStuckHint',
  'comp.adminDash.actionToday.noShow',
  'comp.adminDash.actionToday.noShowHint',
  'comp.adminDash.actionToday.offerNotAccepted',
  'comp.adminDash.actionToday.offerNotAcceptedHint',
  'comp.adminDash.actionToday.openSelection',
  'comp.adminDash.actionToday.more',
];

describe('Wave2 D1 — GpActionTodayWidget aggregates existing RPC (zero DB)', () => {
  it('exists and reads get_selection_dashboard via navGetSb (no new RPC)', () => {
    assert.ok(existsSync(WIDGET_PATH));
    assert.match(WIDGET, /\.rpc\('get_selection_dashboard'\)/);
    assert.match(WIDGET, /navGetSb\?\.\(\)/);
    // must NOT invent a new dedicated RPC for this slice
    assert.doesNotMatch(WIDGET, /get_gp_action_today|get_selection_action_today/);
  });

  it('derives all 5 funnel buckets from the dashboard payload', () => {
    // sem convite (in-band): pending + no cutoff email
    assert.match(WIDGET, /status === 'interview_pending' && !a\.cutoff_approved_email_sent_at/);
    // convite enviado, sem agendamento
    assert.match(WIDGET, /!!a\.cutoff_approved_email_sent_at && !a\.meta\?\.interview_scheduled/);
    // entrevista vencida
    assert.match(WIDGET, /a\.meta\?\.interview_stuck === true/);
    // no-show
    assert.match(WIDGET, /status === 'interview_noshow'/);
    // oferta VEP não aceita (D7)
    assert.match(WIDGET, /a\.vep_recon\?\.status_raw === 'OfferExtended'/);
  });

  it('names the people (uses applicant_name), not just counts', () => {
    assert.match(WIDGET, /applicant_name/);
  });

  it('self-hides on denied (non-GP) or when there is nothing to do', () => {
    assert.match(WIDGET, /if \(denied \|\| !apps\) return null/);
    assert.match(WIDGET, /if \(active\.length === 0\) return null/);
  });

  it('deep-links to the selection cockpit (locale-aware)', () => {
    assert.match(WIDGET, /\/admin\/selection/);
    assert.match(WIDGET, /localePrefix/);
  });
});

describe('Wave2 D1 — wired into the admin home', () => {
  it('admin/index.astro imports and renders the widget', () => {
    assert.match(HOME, /import GpActionTodayWidget from '\.\.\/\.\.\/components\/admin\/GpActionTodayWidget'/);
    assert.match(HOME, /<GpActionTodayWidget client:load \/>/);
  });
});

describe('Wave2 D1 — i18n 3-dict parity', () => {
  for (const key of I18N_KEYS) {
    for (const [lang, body] of Object.entries(DICTS)) {
      it(`${lang} has ${key}`, () => {
        assert.ok(body.includes(`'${key}'`), `${lang} missing ${key}`);
      });
    }
  }

  // the 'more' key is interpolated (names() replaces {n}); a translation that
  // drops the placeholder would silently emit the raw string.
  for (const [lang, body] of Object.entries(DICTS)) {
    it(`${lang} keeps the {n} placeholder in .more`, () => {
      const line = body.split('\n').find((l) => l.includes("'comp.adminDash.actionToday.more'"));
      assert.ok(line && line.includes('{n}'), `${lang} .more missing {n} placeholder`);
    });
  }
});
