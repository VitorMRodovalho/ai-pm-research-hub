// tests/contracts/2423-rotulo-de-servico-nao-diz-membro.test.mjs
// Registrar em "test:structural" + "test:contracts" (#1109). So le arquivo; nao toca o banco.
/**
 * Data de VOLUNTARIADO nao se rotula como FILIACAO.
 *
 * O CASO (#2423): `get_application_pmi_profile` devolve `member_since`/`member_until` calculados de
 * `service_first_start_date`/`service_latest_end_date` — datas de voluntariado. A tela rotulava
 * isso como "Membro desde / Ate", e o tooltip do selo dizia, literalmente,
 * `Membro PMI ativo (service_latest_end_date >= hoje)`.
 *
 * Medido em 22/09/2026 sobre 185 candidaturas: **32** apareciam como ex-membro ou desconhecido
 * tendo filiacao PMI vigente — e a filiacao real estava na MESMA linha, em `pmi_memberships`.
 *
 * Esta fatia e so de TELA. A RPC continua derivando errado ate a fatia 1 da #2423, que e DDL e
 * espera a fila drenar. Entao o objetivo aqui nao e "ficar certo": e **parar de afirmar** o que
 * nao foi medido, e por o fato na tela ao lado.
 *
 * ⚠️ A ASSERCAO AMARRA CONDICAO A RESULTADO, DENTRO DO BLOCO QUE RENDERIZA.
 * `PAGE.includes('Servico PMI')` ficaria verde com o rotulo de volta em "Membro desde", porque a
 * string sobrevive noutro lugar. Entao o guard RECORTA a linha que consome `identity.member_since`
 * e afirma sobre a chave que ELA usa.
 *
 * Cross-ref: #2423, #2134, `src/pages/admin/selection.astro`.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => ({
  lang: l, corpo: readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8'),
}));

/**
 * Recorta a linha que RENDERIZA um campo — o bloco que decide o rotulo daquele valor.
 *
 * ⚠️ Recebe `page` por PARAMETRO. A primeira versao lia a constante do modulo, e por isso a
 * mutacao nao chegava ao avaliador: o teste de mutacao passava o corpo adulterado e a funcao
 * julgava o original, devolvendo lista vazia. Isso e exatamente "mutacao que nao passa pelo
 * avaliador e parafrase" — e foi o proprio teste de mutacao que achou, nao a leitura.
 */
function linhaQueRenderiza(page, campo) {
  return page.split('\n').filter((l) => l.includes(campo) && l.includes('T.modal.'));
}

export function violacoes({ page, dicts }) {
  const v = [];

  // 1. Quem exibe um campo de SERVICO nao pode rotula-lo com uma chave que diz "Member".
  for (const campo of ['identity.member_since', 'identity.member_until', 'pmiC.member_since', 'pmiC.member_until']) {
    const linhas = linhaQueRenderiza(page, campo);
    if (!linhas.length) { v.push(`nada renderiza ${campo}: o guard ficou sem objeto (#2423)`); continue; }
    for (const l of linhas) {
      const chave = (l.match(/T\.modal\.(\w+)/) || [])[1] || '(sem chave)';
      if (!/Service/i.test(chave)) {
        v.push(`${campo} e data de VOLUNTARIADO e esta rotulado por "${chave}", que nao diz servico (#2423)`);
      }
    }
  }

  // 2. Nenhum tooltip pode afirmar data de servico como criterio de filiacao.
  for (const m of page.matchAll(/title="([^"]*service_latest_end_date[^"]*)"/g)) {
    const t = m[1];
    if (!/PROVISORIO|voluntariado|NAO significa/i.test(t)) {
      v.push(`tooltip afirma servico como filiacao sem ressalva: "${t.slice(0, 80)}" (#2423)`);
    }
  }
  if (/title="Membro PMI (ativo|passado) \(/.test(page)) {
    v.push('o tooltip voltou a afirmar "Membro PMI ativo/passado" a partir de servico (#2423)');
  }

  // 3. O fato disponivel no payload nao pode ser descartado no render.
  if (!/m\.expiryDate/.test(page)) {
    v.push('o render de capitulos descarta m.expiryDate — a filiacao real esta no payload e some na tela (#2423)');
  }

  // 4. Paridade i18n da chave nova, nos TRES dicionarios.
  for (const { lang, corpo } of dicts) {
    if (!corpo.includes('admin.selection.modal.pmiProfileMembershipUntil')) {
      v.push(`${lang}: falta a chave pmiProfileMembershipUntil (regra das 3 traducoes)`);
    }
    if (/admin\.selection\.modal\.(pmiProfileMemberSince|pmiProfileMemberUntil|phaseBMemberSince|phaseBMemberUntil)/.test(corpo)) {
      v.push(`${lang}: chave com nome "Member" voltou para um rotulo de servico (#2423)`);
    }
  }
  return v;
}

