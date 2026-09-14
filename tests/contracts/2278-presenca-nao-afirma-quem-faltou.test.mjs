// tests/contracts/2278-presenca-nao-afirma-quem-faltou.test.mjs
// Registrar nas whitelists "test:behavioural" E "test:contracts" do package.json (#1109).
// (DB-aware: as camadas A, C e E abrem conexão. B e D são herméticas.)
/**
 * #2278 — a porta que os agentes usam para ler presença para de afirmar que quem faltou esteve
 * na reunião.
 *
 * O DEFEITO, e ele era literal. `get_event_detail` montava o bloco de presença assim:
 *
 *     'present', true,                        ← literal. NUNCA lia a.present
 *     'excused', COALESCE(a.excused, false)   ← este lia o banco de verdade
 *     'present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id)
 *
 * A premissa era "existir linha em `attendance` = compareceu". Verdadeira enquanto ausência não
 * era registrável; falsa desde que a plataforma passou a gravar `present=false` e `excused`.
 *
 * COMO APARECEU. Um líder de tribo leu a lista pelo MCP em 14/09 e estranhou: "tem pessoas da
 * minha tribo que não estiveram, misturadas com outras que estiveram". A conclusão que circulou
 * foi "MCP certo, UI errada". Era o INVERSO — e essa inversão é o motivo de este arquivo existir:
 * o dado correto sempre esteve no banco e na tela.
 *
 * MEDIDO no evento que motivou o relato:
 *   a RPC devolvia  43 membros, todos present:true, present_count 43
 *   a tabela tinha  43 registros = 37 presentes + 6 ausentes
 *   a UI mostrava   37/88 (correta)
 *
 * ALCANCE: 342 ausências (12,6% de 2.709 registros) sobre 108 eventos.
 *
 * POR QUE SÓ APARECEU AGORA: o registro de ausência saltou para 174 em agosto contra 3 a 38 nos
 * meses anteriores. A função sempre esteve errada; antes acertava por acidente, porque quase não
 * havia ausência para ela descartar. É a forma mais perigosa de defeito — o que fica correto
 * enquanto o dado é pobre, e passa a mentir exatamente quando o dado melhora.
 *
 * As camadas:
 *
 *   A (vivo)      o CORPO VIVO não tem o literal e lê `a.present`. É o corpo no Postgres, não o
 *                 arquivo que o declara: um `CREATE OR REPLACE` posterior via dashboard reverteria
 *                 a função sem tocar em migration nenhuma.
 *   B (estático)  a migration da onda captura o conserto, para o corpo vivo ter origem rastreável.
 *   C (vivo)      a SUPERFÍCIE do defeito não está vazia: existem eventos com ausência registrada.
 *                 Sem esta camada, A e B ficariam verdes num mundo onde ninguém registra falta —
 *                 exatamente o mundo em que o defeito era invisível.
 *   D (hermético) a MORDIDA: a asserção reprova quando o defeito é reinjetado.
 *   E (vivo)      a função continua member-scoped (service_role sem auth.uid() é recusado), para
 *                 o conserto não ter aberto a leitura por acidente.
 *
 * Cross-ref: #2278, #1657 (sem registro não é falta — aqui a inversão: com registro virou
 * presente), #2276/#2273 (a onda anterior, que compartilha a sessão mas não o tema).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { md5, normalizeBody } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** A migration desta onda, achada pelo marcador `_2278_` — não por caminho fixo (#2116). */
function migracaoDaOnda() {
  const f = readdirSync(MIGRATIONS).filter((x) => /_2278_/.test(x) && x.endsWith('.sql')).sort();
  assert.equal(f.length, 1, `esperava 1 migration de #2278, achei ${f.length}: ${JSON.stringify(f)}`);
  return readFileSync(join(MIGRATIONS, f[0]), 'utf8');
}

/**
 * A ASSERÇÃO SOB TESTE, isolada para que a camada D possa mordê-la.
 *
 * Repare no que ela NÃO faz: não afirma "existe gente na lista". O defeito sempre devolveu gente —
 * devolvia gente demais, toda marcada como presente. Ela afirma que o corpo CONSULTA a coluna e
 * que não resta nenhum literal afirmando presença.
 */
