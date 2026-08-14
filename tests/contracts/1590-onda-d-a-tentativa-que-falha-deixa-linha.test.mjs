/**
 * Contract: #1590 onda D — a tentativa de agendamento que falha deixa linha.
 *
 * Antes desta onda, o candidato que abria a agenda e não achava horário tinha registro IDÊNTICO
 * ao de quem nunca clicou (`interview_pending` / `interview_status = none`), e por isso qualquer
 * taxa de sucesso de agendamento dizia 100% por construção. Medido em 13/08/2026 na janela de
 * agosto (a única em que o token existe): 12 despachos · 12 com token · 6 aberturas · 5 reservas
 * → 2 abriram e não reservaram, 5 nunca abriram. Uma das duas voltou 7 vezes em 6 dias.
 *
 * Quatro decisões de forma, e cada uma tem uma INVERSA que este teste proíbe:
 *
 * 1. DESFECHO DERIVADO NA LEITURA, nunca coluna de estado. Uma coluna `outcome` precisaria de cron
 *    para se manter e poderia divergir das linhas que ela resume — a classe que fez a taxa de
 *    presença dizer 100,0 enquanto a grade dizia 61,0. O teste proíbe a coluna existir.
 *
 * 2. `instrumented` SEPARA "não abriu" DE "não foi medido". As 94 linhas anteriores nascem `false`
 *    e a leitura devolve `pre_instrumentation`. Sem isso o primeiro relatório publicaria 94
 *    agendamentos fracassados que nunca fracassaram — o mesmo `ELSE 'absent'` do #1657.
 *
 * 3. HASH DO TOKEN, nunca o token. `selection_dispatch_url_log` tem duas policies PERMISSIVAS e a
 *    de escopo de organização vence a de negação: qualquer autenticado da org lê a tabela inteira.
 *    O token é a credencial de acesso à página de agendamento do candidato.
 *
 * 4. SUPERSEDE antes do INSERT. Um reenvio não é a mesma pessoa falhando duas vezes; sem o
 *    supersede, cada reenvio deixaria para trás uma oferta eternamente "nunca reservada" e o funil
 *    contaria a mesma pessoa N vezes no numerador do fracasso.
 *
 * Camada A (estática, sobre a migration e a EF) + camada B (VIVA, sobre o banco): um guard que só
 * lê arquivo fica verde com o mecanismo inerte, e é exatamente o que aconteceu no #1649.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const EF = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

const MIGRATION = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.includes('1590_onda_d_a_tentativa_que_falha_deixa_linha'))
  .sort()
  .pop();

/** As três funções que a onda toca, pela chave publicada (nome@args), não pelo nome só. */
const CHAVES = {
  funil: 'get_interview_booking_funnel@p_cycle_id uuid',
  despacho: '_dispatch_interview_booking_link@p_application_id uuid, p_caller_id uuid, p_source text',
  abertura: 'validate_interview_booking_token@p_token text',
  fechamento: 'trg_close_dispatch_on_interview@',
};

function captura(chave) {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(chave);
  assert.ok(cap, `sem captura de migration para ${chave}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find((b) => `${b.name}@${b.args}` === chave);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${chave}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/**
 * Comentários FORA antes de qualquer asserção de ausência. O cabeçalho desta migration cita
 * literalmente os predicados que ela proíbe ("não existe coluna `outcome`"), e um guard de
 * ausência sobre o fonte cru casaria o próprio comentário — o defeito medido no #1586b.
 */
const semComentarios = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

const SQL = MIGRATION ? semComentarios(readFileSync(join(MIGRATIONS_DIR, MIGRATION), 'utf8')) : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const anonSkipMsg = 'Skipped: SUPABASE_URL + PUBLIC_SUPABASE_ANON_KEY required';

async function rest(caminho, init) {
  return fetch(`${SUPABASE_URL}/rest/v1/${caminho}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      ...(init?.headers ?? {}),
    },
  });
}

// ── A · a migration existe e diz o que a onda decidiu ────────────────────────────────────────

test('A1: a migration da onda D está no repositório', () => {
  assert.ok(MIGRATION, 'nenhuma migration 1590_onda_d_* encontrada em supabase/migrations');
});

test('A2: as colunas de FATO entram, e nenhuma coluna de ESTADO entra junto', () => {
  for (const col of ['booking_token_md5', 'first_opened_at', 'last_opened_at', 'open_count',
                     'booked_at', 'booked_interview_id', 'superseded_at', 'instrumented']) {
    assert.match(SQL, new RegExp(`ADD COLUMN IF NOT EXISTS\\s+${col}\\b`),
      `a coluna de fato ${col} não é adicionada`);
  }
  // A inversa da decisão 1: uma coluna de desfecho armazenada precisaria de cron e derivaria.
  assert.doesNotMatch(SQL, /ADD COLUMN IF NOT EXISTS\s+outcome\b/,
    'o desfecho voltou a ser COLUNA. Ele é derivado na leitura justamente para não precisar de cron nem poder divergir das linhas que resume.');
});

