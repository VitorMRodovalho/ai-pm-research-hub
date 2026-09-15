#!/usr/bin/env node
/**
 * Veredito UNICO da suite local.
 *
 * O problema que isto resolve (2026-09-15): `npm test` e
 * `test:structural && test:behavioural` — DOIS blocos, cada um com o SEU sumario
 * (`ℹ tests / pass / fail`). Quem espera pelo primeiro marcador de termino le metade da
 * suite e chama de suite. Aconteceu: "3673 testes, 0 falhas" entrou numa mensagem de commit
 * enquanto o bloco 2, ainda rodando, terminaria com 19 falhas. O numero era real; o escopo
 * dele nao era o declarado.
 *
 * O CI NAO tem esse problema: ele roda `test:structural` e `test:behavioural` como jobs
 * SEPARADOS, um sumario por job. Esta armadilha e exclusivamente local, e por isso o
 * conserto e uma ferramenta local — nao se mexe em `npm test`, que o guard do #1908 protege
 * (ele exige que `test` continue casando com os dois nomes).
 *
 * Tres estados, de proposito:
 *   OK          — o bloco terminou e reportou 0 falhas
 *   FALHOU      — o bloco terminou e reportou N falhas
 *   SEM SUMARIO — o bloco NAO chegou a reportar (morreu, foi morto, travou)
 *
 * O terceiro estado e o que mais importa. Na sessao que motivou este script o bloco
 * behavioural morreu no meio e o log ficou sem sumario nenhum; um leitor que so procura
 * "fail 0" teria lido silencio como sucesso. Ausencia de sumario NAO e aprovacao.
 */

import { spawn } from 'node:child_process';

const BLOCOS = ['test:structural', 'test:behavioural'];

/**
 * Le a ULTIMA ocorrencia de cada contador na saida.
 *
 * A ULTIMA, e nao a primeira: e exatamente a leitura da PRIMEIRA que produziu o defeito que
 * este script existe para matar. Exportada para que o guard consiga exercer os tres estados
 * sem rodar a suite inteira.
 */
export function parseSumario(saida) {
  const num = (campo) => {
    const todas = [...saida.matchAll(new RegExp(`^\\s*ℹ ${campo} (\\d+)\\s*$`, 'gm'))];
    return todas.length ? Number(todas[todas.length - 1][1]) : null;
  };
  const tests = num('tests');
  if (tests === null) return null; // nunca reportou
  return { tests, pass: num('pass') ?? 0, fail: num('fail') ?? 0, skipped: num('skipped') ?? 0 };
}

function rodar(script) {
  return new Promise((resolve) => {
    const p = spawn('npm', ['run', script], { stdio: ['inherit', 'pipe', 'pipe'], env: process.env });
    let buf = '';
    const capta = (chunk) => { const s = chunk.toString(); buf += s; process.stdout.write(s); };
    p.stdout.on('data', capta);
    p.stderr.on('data', capta);
    p.on('close', (code, signal) => resolve({ script, code, signal, sumario: parseSumario(buf) }));
  });
}

async function main() {
  const resultados = [];
  // Os DOIS rodam sempre, mesmo que o primeiro reprove: saber que o segundo tambem quebrou vale
  // mais que economizar os minutos dele. E o `&&` do `npm test` e justamente o que esconde isso.
  for (const b of BLOCOS) resultados.push(await rodar(b));

  const larg = Math.max(...BLOCOS.map((b) => b.length));
  console.log('\n' + '═'.repeat(64));
  console.log(`VEREDITO — ${BLOCOS.length} blocos`);
  console.log('═'.repeat(64));

  let totalTests = 0, totalFail = 0, totalSkip = 0;
  let semSumario = 0;

  for (const r of resultados) {
    const nome = r.script.padEnd(larg);
    if (!r.sumario) {
      semSumario += 1;
      const causa = r.signal ? `morto por ${r.signal}` : `saiu com codigo ${r.code}`;
      console.log(`  ${nome}  SEM SUMARIO — ${causa}. NAO conte como aprovado.`);
      continue;
    }
    const { tests, fail, skipped } = r.sumario;
    totalTests += tests; totalFail += fail; totalSkip += skipped;
    const veredito = fail > 0 ? `FALHOU (${fail})` : 'OK';
    console.log(`  ${nome}  ${String(tests).padStart(5)} testes, ${String(fail).padStart(3)} falhas, ${String(skipped).padStart(3)} pulos  ${veredito}`);
  }

  console.log('─'.repeat(64));
  if (semSumario > 0) {
    console.log(`  RESULTADO: INCONCLUSIVO — ${semSumario} de ${BLOCOS.length} blocos nao reportaram.`);
    console.log('             Ausencia de sumario nao e aprovacao. Rode de novo e leia o log.');
    process.exit(2);
  }
  console.log(`  TOTAL: ${totalTests} testes, ${totalFail} falhas, ${totalSkip} pulos`);
  console.log(`  RESULTADO: ${totalFail > 0 ? 'REPROVADO' : 'APROVADO'}`);
  console.log('═'.repeat(64));
  process.exit(totalFail > 0 ? 1 : 0);
}

// So executa quando invocado direto; importar para testar nao dispara a suite.
if (import.meta.url === `file://${process.argv[1]}`) await main();
