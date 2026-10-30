/**
 * Contract: #2847 — the welcome email names the opening the person applied to.
 *
 * {{role_label}} used to come from a fixed map of 4 labels by role_applied, so every
 * opening with role_default = researcher (a facilitation or support role included) was
 * welcomed as "Pesquisador". The label now comes from vep_opportunities.title, cut
 * before the Núcleo suffix.
 *
 * Layers:
 *   (A) openingLabel is IMPORTED and run on the titles of the registered openings and
 *       on the fallbacks;
 *   (B) wiring: the ingest passes the opening title to dispatchWelcome, and the email
 *       variables take the label from openingLabel. Comments are masked.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { openingLabel, ROLE_LABEL } from '../../cloudflare-workers/pmi-vep-sync/src/opening-label.ts';

const SRC = resolve(process.cwd(), 'cloudflare-workers/pmi-vep-sync/src');
const read = (f) => readFileSync(resolve(SRC, f), 'utf8');

// Titles as registered in vep_opportunities (public VEP titles).
const CASES = [
  ['Líder de tribo/iniciativa e Pesquisador chefe (novas temáticas e ou Iniciativas) - Núcleo de IA & GP', 'leader',
    'Líder de tribo/iniciativa e Pesquisador chefe (novas temáticas e ou Iniciativas)'],
  ['Pesquisador e multiplicador de conhecimento em IA - Núcleo IA & GP (Nível 4) - 2026', 'researcher',
    'Pesquisador e multiplicador de conhecimento em IA'],
  ['Gerente de Projeto - Núcleo de Estudo e Pesquisa de IA - PMI GO 2026', 'manager', 'Gerente de Projeto'],
  ['Especialista Voluntário(a) em Propriedade Intelectual, LGPD e Governança Jurídica', 'researcher',
    'Especialista Voluntário(a) em Propriedade Intelectual, LGPD e Governança Jurídica'],
  ['Pesquisador(a) da linha Segundo Cérebro & Comunicação de Times - Núcleo IA & GP (Nível 4) - 2026/27', 'researcher',
    'Pesquisador(a) da linha Segundo Cérebro & Comunicação de Times'],
  ['Facilitador(a) do Grupo de Estudos CPMAI - Núcleo IA & GP - 2026/27', 'researcher', 'Facilitador(a) do Grupo de Estudos CPMAI'],
  ['Gerente de Projeto do Grupo de Estudos CPMAI - Núcleo IA & GP - 2026/27', 'manager', 'Gerente de Projeto do Grupo de Estudos CPMAI'],
  ['Revisor(a) do Grupo de Estudos CPMAI - Núcleo IA & GP - 2026/27', 'researcher', 'Revisor(a) do Grupo de Estudos CPMAI'],
  ['Curadoria Pedagógica do Grupo de Estudos CPMAI - Núcleo IA & GP - 2026/27', 'researcher', 'Curadoria Pedagógica do Grupo de Estudos CPMAI'],
  ['Time de Apoio do Grupo de Estudos CPMAI - Núcleo IA & GP - 2026/27', 'researcher', 'Time de Apoio do Grupo de Estudos CPMAI'],
];

test('#2847: each registered opening is named by its title, without the Núcleo suffix', () => {
  for (const [title, role, expected] of CASES) {
    assert.equal(openingLabel(title, role), expected, title);
  }
});

test('#2847: without a title the label falls back to the role map, then to the raw role', () => {
  assert.equal(openingLabel(null, 'researcher'), ROLE_LABEL.researcher);
  assert.equal(openingLabel('   ', 'manager'), ROLE_LABEL.manager);
  assert.equal(openingLabel(undefined, 'observer'), 'observer');
  assert.equal(ROLE_LABEL.researcher, 'Pesquisador', 'the fallback keeps the labels the email used before');
});

test('#2847: opening-label.ts stays importable by this guard (no imports of its own)', () => {
  assert.doesNotMatch(maskJsComments(read('opening-label.ts')), /^\s*import\s/m);
});

test('#2847: the ingest passes the opening title and the email takes the label from it', () => {
  const index = maskJsComments(read('index.ts'));
  const callAt = index.indexOf('await dispatchWelcome(db, env, {');
  assert.ok(callAt > 0, 'the welcome call must be findable');
  const call = index.slice(callAt, index.indexOf('});', callAt));
  assert.match(call, /\bopportunity_title: opp\.title,/, 'the call must carry the title of THIS opening');

  const welcome = maskJsComments(read('welcome.ts'));
  const varsAt = welcome.indexOf('const variables = {');
  assert.ok(varsAt > 0, 'the email variables must be findable');
  const vars = welcome.slice(varsAt, welcome.indexOf('};', varsAt));
  assert.match(vars, /role_label: openingLabel\(opts\.opportunity_title, opts\.role_applied\),/,
    'role_label must be computed from the opening title, with role_applied only as the fallback');
  assert.doesNotMatch(welcome, /ROLE_LABEL\[/, 'welcome.ts must not keep a second label map');
});