test('A3: `instrumented` nasce false para as antigas e passa a true para as novas', () => {
  assert.match(SQL, /ADD COLUMN IF NOT EXISTS\s+instrumented\s+boolean NOT NULL DEFAULT false/,
    'o ADD precisa usar DEFAULT false para retro-preencher as linhas anteriores como NÃO medidas');
  assert.match(SQL, /ALTER COLUMN instrumented SET DEFAULT true/,
    'sem o segundo default, toda oferta NOVA nasceria marcada como não-medida e o funil ficaria mudo para sempre');
  // A inversa: um UPDATE em vez do duplo default é correto hoje e marca linhas JÁ medidas como
  // não-medidas se a migration reaplicar, porque o ADD COLUMN IF NOT EXISTS é idempotente e ele não.
  assert.doesNotMatch(SQL, /UPDATE public\.selection_dispatch_url_log SET instrumented = false/,
    'o retro-preenchimento voltou a ser UPDATE: reaplicar a migration apagaria a medição das ofertas novas');
});

test('A4: o log guarda o HASH do token, nunca o token', () => {
  assert.match(SQL, /booking_token_md5\s*\)?[\s\S]{0,400}md5\(\s*v_token\s*\)/,
    'a inserção precisa gravar md5(token)');
  assert.doesNotMatch(SQL, /booking_token\s+text[^_]/,
    'apareceu uma coluna de token em claro: a tabela é legível por qualquer autenticado da org (policy permissiva de escopo)');
});

test('A5: o supersede roda ANTES do INSERT da oferta nova', () => {
  const supersede = SQL.indexOf('SET superseded_at = now()');
  const insert = SQL.indexOf('INSERT INTO public.selection_dispatch_url_log');
  assert.ok(supersede > -1, 'o supersede da oferta anterior sumiu do despacho');
  assert.ok(insert > -1, 'o INSERT da linha de despacho sumiu');
  assert.ok(supersede < insert,
    'o supersede passou a rodar DEPOIS do INSERT — nessa ordem ele aposenta a própria linha que acabou de nascer');
});

test('A6: os sete desfechos derivados existem, e pre_instrumentation não afirma falta', () => {
  for (const d of ['pre_instrumentation', 'booked', 'superseded', 'opened_never_booked',
                   'opened_waiting', 'never_opened_expired', 'never_opened_waiting']) {
    assert.ok(SQL.includes(`'${d}'`), `o desfecho ${d} não é derivado pela RPC de leitura`);
  }
  // A ordem do CASE é o contrato: `NOT instrumented` tem de ser o PRIMEIRO ramo, senão uma linha
  // não medida cairia em never_opened_* e viraria uma falta inventada.
  const caseIdx = SQL.indexOf("WHEN NOT l.instrumented");
  const nuncaAbriu = SQL.indexOf("'never_opened_expired'");
  assert.ok(caseIdx > -1 && caseIdx < nuncaAbriu,
    'o ramo `NOT instrumented` deixou de ser o primeiro: linha não medida passa a ser acusada de nunca ter sido aberta');
});

test('A7: a RPC nova é revogada de PUBLIC/anon, e a do candidato continua alcançável', () => {
  assert.match(SQL, /REVOKE EXECUTE ON FUNCTION public\.get_interview_booking_funnel\(uuid\) FROM PUBLIC, anon/,
    'CREATE FUNCTION concede EXECUTE a PUBLIC por padrão (#1710, #1592)');
  assert.doesNotMatch(SQL, /REVOKE EXECUTE ON FUNCTION public\.validate_interview_booking_token/,
    'validate_interview_booking_token é a página do CANDIDATO, que não está logado: revogar anon dela fecha a porta do agendamento');
});

// ── A · a superfície MCP ─────────────────────────────────────────────────────────────────────

test('A8: o funil entrou como SCOPE de selection_dashboard, sem tool nova', () => {
  assert.match(EF, /"funnel"/, 'o scope funnel não está no enum de selection_dashboard');
  assert.match(EF, /sb\.rpc\("get_interview_booking_funnel", \{ p_cycle_id: params\.cycle_id \}\)/,
    'o scope funnel não despacha para a RPC');
  assert.match(EF, /case "funnel":[\s\S]{0,600}isUUID\(params\.cycle_id\)/,
    'o scope funnel precisa validar cycle_id como UUID antes de chamar a RPC');
});

// ── B · o mundo (pula sem credencial; roda no CI com os secrets) ─────────────────────────────

