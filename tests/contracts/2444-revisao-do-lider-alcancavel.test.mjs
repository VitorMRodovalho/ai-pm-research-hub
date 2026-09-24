// tests/contracts/2444-revisao-do-lider-alcancavel.test.mjs
// Estrutural (le so o componente): registrar em "test:structural" + "test:contracts".
/**
 * A revisão pré-curadoria (Manual §4.2, etapas 5 e 6) lê os campos que decide.
 *
 * O CASO (#2444): o CardDetail decidia pelos campos peer_review_* / leader_review_*, e nenhum
 * carregador do quadro os devolvia. O peer review aparecia "Pendente" depois de concluído e
 * "Avaliar como Líder" nunca surgia. Medido em 24/09/2026: 16 cards parados em leader_review,
 * 0 revisões de líder concluídas na história.
 *
 * O guard DERIVA a lista do próprio bloco: todo campo de revisão que o bloco lê tem de estar em
 * REVIEW_FIELDS. Um campo novo usado no bloco e esquecido na leitura reprova aqui.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SRC = readFileSync('src/components/board/CardDetail.tsx', 'utf8');

export function regrasDaRevisao(src) {
  const code = maskJsComments(src);
  const decl = code.match(/const REVIEW_FIELDS = '([^']*)';/);
  const lidos = new Set(decl ? decl[1].split(',').map((f) => f.trim()).filter(Boolean) : []);

  // Recorta no texto CRU (o marcador de fim vive num comentario JSX) e mascara so o recorte.
  const ini = src.indexOf("['draft', 'peer_review', 'leader_review'] as readonly CurationStatus[]");
  const fim = src.indexOf('── Curation Pipeline Visual ──');
  const bloco = ini > 0 && fim > ini ? maskJsComments(src.slice(ini, fim)) : '';
  const usados = new Set([...bloco.matchAll(/\brv\.((?:peer|leader)_review_[a-z_]+)/g)].map((m) => m[1]));

  return {
    blocoAchado: bloco.length > 0 && usados.size > 0,
    // o bloco nao pode ler o campo do `item` cru: e ele que chega sem os campos
    semItemCru: !/\bitem\.(?:peer|leader)_review_/.test(bloco),
    faltandoNaLeitura: [...usados].filter((f) => !lidos.has(f)).sort(),
    // a leitura acontece, na tabela, pelo card, e alimenta o estado que compoe `rv`
    leNaTabela: /sb\.from\('board_items'\)\.select\(REVIEW_FIELDS\)\.eq\('id', item\.id\)\.maybeSingle\(\)[\s\S]{0,120}?setReviewFields\(/.test(code),
    rvCompoe: /const rv: BoardItem = reviewFields \? \{ \.\.\.item, \.\.\.reviewFields \} : item;/.test(code),
    // trocar de card zera o que foi lido do anterior
    zeraAoTrocar: /useEffect\(\(\) => \{\s*setReviewFields\(null\);/.test(code),
  };
}

const OK = { blocoAchado: true, semItemCru: true, faltandoNaLeitura: [], leNaTabela: true, rvCompoe: true, zeraAoTrocar: true };

test('#2444: o bloco da revisao pre-curadoria le da tabela todo campo que decide', () => {
  assert.deepEqual(regrasDaRevisao(SRC), OK);
});

test('#2444 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const mut = (a, b) => {
    const m = SRC.replace(a, b);
    assert.notEqual(m, SRC, `mutacao nao aplicou: ${a}`);
    return regrasDaRevisao(m);
  };
  // 1: campo usado no bloco e retirado da leitura
  assert.deepEqual(mut('peer_review_completed_at, ', '').faltandoNaLeitura, ['peer_review_completed_at']);
  // 2: o bloco volta a ler do item cru (o defeito original)
  assert.equal(mut('{rv.peer_review_completed_at ? (', '{item.peer_review_completed_at ? (').semItemCru, false);
  // 3: a leitura deixa de acontecer
  assert.equal(mut(".select(REVIEW_FIELDS)", ".select('id')").leNaTabela, false);
  // 4: o que foi lido nao entra em `rv`
  assert.equal(mut('{ ...item, ...reviewFields }', '{ ...item }').rvCompoe, false);
  // 5: trocar de card mantem os campos do anterior
  assert.equal(mut('useEffect(() => {\n    setReviewFields(null);', 'useEffect(() => {').zeraAoTrocar, false);
  // 6: a leitura so em comentario nao conta
  assert.equal(mut("const rf = await safe(sb.from('board_items')", "// const rf = await safe(sb.from('board_items')").leNaTabela, false);
});
