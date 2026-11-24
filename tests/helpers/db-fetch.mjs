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
 * O que este helper NÃO faz: esconder falha real. Ele só repete o caso `PGRST003` e o HTTP 522
 * (#3192, abaixo), e devolve a última resposta se as tentativas se esgotarem: um 504 ou um 522
 * persistente continua vermelho, e qualquer outro status passa direto, sem retentativa.
 *
 * #3192, HTTP 522, medido nos edge_logs do projeto em 24/11/2026:
 *
 *   A Cloudflare devolve 522 quando não consegue ABRIR a conexão com a origem. Cada caso é um
 *   request isolado, com ~19,5 s de espera (o limite de conexão dela), em qualquer endpoint,
 *   inclusive leituras triviais, e sem relação com a carga nem com trava do banco. É crônico: 13
 *   casos em 21/11, 25 em 22/11 e 34 nas 24 h até 24/11 17:00 UTC, e três runs do `validate`
 *   ficaram vermelhos por um único 522.
 *
 *   Repetir é seguro pelo mesmo motivo do `PGRST003`: a recusa acontece ANTES de o request
 *   chegar à origem, então uma escrita repetida não executa duas vezes. Por isso só esses dois.
 *   O 520, o 521, o 523 e o 524 não entram: neles a origem pode ter recebido o request.
 *
 * O caminho cobre a suíte inteira, não só quem importa este arquivo: o `scripts/run-suite.mjs`
 * carrega `db-fetch-preload.mjs` com `--import`, que instala a mesma repetição no `fetch` global
 * para os hosts do Supabase. O `createClient` do supabase-js resolve o `fetch` global na hora de
 * cada chamada, então passa por ela sem mudar nenhum teste. Ver `instalarNoFetchGlobal`.
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
 * #3192: o orcamento conta tambem o tempo perdido em 522. Uma linha `<ms> 522` e um 522 que foi
 * repetido; uma linha so com `<ms>` e saturacao de pool, no formato que ja existia. Os dois somam
 * no mesmo orcamento, e o resumo do run (`resumoDoOrcamento`, chamado pelo run-suite) diz
 * quantas chamadas foram repetidas por 522.
 */
export const MOTIVO_522 = '522';

/**
 * O acumulador vive em ARQUIVO, e nao em memoria, por um motivo que quase me escapou: o
 * `node --test` roda cada arquivo de teste em um PROCESSO separado. Um contador de modulo
 * zeraria a cada arquivo, e os eventos de saturacao estao espalhados por dezenas deles — o
 * orcamento nunca somaria e o mecanismo pareceria funcionar sem nunca disparar.
 *
 * Formato: uma linha por evento, com os ms perdidos. Append de linha curta e atomico o
 * bastante entre processos para esta finalidade, e a leitura e uma soma.
 */
// #3192: resolvido a cada leitura, e nao na carga do modulo. Com o preload o modulo ja esta carregado
// antes de o teste rodar, e um teste que aponta DB_FETCH_BUDGET_FILE para um arquivo proprio (o #1869
// faz isso) passaria a ler e ZERAR o acumulador da corrida real.
const arquivoDoOrcamento = () => process.env.DB_FETCH_BUDGET_FILE
  || join(tmpdir(), `db-fetch-budget-${process.env.GITHUB_RUN_ID || process.env.GITHUB_RUN_NUMBER || 'local'}.log`);

/**
 * Fora do CI o arquivo persiste entre execucoes e acumularia para sempre, disparando o
 * orcamento numa corrida saudavel. Uma corrida nao dura duas horas, entao acumulador com essa
 * idade e de outra corrida: descarta.
 */
const VALIDADE_MS = 2 * 60 * 60_000;

const ZERADO = { gastoEmSaturacaoMs: 0, eventosDeSaturacao: 0, gastoEm522Ms: 0, repeticoesPor522: 0 };

function lerAcumulador() {
  try {
    if (Date.now() - statSync(arquivoDoOrcamento()).mtimeMs > VALIDADE_MS) {
      writeFileSync(arquivoDoOrcamento(), '');
      return { ...ZERADO };
    }
    const linhas = readFileSync(arquivoDoOrcamento(), 'utf8').split('\n').filter(Boolean);
    const acc = { ...ZERADO };
    for (const l of linhas) {
      const [valor, motivo] = l.trim().split(/\s+/);
      const n = Number(valor);
      if (!Number.isFinite(n)) continue;
      if (motivo === MOTIVO_522) { acc.gastoEm522Ms += n; acc.repeticoesPor522 += 1; }
      else { acc.gastoEmSaturacaoMs += n; acc.eventosDeSaturacao += 1; }
    }
    return acc;
  } catch { return { ...ZERADO }; }
}

function registrarEvento(ms, motivo) {
  const linha = `${Math.max(0, Math.round(ms))}${motivo ? ` ${motivo}` : ''}\n`;
  try { appendFileSync(arquivoDoOrcamento(), linha); } catch { /* nao derrubar o teste por causa do contador */ }
}

const registrarSaturacao = (ms) => registrarEvento(ms, null);

export function estadoDoOrcamento() {
  const a = lerAcumulador();
  const gastoTotalMs = a.gastoEmSaturacaoMs + a.gastoEm522Ms;
  return {
    ...a,
    gastoTotalMs,
    orcamentoMs: ORCAMENTO_SATURACAO_MS,
    restanteMs: Math.max(0, ORCAMENTO_SATURACAO_MS - gastoTotalMs),
    estourado: gastoTotalMs >= ORCAMENTO_SATURACAO_MS,
    arquivo: arquivoDoOrcamento(),
  };
}

/** #3192: a linha do resumo do run. Uma frase, com as duas contagens e o tempo de cada uma. */
export function resumoDoOrcamento() {
  const e = estadoDoOrcamento();
  const s = (ms) => (ms / 1000).toFixed(1);
  return `db-fetch (#1869/#3192): ${e.repeticoesPor522} chamada(s) repetida(s) por HTTP 522 `
    + `(${s(e.gastoEm522Ms)} s perdidos), ${e.eventosDeSaturacao} por saturacao de pool `
    + `(${s(e.gastoEmSaturacaoMs)} s); orcamento ${s(e.gastoTotalMs)} de ${s(e.orcamentoMs)} s.`;
}

/** Zera o acumulador. Existe para o teste do proprio mecanismo. */
export function resetarOrcamento() {
  try { writeFileSync(arquivoDoOrcamento(), ''); } catch { /* idem */ }
}

function mensagemDeEstouro() {
  const { gastoEmSaturacaoMs, eventosDeSaturacao, gastoEm522Ms, repeticoesPor522 } = lerAcumulador();
  const min = (ms) => (ms / 60_000).toFixed(1);
  return (
    `#1869: orcamento de saturacao esgotado. ${eventosDeSaturacao} chamada(s) perderam a porta do `
    + `PostgREST (PGRST003 / espera estourada) e ${repeticoesPor522} foram recusadas com HTTP 522 `
    + `(#3192), custando ${min(gastoEmSaturacaoMs + gastoEm522Ms)} min de espera `
    + `pura contra um orcamento de ${min(ORCAMENTO_SATURACAO_MS)} min. Isto NAO e defeito da PR: `
    + `e saturacao SUSTENTADA do pool de producao, que a suite divide com trafego real de usuario `
    + `(#1844). Falhando agora, nomeando a causa, em vez de deixar o job ser CANCELADO mudo no `
    + `teto de 95 min.`
  );
}

const dorme = (ms) => new Promise((r) => setTimeout(r, ms));

/** É recusa por pool cheio? */
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
 * #3192: o motivo pelo qual esta resposta pode ser repetida, ou `null`. So dois motivos existem,
 * e nos dois o request nao chegou a executar na origem: `PGRST003` (o PostgREST nao conseguiu
 * conexao do pool) e HTTP 522 (a Cloudflare nao conseguiu abrir conexao com a origem). Qualquer
 * outro status devolve `null` e passa direto ao teste.
 */
export async function motivoDeRepeticao(res) {
  if (res.status === 522) return MOTIVO_522;
  if (await ehSaturacaoDePool(res)) return 'PGRST003';
  return null;
}

/** O `fetch` de verdade, mesmo quando o global ja foi embrulhado por `instalarNoFetchGlobal`. */
const MARCA_EMBRULHO = Symbol.for('nucleo.db-fetch.embrulho');
function fetchDeBaixo() {
  const f = globalThis.fetch;
  return f?.[MARCA_EMBRULHO] ?? f;
}

/** O corpo pode ser reenviado? Um stream so se le uma vez. */
function corpoReenviavel(opcoes) {
  if (opcoes?.body && typeof opcoes.body.getReader === 'function') return false;
  return true;
}

/**
 * O laco comum. `comLimite` liga o limite de espera do #1844 e a repeticao em espera estourada,
 * que e o contrato de quem chama `dbFetch` de proposito. O embrulho global usa `comLimite: false`:
 * ele so acrescenta a repeticao das duas recusas, sem impor limite nem repetir aborto a quem nunca
 * pediu, porque um aborto pode ter acontecido DEPOIS de a escrita chegar ao banco.
 */
async function repetir(entrada, opcoes, { comLimite }) {
  const tentativas = corpoReenviavel(opcoes) ? TENTATIVAS : 1;
  let ultima;
  for (let tentativa = 1; tentativa <= tentativas; tentativa++) {
    const inicio = Date.now();
    const alvo = entrada instanceof Request ? entrada.clone() : entrada;
    try {
      const res = await fetchDeBaixo()(alvo, comLimite ? { ...opcoes, signal: AbortSignal.timeout(LIMITE_MS) } : opcoes);
      const motivo = tentativa < tentativas ? await motivoDeRepeticao(res) : null;
      if (motivo) {
        registrarEvento(Date.now() - inicio, motivo === MOTIVO_522 ? MOTIVO_522 : null);
        // #1869: nao gastar o que nao se tem. Repetir quando o orcamento restante nao cobre outra
        // espera so adia o cancelamento do job.
        if (estadoDoOrcamento().restanteMs < LIMITE_MS) return res;
        ultima = res;
        try { await res.body?.cancel(); } catch { /* resposta descartada */ }
        await dorme(ESPERA_MS * tentativa);
        continue;
      }
      return res;
    } catch (e) {
      if (!comLimite) throw e;
      // AbortError do limite de espera conta como saturação: e o mesmo sintoma, do lado do cliente.
      const abortou = e?.name === 'TimeoutError' || e?.name === 'AbortError';
      if (abortou) registrarSaturacao(Date.now() - inicio);
      if (!abortou || tentativa === tentativas) throw e;
      if (estadoDoOrcamento().restanteMs < LIMITE_MS) throw new Error(mensagemDeEstouro());
      await dorme(ESPERA_MS * tentativa);
    }
  }
  return ultima;
}

/**
 * `fetch` com limite de espera e nova tentativa apenas nas duas recusas (PGRST003 e 522).
 * Devolve a Response; o chamador segue lendo status e corpo como antes.
 */
export async function dbFetch(url, opcoes = {}) {
  // #1869: se a corrida ja gastou o orcamento, nao adianta tentar de novo: cada tentativa
  // custa ate 150 s e o job tem teto. Falha nomeando a causa.
  if (estadoDoOrcamento().estourado) throw new Error(mensagemDeEstouro());
  return repetir(url, opcoes, { comLimite: true });
}

/** Os hosts do Supabase: os das variaveis de ambiente da suite e qualquer `*.supabase.co`. */
function hostsDoSupabase() {
  const hosts = new Set();
  for (const v of [process.env.SUPABASE_URL, process.env.PUBLIC_SUPABASE_URL]) {
    try { if (v) hosts.add(new URL(v).host); } catch { /* variavel malformada: ignora */ }
  }
  return hosts;
}

function hostDe(entrada) {
  try {
    const u = typeof entrada === 'string' ? entrada : (entrada instanceof Request ? entrada.url : String(entrada));
    return new URL(u).host;
  } catch { return null; }
}

export function ehDoSupabase(entrada, hosts = hostsDoSupabase()) {
  const h = hostDe(entrada);
  return h != null && (hosts.has(h) || h.endsWith('.supabase.co'));
}

/**
 * #3192: instala a repeticao no `fetch` global, para os hosts do Supabase. Carregado por
 * `db-fetch-preload.mjs` via `--import` em todo `node --test` da suite.
 *
 * - Outro host passa direto ao `fetch` original, sem nada no meio.
 * - Sem limite de espera e sem repetir aborto: so as duas recusas (ver `repetir`).
 * - Com o orcamento estourado o embrulho NAO derruba a chamada: so deixa de repetir. Quem falha
 *   nomeando a causa continua sendo o `dbFetch` explicito.
 * - Idempotente: instalar duas vezes nao embrulha duas vezes.
 */
export function instalarNoFetchGlobal() {
  const original = globalThis.fetch;
  if (typeof original !== 'function' || original[MARCA_EMBRULHO]) return original;
  const hosts = hostsDoSupabase();
  const embrulho = async function fetchComRepeticao(entrada, opcoes) {
    if (!ehDoSupabase(entrada, hosts) || estadoDoOrcamento().estourado) return original(entrada, opcoes);
    return repetir(entrada, opcoes, { comLimite: false });
  };
  Object.defineProperty(embrulho, MARCA_EMBRULHO, { value: original });
  globalThis.fetch = embrulho;
  return embrulho;
}