test('B1: as colunas de fato existem no banco VIVO', { skip: dbGated ? false : skipMsg }, async () => {
  // Um SELECT nomeando as 8 colunas: 200 prova que existem, 400 prova que a migration não chegou
  // àquele banco. É a leitura mais barata que observa o MUNDO em vez do arquivo.
  const res = await rest('selection_dispatch_url_log?select=booking_token_md5,first_opened_at,last_opened_at,open_count,booked_at,booked_interview_id,superseded_at,instrumented&limit=1');
  assert.equal(res.status, 200,
    `as colunas de fato da onda D não existem no banco vivo (PostgREST devolveu ${res.status}: ${await res.text()})`);
});

test("B2: o corpo VIVO das funções da onda bate com a captura", { skip: dbGated ? false : skipMsg }, async () => {
  // `_audit_list_public_function_bodies` normaliza e hasheia TODO corpo público (1.082 SECDEF), e
  // sob contenção ele estoura o statement_timeout do PostgREST — medido 504 duas vezes em 14/08,
  // com a MESMA árvore que respondeu 200 em 4,5s minutos antes. A retentativa mira esse transiente
  // e só ele: uma deriva de verdade devolve 200 com hash diferente, e continua vermelha.
  let res = await rest('rpc/_audit_list_public_function_bodies', { method: 'POST', body: '{}' });
  if (res.status !== 200) {
    await new Promise((r) => setTimeout(r, 5000));
    res = await rest('rpc/_audit_list_public_function_bodies', { method: 'POST', body: '{}' });
  }
  assert.equal(res.status, 200, `_audit_list_public_function_bodies devolveu ${res.status} em duas tentativas`);
  const linhas = await res.json();
  assert.ok(Array.isArray(linhas) && linhas.length > 0, 'catálogo vivo veio vazio');

  for (const [rotulo, chave] of Object.entries(CHAVES)) {
    const [nome, args] = chave.split('@');
    const viva = linhas.find((l) => l.proname === nome
      && normalizeBody(l.identity_args ?? '') === normalizeBody(args ?? ''));
    assert.ok(viva, `${rotulo}: ${nome}(${args}) não está no catálogo vivo`);
    const { bodyHash, file } = captura(chave);
    assert.equal(viva.body_md5, bodyHash,
      `${rotulo}: o corpo VIVO divergiu de ${file}. Alguém aplicou DDL fora de migration, ou a migration foi editada depois de aplicada.`);
  }
});

test('B3: anon BATE NA PORTA do funil e é recusado', { skip: anonGated ? false : anonSkipMsg }, async () => {
  // Sonda DIRETA, não varredura de catálogo. `_audit_secdef_public_grant_drift` responderia a
  // mesma pergunta, mas ele percorre os 1.082 SECDEF e estoura o statement_timeout do PostgREST
  // sob contenção (medido 504 em 14/08; é a mesma classe do #1742). Um gate que fica vermelho por
  // carga do banco ensina a ignorar vermelho.
  //
  // E esta forma é MAIS forte que a varredura: ela exerce a porta em vez de inspecionar o grant.
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_interview_booking_funnel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
    body: JSON.stringify({ p_cycle_id: '00000000-0000-0000-0000-000000000000' }),
  });
  assert.notEqual(res.status, 200,
    `anon EXECUTOU get_interview_booking_funnel (HTTP 200): o REVOKE da migration não está valendo e a rota expõe PII de candidato. Corpo: ${await res.text()}`);
});

test('B4: nenhuma linha guarda token em claro', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await rest('selection_dispatch_url_log?select=id,booking_token_md5&booking_token_md5=not.is.null');
  assert.equal(res.status, 200, `leitura do log de despacho devolveu ${res.status}`);
  const linhas = await res.json();
  const fora = linhas.filter((l) => !/^[0-9a-f]{32}$/.test(String(l.booking_token_md5)));
  assert.deepEqual(fora.map((l) => l.id), [],
    'há valor em booking_token_md5 que não é um md5 hex de 32 caracteres — provável token em claro numa tabela que qualquer autenticado da org lê');
});

test('B5: nenhuma oferta anterior à medição foi marcada como instrumentada', { skip: dbGated ? false : skipMsg }, async () => {
  // A inversa da decisão 2, observada no mundo: se alguém reaplicar a migration com um UPDATE, ou
  // retro-marcar as antigas, elas passam a ser cobradas por uma reserva que ninguém mediu.
  const res = await rest('selection_dispatch_url_log?select=id,dispatched_at,instrumented,booking_token_md5&instrumented=is.true&booking_token_md5=is.null');
  assert.equal(res.status, 200, `leitura do log de despacho devolveu ${res.status}`);
  const linhas = await res.json();
  assert.deepEqual(linhas.map((l) => l.id), [],
    'há oferta marcada como instrumentada SEM hash de token: ela nunca passou pelo despacho instrumentado e vai ser contada como agendamento fracassado');
});
