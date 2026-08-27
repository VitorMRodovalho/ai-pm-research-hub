// tests/contracts/1948-selo-nao-marca-falta-antes-da-entrada.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1948 — o selo para de gravar falta em reunião ANTERIOR à entrada da pessoa.
 *
 * SINTOMA: o primeiro lote do selo (27/08/2026) gravou 80 faltas, e 17 delas eram de reuniões que
 * aconteceram antes de a pessoa existir na organização. A mais antiga, de 09/07, caiu em quem
 * entrou mais de um mês depois. São as únicas faltas do conjunto indefensáveis POR CONSTRUÇÃO:
 * não dependem de memória de ninguém nem de fonte externa. A pessoa não podia estar lá.
 *
 * DECISÃO DO PM (27/08): o corte é a ENTRADA NA TRIBO.
 *
 * DUAS ESCOLHAS DE DESENHO que este arquivo protege, porque as duas têm um jeito plausível e
 * errado de "consertar":
 *
 *  (1) O predicado é o PRIMEIRO ENGAJAMENTO, não o de tribo. Medido: 2 das 72 pessoas da coorte
 *      operacional não têm engajamento de tribo nenhum (entram por manager/deputy). Um predicado
 *      só-tribo devolveria NULL para elas e as tiraria do selo inteiro — trocaria este defeito por
 *      outro, pior porque silencioso. Para quem entra por tribo as duas definições coincidem (as
 *      17 linhas de hoje são as mesmas nas duas).
 *      E `min(granted_at)` NÃO filtra `revoked_at IS NULL`: um engajamento desde então revogado
 *      ainda PROVA presença na data. Filtrar revogados fez a primeira medição dizer 18 em vez
 *      de 17.
 *
 *  (2) A coorte NÃO encolhe. O selo carrega uma invariante declarada no próprio corpo
 *      (#1729/#1657): "materializa a linha de no-show, então selado + sem linha não ocorre".
 *      As TRÊS grades leem `roster_sealed_at IS NOT NULL` + linha ausente como 'absent'. Tirar a
 *      pessoa da coorte moveria o defeito para a leitura — mesmas faltas falsas, agora sem
 *      nenhuma linha para auditar. A distinção vai na COLUNA (`excused` + motivo), não na
 *      presença da linha.
 *
 * Cross-ref: #1948, #1710 (superfície do selo), #1729 (coorte vazia), #1657 (sem linha ≠ falta).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const MOTIVO = 'Ingresso posterior ao evento (#1948)';

// O predicado vive no BANCO (SSOT); resolvê-lo em JS seria uma segunda definição. Mas resolver um
// por vez são ~70 round-trips por teste, e três testes exercem populações que se sobrepõem — daí
// um memo de ARQUIVO, resolvido em lotes. Mede-se a mesma coisa, em 1/4 do tempo.
const _since = new Map();
async function sinceOf(s, ids) {
  const faltam = [...new Set(ids)].filter((id) => !_since.has(id));
  for (let i = 0; i < faltam.length; i += 8) {
    const lote = faltam.slice(i, i + 8);
    const vs = await Promise.all(lote.map((id) => s.rpc('_member_operational_since', { p_member_id: id })));
    lote.forEach((id, k) => _since.set(id, vs[k]?.data ?? null));
  }
  return _since;
}

// A captura CORRENTE, nunca um arquivo fixado (#1932): um guard preso a um `.sql` segue verde
// descrevendo um corpo que produção não executa mais.
const SEAL = latestFunctionCapture(ROOT, '_seal_event_attendance_apply');
const SINCE = latestFunctionCapture(ROOT, '_member_operational_since');

// ─────────────────────────────────────────────────────────────────────────────
// Estático — sobre a captura corrente
// ─────────────────────────────────────────────────────────────────────────────

test('#1948 estático: existe UMA definição de "desde quando a pessoa era esperada"', () => {
  assert.ok(SINCE, '_member_operational_since não foi capturada por nenhuma migration');
  const b = SINCE.body;
  assert.match(b, /min\(\s*en\.granted_at\s*\)/, 'o corte sai do PRIMEIRO engajamento');
  assert.match(b, /engagements/, 'lê engagements');
  // A escolha deliberada: revogado CONTA. Se alguém "consertar" filtrando revogados, a pessoa
  // passa a parecer ter entrado depois do que entrou — foi exatamente o que inflou 17 para 18.
  assert.doesNotMatch(b, /revoked_at\s+IS\s+NULL/i,
    'min(granted_at) NÃO pode filtrar revogados: revogado ainda prova presença na data');
  assert.match(b, /created_at/, 'tem fallback para quem não tem engajamento nenhum');
});

test('#1948 estático: o selo aplica o corte, e aplica na COLUNA — não na coorte', () => {
  assert.ok(SEAL, '_seal_event_attendance_apply não foi capturada');
  const b = SEAL.body;
  assert.match(b, /_member_operational_since/, 'o selo consulta o SSOT do corte');
  assert.match(b, /excuse_reason/, 'a linha carrega o MOTIVO, não só o booleano');
  assert.match(b, /Ingresso posterior ao evento/, 'o motivo é explícito e auditável');

  // A coorte tem de continuar com os TRÊS filtros originais. Se um sumir, alguém "consertou"
  // encolhendo a coorte — e aí selado+sem-linha volta a ler como falta nas três grades.
  for (const cond of [/is_active\s*=\s*true/, /current_cycle_active\s*=\s*true/,
                      /v_member_operational_tiers/, /_attendance_eligible_events/]) {
    assert.match(b, cond, `a coorte perdeu um filtro (${cond}) — o corte não pode encolher a coorte`);
  }
  // E o corte NÃO pode aparecer como filtro de linha na cláusula da coorte.
  assert.doesNotMatch(b, /WHERE[\s\S]{0,400}v_date\s*>=\s*public\._member_operational_since/i,
    'o corte virou filtro de coorte: isso quebra a invariante "selado => linha existe"');
});

test('#1948 estático: o ensaio separa as duas naturezas', () => {
  const b = SEAL.body;
  assert.match(b, /would_write_excused_pre_entry_n/,
    'sem esta chave o PM lê "N faltas" no ensaio e parte delas não é falta');
  assert.match(b, /sealed_excused_pre_entry_count/, 'o log de auditoria também separa');
});

// ─────────────────────────────────────────────────────────────────────────────
// Vivo — o invariante e os DOIS controles
// ─────────────────────────────────────────────────────────────────────────────

test('#1948 vivo: nenhuma falta em evento selado é anterior à entrada da pessoa',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  const { data: rows, error: e2 } = await s
    .from('attendance')
    .select('id, present, excused, excuse_reason, event_id, member_id, events!inner(date, roster_sealed_at)')
    .not('events.roster_sealed_at', 'is', null)
    .eq('present', false)
    .neq('excused', true)
    .limit(2000);
  assert.ok(!e2, e2?.message);

  const ids = [...new Set((rows ?? []).map((r) => r.member_id))];
  const since = await sinceOf(s, ids);
  const violacoes = (rows ?? []).filter((r) => {
    const d = since.get(r.member_id);
    return d && r.events?.date && r.events.date < d;
  });
  assert.equal(violacoes.length, 0,
    `${violacoes.length} faltas anteriores à entrada seguem gravadas em evento selado`);

  // CONTROLE POSITIVO: um zero só vale se a consulta enxerga alguma coisa. Sem isto, uma junção
  // quebrada devolve o mesmo zero e o guard fica verde por vacuidade.
  assert.ok((rows ?? []).length > 0, 'nenhuma falta lida — o guard passaria por vacuidade');
  assert.ok(ids.length > 0, 'nenhum membro resolvido — o predicado não foi exercido');
});

