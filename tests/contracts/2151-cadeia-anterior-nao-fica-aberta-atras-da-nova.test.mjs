/**
 * #2151 — nenhum documento de governanca pode ter DUAS approval_chains abertas ao mesmo tempo.
 *
 * O DEFEITO DE ORIGEM. Ha dois caminhos para lacrar uma versao e eles nao fazem a mesma coisa:
 *   - `recirculate_governance_doc` supersede a cadeia corrente ANTES de lacrar a proxima;
 *   - `lock_document_version` sozinho nao supersede nada. A unica guarda dele e
 *     `WHERE ac.version_id = p_version_id` — ele pergunta se existe cadeia para AQUELA VERSAO,
 *     nunca se o DOCUMENTO ja tem outra aberta. Versao nova e sempre version_id novo, entao a
 *     guarda nunca dispara.
 *
 * Medido em 02/09/2026: o Adendo de PI e a Politica de PI carregavam cada um duas cadeias em
 * `review`, uma de maio e outra de 30/08, porque a v0 foi lacrada pelo caminho direto. O audit log
 * confirma: `governance.recirculated` existe em 08/05 e 09/05, e nao existe em 30/08.
 *
 * POR QUE O GUARD QUE JA EXISTIA NAO PODIA TER VISTO. `1187-term-version-label-and-zombie-chains`
 * afirma exatamente esta invariante, e esta correto — mas filtra
 * `.eq('doc_type','volunteer_term_template')`, UM tipo entre os 16 do CHECK, e so considera zumbi
 * a cadeia atras de uma com `activated_at`. Nestes dois documentos nao havia cadeia ativada, e o
 * doc_type estava fora do recorte. Denominador estreito e condicao estreita: duas formas de o
 * guard ficar verde sobre o defeito que ele descreve.
 *
 * Este guard nao tem recorte de doc_type e nao exige ativacao: ele pergunta, para o acervo
 * inteiro, se algum documento tem mais de uma cadeia num estado aberto.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL_ = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(URL_ && KEY);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

// Os estados em que uma cadeia esta ABERTA, isto e, ainda pede acao de alguem. Mesma lista que a
// migration 20260805000370 (#1187) usa para decidir o que supersedar.
const ABERTOS = ['draft', 'review', 'approved'];

test(dbGated ? '#2151: nenhum documento tem mais de uma approval_chain aberta' : `SKIP: ${skipMsg}`,
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(URL_, KEY, { auth: { persistSession: false } });

  const { data: chains, error } = await sb
    .from('approval_chains')
    .select('id, document_id, status, opened_at');
  assert.equal(error, null, error?.message);

  // CONTROLE DE VACUIDADE: sem cadeia nenhuma, o agrupamento abaixo passaria sem afirmar nada — que
  // e como um guard sobrevive a propria irrelevancia. O acervo tinha 35 cadeias em 02/09/2026.
  assert.ok((chains ?? []).length >= 20,
    `esperava um acervo de cadeias povoado, achei ${chains?.length ?? 0}: o guard mediria vacuo`);

  // CONTROLE POSITIVO: os estados abertos tem de existir no acervo. Se ninguem estivesse em
  // `review`, a assercao principal passaria por ausencia de dado e nao por ausencia de defeito.
  const abertas = (chains ?? []).filter((c) => ABERTOS.includes(c.status));
  assert.ok(abertas.length > 0,
    'nenhuma cadeia em estado aberto: o controle nao discrimina, a assercao abaixo vale vacuo');

  const porDoc = new Map();
  for (const c of abertas) {
    if (!porDoc.has(c.document_id)) porDoc.set(c.document_id, []);
    porDoc.get(c.document_id).push(c);
  }

  const duplicados = [...porDoc.entries()].filter(([, cs]) => cs.length > 1);

  assert.deepEqual(
    duplicados.map(([doc, cs]) => `${doc}: ${cs.map((c) => `${c.id}@${c.opened_at?.slice(0, 10)}`).join(' + ')}`),
    [],
    'documento com duas cadeias abertas — a anterior nao foi supersedida quando a nova foi lacrada '
    + '(lock_document_version direto em vez de recirculate_governance_doc; ver #2151)'
  );
});
