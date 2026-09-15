/**
 * Classificador da saida do `astro dev` levantado por um harness de teste.
 *
 * Existe por causa da #2279. Em 14/09 o `browser_guards` reprovou assim:
 *
 *   1) `[vite] Uncaught exception: workerd ... Unable to resolve [BaseLayout.astro?...index=0...]`
 *   2) trinta segundos de silencio
 *   3) `locator.waitFor: Timeout 30000ms exceeded` esperando `#boardgov-denied`
 *   4) a retentativa: `Server did not start within 45000ms`
 *
 * Nenhuma das duas mensagens que o passo ENTREGA nomeia a causa. Medido no log daquele run: a
 * ultima requisicao servida foi as 16:10:07, a excecao as 16:10:08, e depois dela o dev server
 * NAO serviu mais nada. A excecao e FATAL, e o marcador `*-denied` e vitima, nao mecanismo.
 * Os dois runs verdes do mesmo dia tem ZERO ocorrencias dela — o controle que separa as duas
 * leituras. A hipotese anterior, de que a FREQUENCIA do erro acompanharia o desfecho, nao se
 * sustenta: este vermelho teve uma unica ocorrencia, a mesma contagem atribuida a um run verde.
 *
 * E a retentativa nao tinha como passar. O `astro dev` e SINGLETON: com o servidor da tentativa 1
 * ainda vivo (PID 2544, porta 42369), a tentativa 2 imprimiu "Another astro dev server is already
 * running" e saiu, enquanto o harness esperava 45s por uma porta NOVA onde nunca haveria nada.
 *
 * Este modulo so CLASSIFICA linhas. Quem age e o harness.
 */

/** O `astro dev` recusou subir porque ja existe outro servidor (singleton). */
export const SINGLETON_BLOCKED = 'singleton-blocked';
/** O runtime do dev server levantou excecao nao capturada: dali em diante ele nao serve mais. */
export const FATAL_EXCEPTION = 'fatal-exception';

// A linha vem com codigos ANSI de cor do vite/astro; sem tirar, nenhum padrao casa.
const ESC = String.fromCharCode(27);
const ANSI = new RegExp(`${ESC}\\[[0-9;]*m`, 'g');
const semAnsi = (linha) => String(linha).replace(ANSI, '');

/**
 * @param {string} linha uma linha de stdout/stderr do `astro dev`
 * @returns {{kind: string, detail: string} | null}
 */
export function classifyDevServerLine(linha) {
  const texto = semAnsi(linha);

  // DUAS variantes reais, medidas no mesmo dia, e um padrão que conhecesse só uma ficaria cego
  // na outra (foi o que aconteceu: a primeira versão deste arquivo só casava a do CI, e ao
  // exercer o harness nesta máquina o fast-fail não disparou — 45s de espera de novo).
  //   CI:    `Another astro dev server is already running.`
  //   local: `{"message":"Dev server already running at http://127.0.0.1:4488 (pid 43476)...`
  // O núcleo comum é "dev server [is] already running"; o `is` é opcional entre as duas.
  if (/dev server (?:is )?already running/i.test(texto)) {
    return { kind: SINGLETON_BLOCKED, detail: texto.trim().slice(0, 400) };
  }

  // `Uncaught exception` sozinho basta: e sempre do runtime, e sempre mata o servidor. Casar
  // tambem por "Unable to resolve" deixaria de fora qualquer OUTRA excecao fatal — e um gate que
  // so conhece o defeito de ontem fica verde no de amanha.
  if (/Uncaught exception/i.test(texto)) {
    return { kind: FATAL_EXCEPTION, detail: texto.trim().slice(0, 400) };
  }

  return null;
}

