import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

/**
 * #1548 — a Agenda Viva e a pauta/ata eram superfícies DISJUNTAS. Medido em 31/07/2026:
 *
 *   * `get_meeting_preparation` (o `action='prepare'` do `meeting_minutes` no MCP) lia
 *     `events.agenda_text` e NUNCA `event_agenda_blocks`. E como toda Reunião Geral tem
 *     `initiative_id` NULL enquanto cada bloco do resultado era escopado por
 *     `initiative_id IS NOT NULL`, o briefing da reunião de maior presença voltava VAZIO.
 *   * `meeting_close` não dizia nada sobre bloco pendente. A Geral de 30/07 teve 45 presenças,
 *     7 blocos, 0 confirmados e 0 XP — descoberto um dia depois, por acaso.
 *
 * A invariante que estes testes defendem NÃO é "o número tal": é que **pendência fica visível** nas
 * três superfícies, e que nenhuma delas CONFIRMA por conta própria — conceder XP é veredito humano
 * (mesma regra do #1534/#1537).
 */

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = URL && KEY ? createClient(URL, KEY, { auth: { persistSession: false } }) : null;

const MIGRATION = 'supabase/migrations/20260805000499_agenda_blocks_reach_the_meeting_surfaces.sql';
const sql = () => readFileSync(MIGRATION, 'utf8');

const corpoDe = (src, nome) => {
  const i = src.indexOf(`CREATE OR REPLACE FUNCTION public.${nome}`);
  assert.ok(i >= 0, `${nome} não está na migration`);
  const rest = src.slice(i);
  return rest.slice(0, rest.indexOf('$function$;'));
};

