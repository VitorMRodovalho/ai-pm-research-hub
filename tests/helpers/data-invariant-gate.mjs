// tests/helpers/data-invariant-gate.mjs
//
// A2 (auditoria de CI, 21/08/2026) — separa INVARIANTE DE DADO de invariante de CÓDIGO.
//
// O PROBLEMA que isto resolve, medido em 21/08. Um evento legítimo de PRODUÇÃO (aplicar DDL no
// banco compartilhado; uma pessoa chamando uma RPC pelo `service_role`) reprovava o check
// **required** de TODA PR aberta, inclusive PR que só mexe em markdown. Em 21/08 isso congelou a
// fila por 5h22m54s, e a PR que pagou o preço mexia num arquivo de teste sem relação nenhuma com
// a causa.
//
// A assimetria que justifica a separação: um invariante de CÓDIGO é função do diff, então o autor
// da PR pode consertá-lo. Um invariante de DADO é função do estado do banco, que o autor não
// controla e muitas vezes nem pode ver. Um portão required que o autor não consegue acionar não é
// portão, é pedágio — e a resposta racional a ele é o bypass, que é pior.
//
// ⚠️ O QUE ISTO NÃO FAZ: não apaga o sinal. Os mesmos testes rodam no `invariants-check`, que já
// é diário por cron, já roda em modo estrito (`INVARIANT_STRICT`) e já NÃO é required. Lá eles
// podem dizer a verdade sem congelar a fila de ninguém. Destravar o portão nunca pode apagar o
// sinal — é a mesma regra que o #1850 já aplica ao `INVARIANT_STRICT`.
//
// ⚠️ E NÃO vale para invariante ESTÁTICO. A Camada A do #1636 (o guard de CLASSE que impede um
// teste NOVO de mirar produção) continua no portão required, porque ela é função do diff: quem
// escreve o teste é quem pode consertá-la. Só a Camada B, que lê linhas de produção, sai.

/** Ligado só onde o job pode dizer a verdade sem congelar a fila (invariants-check.yml). */
export const DATA_INVARIANT_GATE = process.env.DATA_INVARIANT_GATE === '1';

const FORA = 'invariante de DADO fora do portao required (A2): roda no `invariants-check` '
  + '(diario por cron, modo estrito, nao-required). Para rodar aqui: DATA_INVARIANT_GATE=1';

/**
 * Valor de `skip` para um teste de invariante de DADO.
 *
 * Preserva a razão da credencial: sem `SUPABASE_URL`/`SERVICE_ROLE_KEY` o motivo continua sendo
 * "faltou credencial", não "está fora do portão". Confundir os dois esconderia uma suíte que
 * pula em silêncio por falta de `.env`, que é o modo de falha do `skipped 744`.
 */
export function skipDataInvariant(canRun, skipMsg) {
  if (!canRun) return skipMsg;
  return DATA_INVARIANT_GATE ? false : FORA;
}
