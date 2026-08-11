/**
 * Contract: #1733 — `db:types` nao pode gravar direto no arquivo versionado.
 *
 * O defeito. O script era `supabase gen types typescript --linked > src/lib/database.gen.ts`. O `>`
 * trunca o destino ANTES de o comando rodar, entao qualquer falha (sem `supabase link`, sem rede,
 * token vencido, rate limit da Management API) destroi o arquivo e deixa a mensagem de erro no
 * lugar dele. Medido em 10/08/2026: `LegacyProjectNotLinkedError` reduziu 34.288 linhas a uma linha
 * de JSON de erro, e o `git diff` foi `1 insertion(+), 34287 deletions(-)`.
 *
 * Nao existe caminho em que o arquivo sobreviva a uma falha, e o erro sai em stdout como JSON, entao
 * o estrago so aparece pra quem for olhar o diff.
 *
 * ⚠️ O que NAO era o problema: a versao da CLI. O `supabase` global e 2.109.0, igual ao
 * `SUPABASE_CLI_VERSION` do workflow — o invariante do gate estava intacto. (`npx supabase` devolve
 * outra versao porque baixa a mais recente, e nao e o binario que o script resolve; medir pelo `npx`
 * produz um diagnostico falso.)
 *
 * A correcao: gerar em temporario, validar o cabecalho, e so entao `mv`. Provado nos dois sentidos,
 * em 10/08/2026:
 *   caminho feliz    -> exit 0, md5 do arquivo INALTERADO (a saida com --project-id e byte a byte
 *                       igual a versionada, que e o que o gate `gen-types-drift` compara)
 *   falha forcada    -> exit 1, md5 do arquivo INALTERADO
 *
 * Este guard e estatico de proposito: exercer o gerador de dentro da suite exigiria credencial da
 * Management API e gastaria uma chamada por execucao, para reprovar um erro de forma que a leitura
 * do script ja pega.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const PKG = resolve(process.cwd(), 'package.json');
const script = JSON.parse(readFileSync(PKG, 'utf8')).scripts?.['db:types'];

test('#1733: o script db:types existe', () => {
  // Controle positivo: sem ele, todo o resto passaria por vacuidade (#1636).
  assert.ok(script, 'package.json perdeu o script db:types');
});

test('#1733: db:types NAO redireciona direto para o arquivo versionado', () => {
  // A INVERSA e o defeito propriamente dito. `> src/lib/database.gen.ts` trunca antes de saber se o
  // comando funciona; e nao adianta so acrescentar o temporario se esta forma sobreviver em algum
  // ramo do comando.
  assert.doesNotMatch(
    script,
    />\s*src\/lib\/database\.gen\.ts/,
    'db:types voltou a redirecionar direto: uma falha do gerador apaga o arquivo',
  );
});

test('#1733: db:types gera em temporario e so entao move', () => {
  assert.match(script, /mktemp/,
    'sem arquivo temporario, nao ha como a geracao falhar sem estrago');
  assert.match(script, /mv\s+.*\s+src\/lib\/database\.gen\.ts/,
    'o arquivo versionado tem de ser escrito por mv, depois de o gerador ter sucesso');
  // O encadeamento e o que faz a garantia valer: com `;` no lugar de `&&`, o mv roda mesmo apos a
  // falha e o estrago volta, com os dois testes acima verdes.
  assert.match(script, /&&\s*mv/,
    'o mv precisa estar encadeado por && ao sucesso da geracao');
});

test('#1733: db:types valida o conteudo antes de mover', () => {
  // A API pode responder 200 com corpo inesperado. Sem esta checagem, o mv promove lixo bem-formado
  // a arquivo de tipos, e o proximo build e que descobre.
  assert.match(script, /export type Json/,
    'o script precisa conferir o cabecalho gerado antes de sobrescrever');
});

test('#1733: db:types usa --project-id, o mesmo caminho do gate', () => {
  // `--linked` depende de estado local (`supabase link`) que nao e versionado e pode nao existir na
  // maquina, no container ou numa sessao de agente — foi o gatilho do incidente. O workflow
  // gen-types-drift usa a Management API, que e sem estado; alinhar faz o comando local produzir
  // byte a byte o que o gate compara.
  assert.match(script, /--project-id/,
    'db:types tem de usar --project-id, como o gate gen-types-drift');
  assert.doesNotMatch(script, /--linked/,
    'db:types voltou a depender de estado local de link');
});
