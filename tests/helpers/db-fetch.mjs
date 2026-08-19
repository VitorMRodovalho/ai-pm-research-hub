import { appendFileSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

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

/**
 * #1869 — ORCAMENTO DE SUITE, e nao so de chamada.
 *
 * O limite acima protege UMA requisicao. Ele nao protege a CORRIDA: sob saturacao sustentada
 * cada chamada afetada custa ate ~150 s (75 s de espera x 2 tentativas), e trinta delas somam
 * mais de uma hora sobre uma suite que normalmente leva 16 min. O job bate no `timeout-minutes:
 * 95` e o runner o mata como `cancelled`.
 *
 * Um required CANCELADO e pior que um vermelho: nao nomeia nada, bloqueia o merge do mesmo jeito,
 * le como infraestrutura e some da revisao, e gasta 95 minutos para nao dizer nada. Medido em
 * 19/08/2026 sobre os 19 runs mais recentes do ci.yml: 3 cancelados a 95 min, em 3 branches
 * diferentes, com 31, 30 e 25 erros de porta do PostgREST cada. Um run saudavel da mesma janela:
 * 14 min e nenhum.
 *
 * Este orcamento troca os 95 minutos mudos por um vermelho LEGIVEL: contabiliza o tempo perdido
 * especificamente em saturacao e, ao estourar, para de tentar e falha dizendo quantas chamadas
 * perderam a porta e quanto tempo isso custou.
 *
 * O numero: um run saudavel gasta ZERO aqui, entao o orcamento nao dispara em condicao normal.
 * 25 min e o suficiente para atravessar uma saturacao pontual (que e o caso que o #1851 existe
 * para sobreviver) e curto o bastante para falhar muito antes do teto de 95 do job.
 */
export const ORCAMENTO_SATURACAO_MS = 25 * 60_000;

/**
 * O acumulador vive em ARQUIVO, e nao em memoria, por um motivo que quase me escapou: o
 * `node --test` roda cada arquivo de teste em um PROCESSO separado. Um contador de modulo
 * zeraria a cada arquivo, e os eventos de saturacao estao espalhados por dezenas deles — o
 * orcamento nunca somaria e o mecanismo pareceria funcionar sem nunca disparar.
 *
 * Formato: uma linha por evento, com os ms perdidos. Append de linha curta e atomico o
 * bastante entre processos para esta finalidade, e a leitura e uma soma.
 */
const ARQUIVO_ORCAMENTO = process.env.DB_FETCH_BUDGET_FILE
  || join(tmpdir(), `db-fetch-budget-${process.env.GITHUB_RUN_ID || process.env.GITHUB_RUN_NUMBER || 'local'}.log`);

/**
 * Fora do CI o arquivo persiste entre execucoes e acumularia para sempre, disparando o
 * orcamento numa corrida saudavel. Uma corrida nao dura duas horas, entao acumulador com essa
 * idade e de outra corrida: descarta.
 */
const VALIDADE_MS = 2 * 60 * 60_000;

function lerAcumulador() {
  try {
    if (Date.now() - statSync(ARQUIVO_ORCAMENTO).mtimeMs > VALIDADE_MS) {
      writeFileSync(ARQUIVO_ORCAMENTO, '');
      return { gastoEmSaturacaoMs: 0, eventosDeSaturacao: 0 };
    }
    const linhas = readFileSync(ARQUIVO_ORCAMENTO, 'utf8').split('\n').filter(Boolean);
    let ms = 0;
    for (const l of linhas) { const n = Number(l); if (Number.isFinite(n)) ms += n; }
    return { gastoEmSaturacaoMs: ms, eventosDeSaturacao: linhas.length };
  } catch { return { gastoEmSaturacaoMs: 0, eventosDeSaturacao: 0 }; }
}

function registrarSaturacao(ms) {
  try { appendFileSync(ARQUIVO_ORCAMENTO, `${Math.max(0, Math.round(ms))}\n`); } catch { /* nao derrubar o teste por causa do contador */ }
}

export function estadoDoOrcamento() {
  const { gastoEmSaturacaoMs, eventosDeSaturacao } = lerAcumulador();
  return {
    gastoEmSaturacaoMs,
    eventosDeSaturacao,
    orcamentoMs: ORCAMENTO_SATURACAO_MS,
    restanteMs: Math.max(0, ORCAMENTO_SATURACAO_MS - gastoEmSaturacaoMs),
    estourado: gastoEmSaturacaoMs >= ORCAMENTO_SATURACAO_MS,
    arquivo: ARQUIVO_ORCAMENTO,
  };
}

/** Zera o acumulador. Existe para o teste do proprio mecanismo. */
export function resetarOrcamento() {
  try { writeFileSync(ARQUIVO_ORCAMENTO, ''); } catch { /* idem */ }
}

function mensagemDeEstouro() {
  const { gastoEmSaturacaoMs, eventosDeSaturacao } = lerAcumulador();
  const min = (ms) => (ms / 60_000).toFixed(1);
  return (
    `#1869: orcamento de saturacao esgotado. ${eventosDeSaturacao} chamada(s) perderam a porta do `
    + `PostgREST (PGRST003 / espera estourada), custando ${min(gastoEmSaturacaoMs)} min de espera `
    + `pura contra um orcamento de ${min(ORCAMENTO_SATURACAO_MS)} min. Isto NAO e defeito da PR: `
    + `e saturacao SUSTENTADA do pool de producao, que a suite divide com trafego real de usuario `
    + `(#1844). Falhando agora, nomeando a causa, em vez de deixar o job ser CANCELADO mudo no `
    + `teto de 95 min.`
  );
}

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
  // #1869: se a corrida ja gastou o orcamento, nao adianta tentar de novo — cada tentativa
  // custa ate 150 s e o job tem teto. Falha nomeando a causa.
  if (estadoDoOrcamento().estourado) throw new Error(mensagemDeEstouro());

  let ultima;
  for (let tentativa = 1; tentativa <= TENTATIVAS; tentativa++) {
    const inicio = Date.now();
    try {
      const res = await fetch(url, { ...opcoes, signal: AbortSignal.timeout(LIMITE_MS) });
      if (tentativa < TENTATIVAS && (await ehSaturacaoDePool(res))) {
        registrarSaturacao(Date.now() - inicio);
        ultima = res;
        // #1869: nao gastar o que nao se tem. Repetir uma chamada que custa ate 75 s quando o
        // orcamento restante e menor que isso so adia o cancelamento do job.
        if (estadoDoOrcamento().restanteMs < LIMITE_MS) return res;
        await dorme(ESPERA_MS * tentativa);
        continue;
      }
      return res;
    } catch (e) {
      // AbortError do limite de espera conta como saturação: e o mesmo sintoma, do lado do cliente.
      const abortou = e?.name === 'TimeoutError' || e?.name === 'AbortError';
      if (abortou) registrarSaturacao(Date.now() - inicio);
      if (!abortou || tentativa === TENTATIVAS) throw e;
      if (estadoDoOrcamento().restanteMs < LIMITE_MS) throw new Error(mensagemDeEstouro());
      await dorme(ESPERA_MS * tentativa);
    }
  }
  return ultima;
}