test('#2423 — a tela nao chama de filiacao o que e voluntariado', () => {
  // Controle positivo: a pagina precisa estar sendo lida de verdade.
  assert.ok(PAGE.length > 50_000, `controle positivo: selection.astro veio com ${PAGE.length} bytes`);
  assert.equal(DICTS.length, 3, 'os 3 dicionarios tem de ser lidos');
  assert.deepEqual(violacoes({ page: PAGE, dicts: DICTS }), []);
});

test('#2423 mutacao — o detector reprova cada defeito, pela MESMA funcao', () => {
  const dictsOk = DICTS.map((d) => ({ ...d }));

  // Mutacao 1 — o rotulo volta a dizer "Membro desde" para um campo de servico.
  const p1 = PAGE.replace(/T\.modal\.pmiProfileServiceSince/g, 'T.modal.pmiProfileMemberSince');
  assert.notEqual(p1, PAGE, 'a mutacao 1 precisa ter MUDADO o corpo');
  assert.match(violacoes({ page: p1, dicts: dictsOk }).join(' | '), /nao diz servico/,
    'mutacao 1: rotulo de membro sobre campo de servico tem de reprovar');

  // Mutacao 2 — o tooltip volta a afirmar filiacao a partir de servico.
  const p2 = PAGE.replace(/title="PROVISORIO \(#2423\)[^"]*service_latest_end_date[^"]*"/,
                          'title="Membro PMI ativo (service_latest_end_date >= hoje)"');
  assert.notEqual(p2, PAGE, 'a mutacao 2 precisa ter MUDADO o corpo');
  const v2 = violacoes({ page: p2, dicts: dictsOk }).join(' | ');
  assert.match(v2, /tooltip afirma servico como filiacao|voltou a afirmar/,
    'mutacao 2: o tooltip sem ressalva tem de reprovar');

  // Mutacao 3 — o fato volta a ser descartado no render.
  const p3 = PAGE.replace(/m\.expiryDate/g, 'm.nada');
  assert.match(violacoes({ page: p3, dicts: dictsOk }).join(' | '), /descarta m\.expiryDate/,
    'mutacao 3: descartar o vencimento no render tem de reprovar');

  // Mutacao 4 — um dicionario perde a chave nova (a regra das 3 traducoes).
  const d4 = DICTS.map((d, i) => i === 1 ? { ...d, corpo: d.corpo.replace(/admin\.selection\.modal\.pmiProfileMembershipUntil/g, 'x') } : d);
  assert.match(violacoes({ page: PAGE, dicts: d4 }).join(' | '), /falta a chave pmiProfileMembershipUntil/,
    'mutacao 4: paridade i18n quebrada tem de reprovar');

  // Controle sem mutacao, no fim: o estado real continua limpo.
  assert.deepEqual(violacoes({ page: PAGE, dicts: DICTS }), [], 'controle final sem mutacao');
});
