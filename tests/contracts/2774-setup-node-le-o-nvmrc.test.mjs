// tests/contracts/2774-setup-node-le-o-nvmrc.test.mjs
// So le arquivo; nao toca o banco.
/**
 * Todo `actions/setup-node` dos workflows le o `.nvmrc` com `check-latest: true`, e nenhum job
 * chama `node`/`npm`/`npx` sem ele antes. E isto que faz a troca de major do Node ser UMA linha.
 *
 * Frase de falha: quando um passo `setup-node` fixa a versao por literal, perde o `check-latest`,
 * aponta para outro arquivo, ou quando um job chama node sem `setup-node` antes, este guard
 * reprova nomeando arquivo, job e passo.
 *
 * O CASO (#2774), medido em 24/10/2026: 11 passos em 8 arquivos com `node-version: '22'` e nenhum
 * `check-latest`. O runner resolveu `Found in cache @ /opt/hostedtoolcache/node/22.23.3`, a versao
 * SEM as correcoes de seguranca de 20/10, e a primeira run de #2773 reprovou por isso: o astro
 * passou a exigir `>=22.23.4`. E o `release-tag.yml` rodava `node` sem `setup-node` nenhum, no Node
 * que viesse na imagem do runner.
 *
 * Enumeracao: os arquivos do DISCO em `.github/workflows/`, nao uma lista de nomes. E uma
 * contagem cruzada amarra o recorte ao texto: o numero de passos `setup-node` que o recorte acha
 * em cada arquivo tem de ser igual ao numero de ocorrencias de `actions/setup-node@` no texto sem
 * comentarios. Sem isso, um passo escrito noutra forma escaparia do recorte, e o verde seria por
 * vacuidade.
 *
 * Isencao (dado, nao comentario): o canario do proximo major, que por definicao nao usa o `.nvmrc`
 * como versao. Ela so vale com as condicoes verificadas aqui: dispara so por agendamento ou a mao
 * (nunca segura merge), nao cita secret nem a faixa do banco, tira o major de um passo que le o
 * `.nvmrc`, e mantem o `check-latest`. Isencao para arquivo que nao existe, ou para arquivo que
 * passou a ler o `.nvmrc` como os outros, tambem reprova: ficou sem objeto.
 *
 * `CI` e `GITHUB_ACTIONS`: tres sentinelas (`rpc-migration-coverage`, `ef-smoke`, `1619`) reprovam a
 * falta de credencial de banco quando se sabem na CI, para a CI nunca pular calada. Apagar uma das
 * duas variaveis desliga essas sentinelas. So o canario isento pode, porque nao tem banco por
 * desenho, e ele PRECISA, senao reprova por construcao: foi o que a primeira rodada dele mostrou em
 * 24/10/2026 (run 40119188841). Qualquer outro workflow que as apague reprova aqui.
 *
 * Cross-ref: #2774, `.nvmrc`, `.github/workflows/node-next-canary.yml`,
 * `docs/runbooks/RUNBOOK_NODE_MAJOR.md`.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const WF_DIR = resolve(ROOT, '.github/workflows');

export const ISENCOES = [
  {
    arquivo: 'node-next-canary.yml',
    motivo: 'mede o proximo major par (o do .nvmrc + 2); a versao vem de um passo que le o .nvmrc',
  },
];

const GATILHOS_SEM_MERGE = new Set(['schedule', 'workflow_dispatch']);
const SETUP_NODE = /^actions\/setup-node@/;
/** `node`, `npm` ou `npx` em posicao de comando: inicio de linha, depois de `;`, `&`, `|`, `(` ou `$(`. */
const CHAMA_NODE = /(^|[;&|(]|\$\()\s*(node|npm|npx)(\s|$)/m;
/** Tira `CI` ou `GITHUB_ACTIONS` do ambiente: `env -u`, `unset`, chave de `env:` ou atribuicao. */
const APAGA_CI = /(^|\s)-u\s+(CI|GITHUB_ACTIONS)\b|\bunset\b[^\n]*\b(CI|GITHUB_ACTIONS)\b|^\s*(CI|GITHUB_ACTIONS):|(^|[^\w$])(CI|GITHUB_ACTIONS)=/m;

/** Remove comentarios YAML (mesma forma do guard do #1509), para nao asserir sobre prosa. */
function semComentarios(src) {
  return src.replace(/(^|\s)#[^\n]*/g, '$1');
}

const recuo = (l) => l.length - l.trimStart().length;
const semAspas = (v) => (v === null ? null : v.replace(/^(['"])(.*)\1$/, '$2'));

/** Jobs: chave com 2 espacos dentro de `jobs:`, ate a proxima chave de topo. */
function jobs(src) {
  const linhas = src.split('\n');
  const ini = linhas.findIndex((l) => /^jobs:\s*$/.test(l));
  const out = [];
  if (ini === -1) return out;
  let atual = null;
  for (const l of linhas.slice(ini + 1)) {
    if (/^\S/.test(l)) break;
    const m = l.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (m) { atual = { job: m[1], linhas: [] }; out.push(atual); continue; }
    atual?.linhas.push(l);
  }
  return out;
}

/** Passos do job: itens `- ` no recuo do primeiro item depois de `steps:`. */
function passos(linhasDoJob) {
  const i = linhasDoJob.findIndex((l) => /^\s+steps:\s*$/.test(l));
  if (i === -1) return [];
  const recuoSteps = recuo(linhasDoJob[i]);
  const out = [];
  let recuoItem = null;
  let atual = null;
  for (const l of linhasDoJob.slice(i + 1)) {
    if (l.trim() === '') { atual?.push(l); continue; }
    const item = l.trimStart().startsWith('- ');
    if (recuoItem === null && item) recuoItem = recuo(l);
    if (item && recuo(l) === recuoItem) { atual = [l]; out.push(atual); continue; }
    if (recuo(l) <= recuoSteps) break;
    atual?.push(l);
  }
  return out.map((ls) => ls.join('\n'));
}

function campo(passo, chave) {
  const m = passo.match(new RegExp(`^\\s*(?:- )?${chave}:[ \\t]*(.*)$`, 'm'));
  return m ? m[1].trim() : null;
}

/** O corpo do `run:` do passo, em linha ou em bloco (`|` / `>`). */
function corpoDoRun(passo) {
  const ls = passo.split('\n');
  const i = ls.findIndex((l) => /^\s*(?:- )?run:/.test(l));
  if (i === -1) return '';
  const valor = ls[i].replace(/^\s*(?:- )?run:\s*/, '');
  if (!/^[|>][+-]?\s*$/.test(valor)) return valor;
  const recuoChave = recuo(ls[i]) + (ls[i].trimStart().startsWith('- ') ? 2 : 0);
  const corpo = [];
  for (const l of ls.slice(i + 1)) {
    if (l.trim() !== '' && recuo(l) <= recuoChave) break;
    corpo.push(l);
  }
  return corpo.join('\n');
}

/** Gatilhos do `on:`, na forma de bloco ou em linha (`on: push` / `on: [push, pull_request]`). */
function gatilhos(src) {
  const emLinha = src.match(/^on:[ \t]*(\S.*)$/m);
  if (emLinha) return emLinha[1].replace(/[[\]]/g, '').split(',').map((s) => s.trim()).filter(Boolean);
  const ls = src.split('\n');
  const i = ls.findIndex((l) => /^on:\s*$/.test(l));
  if (i === -1) return [];
  const out = [];
  for (const l of ls.slice(i + 1)) {
    if (/^\S/.test(l)) break;
    const m = l.match(/^ {2}([A-Za-z_]+):/);
    if (m) out.push(m[1]);
  }
  return out;
}

/**
 * Julga `[{arquivo, corpo}]` como dado puro: e a MESMA funcao que julga os workflows reais e os
 * adulterados do teste de mutacao. Devolve as violacoes e as contagens que o veredito cita.
 */
export function avaliar(workflows, isencoes = ISENCOES) {
  const v = [];
  let passosSetup = 0;
  let jobsComNode = 0;
  for (const isencao of isencoes) {
    if (!workflows.some((w) => w.arquivo === isencao.arquivo)) {
      v.push(`isencao para ${isencao.arquivo}, que nao existe em .github/workflows: isencao sem objeto, remova-a`);
    }
  }
  for (const { arquivo, corpo } of workflows) {
    const src = semComentarios(corpo);
    const isencao = isencoes.find((i) => i.arquivo === arquivo);
    const ocorrencias = (src.match(/actions\/setup-node@/g) || []).length;
    let achados = 0;
    for (const { job, linhas } of jobs(src)) {
      const ps = passos(linhas);
      const ehSetup = (p) => SETUP_NODE.test(semAspas(campo(p, 'uses')) || '');
      const idxSetup = ps.findIndex(ehSetup);
      const idxNode = ps.findIndex((p) => CHAMA_NODE.test(corpoDoRun(p)));
      if (idxNode !== -1) {
        jobsComNode += 1;
        if (idxSetup === -1 || idxSetup > idxNode) {
          v.push(`${arquivo} › ${job}: o passo ${idxNode + 1} chama node/npm/npx sem \`actions/setup-node\` antes; ` +
            'roda o Node da imagem do runner, que o .nvmrc nao governa');
        }
      }
      ps.forEach((p, n) => {
        if (!ehSetup(p)) return;
        achados += 1;
        const onde = `${arquivo} › ${job} › passo ${n + 1}`;
        const versao = campo(p, 'node-version');
        const arquivoVersao = semAspas(campo(p, 'node-version-file'));
        if (semAspas(campo(p, 'check-latest')) !== 'true') {
          v.push(`${onde}: sem \`check-latest: true\`; o runner fica com o patch que estiver no cache dele`);
        }
        if (isencao) {
          if (arquivoVersao === '.nvmrc') {
            v.push(`${onde}: le o .nvmrc como os outros, entao a isencao de ${arquivo} ficou sem objeto; remova-a`);
            return;
          }
          const ref = versao && versao.match(/^\$\{\{\s*steps\.([\w-]+)\.outputs\.[\w-]+\s*\}\}$/);
          if (!ref) {
            v.push(`${onde}: isento, mas a versao nao vem de um passo (\`\${{ steps.<id>.outputs.<x> }}\`): ${versao}`);
            return;
          }
          const origem = ps.find((q) => campo(q, 'id') === ref[1]);
          if (!origem || !/\.nvmrc/.test(corpoDoRun(origem))) {
            v.push(`${onde}: isento, mas o passo \`${ref[1]}\` que da a versao nao le o .nvmrc`);
          }
          return;
        }
        if (versao !== null) {
          v.push(`${onde}: \`node-version: ${versao}\` em vez do .nvmrc; use \`node-version-file: '.nvmrc'\``);
        }
        if (arquivoVersao !== '.nvmrc') {
          v.push(`${onde}: \`node-version-file\` deveria ser '.nvmrc' e e ${arquivoVersao}`);
        }
      });
    }
    if (achados !== ocorrencias) {
      v.push(`${arquivo}: ${ocorrencias} ocorrencia(s) de actions/setup-node@ no texto e ${achados} passo(s) ` +
        'recortado(s); o recorte perdeu um passo, e o que ele perdeu nao foi julgado');
    }
    if (!isencao && APAGA_CI.test(src)) {
      v.push(`${arquivo}: tira CI ou GITHUB_ACTIONS do ambiente, e isso desliga as sentinelas de credencial ` +
        'de banco; so o canario isento pode');
    }
    if (isencao) {
      for (const linha of src.split('\n').filter((l) => /run-suite\.mjs/.test(l))) {
        if (!/-u\s+CI\b/.test(linha) || !/-u\s+GITHUB_ACTIONS\b/.test(linha)) {
          v.push(`${arquivo}: isento, mas roda as suites com o CI do runner, e as sentinelas de credencial ` +
            `reprovam por construcao (use \`env -u CI -u GITHUB_ACTIONS\`): ${linha.trim()}`);
        }
      }
      const fora = gatilhos(src).filter((g) => !GATILHOS_SEM_MERGE.has(g));
      if (fora.length) v.push(`${arquivo}: isento, mas dispara em ${fora.join(', ')}, que segura merge`);
      if (/\bsecrets\./.test(src)) v.push(`${arquivo}: isento, mas cita secret; o canario nao fala com o banco`);
      if (/wait-for-db-lane/.test(src)) v.push(`${arquivo}: isento, mas entra na faixa do banco`);
      if (achados === 0) v.push(`${arquivo}: isento, mas nao tem passo setup-node: isencao sem objeto`);
    }
    passosSetup += achados;
  }
  return { violacoes: v, passosSetup, jobsComNode };
}

/** O `.nvmrc` e um major puro e par: `check-latest` pega o patch mais novo dele, e so major par vira LTS. */
export function violacoesNvmrc(conteudo) {
  const m = conteudo.match(/^(\d+)\n?$/);
  if (!m) return [`.nvmrc nao e um major puro: ${JSON.stringify(conteudo)}`];
  if (Number(m[1]) % 2 !== 0) return [`.nvmrc = ${m[1]}, major impar: nunca vira LTS`];
  return [];
}

function lerWorkflows() {
  return readdirSync(WF_DIR)
    .filter((f) => /\.ya?ml$/.test(f))
    .sort()
    .map((arquivo) => ({ arquivo, corpo: readFileSync(resolve(WF_DIR, arquivo), 'utf8') }));
}

test('#2774: todo setup-node le o .nvmrc com check-latest, e nenhum job chama node sem ele', (t) => {
  const workflows = lerWorkflows();
  const { violacoes, passosSetup, jobsComNode } = avaliar(workflows);

  // Controle positivo: a varredura precisa ver workflows, passos e jobs de verdade, senao a lista
  // vazia de violacoes sai vazia por vacuidade.
  assert.ok(workflows.length >= 15, `controle positivo: so ${workflows.length} workflows lidos`);
  assert.ok(passosSetup >= 12, `controle positivo: so ${passosSetup} passos setup-node recortados`);
  assert.ok(jobsComNode >= 10, `controle positivo: so ${jobsComNode} jobs chamando node; o detector parou de casar`);

  assert.deepEqual(violacoes, []);
  t.diagnostic(`${passosSetup} passos setup-node em ${workflows.length} workflows; ` +
    `${jobsComNode} jobs chamam node e todos tem setup-node antes; ${ISENCOES.length} isencao declarada`);
});

test('#2774: o .nvmrc e um major puro e par', () => {
  assert.deepEqual(violacoesNvmrc(readFileSync(resolve(ROOT, '.nvmrc'), 'utf8')), []);
});

// ── Mutacao: o detector reprova cada defeito, pela MESMA funcao, e diz POR QUE ──────────────────

const OK = `name: x
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Setup Node.js
        uses: actions/setup-node@v6
        with:
          node-version-file: '.nvmrc'
          check-latest: true
          cache: 'npm'
      - run: npm ci
`;

const CANARIO = `name: canario
on:
  schedule:
    - cron: '41 7 * * 3'
  workflow_dispatch:
jobs:
  canary:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: next
        id: next
        run: |
          echo "major=$(( $(cat .nvmrc) + 2 ))" >> "$GITHUB_OUTPUT"
      - uses: actions/setup-node@v6
        with:
          node-version: \${{ steps.next.outputs.major }}
          check-latest: true
      - run: npm ci
      - run: env -u CI -u GITHUB_ACTIONS node scripts/run-suite.mjs structural
`;

const ISENTO = [{ arquivo: 'canario.yml', motivo: 'fixture' }];

function julga(corpo, { arquivo = 'x.yml', isencoes = [] } = {}) {
  return avaliar([{ arquivo, corpo }], isencoes).violacoes.join(' | ');
}

function muta(original, de, para) {
  const mutado = original.replace(de, para);
  assert.notEqual(mutado, original, `a mutacao precisa ter MUDADO o corpo: ${de}`);
  return mutado;
}

test('#2774 mutacao: passo setup-node fora da regra', () => {
  assert.equal(julga(OK), '', 'controle sem mutacao: o workflow certo nao viola');

  assert.match(julga(muta(OK, "node-version-file: '.nvmrc'", "node-version: '22'")), /em vez do \.nvmrc/,
    'mutacao 1: o estado EXATO de antes de #2774, versao literal');
  assert.match(julga(muta(OK, '          check-latest: true\n', '')), /sem `check-latest: true`/,
    'mutacao 2: sem check-latest');
  assert.match(julga(muta(OK, "node-version-file: '.nvmrc'", "node-version-file: '.node-version'")),
    /deveria ser '\.nvmrc' e e \.node-version/, 'mutacao 3: outro arquivo de versao');
  assert.match(
    julga(muta(OK, "node-version-file: '.nvmrc'", "node-version: '22' # node-version-file: '.nvmrc'")),
    /em vez do \.nvmrc/, 'mutacao 4: o comentario que cita a forma certa nao satisfaz o guard');
  assert.match(julga(muta(OK, /- name: Setup Node\.js\n[\s\S]*?cache: 'npm'\n/, "- { uses: actions/setup-node@v6, with: { node-version: '22' } }\n")),
    /o recorte perdeu um passo/, 'mutacao 5: passo que o recorte nao reconhece nao some calado');
  assert.equal(julga(OK), '', 'controle final sem mutacao');
});

test('#2774 mutacao: job que chama node sem setup-node antes', () => {
  const semSetup = muta(OK, /      - name: Setup Node\.js\n[\s\S]*?cache: 'npm'\n/, '');
  assert.match(julga(semSetup), /build: o passo 2 chama node\/npm\/npx sem `actions\/setup-node` antes/,
    'mutacao 6: o caso do release-tag.yml, node sem setup-node');
  const depois = muta(OK, '      - uses: actions/checkout@v6\n', '      - run: node scripts/x.mjs\n');
  assert.match(julga(depois), /o passo 1 chama node\/npm\/npx sem `actions\/setup-node` antes/,
    'mutacao 7: setup-node DEPOIS do primeiro node nao vale');
  assert.equal(julga(OK), '', 'controle final sem mutacao');
});

test('#2774 mutacao: a isencao do canario vale so com as condicoes dela', () => {
  const comoCanario = (corpo) => julga(corpo, { arquivo: 'canario.yml', isencoes: ISENTO });
  assert.equal(comoCanario(CANARIO), '', 'controle sem mutacao: o canario certo nao viola');

  assert.match(comoCanario(muta(CANARIO, '  workflow_dispatch:\n', '  workflow_dispatch:\n  pull_request:\n')),
    /dispara em pull_request, que segura merge/, 'mutacao 8: canario que segura merge');
  assert.match(comoCanario(muta(CANARIO, 'run: npm ci', 'run: npm ci\n        env:\n          T: ${{ secrets.OUTRO_TOKEN }}')),
    /cita secret/, 'mutacao 9: canario com secret');
  assert.match(comoCanario(muta(CANARIO, '      - run: npm ci\n', '      - uses: ./.github/actions/wait-for-db-lane\n      - run: npm ci\n')),
    /faixa do banco/, 'mutacao 10: canario na faixa do banco');
  assert.match(comoCanario(muta(CANARIO, '${{ steps.next.outputs.major }}', "'26'")),
    /a versao nao vem de um passo/, 'mutacao 11: canario com major literal');
  assert.match(comoCanario(muta(CANARIO, '$(cat .nvmrc)', '24')),
    /o passo `next` que da a versao nao le o \.nvmrc/, 'mutacao 12: o major nao deriva do .nvmrc');
  assert.match(comoCanario(muta(CANARIO, 'node-version: ${{ steps.next.outputs.major }}', "node-version-file: '.nvmrc'")),
    /isencao de canario\.yml ficou sem objeto/, 'mutacao 13: isento que virou comum');
  assert.match(avaliar([{ arquivo: 'x.yml', corpo: OK }], ISENTO).violacoes.join(' | '),
    /isencao para canario\.yml, que nao existe/, 'mutacao 14: isencao para arquivo que sumiu');
  assert.match(julga(CANARIO, { arquivo: 'canario.yml' }), /em vez do \.nvmrc/,
    'mutacao 15: sem a isencao declarada, o mesmo canario reprova (a isencao e o que libera)');
  assert.equal(comoCanario(CANARIO), '', 'controle final sem mutacao');
});

test('#2774 mutacao: CI e GITHUB_ACTIONS so saem do ambiente no canario', () => {
  const comoCanario = (corpo) => julga(corpo, { arquivo: 'canario.yml', isencoes: ISENTO });
  assert.equal(julga(OK), '', 'controle sem mutacao: o workflow comum nao mexe no CI');
  assert.equal(comoCanario(CANARIO), '', 'controle sem mutacao: o canario tira os dois e passa');

  assert.match(julga(muta(OK, '      - run: npm ci\n', '      - run: env -u CI npm ci\n')),
    /tira CI ou GITHUB_ACTIONS do ambiente/, 'mutacao 19: workflow comum com `env -u CI`');
  assert.match(julga(muta(OK, '      - run: npm ci\n', "      - run: npm ci\n        env:\n          CI: 'false'\n")),
    /tira CI ou GITHUB_ACTIONS do ambiente/, 'mutacao 20: workflow comum com CI no `env:` do passo');
  assert.match(julga(muta(OK, '      - run: npm ci\n', '      - run: unset GITHUB_ACTIONS; npm ci\n')),
    /tira CI ou GITHUB_ACTIONS do ambiente/, 'mutacao 21: workflow comum com `unset`');
  assert.equal(julga(muta(OK, '      - run: npm ci\n', '      - run: npm ci # nunca env -u CI aqui\n')), '',
    'controle: o comentario que cita a forma proibida nao conta');
  assert.match(comoCanario(muta(CANARIO, 'env -u CI -u GITHUB_ACTIONS node', 'env -u CI node')),
    /roda as suites com o CI do runner/,
    'mutacao 22: canario que so tira o CI (o GITHUB_ACTIONS sozinho tambem liga as sentinelas)');
  assert.match(comoCanario(muta(CANARIO, 'env -u CI -u GITHUB_ACTIONS node', 'node')),
    /roda as suites com o CI do runner/, 'mutacao 23: canario com o ambiente do runner, como na primeira rodada');
  assert.equal(comoCanario(CANARIO), '', 'controle final sem mutacao');
});

test('#2774 mutacao: .nvmrc', () => {
  assert.deepEqual(violacoesNvmrc('24\n'), [], 'controle sem mutacao');
  assert.match(violacoesNvmrc('24.22.1\n').join(), /major puro/, 'mutacao 16: patch fixo no .nvmrc');
  assert.match(violacoesNvmrc('lts/*\n').join(), /major puro/, 'mutacao 17: alias do nvm');
  assert.match(violacoesNvmrc('25\n').join(), /major impar/, 'mutacao 18: major impar');
  assert.deepEqual(violacoesNvmrc('26\n'), [], 'controle: o proximo major par passa');
});