function afirmaQueLeAColuna(corpo) {
  assert.ok(corpo && corpo.length > 0, 'corpo vazio: nada a afirmar');
  assert.doesNotMatch(
    corpo, /'present'\s*,\s*true/,
    "o corpo voltou a afirmar `'present', true` como literal: presença de quem faltou",
  );
  assert.match(
    corpo, /'present'\s*,\s*COALESCE\(\s*a\.present/,
    'o corpo não lê `a.present`: o valor de presença não vem da coluna',
  );
  // `present_count` tem de FILTRAR. Um COUNT(*) cru conta linhas, e linha não é presença.
  assert.match(
    corpo, /'present_count'[\s\S]{0,200}?present\s+IS\s+TRUE/,
    '`present_count` não filtra por `present IS TRUE`: volta a contar linhas',
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// A — o corpo VIVO, lido do Postgres (não do arquivo que o declara)
// ═══════════════════════════════════════════════════════════════════════════
test('A · o corpo VIVO é o corpo capturado pela migration (hash, não leitura de texto)', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const { data, error } = await c.rpc('_audit_list_public_function_bodies');
  assert.ifError(error);

  const rows = Array.isArray(data) ? data : [];
  assert.ok(rows.length > 0, 'a varredura de corpos voltou vazia: o teste ficaria verde por vácuo');

  const vivo = rows.filter((r) => r.proname === 'get_event_detail');
  assert.equal(vivo.length, 1, `esperava 1 get_event_detail vivo, achei ${vivo.length}`);

  // A RPC de auditoria devolve `body_md5`, e NÃO o texto — ela existe para comparar hashes. Isso
  // torna esta camada mais forte que ler string: ela afirma que o corpo no Postgres é EXATAMENTE
  // o corpo que a migration captura. Combinada com a camada B (a migration contém o conserto),
  // a cadeia prova que o vivo tem o conserto, sem depender de casar substring no corpo vivo.
  // O corpo capturado é o texto ENTRE os delimitadores `$function$` da migration desta onda —
  // que é exatamente o que o Postgres guarda em `prosrc`. A normalização (`\s+` → espaço) é a
  // mesma dos dois lados, e o CLAUDE.md exige que continue sendo: divergir aqui faria TODA função
  // parecer derivada.
  const corpoNaMigration = migracaoDaOnda().match(/AS \$function\$([\s\S]*?)\$function\$/);
  assert.ok(corpoNaMigration, 'não achei o corpo entre $function$ na migration de #2278');

  const esperado = md5(normalizeBody(corpoNaMigration[1]));
  assert.equal(
    vivo[0].body_md5, esperado,
    'o corpo vivo de get_event_detail DIVERGE da última captura em migration. '
    + 'Ou alguém redefiniu a função fora do fluxo (dashboard / execute_sql), ou a migration não '
    + 'é a que está no ar — e nos dois casos o conserto de #2278 pode ter sido desfeito sem deixar '
    + 'rastro em arquivo nenhum.',
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// B — a migration captura o conserto (origem rastreável do corpo vivo)
// ═══════════════════════════════════════════════════════════════════════════
test('B · a migration da onda contém o conserto', () => {
  // Comentários mascarados: este arquivo E a migration citam o literal para EXPLICAR o defeito.
  // Sem mascarar, a asserção de ausência casaria a própria explicação (armadilha já registrada).
  const sql = maskLineComments(migracaoDaOnda());
  afirmaQueLeAColuna(sql);
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.get_event_detail/,
    'a migration não redefine get_event_detail');
});

// ═══════════════════════════════════════════════════════════════════════════
// C — a superfície do defeito existe (senão A e B ficam verdes por vácuo)
// ═══════════════════════════════════════════════════════════════════════════
test('C · há ausência registrada no acervo — o guard não é sobre um caso hipotético', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const { count: ausencias, error } = await c
    .from('attendance').select('id', { count: 'exact', head: true }).eq('present', false);
  assert.ifError(error);

  assert.ok(ausencias > 0,
    'zero ausências registradas no acervo. Se isso for real, o defeito era invisível e as camadas '
    + 'A e B passam sem provar nada — re-meça antes de confiar nelas.');

  // E há pelo menos um evento onde presentes < registros, que é a forma exata do erro:
  // `present_count` respondendo o total de linhas.
  const { data: linhas, error: e2 } = await c
    .from('attendance').select('event_id, present').eq('present', false).limit(1);
  assert.ifError(e2);
  assert.equal(linhas.length, 1, 'não consegui um evento com ausência para ancorar o controle');
});

// ═══════════════════════════════════════════════════════════════════════════
// D — a MORDIDA: a asserção reprova com o defeito de volta
// ═══════════════════════════════════════════════════════════════════════════
test('D · a asserção MORDE: o corpo defeituoso tem de reprovar', () => {
  // Controle POSITIVO: o corpo corrigido passa. Sem ele, os negativos poderiam estar passando
  // por um erro que reprova qualquer entrada.
  const bom = `
    'present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id AND present IS TRUE),
    'absent_count', 0, 'excused_count', 0, 'record_count', 0,
    'present', COALESCE(a.present, false),
    'excused', COALESCE(a.excused, false)`;
  assert.doesNotThrow(() => afirmaQueLeAColuna(bom), 'o corpo corrigido deveria passar');

  // Negativo 1 — o defeito original, literal.
  assert.throws(
    () => afirmaQueLeAColuna(`'present', true, 'excused', COALESCE(a.excused, false)`),
    /literal/,
    'o literal `\'present\', true` passou: a asserção não discrimina o defeito que originou a issue',
  );

  // Negativo 2 — lê a coluna, mas o contador volta a contar LINHAS. Metade do defeito é defeito:
  // era `present_count: 43` que fazia o leitor concluir "todos presentes".
  assert.throws(
    () => afirmaQueLeAColuna(`
      'present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id),
      'present', COALESCE(a.present, false)`),
    /present_count/,
    'um present_count sem filtro passou: volta a contar linhas como se fossem presenças',
  );

  // Negativo 3 — não afirma `true`, mas também não consulta a coluna.
  assert.throws(
    () => afirmaQueLeAColuna(`'present', v_algum_valor, 'present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id AND present IS TRUE)`),
    /não lê `a\.present`/,
    'um corpo que não consulta a.present passou',
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// E — o conserto não abriu a leitura por acidente
// ═══════════════════════════════════════════════════════════════════════════
test('E · get_event_detail continua member-scoped (service_role é recusado)', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  // service_role não tem auth.uid() → a função fail-closes em 'Unauthorized'. O padrão do #1326:
  // o comportamento por audiência é verificado com JWT impersonado em QA manual, porque
  // supabase-js não seta request.jwt.claims e chama a RPC na mesma transação.
  const { data, error } = await c.rpc('get_event_detail', {
    p_event_id: '00000000-0000-0000-0000-000000000000',
  });
  assert.ifError(error);
  assert.equal(data?.error, 'Unauthorized',
    `esperava fail-closed sem auth.uid(), veio: ${JSON.stringify(data)?.slice(0, 200)}`);
});