/**
 * Observador da saida do dev server, com JANELA.
 *
 * Existe por causa da #2308, e a diferenca para a #2279 e o que o controle de 15/09 mostrou.
 * No `browser_guards` a excecao e FATAL: depois dela o servidor nao serve mais nada, entao basta
 * te-la visto. No `validate`/smoke ela NAO e fatal — medido no job 104185959684 (main `ecb36a59`),
 * onde ela apareceu 17 vezes e as 28 rotas de `assertOk` responderam 2xx do comeco ao fim.
 *
 * ⚠️ E PRESENCA NO RUN NAO DISCRIMINA. Controle medido em 15/09, cinco runs VERDES do `validate`:
 *
 *   | run          | desfecho | excecoes | dentro de janela de assertContains |
 *   |--------------|----------|---------:|-----------------------------------:|
 *   | 34907019986  | failure  |       17 |                    >=1 (a que caiu) |
 *   | 34983188642  | success  |        2 |                                   0 |
 *   | 34979378916  | success  |        0 |                                   0 |
 *   | 34925585161  | success  |        0 |                                   0 |
 *   | 34989938199  | success  |        0 |                                   0 |
 *   | 34982813861  | success  |        0 |                                   0 |
 *
 * O run VERDE 34983188642 teve DUAS excecoes e passou: as duas cairam dentro de requisicoes de
 * `assertOk`, que so olham o status. Um classificador que dissesse "houve excecao no run, logo e
 * infraestrutura" teria acusado esse verde. E a mesma mordida que a #2279 ja tinha levado com
 * FREQUENCIA ("um vermelho com UMA ocorrencia tem a mesma contagem atribuida a um verde").
 *
 * Por isso a unidade de atribuicao e a JANELA DA PROPRIA REQUISICAO: a excecao precisa ter sido
 * emitida entre o envio do pedido e a chegada da resposta que se vai inspecionar.
 */
export function createDevServerWatch(agora = () => Date.now()) {
  const eventos = [];
  let linhasLidas = 0;

  return {
    /** Alimenta uma linha de stdout/stderr do dev server. Devolve a classificacao, se houver. */
    observe(linha) {
      linhasLidas += 1;
      const c = classifyDevServerLine(linha);
      if (c) eventos.push({ ...c, at: agora() });
      return c;
    },
    /** Quantas linhas chegaram. ZERO aqui e `unreachable`, nao `ok`: nao se mediu. */
    get linhasLidas() {
      return linhasLidas;
    },
    get totalNoRun() {
      return eventos.length;
    },
    /** Os eventos emitidos DENTRO da janela [inicio, fim] de uma requisicao. */
    naJanela(inicio, fim) {
      return eventos.filter((e) => e.at >= inicio && e.at <= fim);
    },
    /** O primeiro evento de um tipo, se houve. Usado pelo fast-fail de boot. */
    primeiro(kind) {
      return eventos.find((e) => e.kind === kind) || null;
    },
    get ultimoFatal() {
      return [...eventos].reverse().find((e) => e.kind === FATAL_EXCEPTION) || null;
    },
  };
}

/**
 * Enriquece uma falha de CONTEUDO (o corpo nao trouxe o marcador) com o que foi medido.
 *
 * Tres saidas, e as tres sao afirmacoes diferentes:
 *
 *   - nao consegui LER a saida do dev server  -> `unreachable`. A ausencia de excecao aqui nao e
 *     evidencia de nada, e dizer "sem excecao" seria transformar nao-medido em medido-zero.
 *   - excecao DENTRO da janela desta requisicao -> a pagina veio quebrada; a rota e vitima.
 *   - janela limpa -> o marcador esta ausente da PAGINA. Isto e um achado, nao um silencio, e
 *     por isso ele e dito com o numero que o sustenta.
 */
export function explainContentFailure(erro, estado = {}) {
  const { naJanela = [], totalNoRun = 0, linhasLidas = 0, amostras = 1 } = estado;
  const original = erro?.message || String(erro);

  let nota;
  if (linhasLidas === 0) {
    nota =
      '  NAO MEDIDO: nenhuma linha da saida do dev server chegou ate aqui, entao nao da para\n' +
      '  dizer se houve excecao de resolucao. Isto e `unreachable`, nao "nao houve" (#2308).';
  } else if (naJanela.length > 0) {
    nota =
      `  CAUSA MEDIDA: o dev server levantou ${naJanela.length} excecao(oes) DENTRO da janela desta\n` +
      `  requisicao, entao o corpo inspecionado nao e a pagina real. A rota e VITIMA, nao mecanismo.\n` +
      `  Ele levantou: ${naJanela[0].detail}\n` +
      `  (${totalNoRun} no run inteiro, ${linhasLidas} linhas lidas, ${amostras} amostra(s) da rota.)\n` +
      '  Nao conserte a rota que o nome da mensagem: em 15/09 ela variou entre /admin/selection e\n' +
      '  /admin/sustainability, e a causa era a mesma resolucao do BaseLayout (#2308).';
  } else {
    nota =
      `  SEM CAUSA DE INFRAESTRUTURA: ZERO excecoes na janela desta requisicao ` +
      `(${totalNoRun} no run\n  inteiro, ${linhasLidas} linhas lidas, ${amostras} amostra(s)). ` +
      'O marcador esta ausente da PAGINA.\n  Trate como regressao de conteudo, nao como flake (#2308).';
  }

  const novo = new Error(`${original}\n\n${nota}`);
  novo.stack = erro?.stack || novo.stack;
  return novo;
}

