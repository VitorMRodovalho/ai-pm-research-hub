/**
 * #2720 — na fila de /admin/filiacao, termo sem assinatura é "Aguardando assinatura", não Vigente.
 *
 * Decisão do GP (17/10/2026, forma A): status próprio 'unsigned'. Duas metades, nesta ordem: a LEITORA (#2722: a tela
 * conhece o status e não cai diante de um status que não conhece) e depois a PRODUTORA (a fila devolvendo 'unsigned',
 * com desempate pela assinatura). Em 17/10 a ordem inversa derrubou a ilha da fila por 6 minutos: o bundle no ar
 * indexava o semáforo pela chave sem fallback (aplicada em 20261017155646, revertida em 20261017160246).
 *
 * O corpo SQL é lido pela captura MAIS NOVA (#1932). Cada asserção amarra a condição ao resultado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const migs = readdirSync(resolve(ROOT, 'supabase/migrations'));
const ISL = maskJsComments(read('src/components/admin/AffiliationQueueIsland.tsx'));
const FAROL = maskJsComments(read('src/lib/statusFarol.ts'));
const Q = maskLineComments(latestFunctionCapture(ROOT, 'get_affiliation_verification_queue').body);

test('#2720 as migrations aplicadas no banco têm arquivo: a aplicação, a reversão e a produtora', () => {
  assert.equal(migs.filter((f) => f.endsWith('_2720_termo_aguardando_assinatura.sql')).length, 1);
  assert.equal(migs.filter((f) => f.endsWith('_2720_reverte_fila_ao_corpo_da_2718.sql')).length, 1);
  assert.equal(migs.filter((f) => f.endsWith('_2720_unsigned_com_desempate.sql')).length, 1);
});

test('#2720 a assinatura vem do MESMO vínculo que dá a data, e o empate de data é decidido pela assinatura', () => {
  assert.match(Q, /SELECT e\.end_date AS term_end_date,\s+\(e\.agreement_certificate_id IS NOT NULL\) AS term_signed\s+FROM public\.engagements e\s+JOIN public\.engagement_kinds ek ON ek\.slug = e\.kind\s+WHERE e\.person_id = m\.person_id\s+AND e\.status = 'active'\s+AND ek\.requires_agreement = true\s+ORDER BY e\.end_date DESC NULLS LAST,\s+\(e\.agreement_certificate_id IS NOT NULL\) DESC\s+LIMIT 1\s+\) term ON true/,
    'sem o desempate, dois vínculos com a mesma data fazem o status mudar de uma chamada para outra');
  assert.match(Q, /term\.term_end_date,\s+term\.term_signed,/, 'a coorte carrega a assinatura até o CASE');
});

test('#2720 sem assinatura vira unsigned antes de qualquer faixa de data', () => {
  assert.match(Q, /'term_status', CASE\s+WHEN c\.term_signed IS NULL THEN 'none'\s+WHEN NOT c\.term_signed THEN 'unsigned'\s+WHEN c\.term_end_date IS NULL THEN 'none'\s+WHEN c\.term_end_date < CURRENT_DATE THEN 'expired'\s+WHEN c\.term_end_date <= CURRENT_DATE \+ \(v_term_soon_days \|\| ' days'\)::interval THEN 'expiring'\s+ELSE 'valid'\s+END,/);
});

test('#2720 a tela conhece o status: tipo, rótulo, filtro, semáforo e os 3 dicionários', () => {
  assert.match(ISL, /type TermStatus = 'valid' \| 'expiring' \| 'expired' \| 'none' \| 'unsigned';/);
  assert.match(ISL, /unsigned: t\('comp\.affiliationQueue\.term_unsigned', 'Aguardando assinatura'\),/);
  assert.match(ISL, /<option value="unsigned">\{t\('comp\.affiliationQueue\.term_unsigned', 'Aguardando assinatura'\)\}<\/option>/);
  assert.match(FAROL, /export type ValidityKey = [^;]*'unsigned';/);
  assert.match(FAROL, /unsigned:\s+\{ emoji: '[^']+', tone: 'attention' \},/, 'pede um passo da pessoa: não é validade');
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.ok(read(`src/i18n/${loc}.ts`).includes("'comp.affiliationQueue.term_unsigned':"), `${loc} sem term_unsigned`);
  }
});

test('#2720 status desconhecido não derruba a tela: o semáforo cai no neutro e o rótulo mostra a chave', () => {
  const fn = FAROL.slice(FAROL.indexOf('export function validityFarol('));
  assert.match(fn, /^export function validityFarol\(key: ValidityKey\): \{ emoji: string; cls: string \} \{\s+const f = VALIDITY_FAROL\[key\] \?\? VALIDITY_FAROL\.none;\s+return \{ emoji: f\.emoji, cls: toneClasses\(f\.tone\) \};/);
  assert.match(ISL, /return \{ emoji: f\.emoji, label: labels\[status\] \?\? status, cls: f\.cls \};/);
});
