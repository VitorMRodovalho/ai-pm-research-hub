/**
 * #2726 — na tela de termos, quem pode contra-assinar se decide POR LINHA, com o mesmo predicado de
 * counter_sign_certificate (#2104: via da diretoria de voluntários, escalada da presidência, sem
 * auto-contra-assinatura).
 *
 * Duas metades, a LEITORA primeiro (lição de 17/10, #2720): esta PR faz a tela ler `m.can_counter_sign` com o
 * global como fallback, o que é tolerante à função antiga; a migration que passa a mandar o campo por linha
 * vem depois do deploy desta. Cada asserção amarra a condição ao resultado, sobre o código sem comentários.
 *
 * Metade produtora (PR 2): get_volunteer_agreement_status, lida pela captura MAIS NOVA (#1932).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const PANEL = maskJsComments(readFileSync(resolve(ROOT, 'src/components/admin/VolunteerAgreementPanel.tsx'), 'utf8'));
const MIGS = readdirSync(resolve(ROOT, 'supabase/migrations'));
const FN = maskLineComments(latestFunctionCapture(ROOT, 'get_volunteer_agreement_status').body);

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

test('#2726 a migration produtora tem arquivo com a versão registrada', () => {
  const f = MIGS.filter((x) => x.endsWith('_2726_termo_contra_assinatura_por_linha.sql'));
  assert.equal(f.length, 1);
  assert.doesNotMatch(f[0], /^20261018999999_/, 'arquivo ainda com o placeholder: renomeie para a versão registrada');
});

test('#2726 counter_signed vem do termo mais recente do ano, o mesmo do botão', () => {
  assert.match(
    FN,
    /'counter_signed', COALESCE\(\(\s*SELECT c\.counter_signed_at IS NOT NULL FROM public\.certificates c WHERE c\.member_id = m\.id AND c\.type = 'volunteer_agreement'\s+AND c\.status = 'issued'\s+AND EXTRACT\(YEAR FROM c\.issued_at\) = EXTRACT\(YEAR FROM now\(\)\)\s+ORDER BY c\.issued_at DESC LIMIT 1\s*\), false\)/,
  );
});

test('#2726 as vias do #2104: diretoria e presidência do contratante', () => {
  assert.match(FN, /v_route_director := v_caller_is_contracting AND EXISTS \(\s*SELECT 1 FROM public\.members m\s+WHERE m\.id = v_caller_id\s+AND 'voluntariado_director' = ANY/);
  assert.match(FN, /v_route_president := v_caller_is_contracting AND EXISTS \(\s*SELECT 1 FROM public\.members m\s+WHERE m\.id = v_caller_id\s+AND 'chapter_board' = ANY\(COALESCE\(m\.designations, ARRAY\[\]::text\[\]\)\)\s+AND 'legal_signer' = ANY/);
  assert.match(FN, /v_can_counter_sign := v_route_director OR v_route_president;/);
  assert.doesNotMatch(FN, /v_can_counter_sign := v_is_manage_member/);
});

test('#2726 a permissão por linha: nunca o titular; a diretoria; a presidência só por escalada', () => {
  assert.match(
    FN,
    /'can_counter_sign', \(\s*m\.id IS DISTINCT FROM v_caller_id\s+AND \(\s*v_route_director\s+OR \(v_route_president AND \(\s*v_director_vacant\s+OR EXISTS \([\s\S]{0,300}?WHERE pc\.chapter_code = m\.chapter\s+AND cr\.is_contracting_chapter\s+AND 'voluntariado_director' = ANY\(COALESCE\(m\.designations/,
  );
});

test('#2726 a lista inclui quem tem termo do ano assinado e sem contra-assinatura', () => {
  assert.match(
    FN,
    /OR EXISTS \(\s*SELECT 1 FROM public\.certificates c WHERE c\.member_id = m\.id AND c\.type = 'volunteer_agreement'\s+AND c\.status = 'issued'\s+AND c\.counter_signed_at IS NULL\s+AND EXTRACT\(YEAR FROM c\.issued_at\) = EXTRACT\(YEAR FROM now\(\)\)\s*\)\s*\)\s*AND \(v_is_manage_member OR v_is_vol_director OR m\.chapter = v_caller_chapter\)\s*\)\s*\) INTO v_result;/,
  );
});
