/**
 * #2726 — na tela de termos, quem pode contra-assinar se decide POR LINHA, com o mesmo predicado de
 * counter_sign_certificate (#2104: via da diretoria de voluntários, escalada da presidência, sem
 * auto-contra-assinatura).
 *
 * Duas metades, a LEITORA primeiro (lição de 17/10, #2720): esta PR faz a tela ler `m.can_counter_sign` com o
 * global como fallback, o que é tolerante à função antiga; a migration que passa a mandar o campo por linha
 * vem depois do deploy desta. Cada asserção amarra a condição ao resultado, sobre o código sem comentários.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const PANEL = maskJsComments(readFileSync(resolve(ROOT, 'src/components/admin/VolunteerAgreementPanel.tsx'), 'utf8'));

test('#2726 a permissão da linha é o campo por linha, com o global como fallback', () => {
  assert.match(PANEL, /const rowCanCounterSign = \(m: MemberRow\): boolean => m\.can_counter_sign \?\? canCounterSign;/);
  assert.match(PANEL, /can_counter_sign\?: boolean;/);
});

test('#2726 o botão de contra-assinar da linha obedece à permissão da linha', () => {
  assert.match(
    PANEL,
    /\{rowCanCounterSign\(m\) && m\.signed && !m\.counter_signed && \(\s*<button\s+onClick=\{\(\) => counterSignAgreement\(m\)\}/,
  );
});

test('#2726 a seleção em lote obedece à permissão da linha', () => {
  assert.match(
    PANEL,
    /const canBulkSelect = \(m: MemberRow\): boolean =>\s*rowCanCounterSign\(m\) && m\.signed && !m\.counter_signed && m\.agreement_status === 'issued'/,
  );
});

test('#2726 nenhum botão de linha volta a decidir só pelo global', () => {
  assert.doesNotMatch(PANEL, /canCounterSign && m\.signed && !m\.counter_signed/);
});
