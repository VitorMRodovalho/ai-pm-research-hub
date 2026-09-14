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
