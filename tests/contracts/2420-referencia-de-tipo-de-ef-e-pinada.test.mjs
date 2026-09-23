// tests/contracts/2420-referencia-de-tipo-de-ef-e-pinada.test.mjs
// Registrar em "test:structural" + "test:contracts" (#1109). So le arquivo; nao toca o banco.
/**
 * Referencia de TIPO nas Edge Functions e pinada. Sem versao, o portao required depende do que o
 * esm.sh resolver naquele minuto.
 *
 * O CASO (#2420): seis EFs abriam com
 *   /// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
 * SEM versao. O esm.sh resolve para a ultima, e a partir de `functions-js@2.117.0` esse arquivo
 * referencia `openai >= 7.21.0` — faixa que o esm.sh estava servindo com **500**. Resultado: o
 * check `deno`, que e REQUIRED, ficou vermelho em TODA PR do repositorio por ~12 horas, sem que
 * ninguem tivesse mudado uma linha de Edge Function.
 *
 * Medido em 23/09/2026, com deno 2.9.5 (a versao exata que a CI instala) e cache frio:
 *
 *   openai@7.23.0 / 7.21.0 .......... 500      <- a faixa quebrada
 *   openai@7.20.0 / 7.15.0 / 6.0.0 .. 200      <- CONTROLE: nao e o pacote, e a versao
 *   functions-js@2.117.1 -> openai@7.23.0      (o que o flutuante resolvia AS 05h)
 *   functions-js@2.117.0 -> openai@7.21.0      (o que o flutuante resolvia AS 18h34)
 *   functions-js@2.116.0 -> openai@7.10.0      <- o pin escolhido
 *
 * ⚠️ AS VERSOES SE MOVERAM EM 10 HORAS, entre a run da CI e a reproducao local. Um especificador
 * flutuante nao e so um risco: ele torna a nao-reproducao possivel, e reproduzir com outra versao
 * inocentaria o repositorio por engano.
 *
 * ⚠️ E UM ARQUIVO ESQUECIDO BASTA. Controle negativo medido: com os 6 pinados o `deno check`
 * devolve **exit 0**; revertendo **um** deles, volta a **exit 1**. Por isso este guard e DERIVADO
 * — varre todos os arquivos e exige versao em cada referencia — e nao uma lista de seis nomes.
 *
 * Cross-ref: #2420, #1896 (mesmo portao, vetor da arvore npm), `.github/workflows/deno-ef-check.yml`.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join, relative } from 'node:path';

const ROOT = process.cwd();
const EF_DIR = resolve(ROOT, 'supabase/functions');

/** Casa `https://esm.sh/<pacote>` em `/// <reference types="..." />`, com ou sem `@versao`. */
const REF = /\/\/\/\s*<reference\s+types=["']https:\/\/esm\.sh\/(@?[^"'@]+(?:\/[^"'@]+)?)(@[^/"']+)?([^"']*)["']\s*\/>/g;

function arquivosEF() {
  const out = [];
  (function anda(dir) {
    for (const nome of readdirSync(dir)) {
      const p = join(dir, nome);
      if (statSync(p).isDirectory()) anda(p);
      else if (p.endsWith('.ts')) out.push(p);
    }
  })(EF_DIR);
  return out;
}

/**
 * Violacoes: referencia de tipo remota SEM versao.
 *
 * Recebe `[{caminho, corpo}]` como dado puro — e a MESMA funcao que julga os arquivos reais e os
 * adulterados do teste de mutacao.
 */
export function violacoes(arquivos) {
  const v = [];
  for (const { caminho, corpo } of arquivos) {
    for (const m of corpo.matchAll(REF)) {
      const [, pacote, versao] = m;
      if (!versao) {
        v.push(
          `${caminho}: \`reference types\` para esm.sh/${pacote} SEM versao. O esm.sh resolve para ` +
          'a ultima no instante do check, e foi assim que um 500 num pacote transitivo derrubou o ' +
          'required `deno` em todas as PRs por 12h (#2420). Pine a versao.',
        );
      }
    }
  }
  return v;
}

test('#2420 — nenhuma Edge Function referencia tipo remoto sem versao', () => {
  const arquivos = arquivosEF().map((p) => ({ caminho: relative(ROOT, p), corpo: readFileSync(p, 'utf8') }));

  // Controle positivo duplo: a varredura precisa ver EFs de verdade E ver ao menos uma referencia,
  // senao a lista vazia sai vazia por vacuidade e o verde nao significa nada.
  assert.ok(arquivos.length >= 40, `controle positivo: so ${arquivos.length} arquivos .ts varridos`);
  const comRef = arquivos.filter((a) => [...a.corpo.matchAll(REF)].length > 0);
  assert.ok(comRef.length >= 5,
    `controle positivo: so ${comRef.length} arquivos com \`reference types\` — o regex parou de casar`);

  assert.deepEqual(violacoes(arquivos), []);
});

test('#2420 mutacao — o detector reprova a referencia sem versao, pela MESMA funcao', () => {
  const PINADO = [{
    caminho: 'supabase/functions/x/index.ts',
    corpo: '/// <reference types="https://esm.sh/@supabase/functions-js@2.116.0/src/edge-runtime.d.ts" />\nconst a = 1;',
  }];
  assert.deepEqual(violacoes(PINADO), [], 'controle sem mutacao: referencia pinada nao viola');

  // Mutacao 1 — o estado EXATO de antes: a versao some.
  const semVersao = [{ ...PINADO[0], corpo: PINADO[0].corpo.replace('@2.116.0', '') }];
  assert.notEqual(semVersao[0].corpo, PINADO[0].corpo, 'a mutacao 1 precisa ter MUDADO o corpo');
  assert.match(violacoes(semVersao).join(' | '), /SEM versao/,
    'mutacao 1: referencia sem versao tem de reprovar');

  // Mutacao 2 — UM arquivo entre varios pinados. O controle negativo com deno provou que um basta.
  const cincoOkUmNao = [
    ...Array.from({ length: 5 }, (_, i) => ({ ...PINADO[0], caminho: `supabase/functions/ok${i}/index.ts` })),
    { caminho: 'supabase/functions/esquecido/index.ts', corpo: semVersao[0].corpo },
  ];
  assert.equal(violacoes(cincoOkUmNao).length, 1, 'mutacao 2: o esquecido no meio dos certos tem de aparecer');
  assert.match(violacoes(cincoOkUmNao)[0], /esquecido/, 'mutacao 2: e tem de NOMEAR qual arquivo e');

  // Mutacao 3 — outro pacote, mesma forma: o guard nao pode ser especifico de functions-js.
  const outroPacote = [{ ...PINADO[0], corpo: '/// <reference types="https://esm.sh/some-other-pkg/types.d.ts" />' }];
  assert.match(violacoes(outroPacote).join(' | '), /SEM versao/,
    'mutacao 3: a regra e sobre referencia remota sem versao, nao sobre um pacote');

  assert.deepEqual(violacoes(PINADO), [], 'controle final sem mutacao');
});
