// tests/contracts/2287-o-detector-ganha-superficie.test.mjs
// Baldes (#1908 + #1109): "test:structural" E "test:contracts". HERMÉTICO — lê o index.ts do MCP e
// as migrations, sem rede, sem banco, sem subir servidor.
/**
 * #2287 — o detector de contas não ligadas passa a ter onde ser usado, e o aviso para de anunciar
 * urgência que não existe.
 *
 * O QUE A MEDIÇÃO DE 14/09 MOSTROU:
 *
 *   * `detect_unlinked_accounts()` existe desde a #2273 e o cron da #2285 avisa quando ela acha
 *     algo — mas varrendo `src/` e `supabase/functions/` ela aparecia em UM lugar só:
 *     `src/lib/database.gen.ts`, que é tipo gerado. Nenhuma superfície a chamava. O alerta chegava
 *     e não havia onde agir sem abrir o banco.
 *   * `/admin/data-health` era o candidato natural e NÃO serve: o `DataHealthIsland` consulta
 *     `admin_get_anomaly_report`, `get_invariant_alerts` e `list_orphan_interview_events`, e
 *     nenhuma conhece conta sem vínculo. Por isso a notificação saiu sem link.
 *   * Na primeira execução real (16:59) o corpo disse "Dessas, **0** já entrou na plataforma
 *     alguma vez, e esse é o caso urgente". Fato certo, tom errado.
 *
 * As camadas:
 *
 *   A (estático) o MCP alcança a RPC. O scope existe no enum E no switch — declarar um sem o
 *                outro devolve "Unknown scope" em runtime, que é o defeito da #2119 na forma
 *                local: o valor é admitido e o caminho que ele percorre não existe.
 *   B (estático) a ferramenta chama a RPC MASCARADA, nunca o worker cru `_unlinked_accounts_rows`,
 *                que devolve endereço em claro e é revogado de `authenticated`.
 *   C (estático) o scope é classificado como PII alta. A lista sai mascarada, mas é um mapa de
 *                pessoas a um passo de entrar, e o próprio corpo da RPC trata isso como leitura
 *                não-pública.
 *   D (estático) a frase de urgência é CONDICIONAL. Com zero, o aviso diz que é fila.
 *   E (estático) o corpo continua sem endereço: nada de `masked_email` nem `email` no texto da
 *                notificação — ela carrega CONTAGEM, e o detalhe fica atrás do portão.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const MCP = join(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const MIGRATIONS = join(ROOT, 'supabase/migrations');

const mcpSrc = () => readFileSync(MCP, 'utf8');

/** Última migration que (re)define o wrapper do cron — é a que vale (CREATE OR REPLACE). */
function corpoDoCron() {
  const achados = readdirSync(MIGRATIONS)
    .filter(f => f.endsWith('.sql')).sort()
    .map(f => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .filter(s => s.includes('CREATE OR REPLACE FUNCTION public.detect_unlinked_accounts_cron('));
  assert.ok(achados.length >= 1, 'nenhuma migration define o wrapper: guard vazio lê como verde');
  const src = achados[achados.length - 1];
  const i = src.indexOf('CREATE OR REPLACE FUNCTION public.detect_unlinked_accounts_cron(');
  return src.slice(i, src.indexOf('$function$;', i));
}

// ═══════════════════════════════════════════════════════════════════════════
test('A · o scope existe no enum E no switch', () => {
  const src = mcpSrc();
  assert.match(src, /z\.enum\(\[[^\]]*"unlinked_accounts"[^\]]*\]\)\.describe\("Which admin surface\."\)/,
    'o scope não está no enum do admin_dashboard: a chamada seria rejeitada pelo Zod antes de chegar ao switch');
  assert.match(src, /case "unlinked_accounts":/,
    'o scope está no enum mas NÃO no switch: cai no `default` e devolve "Unknown scope". ' +
    'Admitir o valor sem criar o caminho que ele percorre é o defeito da #2119.');
});

test('B · chama a RPC mascarada, nunca o worker cru', () => {
  const src = mcpSrc();
  const i = src.indexOf('case "unlinked_accounts":');
  const linha = src.slice(i, src.indexOf('break;', i));
  assert.match(linha, /sb\.rpc\("detect_unlinked_accounts"\)/,
    'o scope tem de despachar a RPC com portão e máscara');
  assert.ok(
    !/_unlinked_accounts_rows/.test(linha),
    'o MCP chamaria o worker interno, que devolve o endereço EM CLARO e é revogado de ' +
    '`authenticated` justamente para não ser alcançável por esta via',
  );
});

test('C · o scope é classificado como PII alta', () => {
  const src = mcpSrc();
  const m = src.match(/const HIGH_SCOPES = \[([^\]]*)\];/);
  assert.ok(m, 'HIGH_SCOPES não localizado no admin_dashboard');
  assert.match(m[1], /"unlinked_accounts"/,
    'a lista sai com e-mail mascarado, mas é um mapa de pessoas a um passo de entrar; o próprio ' +
    'corpo da RPC trata isso como leitura NÃO pública, e o envelope de auditoria tem de dizer o mesmo');
});

// ═══════════════════════════════════════════════════════════════════════════
test('D · a frase de urgência é condicional, e o ramo de zero não promete urgência', () => {
  const corpo = corpoDoCron();
  assert.match(corpo, /CASE WHEN v_signed_in > 0/,
    'a frase voltou a ser incondicional: com zero o aviso diz "Dessas, 0 já entrou ... e esse é o ' +
    'caso urgente", anunciando urgência onde não há (medido na primeira execução real, 14/09 16:59)');
  const ramoZero = corpo.slice(corpo.indexOf('ELSE'), corpo.indexOf('END)'));
  // Proibir a PALAVRA "urgência" aqui era ingênuo: o ramo de zero legitimamente diz que NÃO é
  // urgência, e a primeira versão deste guard reprovou o texto correto por isso. O que não pode
  // voltar é a PROMESSA — "e esse e o caso urgente" — feita com o número em zero.
  assert.ok(
    !/caso urgente/i.test(ramoZero),
    `o ramo de ZERO voltou a prometer urgência: ${ramoZero.trim().slice(0, 140)}`,
  );
  assert.match(ramoZero, /fila/i,
    'o ramo de zero precisa dizer o que o caso É (trabalho de fila), não só o que ele não é');
  // E o ramo positivo TEM de continuar dizendo que é urgente — senão o conserto virou um
  // apagamento do sinal, em vez de torná-lo condicional.
  const ramoPositivo = corpo.slice(corpo.indexOf('THEN format('), corpo.indexOf('ELSE'));
  assert.match(ramoPositivo, /urgente/i,
    'o ramo POSITIVO perdeu a palavra que dá a prioridade: quem já entrou e não se reconhece é o ' +
    'caso que precisa de ação, e o aviso tem de continuar dizendo isso');
});

test('E · a notificação carrega contagem, nunca endereço', () => {
  const corpo = corpoDoCron();
  const insert = corpo.slice(corpo.indexOf('INSERT INTO public.notifications'),
                             corpo.indexOf('GET DIAGNOSTICS'));
  for (const proibido of ['masked_email', 'x.email', '_mask_email']) {
    assert.ok(!insert.includes(proibido),
      `o corpo da notificação passou a citar ${proibido}: ela vai para o e-mail de 2 pessoas e ` +
      'tem de carregar CONTAGEM, com o detalhe atrás do portão de detect_unlinked_accounts()');
  }
  assert.match(insert, /v_total/, 'a contagem tem de estar lá — senão o aviso não diz nada');
});
