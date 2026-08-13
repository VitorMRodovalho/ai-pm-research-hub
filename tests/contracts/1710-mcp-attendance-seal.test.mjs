/**
 * Contract: #1710 (MCP) — selar tem tool, e a tool devolve o ENSAIO antes de escrever.
 *
 * Depois do #1657, selar a lista de um evento e a UNICA forma de a plataforma afirmar que alguem
 * faltou — e o ato so existia em SQL: `seal_event_attendance`, `unseal_event_attendance` e
 * `preview_seal_attendance` nao tinham nenhuma tool. Medido em 13/08/2026: 0 de 510 eventos
 * passados selados, 55 alcancaveis no ciclo, 111 faltas sobre 44 pessoas.
 *
 * Tres decisoes de forma, e cada uma tem uma inversa que este teste proibe:
 *
 * 1. TOOL PROPRIA, nao acao de `attendance_record`. `unseal` e verbo de REMOCAO, entao a tool que
 *    o abriga e destrutiva por inteiro (precedente do `agenda_blocks`, #1548). Absorve-lo ali
 *    jogaria as 166 chamadas/180d de register/excuse/showcase para tras do confirm-gate do
 *    ADR-0018 sem que nenhuma delas tenha ficado mais perigosa.
 *
 * 2. CONFIRM-GATE. Sem `confirm=true`, seal/unseal devolvem o ensaio daquele evento em vez de
 *    executar. Uma tool que grava falta em massa no primeiro turno nao da ao chamador — humano ou
 *    modelo — a chance de ver o numero.
 *
 * 3. O NUMERO VEM DO ENSAIO, nao de contagem propria da tool. `preview_seal_attendance` carrega a
 *    mesma coorte e o mesmo gate por recurso que a escrita aplica; qualquer segunda contagem
 *    prometeria o que a escrita nao cumpre.
 *
 * Camada unica (A) sobre o fonte da EF: o /semantic exige sessao OAuth de um portador de
 * `manage_event`, que a suite nao tem. O comportamento das RPCs por tras esta provado ao vivo em
 * `1710-selo-escopado-e-reversao.test.mjs`.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

/** O bloco da tool: de `mcp.tool(\n "attendance_seal"` ate o proximo cabecalho de tool. */
function blocoDaTool(nome) {
  const i = SRC.indexOf(`"${nome}",`);
  assert.ok(i > -1, `tool ${nome} nao registrada`);
  const inicio = SRC.lastIndexOf('mcp.tool(', i);
  assert.ok(inicio > -1, `abertura de mcp.tool para ${nome} nao encontrada`);
  const proximo = SRC.indexOf('mcp.tool(', i);
  return SRC.slice(inicio, proximo > -1 ? proximo : SRC.length);
}

/** Sem comentarios: este fonte EXPLICA em prosa a decisao que o teste procura (#1586b). */
const semComentario = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/[^\n]*$/gm, '');

const BLOCO = semComentario(blocoDaTool('attendance_seal'));

test('#1710 MCP: a tool existe, cobre os tres verbos e e classificada como destrutiva', () => {
  assert.match(BLOCO, /action: z\.enum\(\["list", "seal", "unseal"\]\)/,
    'a tool precisa cobrir o ensaio, o ato e a reversao');

  const mapa = SRC.slice(
    SRC.indexOf('const SEMANTIC_TOOL_ANNOTATIONS'),
    SRC.indexOf('\n};', SRC.indexOf('const SEMANTIC_TOOL_ANNOTATIONS')),
  );
  assert.match(mapa, /attendance_seal: SEM_DESTRUCTIVE/,
    'uma tool que APAGA linhas de presenca nao pode ser anunciada ao host como escrita aditiva');
});

test('#1710 MCP: o selo NAO virou acao de attendance_record', () => {
  const outra = semComentario(blocoDaTool('attendance_record'));
  // A INVERSA: absorver seal/unseal ali tornaria `attendance_record` destrutiva por inteiro e
  // levaria register/excuse/showcase — 166 chamadas/180d — para tras do confirm-gate.
  assert.doesNotMatch(outra, /seal_event_attendance|unseal_event_attendance|"seal"|"unseal"/,
    'attendance_record absorveu o selo; isso arrasta as escritas aditivas para o confirm-gate');
});

