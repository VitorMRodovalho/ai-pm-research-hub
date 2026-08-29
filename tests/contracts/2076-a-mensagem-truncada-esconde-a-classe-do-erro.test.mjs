// tests/contracts/2076-a-mensagem-truncada-esconde-a-classe-do-erro.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2076: o guard da faixa classifica o erro da API pela CABECA da mensagem, nao pela cauda.
 *
 * Em 29/08/2026, entre 21:20 e 21:52 UTC, oito runs morreram no passo `wait-for-db-lane`,
 * atingindo quatro PRs abertas e a propria `main`. Nenhum chegou a rodar teste.
 *
 * O guard nao estava errado em PARAR: recusar-se a supor "faixa vazia" quando nao consegue ler e a
 * decisao certa, senao dois processos entram no banco de producao (#1509). O guard tambem NAO
 * estava sem tratamento de cota: a propria #1923 adicionou o ramo que espera o reset sem consumir
 * tentativa.
 *
 * ⚠️ O DEFEITO ERA QUE A MENSAGEM NUNCA CHEGAVA INTEIRA AO CLASSIFICADOR:
 *
 *     msg="$(tr '\n' ' ' < "$errfile" | tail -c 300)"
 *
 * `tail` guarda o FIM. O GitHub escreve a frase que nomeia a classe do erro no COMECO
 * ("You have exceeded a secondary rate limit..."). Medido no log de um run que nao foi re-rodado
 * (`33277182543`), o texto que chegou comecava no meio de uma frase, em
 * " help, please include the request ID", que e o rabo de "If you reach out to GitHub Support for
 * help, please include...". Sem a cabeca, `grep -i 'rate limit'` nao casava, o ramo de espera
 * nunca era tomado, e o job desistia em ~20s de um erro auto-curavel.
 *
 * E a licao "log de CI truncado esconde o nome da falha" com um agravante: aqui o truncamento nao
 * escondeu o nome de um HUMANO, escondeu do CLASSIFICADOR, que por isso tomou o ramo errado.
 *
 * Cross-ref: #2076, #1923 (a licao que previu a exaustao de cota), #1509 (por que falhar fechado),
 * #1505 (por que `concurrency` do GitHub nao serve como faixa).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const ROOT = process.cwd();
const ACTION = readFileSync(resolve(ROOT, '.github/actions/wait-for-db-lane/action.yml'), 'utf8');

/** O action.yml e o unico lugar onde o classificador existe; leio o padrao de la, nao daqui. */
function padraoDoClassificador() {
  // a primeira alternancia `grep -qiE '...'` dentro de api_with_retry e a que classifica cota
  const m = ACTION.match(/grep -qiE '([^']*rate limit[^']*)'/);
  assert.ok(m, 'nao achei o classificador de cota no action.yml');
  return m[1];
}

/** Roda o mesmo `grep -qiE` do action contra um texto, e diz se classificou como cota. */
function classificaComoCota(texto) {
  const r = spawnSync('bash', ['-c', `grep -qiE '${padraoDoClassificador()}'`],
    { input: texto, encoding: 'utf8' });
  return r.status === 0;
}

test('#2076 controle do harness: o classificador distingue os dois lados', () => {
  // Sem isto, um padrao quebrado devolveria false para tudo e o teste do lado negativo passaria
  // por vacuo enquanto o positivo falharia por um motivo falso.
  assert.equal(classificaComoCota('API rate limit exceeded for user'), true,
    'o texto classico de cota tem de casar; o harness nao esta medindo nada');
  assert.equal(classificaComoCota('Not Found (HTTP 404)'), false,
    'um 404 comum nao pode ser lido como cota, senao o guard espera por nada');
});

test('#2076 a mensagem e lida pela CABECA, nao so pela cauda', () => {
  assert.doesNotMatch(ACTION, /msg="\$\(tr '\\n' ' ' < "\$errfile" \| tail -c \d+\)"/,
    'ler so a cauda foi a causa raiz: a frase que nomeia a classe do erro vive no comeco');
  assert.match(ACTION, /head -c \d+/,
    'o classificador precisa enxergar o inicio da mensagem');
  // A cauda nao pode ser PERDIDA: request ID e timestamp vivem no fim, e eram o que o
  // comportamento anterior mostrava. Manter as duas pontas e o que evita trocar um cego por outro.
  assert.match(ACTION, /tail -c \d+/,
    'a cauda ainda tem de aparecer em mensagem longa, senao o request ID some do log');
});

test('#2076 truncagem + classificacao, ENCADEADAS, sobre o texto real do incidente', () => {
  // ESTE E O TESTE QUE DISCRIMINA, e escreve-lo me corrigiu.
  //
  // Meu primeiro rascunho classificava a mensagem completa e dizia "e nao era antes". Falso: o
  // padrao ANTIGO (`rate limit|429|too many requests`) tambem casa a mensagem completa, porque
  // "secondary rate limit" CONTEM "rate limit". O padrao nunca foi o problema. A truncagem era.
  //
  // Entao aqui eu extraio do action a expressao de truncagem E o padrao, aplico uma na outra, e
  // afirmo sobre o resultado. Assim o teste mede o encadeamento que existe em producao, e nao
  // duas metades isoladas que passam por motivos diferentes.
  const completa =
    'You have exceeded a secondary rate limit. Please wait a few minutes before you try again. '
    + 'If you reach out to GitHub Support for help, please include the request ID '
    + 'DC00:58C35:78686FC:18F0E25E:6A935630 and timestamp 2026-08-29 21:59:12 UTC. '
    + 'For more on scraping GitHub and how it may affect your rights, please review our Terms of '
    + 'Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) (HTTP 403)';

  // a primeira reducao de tamanho aplicada a mensagem de erro dentro de api_with_retry
  const corte = ACTION.match(/msg="\$\(printf '%s' "\$raw" \| (head|tail) -c (\d+)\)"/)
             || ACTION.match(/msg="\$\(tr '\\n' ' ' < "\$errfile" \| (head|tail) -c (\d+)\)"/);
  assert.ok(corte, 'nao achei como o action reduz a mensagem de erro');
  const [, lado, n] = corte;

  const visto = lado === 'head' ? completa.slice(0, Number(n)) : completa.slice(-Number(n));
  assert.equal(classificaComoCota(visto), true,
    `o guard corta pela ${lado} em ${n} chars e o classificador NAO ve a classe do erro; `
    + 'e assim que 8 runs morreram em 20s de um erro auto-curavel');

  // controle: a cauda sozinha, que era o que chegava antes, comprovadamente NAO carrega a classe.
  assert.equal(classificaComoCota(completa.slice(-300)), false,
    'se ate a cauda classificasse, este teste nao provaria nada sobre a correcao');
});

test('#2076 limite SECUNDARIO nao usa o relogio da cota primaria', () => {
  // `rate_limit_reset_in()` le `.resources.core.reset`. Num limite secundario esse relogio pode ja
  // ter passado e a funcao devolve 15s, o que produz laco quente e AGRAVA o bloqueio. O GitHub
  // pede espera na casa de minutos.
  assert.match(ACTION, /secondary rate[\s\S]{0,400}?wait_s=(\d+)/,
    'o caso secundario precisa de espera propria, nao do reset da cota primaria');
  const m = ACTION.match(/secondary rate[\s\S]{0,400}?wait_s=(\d+)/);
  assert.ok(Number(m[1]) >= 60,
    `espera de ${m[1]}s e curta demais para limite secundario; o GitHub pede minutos`);
});

test('#2076 o guard continua FALHANDO FECHADO', () => {
  // A garantia do #1509 nao pode ser afrouxada por esta mudanca: nao ler a faixa NUNCA pode virar
  // "faixa vazia". Se este teste cair, a correcao virou um risco de escrita concorrente no banco.
  assert.doesNotMatch(ACTION, /api_with_retry[\s\S]*?\|\|\s*true/,
    'engolir o erro faria a faixa parecer vazia e todo mundo entrar junto no banco (#1509)');
  assert.match(ACTION, /Parando em vez de arriscar rodar concorrente/,
    'a mensagem de desistencia tem de continuar dizendo que para por seguranca');
  assert.match(ACTION, /return 1/, 'esgotado o teto, o guard ainda tem de FALHAR, nao seguir');
});
