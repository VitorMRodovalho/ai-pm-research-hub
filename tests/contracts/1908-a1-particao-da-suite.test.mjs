/**
 * A1 (#1908) — a suíte está partida em ESTRUTURAL e COMPORTAMENTAL, e a partição não apodrece.
 *
 * O PROBLEMA que a A1 resolve, medido em 21-22/08/2026: dos 610 arquivos do check required,
 * **288 não tocam banco nenhum** e custam **12,58s** com `--test-concurrency=4` — e mesmo assim
 * esperavam na faixa serializada do banco (p90 14m21s) e rodavam em série, por uma restrição
 * (#1261) que não se aplica a eles. 47% da suíte refém de uma contenção que não é dela.
 *
 * Pior: quando o `validate` era CANCELADO na fila (7 em 198 runs, #1869), esses 288 morriam junto
 * sem ter executado nada. Separados, respondem em ~13s e o cancelamento não apaga o sinal deles.
 *
 * ⚠️ O QUE ESTE ARQUIVO GUARDA, e por que cada asserção existe:
 *
 *  1. **Ninguém no balde errado.** Um teste de banco em `test:structural` roda FORA da faixa, e
 *     dois processos no mesmo banco de produção é exatamente o estrago do #1509. Um teste
 *     hermético em `test:behavioural` volta a esperar 14 min por nada. As duas direções reprovam.
 *
 *  2. **Ninguém de fora.** O denominador vem do DISCO, não do `package.json`. Antes da A1 o script
 *     `test` era lista explícita, e esquecer de somar um arquivo novo era silêncio puro — foi
 *     assim que `ip-gate-templates.test.mjs` passou 4 meses sem rodar (#1926). Depois da partição
 *     o `test` nem lista arquivo, então uma checagem de união contra ele seria VAZIA. Por isso o
 *     guard varre `tests/` e exige que todo arquivo esteja num balde ou numa exclusão DECLARADA.
 *
 *  3. **A lista de exclusões só desce.** Padrão do #1850: dívida declarada com motivo, com ratchet.
 *
 * Hermético: lê `package.json` e o diretório `tests/`. Sem rede, sem banco.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  MARCA_DE_BANCO,
  EXCLUSOES_DECLARADAS,
  EXCLUSOES_BASELINE,
  arquivosDoScript,
  classificar,
  testesEmDisco,
  lerParticao,
} from '../../scripts/classify-test-suite.mjs';

const ROOT = process.cwd();
const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8'));

test('#1908 controle positivo: o classificador e os dois scripts existem', () => {
  assert.ok(existsSync(resolve(ROOT, 'scripts/classify-test-suite.mjs')),
    'sem o classificador, todas as asserções abaixo passariam por vácuo');
  assert.ok(pkg.scripts['test:structural'], 'package.json perdeu test:structural');
  assert.ok(pkg.scripts['test:behavioural'], 'package.json perdeu test:behavioural');
  const p = lerParticao(pkg);
  assert.ok(p.structural.length > 100, `test:structural tem só ${p.structural.length} arquivos`);
  assert.ok(p.behavioural.length > 100, `test:behavioural tem só ${p.behavioural.length} arquivos`);
});

test('#1908 (1) nenhum arquivo está no balde errado', () => {
  const p = lerParticao(pkg);
  const esperado = classificar([...p.structural, ...p.behavioural]);

  const bancoNoEstrutural = p.structural.filter((f) => esperado.behavioural.includes(f));
  assert.deepEqual(bancoNoEstrutural, [],
    'estes tocam o banco e estão em test:structural, que roda FORA da faixa serializada — '
    + 'dois processos no mesmo banco de produção é o estrago do #1509');

  const hermeticoNoComportamental = p.behavioural.filter((f) => esperado.structural.includes(f));
  assert.deepEqual(hermeticoNoComportamental, [],
    'estes são herméticos e estão em test:behavioural, esperando a faixa por nada — '
    + 'é exatamente o desperdício que a A1 existe para tirar');
});

test('#1908 (2) todo teste em disco roda, ou é exclusão DECLARADA', () => {
  const p = lerParticao(pkg);
  const cobertos = new Set([...p.structural, ...p.behavioural]);
  const disco = testesEmDisco();

  assert.ok(disco.length > 500, `controle positivo: só ${disco.length} arquivos varridos em tests/`);

  const descobertos = disco.filter((f) => !cobertos.has(f) && !EXCLUSOES_DECLARADAS.has(f));
  assert.deepEqual(descobertos, [],
    'estes existem em disco e NENHUM script os roda, sem estarem declarados como exclusão. '
    + 'Some em silêncio: a suíte fica verde sem eles exatamente como ficaria com eles. '
    + 'É o defeito da #1926 (4 meses). Some ao balde certo, ou declare com motivo.');
});

test('#1908 (2) nenhum arquivo listado deixou de existir', () => {
  const p = lerParticao(pkg);
  const esperado = classificar([...p.structural, ...p.behavioural]);
  assert.deepEqual(esperado.ausentes, [],
    'estes estão nos scripts e não existem em disco: o `node --test` falharia no arranque');
});

test('#1908 (3) a lista de exclusões só DESCE', () => {
  assert.ok(EXCLUSOES_DECLARADAS.size <= EXCLUSOES_BASELINE,
    `exclusões subiram de ${EXCLUSOES_BASELINE} para ${EXCLUSOES_DECLARADAS.size}. `
    + 'Cada entrada nova é um teste que deixou de rodar — declarar não é resolver.');

  const disco = new Set(testesEmDisco());
  for (const [f, motivo] of EXCLUSOES_DECLARADAS) {
    assert.ok(disco.has(f), `exclusão declarada aponta arquivo inexistente: ${f}`);
    assert.ok(motivo && motivo.length > 20, `a exclusão de ${f} precisa de motivo escrito, não vazio`);
  }
});

test('#1908 os dois baldes rodam com a concorrência certa', () => {
  // A serialização do #1261 vale para quem fala com o banco. Aplicá-la ao balde hermético é
  // justamente o custo que a A1 remove: 30,4s em série contra 12,6s com concorrência 4.
  assert.match(pkg.scripts['test:behavioural'], /--test-concurrency=1\b/,
    'o balde comportamental TEM de rodar em série: é a garantia do #1261 sobre o banco compartilhado');
  assert.doesNotMatch(pkg.scripts['test:structural'], /--test-concurrency=1\b/,
    'o balde estrutural em série devolve os 30s que a A1 existe para cortar');
});

test('#1908 `test` continua rodando os DOIS, para o dev local não mudar', () => {
  const t = pkg.scripts['test'];
  assert.match(t, /test:structural/, '`npm test` local tem de continuar cobrindo tudo');
  assert.match(t, /test:behavioural/, '`npm test` local tem de continuar cobrindo tudo');
  assert.doesNotMatch(t, /\|\|/,
    'ligar os dois com `||` faria o segundo rodar só quando o primeiro FALHA — use `&&`');
  assert.equal(arquivosDoScript(t).length, 0,
    '`test` voltou a listar arquivo à mão: a partição passa a ter duas fontes que divergem');
});

test('#1908 o critério de classificação continua sendo o medido', () => {
  // Se alguém afrouxar a marca, arquivos de banco passam a parecer herméticos e vão para o balde
  // que roda fora da faixa. A regressão seria silenciosa: verde, e concorrente no banco.
  //
  // ⚠️ Os sinais são montados por pedaços de propósito. Escritos por extenso, ESTE arquivo casaria
  // com a própria marca e seria classificado como comportamental — foi o que aconteceu na primeira
  // versão dele. Ver a nota sobre a assimetria no cabeçalho de `classify-test-suite.mjs`.
  const SB = 'SUPA' + 'BASE_';
  for (const sinal of [`${SB}URL`, `${SB}SERVICE_ROLE_KEY`, `${SB}ANON_KEY`, 'db-' + 'fetch']) {
    assert.match(sinal, MARCA_DE_BANCO, `a marca de banco deixou de reconhecer \`${sinal}\``);
  }
  assert.doesNotMatch('tests/contracts/qualquer-coisa-hermetica.test.mjs', MARCA_DE_BANCO,
    'controle negativo: a marca não pode casar com um caminho qualquer');
});