/**
 * A assercao de CONTEUDO com re-amostragem, isolada aqui para poder ser PROVADA POR MUTACAO.
 *
 * Se ela vivesse dentro de `scripts/smoke-routes.mjs` nao daria para exercita-la: aquele modulo
 * chama `run()` no topo, entao importa-lo sobe um dev server. Aqui ela recebe `pedir` por injecao,
 * e o guard da #2308 injeta os dois defeitos que importam:
 *
 *   - marcador GENUINAMENTE ausente  -> tem de reprovar depois de esgotar as amostras (se isto
 *     passasse, a re-amostragem teria afrouxado uma assercao de SEGURANCA, que e o que o `*-denied`
 *     afirma: que a rota admin nao vaza conteudo para quem nao tem autoridade).
 *   - marcador que aparece na 2a amostra -> tem de passar E ANUNCIAR, com token estavel.
 *
 * @param {object} o
 * @param {() => Promise<{res: {ok: boolean, status: number, text: () => Promise<string>}, inicio: number, fim: number}>} o.pedir
 */
export async function assertContentWithResamples({
  path,
  fragment,
  pedir,
  watch,
  tentativas = 3,
  esperar = async () => {},
  log = () => {},
}) {
  let ultimaJanela = [];

  for (let n = 1; n <= tentativas; n += 1) {
    if (n > 1) await esperar();
    const { res, inicio, fim } = await pedir();
    if (!res.ok) {
      throw new Error(`Expected ${path} to return 2xx for content check, got ${res.status}`);
    }
    const body = await res.text();
    if (body.includes(fragment)) {
      if (n > 1) {
        // Token ESTAVEL de proposito: um verde que so aconteceu na segunda amostra tem de ser
        // CONTAVEL depois. Sem isto a intermitencia sai do registro e a #2308 volta a ser
        // descoberta do zero — que e exatamente o que aconteceu 78 vezes com o alerta do monitor.
        log(
          `[smoke][#2308] REAMOSTRAGEM-SALVOU ${path} — o marcador "${fragment}" so apareceu na ` +
          `amostra ${n}/${tentativas}. O servidor esta vivo e a pagina oscila: este passo passou ` +
          'APESAR da #2308. Conte esta linha antes de declarar a #2308 resolvida.',
        );
      }
      return;
    }
    ultimaJanela = watch.naJanela(inicio, fim);
    log(
      `[smoke][#2308] amostra ${n}/${tentativas} de ${path} veio sem "${fragment}" ` +
      `(${ultimaJanela.length} excecao(oes) do dev server na janela desta requisicao)`,
    );
  }

  throw explainContentFailure(new Error(`Expected ${path} to contain "${fragment}"`), {
    naJanela: ultimaJanela,
    totalNoRun: watch.totalNoRun,
    linhasLidas: watch.linhasLidas,
    amostras: tentativas,
  });
}

/**
 * Enriquece um erro do harness com a causa REAL, quando ela foi observada antes.
 * Sem isto o passo entrega "Timeout 30000ms exceeded", que descreve o sintoma e esconde o motivo.
 */
export function explainWithDevServerState(erro, estado) {
  if (!estado?.fatal) return erro;
  const original = erro?.message || String(erro);
  const novo = new Error(
    `${original}\n\n` +
    `  CAUSA PROVAVEL: o dev server morreu ANTES desta espera e parou de servir.\n` +
    `  Ele levantou: ${estado.fatal.detail}\n` +
    `  Toda rota pedida depois disso fica sem resposta, entao a assercao que estourou e a ` +
    `primeira DEPOIS da queda, nao necessariamente a que quebrou (#2279).`,
  );
  novo.stack = erro?.stack || novo.stack;
  return novo;
}