// ── 1) A regra de PII mora em UM lugar ────────────────────────────────────────
test('#1548 estático: get_geral_agenda_viva CHAMA a regra, não a reimplementa', () => {
  const corpo = corpoDe(sql(), 'get_geral_agenda_viva');
  assert.match(
    corpo, /public\._agenda_block_owner_visible\(/,
    'a função tem de delegar a decisão de PII ao helper',
  );
  // O tell da volta da duplicata: o teste `status = 'no_show'` inline no CASE do owner_first_name.
  assert.ok(
    !/'owner_first_name',\s*CASE\s*\n\s*WHEN bk\.status = 'no_show'/.test(corpo),
    'a regra LGPD PD-5 voltou a ser inline aqui. Duas cópias divergem, e a que divergir vira ' +
    'vazamento: o nome de quem não apresentou passa a aparecer para o público.',
  );
});

test('#1548 DB: a regra de PII falha FECHANDO, inclusive com NULL', async (t) => {
  if (!sb) return t.skip('sem SUPABASE_URL/SERVICE_ROLE_KEY');
  const casos = [
    // [status, is_mine, is_admin, esperado_visivel]
    ['no_show', false, false, false],
    ['no_show', true, false, true],
    ['no_show', false, true, true],
    ['reserved', false, false, true],
    ['confirmed', false, false, true],
    ['no_show', null, null, false], // fail-closed: sem informação, esconde
  ];
  for (const [status, mine, admin, esperado] of casos) {
    const { data, error } = await sb.rpc('_agenda_block_owner_visible', {
      p_status: status, p_is_mine: mine, p_is_admin: admin,
    });
    assert.equal(error, null, `erro na sonda (${status}/${mine}/${admin}): ${error?.message}`);
    assert.equal(
      data, esperado,
      `visibilidade errada para status=${status} is_mine=${mine} is_admin=${admin}`,
    );
  }
});

// ── 2) prepare enxerga a pauta real ───────────────────────────────────────────
test('#1548 estático: get_meeting_preparation lê os blocos e não só agenda_text', () => {
  const corpo = corpoDe(sql(), 'get_meeting_preparation');
  assert.match(corpo, /'agenda_blocks'/, 'o briefing precisa carregar os blocos');
  assert.match(corpo, /public\.event_agenda_blocks/, 'precisa LER a tabela, não só declarar a chave');
  // TODA ocorrência tem de ser gateada, não "pelo menos uma". A primeira versão deste guard usava
  // `match` e sobrevivia a tirar o gate de um dos dois lugares (topo e dentro de recent_meetings) —
  // descoberto por mutação. Guard que aceita "existe pelo menos um" não protege o outro.
  const ocorrencias = [...corpo.matchAll(/'agenda_blocks_pending',\s*/g)];
  assert.ok(ocorrencias.length >= 2, 'esperadas 2 ocorrências de agenda_blocks_pending (topo + recent_meetings)');
  for (const m of ocorrencias) {
    const depois = corpo.slice(m.index + m[0].length, m.index + m[0].length + 40);
    assert.match(
      depois, /^CASE WHEN v_is_admin THEN/,
      'a CONTAGEM de pendentes é justamente a linha que o #1071 esconde do membro comum — TODA ' +
      'ocorrência tem de ser gateada por manage_event. NULL = "não divulgado"; 0 seria mentira. ' +
      `Ocorrência sem gate perto de: ${JSON.stringify(depois)}`,
    );
  }
  // O recorte por status tem de acompanhar o de get_geral_agenda_viva, senão as duas divergem.
  assert.match(
    corpo, /v_is_past AND v_is_admin AND b\.status = 'reserved'/,
    'passado+reserved só para quem tem manage_event (#1071)',
  );
});

test('#1548 estático: o escopo por iniciativa não pode zerar evento org-wide', () => {
  const corpo = corpoDe(sql(), 'get_meeting_preparation');
  // `recent_meetings` era escopado só por initiative_id; toda Reunião Geral tem initiative_id NULL,
  // então voltava vazia justamente onde mais importa.
  assert.match(
    corpo, /ELSE e3\.initiative_id IS NULL AND e3\.type = v_event\.type/,
    'sem o ramo org-wide, "reuniões recentes" volta vazia para toda Reunião Geral',
  );
});

// ── 3) meeting_close reporta, e NUNCA confirma ────────────────────────────────
test('#1548 estático: meeting_close reporta bloco pendente', () => {
  const corpo = corpoDe(sql(), 'meeting_close');
  for (const chave of ['agenda_blocks_total', 'agenda_blocks_pending', 'agenda_blocks_pending_list', 'blocks_pending_signal']) {
    assert.ok(corpo.includes(`'${chave}'`), `o envelope perdeu ${chave}`);
  }
});

test('#1548 estático: NENHUMA das três superfícies ESCREVE em event_agenda_blocks', () => {
  const src = sql();
  for (const fn of ['get_meeting_preparation', 'meeting_close', 'detect_agenda_blocks_pending_cron', '_agenda_blocks_pending_rows']) {
    const corpo = corpoDe(src, fn);
    assert.ok(
      !/(UPDATE|INSERT INTO|DELETE FROM)\s+public\.event_agenda_blocks/.test(corpo),
      `${fn} escreve em event_agenda_blocks. Conceder XP é veredito humano sobre quem de fato ` +
      'apresentou (#1534/#1537) — estas superfícies REPORTAM, nunca confirmam.',
    );
  }
});

// ── 4) o cron é alcançável, e só por quem deve ────────────────────────────────
test('#1548 estático: o cron NÃO tem gate de auth.uid() e tem ACL apertada', () => {
  const src = sql();
  const corpo = corpoDe(src, 'detect_agenda_blocks_pending_cron');
  assert.ok(
    !/auth\.uid\(\)/.test(corpo),
    'sob pg_cron não há JWT: auth.uid() é NULL, o gate nega, e o job roda VERDE e VAZIO todo dia ' +
    '(medido no #1543). A proteção aqui é o ACL, não um gate de usuário.',
  );
  for (const papel of ['anon', 'authenticated']) {
    assert.ok(
      new RegExp(`REVOKE ALL ON FUNCTION public\\.detect_agenda_blocks_pending_cron\\(\\) FROM ${papel}`).test(src),
      `sem REVOKE de ${papel}, qualquer um dispara o detector (é o furo que ` +
      'detect_recurrence_stockout_cron tem hoje — ver #1548)',
    );
  }
});

test('#1548 DB: o detector é chamável pelo service_role (a porta do cron existe de fato)', async (t) => {
  if (!sb) return t.skip('sem SUPABASE_URL/SERVICE_ROLE_KEY');
  // Leitura pura: audita o conjunto detectado sem disparar o alerta. Se isto falhar, o cron
  // agendado rodaria quebrado — e um cron que falha é indistinguível de um cron sem nada a fazer.
  const { error } = await sb.rpc('_agenda_blocks_pending_rows', { p_horizon_days: 60 });
  assert.equal(error, null, `_agenda_blocks_pending_rows deveria ser chamável pelo service_role: ${error?.message}`);
});

test('#1548 DB: chamar o detector DUAS VEZES na mesma sessão não quebra', async (t) => {
  if (!sb) return t.skip('sem SUPABASE_URL/SERVICE_ROLE_KEY');
  // A primeira versão usava `CREATE TEMP TABLE ... ON COMMIT DROP`, que estoura com
  // "relation already exists" na segunda chamada dentro da mesma transação.
  const a = await sb.rpc('_agenda_blocks_pending_rows', { p_horizon_days: 60 });
  const b = await sb.rpc('_agenda_blocks_pending_rows', { p_horizon_days: 60 });
  assert.equal(a.error, null, `1ª chamada falhou: ${a.error?.message}`);
  assert.equal(b.error, null, `2ª chamada falhou: ${b.error?.message}`);
});

test('#1548 estático: o detector é idempotente por (destinatário, reunião)', () => {
  const corpo = corpoDe(sql(), 'detect_agenda_blocks_pending_cron');
  assert.match(
    corpo, /NOT EXISTS \([\s\S]*?n\.source_id = pm\.event_id[\s\S]*?n\.created_at >= now\(\) - interval '6 days'/,
    'sem a guarda por (destinatário, evento, janela) o alerta vira spam diário e ensina a ignorá-lo',
  );
});
