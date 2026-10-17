/**
 * #2720 — na fila de /admin/filiacao, termo sem assinatura é "Aguardando assinatura", não Vigente.
 *
 * Decisão do GP (17/10/2026, forma A): status próprio 'unsigned'. Esta é a METADE LEITORA: a tela conhece o status e
 * não cai diante de um status que não conhece. A metade produtora (a fila devolvendo 'unsigned') vai numa migration
 * DEPOIS do deploy desta, porque em 17/10 a ordem inversa derrubou a ilha da fila por 6 minutos: o bundle no ar
 * indexava o semáforo pela chave sem fallback (aplicada em 20261017155646, revertida em 20261017160246).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const migs = readdirSync(resolve(ROOT, 'supabase/migrations'));
const ISL = maskJsComments(read('src/components/admin/AffiliationQueueIsland.tsx'));
const FAROL = maskJsComments(read('src/lib/statusFarol.ts'));

test('#2720 as migrations aplicadas no banco têm arquivo: a aplicação e a reversão', () => {
  assert.equal(migs.filter((f) => f.endsWith('_2720_termo_aguardando_assinatura.sql')).length, 1);
  assert.equal(migs.filter((f) => f.endsWith('_2720_reverte_fila_ao_corpo_da_2718.sql')).length, 1);
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
