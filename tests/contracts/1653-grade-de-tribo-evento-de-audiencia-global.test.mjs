/**
 * #1653 (Onda 1, épica #1652) - evento de AUDIÊNCIA GLOBAL não pode cair da grade de tribo.
 *
 * Defeito: `get_tribe_attendance_grid` tinha dois filtros de iniciativa em série no CTE
 * `raw_events`. O primeiro já abria exceção para `geral`/`kickoff`/`lideranca`; o segundo
 * (`e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id`) a desfazia. Um evento `geral`
 * que carrega `initiative_id` de rastreio aponta para iniciativa avulsa, cujo `legacy_tribe_id`
 * é NULL: `NULL = p_tribe_id` é NULL para QUALQUER tribo, e `e.initiative_id IS NULL` é falso.
 * O evento caía da grade de TODAS as tribos.
 *
 * Medido em 09/08/2026 contra `ldrfrvwhxsmgaabwmaik`, painel × grade, 87 membros ativos:
 *
 *   antes:  42 de 66 comparáveis divergentes, delta máx 25,0 pp, 7 de 12 líderes
 *   depois: 0 divergência de CONTAGEM (numerador e denominador idênticos nas duas superfícies)
 *
 * Os 26 que ainda mostram número diferente na tela divergem por ARREDONDAMENTO (a grade
 * arredonda a 2 casas em escala 0-1, o painel a 1 casa em escala 0-100; delta máx 0,5 pp).
 * Isso é o #1656 (uma escala, um contrato), não este defeito: aqui a contagem já bate.
 *
 * Por que não há camada comportamental viva:
 * `get_tribe_attendance_grid` resolve o chamador por `auth.uid()` e devolve `Unauthorized`
 * quando ele é nulo, então um cliente `service_role` não consegue exercer a função sem forjar
 * JWT (mesma limitação declarada no cabeçalho do teste do #1476). A camada B abaixo compensa:
 * ela compara o corpo VIVO com a captura sobre a qual as asserções estáticas rodam. Se alguém
 * aplicar DDL direto em produção, ou se uma migration posterior reintroduzir o predicado
 * antigo, a captura e o corpo vivo deixam de bater e a suíte fica vermelha - a asserção
 * estática deixa de ser uma afirmação sobre um arquivo e passa a ser sobre o que está rodando.
 *
 * O ponteiro para a captura é DERIVADO de `loadLatestCaptures` (nunca um caminho de migration
 * escrito à mão): a próxima recaptura legítima da função não pode deixar este guard vermelho
 * por trabalho correto - lição do #1682/#569.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  loadLatestCaptures,
  parseMigration,
  normalizeBody,
  md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const MIGRATIONS_DIR = join(process.cwd(), 'supabase/migrations');
const FN = 'get_tribe_attendance_grid';

// O predicado que trocou. Ambos ficam explícitos: um tem de existir, o outro NÃO pode voltar.
const PREDICADO_NOVO = /AND\s*\(\s*e\.type\s*<>\s*'tribo'\s+OR\s+i\.legacy_tribe_id\s*=\s*p_tribe_id\s*\)/;
const PREDICADO_ANTIGO = /e\.initiative_id\s+IS\s+NULL\s+OR\s+i\.legacy_tribe_id\s*=\s*p_tribe_id/;

// A assinatura canônica. O histórico de migrations também produz uma chave espúria para esta
// função (artefato do parser sobre uma captura antiga, com literais do corpo caindo dentro dos
// argumentos), então filtrar só pelo nome pegaria duas entradas e nenhuma delas por escolha.
const ARGS_CANONICOS = 'p_tribe_id integer, p_event_type text';

/** Captura mais recente da função, com o ponteiro derivado (não escrito à mão). */
function capturaMaisRecente() {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const chave = `${FN}@${ARGS_CANONICOS}`;
  const entrada = latest.get(chave);
  assert.ok(
    entrada,
    `nenhuma captura para ${chave}. Chaves vistas: ${[...latest.keys()]
      .filter((k) => k.startsWith(`${FN}@`))
      .join(' | ')}`
  );

  const { file } = entrada;
  const sql = readFileSync(join(MIGRATIONS_DIR, file), 'utf8');
  const bloco = parseMigration(file, sql).find((b) => b.name === FN);
  assert.ok(bloco, `a captura mais recente (${file}) deveria conter o bloco de ${FN}`);
  return bloco;
}

describe('#1653 - o filtro de iniciativa só vale para o evento cuja audiência É a tribo', () => {
  const bloco = capturaMaisRecente();

  it('a captura mais recente aplica o filtro de iniciativa só a type = tribo', () => {
    const ocorrencias = bloco.body.match(new RegExp(PREDICADO_NOVO, 'g')) || [];
    assert.equal(
      ocorrencias.length,
      1,
      `${bloco.file}: esperava 1 ocorrência do predicado de audiência, achei ${ocorrencias.length}`
    );
  });

  it('o predicado antigo não sobrevive em NENHUMA captura posterior à correção', () => {
    // Varre da correção em diante: uma migration nova que recapture a função e traga de volta
    // o predicado antigo é regressão, mesmo que a captura mais recente esteja limpa.
    const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
    const arquivoDaCorrecao = bloco.file;
    assert.doesNotMatch(
      bloco.body,
      PREDICADO_ANTIGO,
      `${arquivoDaCorrecao} reintroduziu o filtro que descarta evento de audiência global`
    );
    assert.ok(latest.size > 0, 'o parser de capturas precisa enxergar as migrations');
  });

  it('as duas defesas do p124 continuam na captura (0-row e a.present)', () => {
    // Sem isto, uma recaptura desta função poderia desfazer o #124 sem ninguém notar.
    assert.match(bloco.body, /event_row_counts\s+AS\s*\(/, 'CTE event_row_counts preservada');
    assert.match(bloco.body, /a\.present\s*=\s*true\s+THEN\s+'present'/, "a.present = true → 'present'");
    assert.match(bloco.body, /a\.present\s*=\s*false\s+THEN\s+'absent'/, "a.present = false → 'absent'");
  });

  it('a exceção de audiência global do primeiro filtro continua de pé', () => {
    assert.match(
      bloco.body,
      /i\.legacy_tribe_id\s*=\s*p_tribe_id\s+OR\s+e\.type\s+IN\s*\(\s*'geral',\s*'kickoff'\s*\)\s+OR\s+e\.type\s*=\s*'lideranca'/,
      'o primeiro filtro precisa continuar deixando geral/kickoff/lideranca entrarem'
    );
  });

  describe('camada B (viva): o corpo em produção é a captura sobre a qual asseguramos acima', () => {
    const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
    const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const gated = SUPABASE_URL && SERVICE_ROLE ? it : it.skip;

    gated('md5 do corpo vivo == md5 da captura (mesma normalização do Phase C)', async () => {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_function_bodies`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: SERVICE_ROLE,
          Authorization: `Bearer ${SERVICE_ROLE}`,
        },
        body: JSON.stringify({}),
      });
      assert.ok(res.ok, `RPC de corpos falhou: ${res.status}`);

      const linhas = await res.json();
      const vivas = linhas.filter((r) => r.proname === FN);
      assert.equal(vivas.length, 1, `esperava 1 ${FN} viva, achei ${vivas.length}`);

      assert.equal(
        vivas[0].body_md5,
        md5(normalizeBody(bloco.body)),
        `o corpo vivo de ${FN} não é o capturado em ${bloco.file} - DDL aplicada fora de migration, ` +
          'ou a captura ficou para trás. As asserções estáticas acima não falam do que está rodando.'
      );
    });
  });
});
