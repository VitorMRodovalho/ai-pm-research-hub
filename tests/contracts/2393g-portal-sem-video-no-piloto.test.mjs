/**
 * Contract: #2393, fatia 3 (ADR-0134, decisão D4 do GP em 02/11/2026) — o portal do candidato sem o vídeo geral
 * quando o token não tem o escopo 'video_screening'.
 *
 * O token de candidatura de vaga piloto da linha sai sem 'video_screening' (trigger do banco, guard 2393f). O
 * servidor já recusa gravar e recusar vídeo sem o escopo; este guard garante que o portal também não OFERECE:
 *   - a decisão vem do escopo do token (payload.scopes), não de outra coisa;
 *   - o consentimento de voz (que só serve para gravar vídeo) e a seção inteira de vídeo e entrevista ficam dentro
 *     de {hasVideoScope && ( ... )};
 *   - sem o escopo, um aviso neutro ocupa o lugar;
 *   - os botões que abrem esses fluxos não aparecem fora do bloco condicionado;
 *   - a chave do aviso existe nos 3 dicionários, e o texto em pt-BR é o aprovado pelo GP (03/11/2026).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const BRUTO = readFileSync(resolve(ROOT, 'src/components/pmi-onboarding/PMIOnboardingPortal.tsx'), 'utf8');
const SRC = maskJsComments(BRUTO).replace(/\s+/g, ' ');

// O bloco condicionado da seção de vídeo e entrevista: do {hasVideoScope && ( até o )} que fecha antes do rodapé.
function blocoDoVideo() {
  const ini = SRC.indexOf('{hasVideoScope && ( <section className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">');
  const fim = SRC.indexOf('</section> )} <footer', ini);
  assert.ok(ini !== -1 && fim > ini, 'a seção de vídeo e entrevista não está dentro de {hasVideoScope && ( ... )} antes do rodapé');
  return { ini, fim, texto: SRC.slice(ini, fim) };
}

test('#2393g: o portal decide pelo escopo de vídeo do token', () => {
  assert.match(SRC, /const hasVideoScope = \(payload\.scopes \?\? \[\]\)\.includes\('video_screening'\);/,
    'hasVideoScope não vem de payload.scopes');
  assert.equal((SRC.match(/hasVideoScope =/g) || []).length, 1, 'hasVideoScope é atribuído mais de uma vez');
});

test('#2393g: o consentimento de voz só aparece com o escopo de vídeo', () => {
  assert.match(SRC, /\{hasVideoScope && \( <section data-testid="voice-biometric-consent-section"/,
    'o consentimento de voz não está condicionado ao escopo de vídeo');
});

test('#2393g: a seção de vídeo e entrevista inteira fica no bloco do escopo, e sem ele vem o aviso neutro', () => {
  const { texto } = blocoDoVideo();
  for (const marca of ["T('pmi.onboarding.videoScreeningTitle')", "T('pmi.onboarding.interviewCtaButton')", 'PILLARS.map(', "T('pmi.onboarding.videoRecordButton')", 'optInterviewConfirm && (', 'revertInterviewConfirm && (']) {
    assert.ok(texto.includes(marca), `a seção condicionada não traz ${marca}`);
  }
  assert.match(SRC, /\{!hasVideoScope && \( <section data-testid="no-video-scope-notice" [^>]*> <p [^>]*>\{T\('pmi\.onboarding\.noVideoScopeNotice'\)\}<\/p> <\/section> \)\}/,
    'sem o escopo, o aviso neutro não ocupa o lugar');
});

test('#2393g: os botões de vídeo e entrevista não aparecem fora do bloco do escopo', () => {
  const { ini, fim } = blocoDoVideo();
  const fora = SRC.slice(0, ini) + SRC.slice(fim);
  for (const marca of ["T('pmi.onboarding.interviewCtaButton')", "T('pmi.onboarding.videoRecordButton')", "T('pmi.onboarding.interviewScheduleButton')", 'setOptInterviewConfirm(true)']) {
    assert.ok(!fora.includes(marca), `${marca} aparece fora do bloco do escopo de vídeo`);
  }
});

test('#2393g: a chave do aviso existe nos 3 dicionários', () => {
  for (const l of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8');
    assert.match(d, /^ {2}'pmi\.onboarding\.noVideoScopeNotice': '[^']{20,}',$/m, `${l}: falta a chave do aviso`);
  }
});

test('#2393g: o texto do aviso em pt-BR é o aprovado pelo GP', () => {
  const d = readFileSync(resolve(ROOT, 'src/i18n/pt-BR.ts'), 'utf8');
  assert.match(d, /^ {2}'pmi\.onboarding\.noVideoScopeNotice': 'Nesta vaga, as próximas etapas são combinadas com o líder da linha, e o contato chega por e-mail\.',$/m,
    'o texto do aviso mudou sem nova aprovação');
});
