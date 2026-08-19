/**
 * #1869 — o orcamento de suite troca 95 minutos MUDOS por um vermelho legivel.
 *
 * O `validate` e required. Quando a suite nao termina dentro do `timeout-minutes: 95`, o runner
 * mata o job como `cancelled` — que nao e verde nem vermelho, e bloqueia o merge do mesmo jeito.
 * Medido em 19/08/2026 sobre os 19 runs mais recentes do ci.yml: 3 cancelados a 95 min, em 3
 * branches diferentes, com 31, 30 e 25 erros de porta do PostgREST cada. Um run saudavel da
 * mesma janela: 14 min e nenhum.
 *
 * A aritmetica: o `dbFetch` espera ate 75 s e repete, entao cada chamada afetada custa ate
 * ~150 s. Trinta delas somam mais de uma hora sobre uma suite de 16 min.
 *
 * ⚠️ O acumulador vive em ARQUIVO de proposito. O `node --test` roda cada arquivo de teste em um
 * PROCESSO separado, entao um contador de modulo zeraria a cada arquivo e o orcamento nunca
 * somaria — o mecanismo pareceria funcionar sem nunca disparar. Estes testes usam um arquivo
 * proprio, para nao contaminar o acumulador da corrida real.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ARQUIVO_DO_TESTE = join(tmpdir(), `db-fetch-budget-TESTE-${process.pid}.log`);
process.env.DB_FETCH_BUDGET_FILE = ARQUIVO_DO_TESTE;

const {
  dbFetch, LIMITE_MS, ORCAMENTO_SATURACAO_MS, estadoDoOrcamento, resetarOrcamento, ehSaturacaoDePool,
} = await import('../helpers/db-fetch.mjs');

const resposta = (status, corpo) => new Response(corpo, { status });
const PGRST003 = JSON.stringify({ code: 'PGRST003', message: 'Timed out acquiring connection from connection pool.' });
const FONTE = readFileSync('tests/helpers/db-fetch.mjs', 'utf8');

test('#1869: o acumulador e COMPARTILHADO entre processos, nao de modulo', () => {
  assert.ok(/appendFileSync|writeFileSync/.test(FONTE),
    'o acumulador tem de persistir em arquivo: `node --test` usa um processo por arquivo de teste, '
    + 'e um contador de modulo nunca somaria entre eles');
  assert.equal(estadoDoOrcamento().arquivo, ARQUIVO_DO_TESTE,
    'o arquivo tem de ser configuravel, senao o teste contamina a corrida real');
});

test('#1869: run saudavel nao toca o orcamento', async () => {
  resetarOrcamento();
  const original = globalThis.fetch;
  globalThis.fetch = async () => resposta(200, '{"ok":true}');
  try {
    for (let i = 0; i < 5; i++) await dbFetch('https://exemplo.invalid/x', { method: 'POST' });
  } finally { globalThis.fetch = original; }

  const e = estadoDoOrcamento();
  assert.equal(e.eventosDeSaturacao, 0, 'nenhum evento num run saudavel');
  assert.equal(e.gastoEmSaturacaoMs, 0, 'orcamento intocado');
  assert.equal(e.estourado, false);
});

test('#1869: saturacao seguida de sucesso e contabilizada, e a chamada devolve o 200', async () => {
  resetarOrcamento();
  const original = globalThis.fetch;
  let n = 0;
  globalThis.fetch = async () => (++n === 1 ? resposta(504, PGRST003) : resposta(200, '{"ok":true}'));
  try {
    const res = await dbFetch('https://exemplo.invalid/x', { method: 'POST' });
    assert.equal(res.status, 200, 'a retentativa tem de aproveitar o sucesso');
  } finally { globalThis.fetch = original; }

  assert.equal(estadoDoOrcamento().eventosDeSaturacao, 1, 'exatamente 1 evento contabilizado');
});

test('#1869: com o orcamento ESTOURADO a chamada falha nomeando a causa, sem tocar a rede', async () => {
  resetarOrcamento();
  appendFileSync(ARQUIVO_DO_TESTE, `${ORCAMENTO_SATURACAO_MS + 1}\n`);
  assert.equal(estadoDoOrcamento().estourado, true, 'pre-condicao: orcamento estourado');

  const original = globalThis.fetch;
  let tocouARede = false;
  globalThis.fetch = async () => { tocouARede = true; return resposta(200, '{}'); };
  try {
    await assert.rejects(
      () => dbFetch('https://exemplo.invalid/x', { method: 'POST' }),
      (err) => {
        const m = String(err.message);
        for (const trecho of ['orcamento de saturacao esgotado', 'perderam a porta do',
                              'NAO e defeito da PR', 'saturacao SUSTENTADA', 'CANCELADO mudo', '#1844']) {
          assert.ok(m.includes(trecho), `a mensagem precisa citar "${trecho}". Veio: ${m}`);
        }
        return true;
      },
    );
  } finally { globalThis.fetch = original; }

  assert.equal(tocouARede, false, 'estourado o orcamento, nao se gasta mais tempo na rede');
  resetarOrcamento();
});

test('#1869: a retentativa para quando o restante nao cobre outra espera', () => {
  assert.ok(/restanteMs\s*<\s*LIMITE_MS/.test(FONTE),
    'o dbFetch tem de comparar o restante com o custo de UMA espera antes de repetir');
  assert.ok(ORCAMENTO_SATURACAO_MS > LIMITE_MS * 4,
    'o orcamento tem de comportar varias esperas, senao dispara em saturacao pontual');
});

test('#1869: o orcamento falha MUITO antes do teto de 95 min do job', () => {
  assert.ok(ORCAMENTO_SATURACAO_MS < (95 * 60_000) / 2,
    `${ORCAMENTO_SATURACAO_MS / 60000} min tem de ser bem menor que o teto, senao o job e `
    + 'cancelado antes de a mensagem aparecer — que e exatamente o defeito');
});

test('#1869: acumulador velho e descartado (corrida local nao herda a anterior)', () => {
  assert.ok(/VALIDADE_MS/.test(FONTE),
    'fora do CI o arquivo persiste entre execucoes; sem validade, uma corrida saudavel herdaria '
    + 'o gasto da anterior e falharia sem motivo');
});

test('#1869: so PGRST003 conta como saturacao', async () => {
  assert.equal(await ehSaturacaoDePool(resposta(500, 'erro interno')), false);
  assert.equal(await ehSaturacaoDePool(resposta(504, 'gateway timeout generico')), false,
    '504 sem PGRST003 nao e saturacao — retentar mascararia defeito real');
  assert.equal(await ehSaturacaoDePool(resposta(504, PGRST003)), true);
});

writeFileSync(ARQUIVO_DO_TESTE, '');
