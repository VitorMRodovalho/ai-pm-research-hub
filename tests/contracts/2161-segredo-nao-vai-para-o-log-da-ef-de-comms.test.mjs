// tests/contracts/2161-segredo-nao-vai-para-o-log-da-ef-de-comms.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json.
/**
 * Contract: a EF de comms monta URLs com segredo na QUERY (`key=` do YouTube, `access_token=` do
 * Meta) e os chamadores logam o erro com `console.warn('Media fetch ...', e)`. Enquanto
 * `fetchWithRetry` colocava a URL crua na mensagem, a chave saia em texto claro.
 *
 * Medido em 03/09/2026 na main, via API de code scanning: 4 alertas HIGH `js/clear-text-logging`
 * abertos desde 02/09, todos neste arquivo e todos pelo mesmo caminho —
 *
 *     segredo -> URL -> mensagem de erro -> console.warn
 *
 *   linha 583  apiKey       (YouTube: search + videos)
 *   linha 534  oauth_token
 *   linha 425  oauth_token
 *   linha 238  apiKey
 *
 * O alerta estava na linha de base do #1966, logo era CONHECIDO e catracavel; consertar faz a
 * base encolher, que e a direcao que aquele workflow declara ("a lista so encolhe").
 *
 * Ratchet estatico da EF (roda em Deno) + prova de comportamento da regra de redacao.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const EF = readFileSync(resolve(process.cwd(), 'supabase/functions/sync-comms-metrics/index.ts'), 'utf8');
const semComentarios = EF.replace(/^\s*\/\/.*$/gm, '');

test('#2161 nenhuma mensagem de erro de fetchWithRetry carrega a URL crua', () => {
  // As duas saidas de erro da funcao — o esgotamento das tentativas e a falha de rede — tem de
  // passar pela redacao. Conta-se, em vez de conferir presenca: uma unica ocorrencia de
  // `redactUrl` satisfaria um match solto mesmo com a outra saida ainda vazando.
  const usos = (semComentarios.match(/redactUrl\(url\)/g) || []).length;
  assert.ok(usos >= 2, `esperadas ao menos 2 saidas redigidas (retries esgotados + falha de rede), achei ${usos}`);

  assert.ok(
    !/retries: \$\{url\}/.test(semComentarios),
    'a mensagem de retries esgotados voltou a interpolar a URL crua',
  );
  assert.ok(
    !/if \(attempt === maxRetries - 1\) throw error;/.test(semComentarios),
    'o erro original do fetch voltou a ser re-lancado: a mensagem que o Deno monta inclui a URL',
  );
});

test('#2161 a redacao apaga a QUERY inteira, e nao um parametro nomeado', () => {
  // Filtrar por nome de parametro erra no proximo provedor que chamar o campo de outra coisa.
  // A regra implementada e "origem + path", e esta e a prova de que ela apaga o segredo.
  const redactUrl = (u) => { try { const p = new URL(u); return `${p.origin}${p.pathname}`; } catch { return '(url ilegivel)'; } };

  const comChave = 'https://www.googleapis.com/youtube/v3/videos?part=statistics&id=abc&key=SEGREDO_AQUI';
  const saida = redactUrl(comChave);
  assert.ok(!saida.includes('SEGREDO_AQUI'), 'o segredo sobreviveu a redacao');
  assert.ok(!saida.includes('?'), 'a query inteira tem de sair');
  assert.equal(saida, 'https://www.googleapis.com/youtube/v3/videos');

  // CONTROLE POSITIVO: o valor diagnostico tem de sobreviver, senao a redacao troca um problema
  // por outro (log inutil para achar qual endpoint falhou).
  assert.ok(saida.includes('youtube/v3/videos'), 'o endpoint tem de continuar identificavel');

  // Meta usa outro nome de parametro; a mesma regra tem de cobrir.
  const comToken = 'https://graph.facebook.com/v21.0/me/media?access_token=OUTRO_SEGREDO';
  assert.ok(!redactUrl(comToken).includes('OUTRO_SEGREDO'), 'a regra tem de valer para qualquer nome de parametro');

  // Entrada invalida nao pode estourar dentro de um handler de erro.
  assert.equal(redactUrl('nao e url'), '(url ilegivel)');
});

test('#2161 a funcao de redacao existe no arquivo com a mesma regra que o teste prova', () => {
  // Sem esta amarra, o teste acima provaria a regra da SUA COPIA e nao a da EF — a familia de
  // defeito em que o guard mede a si mesmo.
  // O FIM da expressao e ancorado de proposito. A primeira versao deste guard exigia apenas que
  // `${p.origin}${p.pathname}` aparecesse, e por isso sobreviveu a acrescentar `${p.search}`
  // logo depois — ou seja, ficou verde com a query, e o segredo, de volta no log. Injetar o
  // defeito foi o que mostrou. Exigir o fechamento da template string fecha a brecha.
  assert.match(
    semComentarios,
    /function redactUrl\(u: string\): string \{[\s\S]{0,200}\$\{p\.origin\}\$\{p\.pathname\}`;/,
    'a EF tem de implementar a redacao como origem+path, e terminar ali',
  );
  assert.ok(
    !/\$\{p\.search\}|\$\{p\.searchParams\}/.test(semComentarios),
    'a query nao pode voltar para nenhuma string montada a partir da URL',
  );
});
