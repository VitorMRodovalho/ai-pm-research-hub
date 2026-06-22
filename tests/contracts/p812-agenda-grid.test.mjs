import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// #812 FE — Agenda Viva columns-by-date grid + temporal state on the home.
// Anti-hardcode + i18n parity (mirrors the cycle4-coverage-map contract). No DB needed:
// purely static assertions on the component, the home wiring, and the 3 dictionaries.

const COMPONENT = readFileSync('src/components/agenda/AgendaVivaPublic.tsx', 'utf8');
const SECTION = readFileSync('src/components/sections/WeeklyScheduleSection.astro', 'utf8');

const NEW_KEYS = [
  'comp.agendaViva.statusNotHeld',
  'comp.agendaViva.concludedBadge',
  'comp.agendaViva.columnNoBlocks',
  'comp.agendaViva.blocksLabel',
  'comp.agendaViva.blockLabelOne',
  'comp.agendaViva.gridAria',
];

describe('p812 FE — Agenda Viva grid', () => {
  it('home surfaces the past→future timeline via range="both"', () => {
    assert.match(SECTION, /<AgendaVivaPublic[^>]*range="both"/, 'home must request the both-window timeline');
  });

  it('component reads the canonical RPC with the window parameter', () => {
    assert.match(COMPONENT, /rpc\('get_geral_agenda_viva'/, 'reads the events-derived canonical RPC');
    assert.match(COMPONENT, /p_window:\s*range/, 'passes the selected window to the RPC');
  });

  it('status chips are i18n-driven, not hardcoded (incl. neutral no_show label)', () => {
    for (const key of ['statusReserved', 'statusConfirmed', 'statusNotHeld']) {
      assert.match(COMPONENT, new RegExp(`t\\('comp\\.agendaViva\\.${key}'`), `${key} chip must come from i18n`);
    }
    // LGPD PD-5: the public no_show chip must NEVER say "did not show up" / "não compareceu".
    assert.ok(!/não compareceu/i.test(COMPONENT), 'no_show must use a neutral label, never "não compareceu"');
    // owner name is rendered defensively (RPC returns null for a suppressed no_show owner).
    assert.match(COMPONENT, /b\.owner_first_name \?/, 'owner_first_name must be rendered defensively (may be null)');
  });

  it('layout stacks on mobile and rows on desktop (PD-3)', () => {
    assert.match(COMPONENT, /flex-col md:flex-row/, 'columns stack vertically on mobile, row on desktop');
  });

  it('no hardcoded calendar dates or cadence times in the grid', () => {
    assert.ok(!/\b\d{4}-\d{2}-\d{2}\b/.test(COMPONENT), 'no hardcoded ISO dates');
    assert.ok(!/\b\d{1,2}:\d{2}\b/.test(COMPONENT), 'no hardcoded clock times');
  });

  it('new i18n keys exist in all 3 dictionaries (parity)', () => {
    for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
      const i18n = readFileSync(`src/i18n/${dict}.ts`, 'utf8');
      for (const key of NEW_KEYS) {
        assert.match(i18n, new RegExp(`'${key.replace(/\./g, '\\.')}'\\s*:`), `${dict} must define ${key}`);
      }
    }
  });
});
