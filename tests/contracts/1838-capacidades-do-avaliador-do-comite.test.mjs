/**
 * #1838 — o avaliador do comitê deixa de ser barrado nas telas ao redor da entrevista.
 *
 * Medido em 17/08/2026: um avaliador do comitê do ciclo aberto (tem `view_pii`, não tem
 * `manage_platform`, `manage_member` nem `view_internal_analytics`) estava barrado em SEIS RPCs.
 * Duas das exigências eram incoerentes com o que a RPC faz: `update_application_contact` pedia
 * `manage_member`, que é ciclo de vida de MEMBRO e é GP-only por invariante de LGPD, para editar
 * o contato de um CANDIDATO; e `get_application_onboarding_pct` pedia `manage_platform` para
 * devolver um inteiro.
 *
 * Decisão do PM: gate por participação no comitê do ciclo somada a `view_pii`.
 *
 * O que este guard protege:
 *
 *   1. **O gate é ADITIVO.** A capacidade original continua no predicado de cada uma das seis.
 *      Trocar em vez de somar tiraria acesso de quem já tinha, e ninguém pediu isso.
 *   2. **Comitê sozinho não basta.** `view_pii` tem de estar na conjunção; sem ela, qualquer
 *      integrante do comitê passaria a ler PII de candidato.
 *   3. **A tela fala a língua do servidor (#1590).** O eixo da página é calculado do MESMO sinal
 *      que o servidor usa (`selection_committee_role_for` e `is_selection_committee_member(id,
 *      NULL)` compartilham o predicado `status='open' OR phase='evaluating'`).
 *   4. **Leitura e escrita têm recortes DIFERENTES, e é de propósito.** Ler abre para qualquer
 *      papel do comitê; escrever (`update_application_contact`, `capture_vep_baseline`) abre só
 *      para os papéis que decidem. O domínio da coluna é ('evaluator','lead','observer'), então
 *      a lista de dois exclui exatamente o observador — recorte exaustivo, não amostra que
 *      envelhece quando um papel novo aparecer.
 *   5. **Nunca exigir `lead`.** O avaliador da issue não é lead; um gate que pedisse `lead`
 *      deixaria de fora justamente a pessoa que motivou a mudança.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
// A mudança saiu em QUATRO migrations, uma por lote de RPC — os corpos são grandes e aplicar em
// lotes deixa cada um verificável por md5 antes do seguinte. O guard lê o conjunto, não um arquivo:
// pinar um nome só faria o teste passar por acidente se um lote sumisse.
const MARCA = '1838_capacidades_do_avaliador_do_comite';
const ARQUIVOS = readdirSync(MIGRATIONS_DIR).filter((f) => f.includes(MARCA) && f.endsWith('.sql'));
const SQL = ARQUIVOS.map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');
// Guard que PROIBE um padrão precisa ler só o código: o cabeçalho destas migrations explica
// "CREATE FUNCTION virou CREATE OR REPLACE", e a explicação casaria com a própria proibição.
const SQL_SEM_COMENTARIO = SQL.replace(/^\s*--.*$/gm, '');

const PAGINA_PATH = 'src/pages/admin/selection.astro';
const PAGINA = existsSync(PAGINA_PATH) ? readFileSync(PAGINA_PATH, 'utf8') : '';

/** As seis, com a capacidade que já era exigida antes desta mudança. */
const SEIS = [
  ['update_application_contact', 'manage_member'],
  ['get_application_onboarding_pct', 'manage_platform'],
  ['get_vep_divergence_report', 'view_internal_analytics'],
  ['get_vep_role_cohort_reconciliation', 'view_internal_analytics'],
  ['get_vep_baseline_history', 'view_internal_analytics'],
  ['capture_vep_baseline', 'view_internal_analytics'],
];

