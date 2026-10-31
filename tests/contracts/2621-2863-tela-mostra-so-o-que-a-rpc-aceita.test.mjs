/**
 * Contract: #2621 (G1) e #2863 (G13) — a tela só oferece a ação que o servidor aceita.
 *
 * G1. O botão "Submeter para Curadoria" do card aparecia para `isLeader || isCardAssignee`, e a
 * `submit_for_curation` recusa o atribuído ("Requires participate_in_governance_review or
 * tribe_leader", medido em 30/10/2026). A tela passa a ler `can_submit_curation` de
 * `get_artifact_classification`, que o servidor calcula com a regra de autoridade da RPC. A RPC não
 * foi alargada. O reenvio segue a mesma condição do botão.
 *
 * G13. Os dois diagnósticos do /admin/portfolio (`admin_detect_board_taxonomy_drift` e
 * `admin_run_portfolio_data_sanity`) recusam quem não tem `manage_platform`, e os botões apareciam
 * para todo mundo que abre a página. Passam a nascer escondidos e só aparecem com
 * `canFor('manage_platform')` fora da simulação, reaplicado quando o Nav carrega as capacidades.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const ler = (rel) => readFileSync(resolve(ROOT, rel), 'utf8');
export const CARD = ler('src/components/board/CardDetail.tsx');
export const PORTFOLIO = ler('src/pages/admin/portfolio.astro');

/** G1: o que decide o botão e o reenvio, sem comentário. */
export function envio(src) {
  const c = maskJsComments(src);
  return {
    campoDoServidor: /const canSubmitCuration = !!classif\?\.can_submit_curation;/.test(c),
    tipoDoCampo: /can_submit_curation\?: boolean;/.test(c),
    // A condição amarrada ao botão que ela mostra: nada entre o `&& (` e o onClick a não ser markup.
    botao: /\{item\.curation_status === 'draft' && needsCuration && canSubmitCuration && \(\s*<div[^{}]*>\s*<span[^>]*>\s*\{[^{}]*\}\s*<\/span>\s*<button\s+onClick=\{handleSubmitToCuration\}/.test(c),
    reenvio: /const canResubmit = needsCuration && canSubmitCuration;/.test(c),
    // INVERSA: o atribuído não volta a abrir o botão nem o reenvio.
    semAtribuido: !/needsCuration && \([^)]*isCardAssignee[^)]*\) && \(\s*<div[^{}]*>\s*<span[^>]*>\s*\{[^{}]*\}\s*<\/span>\s*<button\s+onClick=\{handleSubmitToCuration\}/.test(c)
      && !/const canResubmit = [^;]*isCardAssignee/.test(c),
  };
}

/** G13: o contêiner dos dois botões nasce escondido e só o portão de manage_platform o mostra. */
export function diagnosticos(src) {
  const c = maskJsComments(src);
  return {
    nasceEscondido: /<div id="portfolio-platform-actions" class="hidden [^"]*">\s*<button id="portfolio-run-taxonomy-alerts"[^>]*>[^<]*<\/button>\s*<button id="portfolio-run-sanity"[^>]*>[^<]*<\/button>\s*<\/div>/.test(c),
    portao: /const show = !getSimulation\(\)\.active && canFor\('manage_platform'\);\s*document\.getElementById\('portfolio-platform-actions'\)\?\.classList\.toggle\('hidden', !show\);/.test(c),
    aplicaNoBoot: /if \(!hasPortfolioAccess\(member\)\) \{\s*denied\?\.classList\.remove\('hidden'\);\s*return;\s*\}\s*applyPlatformActions\(\);/.test(c),
    reaplicaNasCapacidades: /window\.addEventListener\('nav:capabilities', applyPlatformActions\);/.test(c),
    // INVERSA: nenhum outro caminho tira o hidden do contêiner ou de um dos botões.
    semAtalho: !/getElementById\('portfolio-(?:platform-actions|run-taxonomy-alerts|run-sanity)'\)\?\.classList\.remove\('hidden'\)/.test(c),
  };
}

test('#2621 G1: o botão de envio e o reenvio seguem can_submit_curation, que vem do servidor', () => {
  const e = envio(CARD);
  assert.ok(e.tipoDoCampo, 'ArtifactClassification não declara can_submit_curation');
  assert.ok(e.campoDoServidor, 'canSubmitCuration não vem de classif.can_submit_curation');
  assert.ok(e.botao, 'o botão "Submeter para Curadoria" não está condicionado a draft, needsCuration e canSubmitCuration');
  assert.ok(e.reenvio, 'o reenvio não segue a mesma condição do botão');
});

test('#2621 G1 (INVERSA): o atribuído não abre o botão nem o reenvio', () => {
  assert.ok(envio(CARD).semAtribuido, 'isCardAssignee voltou à condição do botão ou do reenvio');
});

test('#2863 G13: os dois diagnósticos nascem escondidos e só aparecem com manage_platform', () => {
  const d = diagnosticos(PORTFOLIO);
  assert.ok(d.nasceEscondido, 'o contêiner dos dois botões não nasce com hidden, ou os botões saíram dele');
  assert.ok(d.portao, 'o contêiner não é mostrado só com canFor(manage_platform) fora da simulação');
  assert.ok(d.aplicaNoBoot, 'o portão não é aplicado no boot, depois da checagem de acesso');
  assert.ok(d.reaplicaNasCapacidades, 'o portão não é reaplicado quando o Nav carrega as capacidades');
});

test('#2863 G13 (INVERSA): nenhum outro caminho mostra os botões', () => {
  assert.ok(diagnosticos(PORTFOLIO).semAtalho, 'um classList.remove("hidden") direto mostra os botões sem o portão');
});
