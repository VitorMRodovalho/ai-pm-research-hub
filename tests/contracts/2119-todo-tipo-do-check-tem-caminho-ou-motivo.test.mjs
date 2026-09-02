/**
 * #2119 - todo doc_type admitido pelo CHECK ou resolve cadeia, ou consta do mapa de
 * fora-do-fluxo COM MOTIVO. Nenhum pode ficar em nenhum dos dois.
 *
 * O DEFEITO DE ORIGEM: ampliar o CHECK admite o valor e nao cria o caminho que ele percorre.
 * Medido em 02/09/2026, antes desta entrega: o CHECK admitia 14 tipos e `resolve_default_gates`
 * cobria 11. Os tres descobertos (accession_term, data_processing_agreement,
 * declaration_template) JA TINHAM documento na base, um cada, e nenhum alcancava ratificacao:
 * o resolvedor devolvia NULL e a cadeia nunca se montava. Travava em silencio.
 *
 * POR QUE O GUARD DERIVA DO CHECK E NAO DE UMA LISTA DE NOMES. O guard anterior
 * (`p262-312-w4a-gate-templates-6-doc-types`) mantinha `ALL_DOC_TYPES` escrito a mao com 11
 * nomes. Um tipo novo entrava admitido pelo CHECK e saia do alcance do guard sem nada ficar
 * vermelho: a lista nao cresce sozinha. Aqui o denominador E o CHECK, entao tipo novo nasce
 * coberto.
 *
 * E POR QUE `NULL` NAO BASTA COMO "FORA DO FLUXO". Antes desta entrega, "sem cadeia por desenho"
 * e "sem cadeia por lacuna" eram o MESMO NULL, e nenhum guard podia distinguir. Agora
 * `governance_doc_type_out_of_flow` devolve o motivo textual, e a ausencia nos dois lugares e
 * que reprova.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL_ = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(URL_ && KEY);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(URL_, KEY, { auth: { persistSession: false } });

/**
 * Le os tipos admitidos DO CHECK, que e o denominador desta issue.
 * NAO ha fallback de proposito: se a RPC sumir, o guard tem de REPROVAR, e nao cair para uma
 * amostra menor e passar. Denominador silenciosamente reduzido e como o defeito nasceu.
 */
async function tiposDoCheck(client) {
  const { data, error } = await client.rpc('_audit_doc_type_check_values');
  assert.equal(error, null, `_audit_doc_type_check_values indisponivel: ${error?.message ?? ''}`);
  return data;
}

test(dbGated ? '#2119: todo tipo do CHECK tem cadeia OU motivo de fora-do-fluxo' : `SKIP: ${skipMsg}`,
  { skip: dbGated ? false : skipMsg }, async () => {
  const client = sb();

  // O denominador vem do CHECK. Sem ele, o guard mediria uma amostra e passaria por vacuidade.
  const tipos = await tiposDoCheck(client);
  assert.ok(Array.isArray(tipos) && tipos.length > 0,
    'nao consegui ler os tipos do CHECK: sem denominador, este guard nao mede nada');

  // PISO CONTRA VACUIDADE: o CHECK tem de ter crescido para 15 nesta entrega.
  assert.ok(tipos.length >= 15,
    `o CHECK admite ${tipos.length} tipos; esperava ao menos 15 apos a #2119/#2120`);

  const semCaminho = [];
  const foraDoFluxo = [];
  for (const t of tipos) {
    const { data: gates } = await client.rpc('resolve_default_gates', { p_doc_type: t });
    if (gates !== null && gates !== undefined) continue;
    const { data: motivo } = await client.rpc('governance_doc_type_out_of_flow', { p_doc_type: t });
    if (motivo) { foraDoFluxo.push(t); continue; }
    semCaminho.push(t);
  }

  assert.deepEqual(semCaminho, [],
    `tipo(s) admitidos pelo CHECK sem cadeia e sem motivo de fora-do-fluxo: ${semCaminho.join(', ')}`);

  // CONTROLE POSITIVO nos DOIS sentidos: se nada estivesse fora do fluxo, o ramo do motivo nunca
  // seria exercido e este guard passaria sem testar a metade que a #2119 criou.
  assert.ok(foraDoFluxo.length > 0,
    'nenhum tipo fora do fluxo: o mapa de motivo nao foi exercido, guard verde por vacuidade');
  assert.ok(foraDoFluxo.includes('declaration_template'),
    'declaration_template tem de estar fora do fluxo por desenho (Clausula 5.1)');
});

test(dbGated ? '#2119: os tres tipos novos abrem com curator(all), invariante do p35' : `SKIP: ${skipMsg}`,
  { skip: dbGated ? false : skipMsg }, async () => {
  const client = sb();
  for (const t of ['accession_term', 'data_processing_agreement', 'assignment_term']) {
    const { data: gates, error } = await client.rpc('resolve_default_gates', { p_doc_type: t });
    assert.equal(error, null, error?.message);
    assert.ok(Array.isArray(gates) && gates.length > 0, `${t} continua sem cadeia`);
    assert.equal(gates[0].kind, 'curator', `${t} nao abre com curator`);
    assert.equal(gates[0].threshold, 'all', `${t} nao abre com threshold "all"`);
  }
  // CONTROLE NEGATIVO: `policy` e a unica excecao viva a invariante, e tem de continuar sendo.
  const { data: pol } = await client.rpc('resolve_default_gates', { p_doc_type: 'policy' });
  assert.equal(pol[0].kind, 'committee_majority',
    'policy deixou de ser a excecao: ou a invariante mudou, ou o resolvedor quebrou');
});

test(dbGated ? '#2119: o motivo de fora-do-fluxo e auditavel, nao um rotulo' : `SKIP: ${skipMsg}`,
  { skip: dbGated ? false : skipMsg }, async () => {
  const client = sb();
  const { data: motivo } = await client.rpc('governance_doc_type_out_of_flow',
    { p_doc_type: 'declaration_template' });
  assert.ok(typeof motivo === 'string' && motivo.length >= 80,
    'motivo curto e desculpa, nao razao: quem ler daqui a seis meses precisa do fundamento');
  assert.match(motivo, /5\.1/, 'o motivo tem de citar a clausula que o sustenta');

  // CONTROLE: um tipo COM cadeia nao pode ter motivo, senao os dois lugares se contradizem.
  const { data: nada } = await client.rpc('governance_doc_type_out_of_flow',
    { p_doc_type: 'cooperation_agreement' });
  assert.equal(nada, null, 'tipo com cadeia nao pode constar do mapa de fora-do-fluxo');
});
