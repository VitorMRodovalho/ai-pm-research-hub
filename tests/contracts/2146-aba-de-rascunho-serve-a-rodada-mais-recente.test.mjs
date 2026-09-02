/**
 * #2146 - a aba de rascunho tem de servir a rodada MAIS RECENTE.
 *
 * `get_next_draft_version` ordenava por `version_number ASC`, o que devolve o rascunho mais
 * ANTIGO acima da versao corrente. Com UM rascunho aberto, "proximo" e "mais recente" sao a mesma
 * linha e o defeito e invisivel. Com DOIS, divergem para sempre.
 *
 * Medido em 02/09/2026 no TAP: corrente M02, rascunhos 1=M01 3=M03 4=M04, e a tela servia M03.
 * `ReviewChainIsland` usa esta RPC para a aba "Draft", entao quem abrisse o link canonico lia a
 * rodada anterior achando que lia a atual.
 *
 * O guard resolve pela captura MAIS RECENTE (nao fixa arquivo, licao do #1932) e exercita a
 * funcao VIVA, porque afirmar sobre texto foi o que deixou este defeito passar por meses.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const FN = latestFunctionCapture(ROOT, 'get_next_draft_version');

const URL_ = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(URL_ && KEY);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

test('#2146 estatico: a ordenacao e DESC, e o filtro de destrancado continua', () => {
  assert.match(FN.body, /ORDER BY dv\.version_number DESC/,
    'ASC devolve o rascunho mais ANTIGO: e o defeito inteiro');
  assert.doesNotMatch(FN.body, /ORDER BY dv\.version_number ASC/,
    'nao pode sobrar a ordenacao antiga');
  assert.match(FN.body, /dv\.locked_at IS NULL/,
    'so rascunho aberto e candidato; sem isto a aba serviria versao lacrada');
  assert.match(FN.body, /dv\.version_number > v_current\.version_number/,
    'so acima da corrente; sem isto a aba andaria para tras');
});

test('#2146 estatico: nada alem da ordenacao muda', () => {
  assert.match(FN.block, /CREATE OR REPLACE FUNCTION public\.get_next_draft_version\(p_version_id uuid\)/);
  assert.match(FN.block, /\bSTABLE\b/, 'a volatilidade tem de continuar STABLE');
  assert.match(FN.block, /SECURITY DEFINER/);
  assert.doesNotMatch(FN.block, /DROP FUNCTION/);
});

test(dbGated ? '#2146 vivo: a RPC devolve o rascunho de MAIOR version_number' : `SKIP: ${skipMsg}`,
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(URL_, KEY, { auth: { persistSession: false } });

  // Escolhe, por DADO, um documento que exerca o caso: corrente + DOIS ou mais rascunhos acima.
  // Com um rascunho so, ASC e DESC coincidem e o teste passaria por vacuidade.
  const { data: docs, error: e1 } = await sb
    .from('governance_documents').select('id, current_version_id').not('current_version_id','is',null);
  assert.equal(e1, null, e1?.message);

  let alvo = null;
  for (const d of docs ?? []) {
    const { data: cur } = await sb.from('document_versions')
      .select('version_number').eq('id', d.current_version_id).maybeSingle();
    if (!cur) continue;
    const { data: acima } = await sb.from('document_versions')
      .select('id, version_number, version_label')
      .eq('document_id', d.id).is('locked_at', null).gt('version_number', cur.version_number)
      .order('version_number', { ascending: false });
    if ((acima ?? []).length >= 2) { alvo = { doc: d, acima }; break; }
  }

  // CONTROLE: sem um documento com DOIS rascunhos acima, este teste nao distingue ASC de DESC.
  assert.ok(alvo, 'nenhum documento com 2+ rascunhos abertos acima da corrente: o caso que ' +
    'separa ASC de DESC nao existe na base, e o guard passaria por vacuidade');

  const { data: rpc, error: e2 } = await sb.rpc('get_next_draft_version',
    { p_version_id: alvo.doc.current_version_id });
  assert.equal(e2, null, e2?.message);
  assert.equal(rpc?.exists, true, 'havia rascunho acima da corrente e a RPC disse que nao');

  const maisRecente = alvo.acima[0];
  const maisAntigo  = alvo.acima[alvo.acima.length - 1];
  assert.equal(rpc.version_id, maisRecente.id,
    `a RPC devolveu ${rpc.version_label} e o mais recente e ${maisRecente.version_label}`);
  // CONTROLE NEGATIVO: e nao pode ser o mais antigo, que era o que ASC devolvia.
  assert.notEqual(rpc.version_id, maisAntigo.id,
    `a RPC voltou a devolver o rascunho mais antigo (${maisAntigo.version_label})`);
});