/** As duas que ESCREVEM. Observador não passa nestas. */
const ESCRITAS = ['update_application_contact', 'capture_vep_baseline'];
/** As quatro que só LEEM. Qualquer papel do comitê passa. */
const LEITURAS = SEIS.map(([n]) => n).filter((n) => !ESCRITAS.includes(n));

/** O bloco CREATE OR REPLACE de uma função dentro da migration. */
function bloco(nome) {
  const i = SQL.search(
    new RegExp(String.raw`CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?` + nome + String.raw`\s*\(`, 'i'),
  );
  if (i === -1) return '';
  // até o próximo CREATE OR REPLACE, ou o fim
  const resto = SQL.slice(i + 10);
  const j = resto.search(/CREATE\s+OR\s+REPLACE\s+FUNCTION/i);
  return j === -1 ? SQL.slice(i) : SQL.slice(i, i + 10 + j);
}

describe('#1838 — capacidades do avaliador do comitê', () => {
  it('as QUATRO migrations do lote existem', () => {
    assert.equal(
      ARQUIVOS.length,
      4,
      `esperava 4 migrations contendo ${MARCA}, achei ${ARQUIVOS.length}: ${ARQUIVOS.join(', ')}`,
    );
  });

  it('as SEIS RPCs são redefinidas, e com OR REPLACE (que preserva as ACLs)', () => {
    const faltando = SEIS.map(([nome]) => nome).filter((nome) => !bloco(nome));
    assert.deepEqual(faltando, [], `RPC(s) ausentes da migration: ${faltando.join(', ')}`);
    assert.equal(
      (SQL.match(/CREATE OR REPLACE FUNCTION/g) || []).length,
      SEIS.length,
      'a migration precisa redefinir exatamente as seis',
    );
    assert.doesNotMatch(
      SQL_SEM_COMENTARIO,
      /CREATE\s+FUNCTION\s+(?!OR)/i,
      'CREATE FUNCTION sem OR REPLACE derruba as ACLs da função',
    );
  });

  it('cada gate é ADITIVO: a capacidade original continua no predicado', () => {
    const perdidas = SEIS.filter(([nome, cap]) => !bloco(nome).includes(`'${cap}'`))
      .map(([nome, cap]) => `${nome} perdeu ${cap}`);
    assert.deepEqual(
      perdidas,
      [],
      'trocar a capacidade em vez de somar tiraria acesso de quem já tinha:\n  ' + perdidas.join('\n  '),
    );
  });

  it('cada gate exige comitê E view_pii juntos, nunca comitê sozinho', () => {
    const erradas = [];
    for (const [nome] of SEIS) {
      const b = bloco(nome);
      // Três formas legítimas, uma por escopo: sem ciclo (NULL), por ciclo da candidatura, e a
      // com filtro de papel para as escritas. Exigir UMA delas acusaria as outras duas.
      const temComite = /is_selection_committee_member/.test(b)
        || /selection_committee_role_for/.test(b)
        || /JOIN public\.selection_committee sc/.test(b);
      if (!temComite) { erradas.push(`${nome}: sem checagem de comitê`); continue; }
      if (!/'view_pii'/.test(b)) erradas.push(`${nome}: comitê sem view_pii — abriria PII de candidato`);
    }
    assert.deepEqual(erradas, [], erradas.join('\n  '));
  });

  it('o escopo de candidatura usa o ciclo DAQUELA candidatura, e falha fechado', () => {
    for (const nome of ['update_application_contact', 'get_application_onboarding_pct']) {
      const b = bloco(nome);
      // O que importa é o EXISTS amarrado em p_application_id: ele resolve o ciclo DAQUELA
      // candidatura e falha fechado quando ela não existe. A forma de dentro difere entre a
      // leitura (qualquer papel) e a escrita (papel restrito), e as duas são válidas aqui.
      assert.match(
        b,
        /EXISTS \(SELECT 1 FROM public\.selection_applications sa[\s\S]*?sa\.id = p_application_id/,
        `${nome} precisa amarrar o comitê ao ciclo DA candidatura; sem isso cairia no ramo do ` +
          'ciclo aberto e uma candidatura inexistente passaria pelo ramo errado',
      );
      assert.match(
        b,
        /sa\.cycle_id/,
        `${nome} precisa usar o cycle_id da candidatura, não um ciclo implícito`,
      );
    }
  });

  it('as LEITURAS de VEP usam o predicado do ciclo aberto, que é o que a página publica', () => {
    for (const nome of ['get_vep_divergence_report', 'get_vep_role_cohort_reconciliation',
                        'get_vep_baseline_history']) {
      assert.match(
        bloco(nome),
        /is_selection_committee_member\(v_caller_id, NULL\)/,
        `${nome} não recebe ciclo; NULL é o predicado open/evaluating, igual ao da página`,
      );
    }
  });

  it('as duas ESCRITAS restringem o papel; observador não escreve', () => {
    for (const nome of ESCRITAS) {
      const b = bloco(nome);
      assert.match(
        b,
        /'evaluator', 'lead'/,
        `${nome} ESCREVE e precisa restringir o papel do comitê aos que decidem`,
      );
      assert.doesNotMatch(
        b,
        /is_selection_committee_member\(v_caller_id, NULL\)/,
        `${nome} ESCREVE: o predicado role-agnostic deixaria observador gravar`,
      );
    }
  });

  it('as LEITURAS continuam abertas a qualquer papel do comitê', () => {
    for (const nome of LEITURAS) {
      assert.doesNotMatch(
        bloco(nome),
        /'evaluator', 'lead'/,
        `${nome} só LÊ; restringir papel aqui fecharia a tela para o observador, ` +
          'e observar o processo é exatamente o papel dele',
      );
    }
  });

  it('a mensagem de recusa da ESCRITA não promete o que a leitura promete', () => {
    // Um observador que leia "committee membership with view_pii" conclui que tem o que precisa,
    // e tem — menos o papel. A mensagem da escrita precisa nomear o papel.
    assert.match(
      bloco('capture_vep_baseline'),
      /RAISE EXCEPTION '[^']*evaluator\/lead[^']*'/,
      'a recusa da escrita tem de dizer que o recorte é de PAPEL',
    );
  });

  it('a página ganhou o eixo, e ele espelha o servidor', () => {
    assert.match(
      PAGINA,
      /body:not\(\[data-sel-can-operate-selection="1"\]\)\s*\[data-sel-requires~="operate_selection"\]/,
      'sem a regra de CSS o eixo não esconde nada e o fail-closed some',
    );
    assert.match(
      PAGINA,
      /set\('data-sel-can-operate-selection', canManageMember \|\| \(isCommitteeWriter && canViewPii\)\)/,
      'o eixo da página tem de ser a MESMA disjunção do servidor',
    );
    assert.match(
      PAGINA,
      /const isCommitteeWriter = \['evaluator', 'lead'\]\.includes\(m\?\.selection_committee_role \?\? ''\)/,
      'o eixo gateia ESCRITA: papel que decide, e nunca só `lead` (o avaliador da issue não é lead)',
    );
    assert.doesNotMatch(
      PAGINA,
      /data-sel-can-operate-selection'[^)]*=== 'lead'/,
      'exigir lead deixaria de fora justamente a pessoa que motivou a mudança',
    );
  });

  it('o botão de contato passou a declarar o eixo novo', () => {
    const linha = PAGINA.split('\n').find((l) => l.includes('id="save-contact-btn"')) ?? '';
    assert.ok(linha, 'âncora save-contact-btn ausente');
    assert.match(linha, /data-sel-requires="[^"]*operate_selection/);
    assert.doesNotMatch(
      linha,
      /data-sel-requires="[^"]*manage_member/,
      'manter manage_member esconderia o botão de quem o servidor agora autoriza',
    );
  });
});
