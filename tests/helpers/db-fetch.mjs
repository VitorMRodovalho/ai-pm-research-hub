/**
 * #1844 — `fetch` para testes DB-aware, com limite de espera e nova tentativa em saturação
 * de pool.
 *
 * Por que existe, medido em 17-18/08/2026:
 *
 *   O PostgREST devolve `PGRST003` ("Timed out acquiring connection from connection pool")
 *   com **HTTP 504** quando o pool está no teto. Em repouso ele mantém 6 conexões ociosas;
 *   sob carga chegou a **15 ativas**. `check_schema_invariants()` sozinho leva **2,53 s** por
 *   chamada, então cada requisição pesada segura uma conexão por segundos.
 *
 *   Duas consequências, as duas observadas:
 *
 *   1. **`fetch` sem limite transforma saturação em trava.** Um teste ficou **61 segundos**
 *      pendurado antes de devolver 504. Com centenas de testes DB-aware, algumas dezenas assim
 *      levam a corrida de 13 minutos ao teto de 95 do job, que morre como `cancelled` — sinal
 *      que se parece com intervenção humana, não com defeito.
 *   2. **Saturação de pool é TRANSITÓRIA por natureza.** Uma conexão volta em segundos. Falhar
 *      na primeira recusa reporta como defeito do código o que é fila de infraestrutura, e foi
 *      assim que três PRs sem relação nenhuma ficaram vermelhas.
 *
 * O que este helper NÃO faz: esconder falha real. Ele só repete o caso `PGRST003`, e devolve a
 * última resposta se as tentativas se esgotarem — um 504 persistente continua vermelho, e
 * qualquer outro status passa direto, sem retentativa.
 */

/**
 * Limite de espera por requisição.
 *
 * ⚠️ **Medido em 18/08/2026, 15:45 UTC, e o primeiro número que eu escolhi (20 s) estava ERRADO:**
 * três chamadas seguidas de `check_schema_invariants()` pela porta do PostgREST levaram
 * **60,9 s (PGRST003), 33,3 s (sucesso) e 49,1 s (sucesso)** — enquanto o SQL puro da mesma
 * função leva **2,53 s**. A diferença inteira é fila de pool.
 *
 * Duas consequências para este número:
 *
 *   1. Um limite abaixo de ~50 s **abortaria chamadas saudáveis**, trocando um defeito de
 *      infraestrutura por um defeito fabricado por nós.
 *   2. O PostgREST devolve `PGRST003` por conta própria em ~61 s. O limite do cliente precisa
 *      ficar ACIMA disso, senão o cliente aborta antes e a gente perde justamente o sinal que
 *      identifica a saturação — e que é o único retentável.
 */
export const LIMITE_MS = 75_000;

/** Tentativas totais (1 original + 2 repetições) e espera entre elas. */
export const TENTATIVAS = 3;
export const ESPERA_MS = 3_000;

const dorme = (ms) => new Promise((r) => setTimeout(r, ms));

/** É recusa por pool cheio? Só isso é retentável. */
export async function ehSaturacaoDePool(res) {
  if (res.status !== 504 && res.status !== 503) return false;
  try {
    const texto = await res.clone().text();
    return texto.includes('PGRST003');
  } catch {
    return false;
  }
}

/**
 * `fetch` com limite de espera e nova tentativa apenas em saturação de pool.
 * Devolve a Response — o chamador segue lendo status e corpo como antes.
 */
export async function dbFetch(url, opcoes = {}) {
  let ultima;
  for (let tentativa = 1; tentativa <= TENTATIVAS; tentativa++) {
    try {
      const res = await fetch(url, { ...opcoes, signal: AbortSignal.timeout(LIMITE_MS) });
      if (tentativa < TENTATIVAS && (await ehSaturacaoDePool(res))) {
        ultima = res;
        await dorme(ESPERA_MS * tentativa);
        continue;
      }
      return res;
    } catch (e) {
      // AbortError do limite de espera conta como saturação: e o mesmo sintoma, do lado do cliente.
      const abortou = e?.name === 'TimeoutError' || e?.name === 'AbortError';
      if (!abortou || tentativa === TENTATIVAS) throw e;
      await dorme(ESPERA_MS * tentativa);
    }
  }
  return ultima;
}
