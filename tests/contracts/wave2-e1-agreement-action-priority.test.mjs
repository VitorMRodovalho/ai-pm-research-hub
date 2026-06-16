/**
 * Contract: Wave 2 / E1 — fila de acordos pendentes PRIORIZADA por ação.
 *
 * Gap (discovery #740): "Diretoria de Voluntariado não distingue 'pending que JÁ
 * pode assinar' de 'pending ainda no funil'. Visão é de conformidade, não de ação
 * priorizada." A fila já existia em /admin/certificates (RPC get_pending_agreement_engagements,
 * #177) mas era "visibility-only" sem ordenação. E1 a transforma em ação priorizada:
 * quem está apto a assinar (next_action=notify_member_to_sign_volunteer_term) e ainda
 * NÃO foi notificado vai ao topo, destacado, com contagem "aptos a assinar agora".
 *
 * 100% ancorado: nenhuma RPC nova — só ordena/destaca o payload existente. Static-only.
 *
 * Cross-ref: #740, #177 (pending agreement queue), get_pending_agreement_engagements.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const PAGE = readFileSync('src/pages/admin/certificates.astro', 'utf8');

describe('Wave2 E1 — action-prioritized pending-agreement queue', () => {
  it('still consumes the existing RPC (no new backend)', () => {
    assert.match(PAGE, /\.rpc\('get_pending_agreement_engagements'\)/);
  });

  it('defines "apto a assinar agora" = notify-to-sign AND not yet notified', () => {
    assert.match(PAGE, /const isAptoNow = \(r: any\): boolean =>/);
    assert.match(PAGE, /next_action === 'notify_member_to_sign_volunteer_term' && !r\.has_agreement_notification/);
  });

  it('ranks actionable-first and sorts the queue (apto-now = rank 0)', () => {
    assert.match(PAGE, /paRank = \(r: any\): number => isAptoNow\(r\) \? 0 :/);
    assert.match(PAGE, /const sortedPending = \[\.\.\.pendingAgreements\.pending\]\.sort\(/);
    assert.match(PAGE, /paRank\(a\) - paRank\(b\)/);
    // render must iterate the SORTED list, not the raw payload
    assert.match(PAGE, /sortedPending\.map\(\(row: any\) =>/);
    assert.doesNotMatch(PAGE, /pendingAgreements\.pending\.map\(/);
  });

  it('surfaces a count of "aptos a assinar agora" and a per-row badge', () => {
    assert.match(PAGE, /const aptoNowCount = sortedPending\.filter\(isAptoNow\)\.length/);
    assert.match(PAGE, /aptoNowCount > 0 \?/);
    assert.match(PAGE, /paT\('badge_apto_now'\)/);
    assert.match(PAGE, /paT\('apto_now_count'\)/);
  });

  it('reframes the subheading from "visibility only" to action-prioritized', () => {
    assert.doesNotMatch(PAGE, /Apenas visibilidade/);
    assert.doesNotMatch(PAGE, /Visibility only/);
    assert.match(PAGE, /Priorizado por ação/);
  });

  it('new inline labels exist in all 3 locales', () => {
    for (const key of ['badge_apto_now', 'apto_now_count']) {
      const count = (PAGE.match(new RegExp(`${key}:`, 'g')) || []).length;
      assert.ok(count >= 3, `${key} should appear in all 3 PA_LABELS locales (found ${count})`);
    }
  });
});