test('#1948 vivo: a correção não passou do ponto (ninguém que JÁ estava foi justificado)',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  const { data: rows, error } = await s
    .from('attendance')
    .select('member_id, events!inner(date)')
    .eq('excuse_reason', MOTIVO)
    .limit(1000);
  assert.ok(!error, error?.message);
  assert.ok((rows ?? []).length > 0, 'nenhuma linha corrigida — o controle não mede nada');

  const since2 = await sinceOf(s, (rows ?? []).map((r) => r.member_id));
  let excesso = 0;
  for (const r of rows ?? []) {
    const d = since2.get(r.member_id);
    if (d && r.events?.date && r.events.date >= d) excesso += 1;
  }
  assert.equal(excesso, 0,
    `${excesso} linhas foram justificadas para gente que JÁ estava na organização na data`);
});

test('#1948 vivo: ninguém aparece PRESENTE antes da própria entrada',
  { skip: dbGated ? false : skipMsg }, async () => {
  // Este é o controle que valida o PREDICADO em si, não a correção. Se alguém está marcado
  // presente numa reunião anterior à sua entrada, ou a presença é falsa ou a data de entrada é —
  // e nos dois casos o corte do selo está apoiado em areia.
  const s = sb();
  const { data: rows, error } = await s
    .from('attendance')
    .select('member_id, events!inner(date, roster_sealed_at)')
    .eq('present', true)
    .not('events.roster_sealed_at', 'is', null)
    .limit(2000);
  assert.ok(!error, error?.message);
  assert.ok((rows ?? []).length > 0, 'nenhuma presença lida — controle vazio');

  const cache = await sinceOf(s, (rows ?? []).map((r) => r.member_id));
  let antes = 0;
  for (const r of rows ?? []) {
    const d = cache.get(r.member_id);
    if (d && r.events?.date && r.events.date < d) antes += 1;
  }
  assert.equal(antes, 0,
    `${antes} presenças registradas ANTES da entrada — o predicado de corte não é confiável`);
});

test('#1948 vivo: o helper não é executável por anon', { skip: dbGated ? false : skipMsg }, async () => {
  // `CREATE FUNCTION` nasce com EXECUTE para PUBLIC, e portanto para anon.
  const anonKey = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
  if (!anonKey) return; // sem chave anon no ambiente, não há o que exercer
  const anon = createClient(SUPABASE_URL, anonKey, { auth: { persistSession: false } });
  const { error } = await anon.rpc('_member_operational_since',
    { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(error, 'anon conseguiu executar _member_operational_since');
});
