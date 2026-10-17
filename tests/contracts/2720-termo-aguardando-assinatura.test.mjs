/**
 * #2720 — na fila de /admin/filiacao, termo sem assinatura é "Aguardando assinatura", não Vigente.
 *
 * O term_status da fila (#1129) saía só da end_date do engajamento que exige termo. Medido em 17/10/2026: 5 pessoas
 * marcadas Vigente sem o termo assinado. Decisão do GP (17/10, forma A): status próprio 'unsigned', que passa na
 * frente de qualquer faixa de data, porque Vigente, Vencendo e Vencido só fazem sentido para termo assinado.
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
const Q = maskLineComments(latestFunctionCapture(ROOT, 'get_affiliation_verification_queue').body);
const migName = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('_2720_termo_aguardando_assinatura.sql'));
const ISL = maskJsComments(read('src/components/admin/AffiliationQueueIsland.tsx'));
const FAROL = maskJsComments(read('src/lib/statusFarol.ts'));

test('#2720 há exatamente uma migration', () => {
  assert.equal(migName.length, 1, `esperava 1 migration *_2720_termo_aguardando_assinatura.sql, achei ${migName.length}`);
});

test('#2720 a assinatura é lida no MESMO engajamento que dá a data do termo', () => {
  assert.match(Q, /SELECT e\.end_date AS term_end_date,\s+\(e\.agreement_certificate_id IS NOT NULL\) AS term_signed\s+FROM public\.engagements e\s+JOIN public\.engagement_kinds ek ON ek\.slug = e\.kind\s+WHERE e\.person_id = m\.person_id\s+AND e\.status = 'active'\s+AND ek\.requires_agreement = true\s+ORDER BY e\.end_date DESC NULLS LAST\s+LIMIT 1\s+\) term ON true/);
  assert.match(Q, /term\.term_end_date,\s+term\.term_signed,/, 'a coorte carrega a assinatura até o CASE');
});

test('#2720 sem assinatura vira unsigned antes de qualquer faixa de data', () => {
  assert.match(Q, /'term_status', CASE\s+WHEN c\.term_signed IS NULL THEN 'none'\s+WHEN NOT c\.term_signed THEN 'unsigned'\s+WHEN c\.term_end_date IS NULL THEN 'none'\s+WHEN c\.term_end_date < CURRENT_DATE THEN 'expired'\s+WHEN c\.term_end_date <= CURRENT_DATE \+ \(v_term_soon_days \|\| ' days'\)::interval THEN 'expiring'\s+ELSE 'valid'\s+END,/);
});

test('#2720 a tela: status no tipo, no rótulo, no filtro e no semáforo', () => {
  assert.match(ISL, /type TermStatus = 'valid' \| 'expiring' \| 'expired' \| 'none' \| 'unsigned';/);
  assert.match(ISL, /unsigned: t\('comp\.affiliationQueue\.term_unsigned', 'Aguardando assinatura'\),/);
  assert.match(ISL, /<option value="unsigned">\{t\('comp\.affiliationQueue\.term_unsigned', 'Aguardando assinatura'\)\}<\/option>/);
  assert.match(FAROL, /export type ValidityKey = [^;]*'unsigned';/);
  assert.match(FAROL, /unsigned:\s+\{ emoji: '[^']+', tone: 'attention' \},/, 'pede um passo da pessoa: não é validade');
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.ok(read(`src/i18n/${loc}.ts`).includes("'comp.affiliationQueue.term_unsigned':"), `${loc} sem term_unsigned`);
  }
});
