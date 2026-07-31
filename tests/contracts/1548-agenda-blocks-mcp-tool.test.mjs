import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

/**
 * #1548 onda 2 — a Agenda Viva de Protagonismo não tinha NENHUMA superfície MCP.
 * `grep -rln "agenda_block" supabase/functions/nucleo-mcp/` devolvia zero arquivos: reservar,
 * editar e confirmar bloco só existiam pela web. Foi por isso que os 7 blocos sem confirmar da
 * Reunião Geral de 30/07 (0 XP, contra 84 e 68 das duas anteriores) só eram corrigíveis por
 * clique humano — não havia caminho automatizável nem assistido.
 *
 * A tool `agenda_blocks` fecha isso. A invariante que estes testes defendem NÃO é "a tool existe":
 * é que **conceder XP continua sendo um ato deliberado**. Confirmar um bloco dá pontos a uma
 * pessoa real; confirmar um evento dá pontos a várias de uma vez. As duas escritas passam pelo
 * preview/confirm do ADR-0018 W1, e o preview lista os alvos EXATOS.
 */

const SRC = readFileSync('supabase/functions/nucleo-mcp/index.ts', 'utf8');

const corpoDaTool = () => {
  const i = SRC.indexOf('mcp.tool(\n    "agenda_blocks"');
  assert.ok(i >= 0, 'a tool agenda_blocks não está registrada');
  // até o próximo registro de tool
  const rest = SRC.slice(i + 10);
  const j = rest.indexOf('mcp.tool(');
  return rest.slice(0, j > 0 ? j : rest.length);
};

test('#1548 a tool existe e cobre o ciclo: ler, confirmar, não-realizado', () => {
  const corpo = corpoDaTool();
  assert.match(corpo, /z\.enum\(\["list", "confirm", "no_show"\]\)/, 'as três ações têm de existir');
  for (const rpc of ['get_meeting_preparation', 'get_geral_agenda_viva', 'confirm_agenda_block', 'confirm_event_blocks', 'revoke_agenda_block_xp']) {
    assert.ok(corpo.includes(`"${rpc}"`), `a tool não alcança ${rpc}`);
  }
});

test('#1548 NENHUMA escrita executa sem confirm=true (ADR-0018 W1)', () => {
  const corpo = corpoDaTool();
  const iGate = corpo.indexOf('params.confirm !== true');
  assert.ok(iGate > 0, 'o confirm-gate sumiu: confirmar concede XP a pessoas reais');

  // As chamadas de escrita têm de estar DEPOIS do gate no fluxo. Se qualquer uma aparecer antes,
  // existe um caminho que grava sem preview.
  const antesDoGate = corpo.slice(0, iGate);
  for (const rpc of ['confirm_agenda_block', 'confirm_event_blocks', 'revoke_agenda_block_xp']) {
    assert.ok(
      !new RegExp(`sb\\.rpc\\(\\s*["'\`]?${rpc}`).test(antesDoGate),
      `${rpc} é chamada ANTES do confirm-gate — existe caminho que concede/estorna XP sem preview`,
    );
  }
});

test('#1548 o preview lista os alvos exatos, não só um aviso', () => {
  const corpo = corpoDaTool();
  const iGate = corpo.indexOf('params.confirm !== true');
  const bloco = corpo.slice(iGate, iGate + 1800);
  assert.match(bloco, /event_agenda_blocks/, 'o preview tem de consultar os blocos alvo');
  assert.match(bloco, /targets:/, 'o preview tem de devolver a lista de alvos');
  assert.match(bloco, /target_count:/, '"confirmar o evento" sem contagem é verbo sem objeto');
  assert.match(bloco, /next_call:/, 'o preview tem de dizer como executar');
});

test('#1548 a tool é classificada como DESTRUCTIVE — o action set tem verbo de remoção', () => {
  assert.match(
    SRC, /agenda_blocks:\s*SEM_DESTRUCTIVE/,
    "`no_show` marca não realizado E estorna XP (pontos negativos no ledger, #1087). Uma tool cujo " +
    'action set contém verbo de remoção é destrutiva, e a annotation destructiveHint depende disso.',
  );
});

test('#1548 erro no CORPO da RPC não vira sucesso no envelope', () => {
  const corpo = corpoDaTool();
  // As RPCs de bloco devolvem {error: 'access_denied'} no corpo em vez de estourar. Sem este
  // tratamento, uma recusa de autoridade voltaria como "bloco confirmado" — a família do #1525/#1532.
  assert.match(
    corpo, /\(data as any\)\?\.error/,
    'a tool precisa inspecionar `data.error`: as RPCs recusam no CORPO, não por exceção. ' +
    'Sem isso, access_denied é reportado como sucesso.',
  );
});

test('#1548 NULL em agenda_blocks_pending não é lido como zero', () => {
  const corpo = corpoDaTool();
  // A contagem volta NULL para quem não tem manage_event (a onda 1 gateou isso de propósito).
  // Um resumo que dissesse "0 pendentes" para esse chamador seria mentira.
  // Duas pontas observáveis, verificadas separadamente. A primeira versão deste teste usava um
  // único `match` e sobrevivia a mutar UMA das duas ocorrências — mesmo vício do guard da onda 1.
  assert.match(
    corpo, /nao divulgada a este chamador/,
    'o RESUMO precisa dizer que a contagem não foi divulgada, em vez de afirmar "0 pendentes"',
  );
  assert.match(
    corpo, /warnings:[\s\S]{0,300}NULL nao e zero/,
    'o WARNING precisa nomear a armadilha para quem consome o envelope: NULL não é zero',
  );
  const ocorrencias = (corpo.match(/pending === null \|\| pending === undefined/g) || []).length;
  assert.ok(
    ocorrencias >= 2,
    `esperadas ao menos 2 checagens de NULL (resumo + warning), encontradas ${ocorrencias}`,
  );
});

test('#1548 a versão da superfície semântica tem UMA fonte, usada nas duas pontas', () => {
  // Era literal em dois lugares e eles divergiram: o McpServer anunciava 0.12.0 enquanto o /health
  // dizia 0.11.0. O #1392 já havia derivado o `tools` do health pelo mesmo motivo; o `version`
  // ficou para trás — e um health que mente sobre a versão é pior que um health ausente.
  assert.match(SRC, /const SEMANTIC_SURFACE_VERSION = "\d+\.\d+\.\d+";/, 'a constante única precisa existir');
  assert.match(
    SRC, /new McpServer\(\s*\{\s*name:\s*"nucleo-ia-semantic"\s*,\s*version:\s*SEMANTIC_SURFACE_VERSION\s*\}\s*\)/,
    'o McpServer tem de usar a constante, não um literal',
  );
  assert.match(
    SRC, /"\/semantic":\s*\{[^}]*version:\s*SEMANTIC_SURFACE_VERSION\b/,
    'o payload do /health tem de usar a MESMA constante — senão volta a divergir em silêncio',
  );
  const literais = (SRC.match(/version:\s*"0\.\d+\.\d+"/g) || []).filter((l) => !l.includes('2.80.0') && !l.includes('0.2.0'));
  assert.deepEqual(literais, [], `versão de superfície semântica ainda literal em: ${literais.join(', ')}`);
});
