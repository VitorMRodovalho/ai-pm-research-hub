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

test('#1548 a tool existe e cobre o ciclo: ler, reservar, confirmar, não-realizado', () => {
  const corpo = corpoDaTool();
  // #2158: o ciclo era só o de VEREDITO (confirmar quem apresentou, marcar quem faltou). Faltava
  // o de INTENÇÃO: `reserve_agenda_block` existia no banco desde a #1548 e nunca foi exposta, o
  // que deixava um agente capaz de estornar XP de uma apresentação e incapaz de inscrever
  // alguém para apresentar.
  assert.match(corpo, /z\.enum\(\["list", "reserve", "confirm", "no_show"\]\)/, 'as quatro ações têm de existir');
  for (const rpc of ['get_meeting_preparation', 'get_geral_agenda_viva', 'reserve_agenda_block', 'confirm_agenda_block', 'confirm_event_blocks', 'revoke_agenda_block_xp']) {
    assert.ok(corpo.includes(`"${rpc}"`), `a tool não alcança ${rpc}`);
  }
});

test('#2158 reservar é SELF-SCOPED e não inventa reserva em nome de outro membro', () => {
  const corpo = corpoDaTool();
  // A RPC resolve o dono de auth.uid() e há UNIQUE (event_id, owner_member_id): não existe
  // reservar EM NOME DE outro membro. Terceiro se expressa nomeando quem apresenta em
  // `guest_name`. Um parâmetro de dono aqui seria a tool contrariando a RPC que ela embrulha.
  assert.ok(
    !/p_owner_member_id|p_member_id:\s*params/.test(corpo),
    'a tool não pode passar dono/membro-alvo para reserve_agenda_block: a reserva é do chamador',
  );
  assert.match(corpo, /guest_name/, 'o caminho de terceiro (nomear quem apresenta) tem de existir');
  assert.match(
    corpo, /EM SEU NOME/,
    'o preview tem de dizer a quem a reserva pertence — o XP da confirmação vai para o dono',
  );
});

test('#2158 reservar NÃO é gateado por manage_event', () => {
  const corpo = corpoDaTool();
  // Medido em 03/09/2026: `reserve_agenda_block` é exercida por 80 dos 100 membros ativos e
  // `manage_event` por 14. A RPC pede a capacidade própria; se a tool anunciasse manage_event
  // para reservar, a descrição mentiria sobre quem pode chamar.
  const i = corpo.indexOf('if (params.action === "reserve")');
  assert.ok(i > 0, 'o ramo de reserve sumiu');
  const ramo = corpo.slice(i, corpo.indexOf('// ── writes: preview por padrao', i));
  assert.ok(ramo.length > 0, 'não consegui delimitar o ramo de reserve');

  // A primeira versão deste guard procurava a PALAVRA `manage_event` no ramo e reprovava por
  // casar o comentário que explica justamente por que ela não é usada, mais o `next_actions` que
  // avisa que CONFIRMAR (depois, outra ação) exige manage_event. Os dois são legítimos. O que não
  // pode existir é o PORTÃO: uma checagem de autoridade por manage_event dentro do ramo, ou um
  // envelope de auditoria anunciando manage_event como a permissão exercida.
  const semComentarios = ramo.replace(/^\s*\/\/.*$/gm, '');
  assert.ok(
    !/canV4\([^)]*manage_event/.test(semComentarios),
    'o ramo de reserve não pode checar manage_event: quem gateia é a RPC, por reserve_agenda_block',
  );
  assert.ok(
    !/permission:\s*"[^"]*manage_event/.test(semComentarios),
    'o envelope de auditoria do reserve não pode anunciar manage_event como a permissão exercida',
  );
  assert.match(
    ramo, /permission:\s*"reserve_agenda_block/,
    'o envelope tem de nomear a capacidade que a RPC de fato exige',
  );
  assert.match(ramo, /reserve_agenda_block/, 'o ramo tem de nomear a capacidade que a RPC exige');
});

test('#1548 NENHUMA escrita executa sem confirm=true (ADR-0018 W1)', () => {
  const corpo = corpoDaTool();
  const iGate = corpo.indexOf('params.confirm !== true');
  assert.ok(iGate > 0, 'o confirm-gate sumiu: confirmar concede XP a pessoas reais');

  // As chamadas de escrita têm de estar DEPOIS do gate no fluxo. Se qualquer uma aparecer antes,
  // existe um caminho que grava sem preview.
  const antesDoGate = corpo.slice(0, iGate);
  // #2158: `reserve_agenda_block` entra na mesma lista. Ela não move XP, mas ocupa a pauta de uma
  // Reunião Geral e é irreversível pelo MCP (não há ação de cancelar), então também não pode
  // executar sem o chamador ter visto o que vai acontecer.
  for (const rpc of ['reserve_agenda_block', 'confirm_agenda_block', 'confirm_event_blocks', 'revoke_agenda_block_xp']) {
    assert.ok(
      !new RegExp(`sb\\.rpc\\(\\s*["'\`]?${rpc}`).test(antesDoGate),
      `${rpc} é chamada ANTES do confirm-gate — existe caminho que grava sem preview`,
    );
  }
});

test('#1548 o preview de confirm/no_show lista os alvos exatos, não só um aviso', () => {
  const corpo = corpoDaTool();
  // Ancorado no bloco de ESCRITA-VEREDITO, e não no primeiro `params.confirm !== true` que
  // aparecer: desde a #2158 o primeiro gate é o do `reserve`, cujo preview mostra OCUPAÇÃO em vez
  // de alvos. Procurar "o primeiro" faria este teste medir o bloco errado e passar por acidente.
  const iSecao = corpo.indexOf('// ── writes: preview por padrao');
  assert.ok(iSecao > 0, 'a seção de escrita confirm/no_show sumiu');
  const iGate = corpo.indexOf('params.confirm !== true', iSecao);
  assert.ok(iGate > iSecao, 'o confirm-gate de confirm/no_show sumiu');
  const bloco = corpo.slice(iGate, iGate + 1800);
  assert.match(bloco, /event_agenda_blocks/, 'o preview tem de consultar os blocos alvo');
  assert.match(bloco, /targets:/, 'o preview tem de devolver a lista de alvos');
  assert.match(bloco, /target_count:/, '"confirmar o evento" sem contagem é verbo sem objeto');
  assert.match(bloco, /next_call:/, 'o preview tem de dizer como executar');
});

test('#2158 o preview de reserve mostra a ocupação, que é o que faz a reserva ser recusada', () => {
  const corpo = corpoDaTool();
  const i = corpo.indexOf('if (params.action === "reserve")');
  assert.ok(i > 0, 'o ramo de reserve sumiu');
  const iGate = corpo.indexOf('params.confirm !== true', i);
  assert.ok(iGate > i, 'reservar tem de passar pelo confirm-gate como as outras escritas');
  const bloco = corpo.slice(iGate, iGate + 1800);
  assert.match(bloco, /capacity/, 'o preview tem de dizer quanto da pauta já está tomado');
  assert.match(bloco, /cap_min/, 'sem o teto declarado, o chamador só descobre o limite ao ser recusado');
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