test('#1710 MCP: sem confirm=true, seal/unseal devolvem o ensaio em vez de executar', () => {
  assert.match(BLOCO, /confirm: z\.boolean\(\)\.optional\(\)/,
    'a tool nao tem o parametro de confirmacao do ADR-0018');

  const iGuarda = BLOCO.indexOf('params.confirm !== true');
  assert.ok(iGuarda > -1, 'nao ha guarda de confirmacao');

  // O que de fato importa: a guarda tem de RETORNAR antes de qualquer chamada de escrita. Uma
  // guarda que so avisa e segue adiante deixaria este teste verde e a escrita acontecendo.
  const iEscrita = BLOCO.indexOf('sb.rpc(rpc,');
  assert.ok(iEscrita > -1, 'a tool nao chama a RPC de escrita');
  assert.ok(iGuarda < iEscrita,
    'a guarda de confirm vem DEPOIS da escrita: a primeira chamada ja gravaria falta');
  const trecho = BLOCO.slice(iGuarda, iEscrita);
  assert.match(trecho, /return semanticOk\(/,
    'o ramo sem confirm precisa retornar o ensaio, e nao apenas registrar um aviso');
});

test('#1710 MCP: o numero mostrado vem do ensaio, nao de contagem propria', () => {
  assert.match(BLOCO, /sb\.rpc\("preview_seal_attendance"/,
    'a tool tem de ler o ensaio para dizer quantas faltas seriam gravadas');
  assert.match(BLOCO, /would_write_absent_n/,
    'o preview nao reporta quantas faltas seriam gravadas');
  // A INVERSA: contar por conta propria cria uma segunda definicao de elegibilidade — a divergencia
  // que o #1722 gastou uma sessao reconciliando entre a grade e o selo.
  assert.doesNotMatch(BLOCO, /from\("attendance"\)|from\("members"\)|v_member_operational_tiers/,
    'a tool monta coorte propria em vez de usar o ensaio');
});

test('#1710 MCP: a reversao anuncia o que NAO foi revertido', () => {
  // `unseal` preserva a linha em que alguem marcou presenca ou justificou depois do selo. Se a tool
  // nao disser isso, o chamador conclui que a reversao foi total quando nao foi.
  assert.match(BLOCO, /kept_touched_count/,
    'a tool nao reporta as linhas preservadas pela reversao');
});

test('#1710 MCP: /semantic conta a tool nova, e o teto de 256 do /mcp nao a conta', () => {
  const guard = readFileSync(resolve(ROOT, 'tests/contracts/1377-mcp-actions-overflow-coverage.test.mjs'), 'utf8');
  // A tool vive so no /semantic. Conta-la contra o teto do /mcp fabricaria a queda de outra tool do
  // outro lado do corte alfabetico — um sintoma inteiramente inventado pela contagem errada.
  assert.match(guard, /'attendance_seal',/,
    'attendance_seal precisa estar em SEMANTIC_ONLY no guard do #1377');

  // O /semantic tem QUATRO contadores pinados em arquivos que nao se conhecem, e um deles pina
  // tambem a VERSAO da superficie. Varrer por palpite achou dois; o terceiro custou um CI vermelho
  // (#1755) e o quarto so apareceu quando a suite inteira rodou offline. Esta lista existe para que
  // o proximo a somar uma tool encontre os quatro de uma vez, e nao um vermelho por vez.
  const anot = readFileSync(resolve(ROOT, 'tests/contracts/1402-semantic-tool-annotations.test.mjs'), 'utf8');
  assert.match(anot, /exactly 54 registered tools/,
    'o numero pinado de tools do /semantic (1402) nao acompanhou a tool nova');

  const ponte = readFileSync(resolve(ROOT, 'tests/contracts/mcp-semantic-gateway-bridge.test.mjs'), 'utf8');
  assert.match(ponte, /exactly 54 mcp\.tool\(\) calls/,
    'o segundo numero pinado do /semantic (mcp-semantic-gateway-bridge) nao acompanhou a tool nova');

  const w6b = readFileSync(resolve(ROOT, 'tests/contracts/semantic-envelope-w6b.test.mjs'), 'utf8');
  assert.match(w6b, /= 54 tools \(derived, not hardcoded\) \+ version 0\.13\.0/,
    'o terceiro numero pinado do /semantic (semantic-envelope-w6b), que pina TAMBEM a versao da superficie, nao acompanhou');

  const manifesto = JSON.parse(readFileSync(resolve(ROOT, 'src/lib/mcp-manifest.json'), 'utf8'));
  assert.ok(JSON.stringify(manifesto).includes('attendance_seal'),
    'o manifesto publico de /docs/mcp esta velho: rode `node scripts/generate-mcp-manifest.mjs`');
});
