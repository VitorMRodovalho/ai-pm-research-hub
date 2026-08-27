// tests/contracts/2022-contra-assinar-invalida-o-pdf-congelado.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2022 — contra-assinar invalida o PDF congelado.
 *
 * SINTOMA: um voluntário abriu o próprio termo e ele dizia "Pendente contra-assinatura" — já
 * assinado pelas duas partes. Medido em 27/08/2026: 47 de 85 termos contra-assinados exibiam isso.
 *
 * CAUSA: o download serve o artefato congelado (`pdf_url`) primeiro e só reconstrói quando ele não
 * existe. A contra-assinatura não mexia em `pdf_url`, então o arquivo servido continuava sendo o
 * renderizado ANTES dela.
 *
 * O conserto é uma linha. O que exigiu medição foi a SEGURANÇA dela: descartar o congelado só é
 * aceitável se a reconstrução sempre achar o texto acordado, porque o guard do #648 se RECUSA a
 * renderizar um termo em branco. Um termo sem fonte ficaria sem PDF nenhum — trocaria "o arquivo
 * diz a coisa errada" por "não há arquivo", que é pior.
 *
 * ⚠️ Por isso o teste vivo abaixo NÃO é decoração: ele é a condição que torna o conserto seguro.
 * Enquanto ele estiver verde, todo termo é reconstruível. No dia em que ficar vermelho, alguém
 * está prestes a perder um documento assinado.
 *
 * E o predicado de "é reconstruível?" vive AQUI e no guard em TypeScript (`pdf.ts`), não numa
 * terceira cópia dentro da RPC — um segundo predicado em SQL divergiria em silêncio, e a
 * divergência só apareceria no dia do prejuízo.
 *
 * Cross-ref: #2022, #648 (o guard que recusa renderizar em branco), #2023 (entrega do PDF às
 * partes — depende deste), #2024 (o fuso do carimbo, achado no mesmo backfill).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const SINGLE = latestFunctionCapture(ROOT, 'counter_sign_certificate');
const BULK = latestFunctionCapture(ROOT, 'bulk_counter_sign_certificates');

test('#2022 estático: a contra-assinatura invalida o congelado', () => {
  assert.ok(SINGLE, 'counter_sign_certificate não foi capturada por nenhuma migration');
  assert.match(SINGLE.body, /pdf_url\s*=\s*NULL/i,
    'sem isto o download continua servindo o PDF renderizado ANTES da contra-assinatura');
  // E o log tem de dizer POR QUE o arquivo mudou — senão o artefato troca sem rastro.
  assert.match(SINGLE.body, /frozen_pdf_invalidated/,
    'a invalidação do congelado não aparece na auditoria');
});

test('#2022 estático: o caminho em LOTE delega, em vez de repetir a escrita', () => {
  assert.ok(BULK, 'bulk_counter_sign_certificates não foi capturada');
  assert.match(BULK.body, /public\.counter_sign_certificate\s*\(/,
    'o lote parou de delegar: portão de autoridade, hash, auditoria, notificação e a invalidação ' +
    'do PDF passariam a ter duas implementações');
  // Se o lote ganhar UPDATE próprio em certificates, ele saiu da delegação.
  assert.doesNotMatch(BULK.body, /UPDATE\s+public\.certificates/i,
    'o lote passou a escrever direto em certificates — isso duplica as garantias da RPC canônica');
});

test('#2022 vivo: TODO termo é reconstruível — a condição que torna seguro descartar o congelado',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  const { data: certs, error } = await s
    .from('certificates')
    .select('id, content_snapshot, template_id, counter_signed_at')
    .eq('type', 'volunteer_agreement')
    .limit(1000);
  assert.ok(!error, error?.message);
  assert.ok((certs ?? []).length > 0, 'nenhum termo lido — o guard passaria por vacuidade');

  // As três fontes que `hydrateCertData` tenta, na mesma ordem do código.
  const { data: docs } = await s.from('governance_documents').select('id, content').limit(2000);
  const comConteudo = new Set((docs ?? []).filter((d) => d.content).map((d) => String(d.id)));

  const semFonte = (certs ?? []).filter((c) => {
    const snap = c.content_snapshot || {};
    const viaHtml = typeof snap.html_body === 'string' && snap.html_body.trim().length > 0;
    const viaClausulas = !!(snap.clauses && snap.clauses.clause1);
    const viaTemplate = c.template_id && comConteudo.has(String(c.template_id));
    return !viaHtml && !viaClausulas && !viaTemplate;
  });

  assert.deepEqual(semFonte.map((c) => c.id), [],
    `${semFonte.length} termos não têm de onde reconstruir o texto. Descartar o PDF congelado ` +
    `desses deixaria a pessoa SEM documento — o guard do #648 recusa renderizar em branco.`);

  // CONTROLE POSITIVO: prova que o teste consegue enxergar a ausência de fonte. Sem isto, um
  // `content_snapshot` que viesse todo nulo daria a mesma lista vazia por outro motivo.
  const inventado = { content_snapshot: {}, template_id: null };
  const snapI = inventado.content_snapshot;
  const detecta = !(typeof snapI.html_body === 'string' && snapI.html_body.trim())
    && !(snapI.clauses && snapI.clauses.clause1)
    && !(inventado.template_id && comConteudo.has(String(inventado.template_id)));
  assert.ok(detecta, 'o predicado não detecta um termo sem fonte nenhuma — não está medindo nada');
  assert.ok(comConteudo.size > 0, 'nenhum template com conteúdo — a terceira fonte não foi exercida');
});
