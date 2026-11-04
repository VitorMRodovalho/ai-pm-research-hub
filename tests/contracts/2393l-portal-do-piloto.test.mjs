/**
 * Contract: #2393, fatia A2 (ADR-0134) — o portal da candidatura de vaga piloto da linha fala da vaga, não do ciclo.
 *
 *   C1 (D27): a vaga fica no ciclo 4, então o portal do piloto mostra o período da vaga no lugar do ciclo;
 *   C2, X1: o piloto vê a própria jornada (quem avalia, a data do convite do vídeo, o resultado), e não o texto do
 *       comitê do fluxo geral;
 *   C6: depois do consentimento, a pessoa vê que a escolha ficou registrada e o que vem a seguir;
 *   C10, C12: status com rótulo e validade do link com data;
 *   ux 6: as saídas "ajuda ou adaptação" e "desistir".
 * Tudo depende de 'opening' no payload (M1); sem ele, o portal fica como era.
 * Camada S (estática): cada asserção casa a condição com o resultado no trecho que decide.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SRC = maskJsComments(readFileSync(resolve(ROOT, 'src/components/pmi-onboarding/PMIOnboardingPortal.tsx'), 'utf8')).replace(/\s+/g, ' ');
const CHAVES = ['introPilot', 'periodLabel', 'periodValue', 'expiresOn', 'journeyTitle', 'journeyReceived', 'journeyNow', 'journeyVideo',
  'journeyVideoSoon', 'journeyFit', 'journeyResult', 'journeyWho', 'consentDone', 'consentDonePilot', 'helpLine', 'withdrawLine',
  'withdrawSubject', 'helpSubject'];

test('#2393l: a trilha vem da vaga no payload, e sem ela o portal fica como era', () => {
  assert.match(SRC, /opening\?: \{ opportunity_id: string; title: string \| null; start_date: string \| null; end_date: string \| null; evaluation_track: [^;]*; video_invite_by: string \| null; \} \| null;/,
    'o tipo da vaga no payload mudou');
  assert.match(SRC, /const opening = payload\.opening \?\? null; const isLinePilot = opening\?\.evaluation_track === 'line_pilot';/,
    'a trilha deixou de vir da vaga');
});

test('#2393l C1: no piloto, a abertura e o selo falam do período da vaga, não do ciclo', () => {
  assert.match(SRC,
    /\{isLinePilot \? T\('pmi\.onboarding\.introPilot'\) \.replace\('\{opening\}', openingName\) \.replace\('\{start\}', fmtData\(opening\?\.start_date\)\) \.replace\('\{end\}', fmtData\(opening\?\.end_date\)\) : T\('pmi\.onboarding\.intro'\) \.replace\('\{role\}', roleLabel\) \.replace\('\{cycle\}', cycle\.title\)\}/,
    'a abertura do piloto voltou a falar do ciclo');
  assert.match(SRC,
    /\{isLinePilot \? \( <span [^>]*> \{T\('pmi\.onboarding\.periodLabel'\)\}: <strong>\{T\('pmi\.onboarding\.periodValue'\)\.replace\('\{start\}', fmtData\(opening\?\.start_date\)\)\.replace\('\{end\}', fmtData\(opening\?\.end_date\)\)\}<\/strong> <\/span> \) : \( <span [^>]*> \{T\('pmi\.onboarding\.cycleCode'\)\}: <strong>\{cycle\.cycle_code\}<\/strong> <\/span> \)\}/,
    'o selo do piloto voltou a mostrar o ciclo');
});

test('#2393l C2 e X1: o piloto vê a jornada, e o texto do comitê fica para as outras candidaturas', () => {
  const ini = SRC.indexOf('{isLinePilot && ( <section data-testid="pilot-journey"');
  assert.ok(ini >= 0, 'a jornada do piloto sumiu ou deixou de depender da trilha');
  const jornada = SRC.slice(ini, SRC.indexOf('</section>', ini));
  for (const k of ['journeyReceived', 'journeyNow', 'journeyFit', 'journeyResult', 'journeyWho'])
    assert.ok(jornada.includes(`T('pmi.onboarding.${k}')`), `a jornada perdeu ${k}`);
  assert.match(jornada, /\{opening\?\.video_invite_by \? T\('pmi\.onboarding\.journeyVideo'\)\.replace\('\{date\}', fmtData\(opening\.video_invite_by\)\) : T\('pmi\.onboarding\.journeyVideoSoon'\)\}/,
    'a jornada deixou de prometer a data do convite que a vaga declara');
  assert.match(jornada, /href=\{mailto\(T\('pmi\.onboarding\.helpSubject'\)\)\}/, 'a saída de ajuda sumiu');
  assert.match(jornada, /href=\{mailto\(T\('pmi\.onboarding\.withdrawSubject'\)\)\}/, 'a saída de desistência sumiu');
  assert.match(SRC, /\{isInPreOnboarding && !isLinePilot && \( <section className="bg-blue-50 border border-blue-200 rounded-xl p-6"> <h2 [^>]*> 📋 \{T\('pmi\.onboarding\.evaluationPhase'\)\}/,
    'o texto do comitê voltou a aparecer para o piloto');
});

test('#2393l C6: depois do consentimento, a pessoa vê que a escolha ficou registrada e o próximo passo', () => {
  assert.match(SRC, /application: \{ \.\.\.app, has_consent: grant, has_revoked: !grant \} \}\); setConsentConfirmed\(true\);/,
    'a confirmação deixou de vir depois do registro');
  assert.match(SRC,
    /\{consentConfirmed && \( <p role="status" data-testid="consent-done" [^>]*> \{isLinePilot && opening\?\.video_invite_by \? T\('pmi\.onboarding\.consentDonePilot'\)\.replace\('\{date\}', fmtData\(opening\.video_invite_by\)\) : T\('pmi\.onboarding\.consentDone'\)\} <\/p> \)\}/,
    'a confirmação do consentimento mudou de condição ou de texto');
});

test('#2393l C10 e C12: status com rótulo e validade do link com data', () => {
  assert.match(SRC, /const statusHumano = i18n\[`meStatus\.statusBadge\.\$\{app\?\.status\}`\] \?\? app\?\.status;/, 'o rótulo do status deixou de vir do dicionário');
  assert.match(SRC, /\{T\('pmi\.onboarding\.status'\)\}: <strong>\{statusHumano\}<\/strong>/, 'o status voltou a sair cru');
  assert.match(SRC, /⏰ \{T\('pmi\.onboarding\.expiresOn'\)\.replace\('\{date\}', fmtData\(token_metadata\.expires_at\)\)\}/, 'a validade voltou a ser em dias');
  for (const p of ['src/pages/pmi-onboarding/[token].astro', 'src/pages/en/pmi-onboarding/[token].astro', 'src/pages/es/pmi-onboarding/[token].astro'])
    assert.match(readFileSync(resolve(ROOT, p), 'utf8'), /buildPageI18n\(\['pmi\.onboarding', 'meStatus\.statusBadge'\], lang\)/, `${p} não entrega os rótulos de status`);
});

test('#2393l: as chaves do portal do piloto existem nas 3 línguas', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    for (const k of CHAVES) assert.match(d, new RegExp(`\\n  'pmi\\.onboarding\\.${k}': '[^'\\n]{5,}`), `${lang}: falta ${k}`);
    for (const k of ['journeyVideo', 'consentDonePilot']) assert.match(d, new RegExp(`'pmi\\.onboarding\\.${k}': '[^'\\n]*\\{date\\}`), `${lang}: ${k} sem {date}`);
    assert.doesNotMatch(d.split('\n').filter((l) => /'pmi\.onboarding\.(journey|intro|consentDone|help|withdraw|period|expiresOn)/.test(l)).join('\n'), /—|–/, `${lang}: travessão no texto do piloto`);
  }
});
