import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  buildGovernanceMergeValues,
  extractGovernanceMergeFields,
  renderGovernanceMergeFields,
  shouldRenderGovernanceMergeFields,
} from '../../src/lib/governance/mergeFields.ts';

const IP_AGREEMENT = readFileSync('src/pages/governance/ip-agreement.astro', 'utf8');
const PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

test('#645 merge-fields: extracts and renders known legal placeholders without mutating template text', () => {
  const html = '<p>{{capitulo_aderente}} — {{representante_aderente}} — {{presidente_pmigo}}</p>';
  assert.deepEqual(extractGovernanceMergeFields(html), [
    'capitulo_aderente',
    'presidente_pmigo',
    'representante_aderente',
  ]);

  const values = buildGovernanceMergeValues({
    now: new Date('2026-06-13T12:00:00-03:00'),
    member: {
      name: 'Ana <Legal>',
      email: 'ana@example.org',
      chapter: 'PMI-CE',
      city: 'Fortaleza',
      operational_role: 'chapter_liaison',
    },
  });
  const rendered = renderGovernanceMergeFields(html, values);
  assert.deepEqual(rendered.unresolved, []);
  assert.ok(rendered.applied.includes('capitulo_aderente'));
  assert.match(rendered.html, /PMI-CE/);
  assert.match(rendered.html, /Ana &lt;Legal&gt;/, 'rendered values must be HTML-escaped');
  assert.match(rendered.html, /Ivan Lourenço/);
});

test('#645 merge-fields: fail-closes unresolved placeholders for signing', () => {
  const rendered = renderGovernanceMergeFields('<p>{{cnpj_aderente}} {{chapter_witness_role}}</p>', {});
  assert.deepEqual(rendered.applied, []);
  assert.deepEqual(rendered.unresolved, ['chapter_witness_role', 'cnpj_aderente']);
  assert.match(rendered.html, /governance-merge-missing/);
  assert.match(rendered.html, /data-merge-field="cnpj_aderente"/);
});

test('#645 merge-fields: only legal governance instruments get merge rendering', () => {
  assert.equal(shouldRenderGovernanceMergeFields('cooperation_agreement'), true);
  assert.equal(shouldRenderGovernanceMergeFields('accession_term'), true);
  assert.equal(shouldRenderGovernanceMergeFields('data_processing_agreement'), true);
  assert.equal(shouldRenderGovernanceMergeFields('manual'), false);
  assert.equal(shouldRenderGovernanceMergeFields('volunteer_term_template'), false);
});

test('#645 route wiring: /governance/ip-agreement renders merge fields before signing and blocks unresolved fields', () => {
  assert.match(IP_AGREEMENT, /renderGovernanceMergeFields/);
  assert.match(IP_AGREEMENT, /shouldRenderGovernanceMergeFields\(chain\.doc_type\)/);
  assert.match(IP_AGREEMENT, /querySelectorAll\(['"]\.governance-merge-missing['"]\)/);
  assert.match(IP_AGREEMENT, /ipagr\.mergeFields\.locked/);
});

test('#645 i18n: merge-field blocking copy exists in all locales', () => {
  for (const [name, body] of [['pt', PT], ['en', EN], ['es', ES]]) {
    assert.match(body, /ipagr\.mergeFields\.blockedTitle/, `${name} blockedTitle`);
    assert.match(body, /ipagr\.mergeFields\.blockedBody/, `${name} blockedBody`);
    assert.match(body, /ipagr\.mergeFields\.rendered/, `${name} rendered`);
    assert.match(body, /ipagr\.mergeFields\.locked/, `${name} locked`);
  }
});
