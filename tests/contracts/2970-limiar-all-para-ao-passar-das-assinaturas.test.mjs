// tests/contracts/2970-limiar-all-para-ao-passar-das-assinaturas.test.mjs
/**
 * #2970: no limiar 'all', _gate_threshold_met para de contar elegíveis assim que passa das assinaturas.
 *
 * 'all' é "S >= E": S = assinaturas approval/acknowledge do portão, E = membros ativos com _can_sign_gate. Contar E
 * inteiro roda _can_sign_gate (no curator, can()) para todo membro ativo, e isso acontecia a cada consulta do sino
 * de quem pode assinar um portão posterior. A forma nova conta elegíveis só até S+1 e compara com S:
 * min(E, S+1) <= S vale exatamente quando E <= S.
 *
 * O guard afirma, sobre o ramo 'all' do corpo mais novo de _gate_threshold_met:
 *   1. a contagem limitada: os elegíveis são "m.is_active E _can_sign_gate(m.id, p_chain_id, kind)", o LIMIT é a
 *      contagem de assinaturas + 1, e o resultado é comparado com <= à MESMA contagem de assinaturas;
 *   2. o cache de preview (preview_gate_eligibles_cache) só aparece dentro do ORDER BY da busca: ordena, nunca
 *      decide quem conta;
 *   3. o recorte do ramo é o certo: começa no WHEN do 'all' e termina no WHEN seguinte.
 *
 * A equivalência no banco não é medida aqui (o guard 654 compara _prior_gates_satisfied com _gate_threshold_met ao
 * vivo no CI). A prova de que a forma nova responde igual à antiga em toda cadeia aberta é o P1 da verificação do
 * apply.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { maskLineComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const espaco = (s) => s.replace(/\s+/g, ' ').trim();
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** O ramo 'all' do CASE, sem comentários e com espaço normalizado; null se não achar. */
export function ramoAll(body) {
  const c = espaco(maskLineComments(body));
  const ini = c.indexOf("WHEN (p_gate->>'threshold') = 'all' THEN");
  if (ini === -1) return null;
  const fim = c.indexOf("WHEN (p_gate->>'threshold')", ini + 1);
  return fim === -1 ? null : c.slice(ini, fim).trim();
}

// A contagem de assinaturas do portão, como o ramo a escreve (as duas ocorrências precisam ser esta).
const S = "SELECT count(*) FROM public.approval_signoffs s WHERE s.approval_chain_id = p_chain_id " +
  "AND s.gate_kind = (p_gate->>'kind') AND s.signoff_type IN ('approval','acknowledge')";

/** As partes que decidem, ligadas: elegível, limite S+1, comparação <= S. */
export function contagemLimitada(ramo) {
  const re = new RegExp(
    "^WHEN \\(p_gate->>'threshold'\\) = 'all' THEN " +
      '\\(SELECT count\\(\\*\\) FROM \\( SELECT 1 FROM \\(SELECT m\\.id FROM public\\.members m WHERE m\\.is_active ' +
      'ORDER BY (.+?) OFFSET 0\\) m ' +
      "WHERE public\\._can_sign_gate\\(m\\.id, p_chain_id, p_gate->>'kind'\\) " +
      'LIMIT \\(' + esc(S) + '\\) \\+ 1 \\) e\\) ' +
      '<= \\(' + esc(S) + '\\)$',
  );
  const m = ramo.match(re);
  return m ? { ordem: m[1] } : null;
}

const CAP = latestFunctionCapture(ROOT, '_gate_threshold_met');
const RAMO = ramoAll(CAP.body);

test("o ramo 'all' existe e termina no WHEN seguinte", () => {
  assert.ok(RAMO, `${CAP.file}: não achei o ramo 'all' de _gate_threshold_met seguido de outro WHEN`);
  assert.doesNotMatch(RAMO, /'majority'|'window_optional'/, `${CAP.file}: o recorte do ramo 'all' invadiu o ramo seguinte`);
});

test("'all' conta elegíveis ativos até S+1 e compara com <= S, com a mesma contagem de assinaturas", () => {
  assert.ok(RAMO, `${CAP.file}: ramo 'all' ausente`);
  assert.ok(
    contagemLimitada(RAMO),
    `${CAP.file}: o ramo 'all' não é "count(até S+1 elegíveis ativos por _can_sign_gate) <= S". Ramo lido:\n${RAMO}`,
  );
});

test('o cache de preview só ordena a busca: aparece no ORDER BY e em nenhum outro lugar do ramo', () => {
  const c = RAMO && contagemLimitada(RAMO);
  assert.ok(c, `${CAP.file}: forma do ramo 'all' não reconhecida (ver o teste anterior)`);
  assert.match(c.ordem, /preview_gate_eligibles_cache/, `${CAP.file}: a busca não começa pelos indicados do cache`);
  const fora = RAMO.replace(c.ordem, '');
  assert.doesNotMatch(fora, /preview_gate_eligibles_cache/, `${CAP.file}: o cache aparece fora do ORDER BY e pode decidir quem conta`);
});

test('o leitor recusa as formas que mudam a resposta', () => {
  const base = "WHEN (p_gate->>'threshold') = 'all' THEN (SELECT count(*) FROM ( SELECT 1 FROM (SELECT m.id FROM public.members m WHERE m.is_active " +
    'ORDER BY x DESC, m.id OFFSET 0) m ' +
    "WHERE public._can_sign_gate(m.id, p_chain_id, p_gate->>'kind') " +
    `LIMIT (${S}) + 1 ) e) <= (${S})`;
  assert.deepEqual(contagemLimitada(base), { ordem: 'x DESC, m.id' });
  assert.equal(contagemLimitada(base.replace(') + 1 ) e)', ') ) e)')), null, 'LIMIT S (sem o +1) responde "atingido" sempre');
  assert.equal(contagemLimitada(base.replace(') e) <= (', ') e) < (')), null, '< S inverte o portão vazio');
  assert.equal(contagemLimitada(base.replace('WHERE m.is_active ', 'WHERE true ')), null, 'sem is_active conta inativo');
  assert.equal(contagemLimitada(base.replace(`<= (${S})`, `<= (${S.replace("'acknowledge'", "'abstain'")})`)), null, 'as duas contagens de S precisam ser a mesma');
});
