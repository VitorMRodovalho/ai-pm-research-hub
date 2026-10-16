/**
 * #2593, fatia C3a — o convidado externo já avisado acompanha o EVENTO.
 *
 * Medido em 16/10/2026: `update_event` não olhava os blocos, `events` não tinha gatilho para o convidado e não havia
 * lembrete. Um convidado convidado para 19h ficava com a agenda errada se a reunião mudasse, e não sabia se ela fosse
 * cancelada.
 *
 * O que este arquivo prova:
 *   (A) atualização e lembrete só para bloco confirmado E já avisado; um lembrete por bloco e horário;
 *   (B) o gatilho do evento: cancelar => cancelamento; mudar quando/onde => atualização; melhor-esforço;
 *   (C) o lembrete roda às 12:00 UTC para as reuniões de amanhã no fuso do evento, fora as canceladas;
 *   (D) os textos aprovados pelo GP em 16/10, nos 3 idiomas, com o rodapé de pessoa externa;
 *   (E) a EF: atualização e lembrete também exigem bloco confirmado; o lembrete sai sem ICS; só o convite carimba;
 *   (F) as asserções mordem; (G) camada viva.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const MIG_DIR = join(ROOT, 'supabase/migrations');
const MIG_FILE = readdirSync(MIG_DIR).filter((f) => /_2593_c3a_/.test(f));
const MIG = MIG_FILE.length === 1 ? maskLineComments(readFileSync(join(MIG_DIR, MIG_FILE[0]), 'utf8')) : '';
const EF = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/send-campaign/index.ts'), 'utf8'));

const body = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);

function violacoesEnvio(b) {
  const v = [];
  if (!/IF p_kind NOT IN \('invite', 'cancel', 'update', 'reminder'\) THEN\s+RAISE EXCEPTION/.test(b)) v.push('tipos aceitos');
  if (!/IF p_kind IN \('update', 'reminder'\) AND \(v_b\.status <> 'confirmed' OR v_b\.guest_notified_at IS NULL\) THEN\s+RETURN NULL;/.test(b)) {
    v.push('atualização/lembrete sem exigir bloco confirmado e já avisado');
  }
  if (!/IF p_kind = 'reminder' AND EXISTS \(\s+SELECT 1 FROM public\.campaign_sends s\s+WHERE s\.audience_filter->>'source' = 'agenda_guest' AND s\.audience_filter->>'kind' = 'reminder'\s+AND s\.audience_filter->>'block_id' = p_block_id::text\s+AND s\.audience_filter->'variables'->>'start_utc' = v_start_utc\s+AND s\.status <> 'failed'\) THEN\s+RETURN NULL;/.test(b)) {
    v.push('lembrete sem a trava de um por bloco e horário');
  }
  if (!/WHEN 'update' THEN 'agenda-atualizacao-convidado'\s+ELSE 'agenda-lembrete-convidado' END;/.test(b)) v.push('template por tipo');
  if (!/'start_utc', v_start_utc,/.test(b)) v.push('o envio não guarda o horário que a trava compara');
  return v;
}

function violacoesGatilho(b) {
  const v = [];
  if (!/IF NEW\.status = 'cancelled' AND OLD\.status IS DISTINCT FROM 'cancelled' THEN\s+v_kind := 'cancel';/.test(b)) v.push('cancelar a reunião não vira cancelamento');
  if (!/ELSIF NEW\.status IS DISTINCT FROM 'cancelled'\s+AND \(NEW\.date IS DISTINCT FROM OLD\.date OR NEW\.time_start IS DISTINCT FROM OLD\.time_start\s+OR NEW\.timezone IS DISTINCT FROM OLD\.timezone OR NEW\.meeting_link IS DISTINCT FROM OLD\.meeting_link\s+OR NEW\.duration_minutes IS DISTINCT FROM OLD\.duration_minutes\) THEN\s+v_kind := 'update';/.test(b)) {
    v.push('mudar quando/onde não vira atualização');
  }
  if (!/WHERE b\.event_id = NEW\.id AND b\.external_guest AND b\.status = 'confirmed' AND b\.guest_notified_at IS NOT NULL/.test(b)) v.push('alvo do gatilho');
  if (!/PERFORM public\._agenda_guest_send\(r\.id, v_kind, COALESCE\(v_actor, r\.owner_member_id\), true\);\s+EXCEPTION WHEN OTHERS THEN\s+RAISE WARNING/.test(b)) {
    v.push('o aviso não é melhor-esforço (uma falha travaria a mudança do evento)');
  }
  return v;
}

function violacoesCron(b) {
  const v = [];
  if (!/WHERE b\.external_guest AND b\.status = 'confirmed' AND b\.guest_notified_at IS NOT NULL\s+AND e\.status IS DISTINCT FROM 'cancelled'\s+AND e\.date = \(now\(\) AT TIME ZONE COALESCE\(e\.timezone, 'America\/Sao_Paulo'\)\)::date \+ 1/.test(b)) {
    v.push('o lembrete não pega só as reuniões de amanhã, confirmadas e não canceladas');
  }
  if (!/v_send := public\._agenda_guest_send\(r\.id, 'reminder', r\.owner_member_id, true\);/.test(b)) v.push('o cron não manda o lembrete');
  if (!/IF public\._request_is_rest_caller\(\) THEN\s+RAISE EXCEPTION/.test(b)) v.push('o cron fica chamável pela API');
  return v;
}

// ── A–C ───────────────────────────────────────────────────────────────────────────────
test('#2593 C3a: atualização e lembrete só para bloco confirmado e já avisado', () => {
  assert.deepEqual(violacoesEnvio(body('_agenda_guest_send')), []);
});

test('#2593 C3a: o gatilho do evento avisa o convidado já avisado', () => {
  assert.deepEqual(violacoesGatilho(body('_trg_event_agenda_guest_lifecycle')), []);
  assert.match(MIG,
    /CREATE TRIGGER trg_event_agenda_guest_lifecycle\s+AFTER UPDATE OF date, time_start, timezone, meeting_link, duration_minutes, status ON public\.events\s+FOR EACH ROW EXECUTE FUNCTION public\._trg_event_agenda_guest_lifecycle\(\);/);
});

test('#2593 C3a: lembrete às 9h de Brasília, para as reuniões de amanhã', () => {
  assert.deepEqual(violacoesCron(body('_agenda_guest_reminder_cron')), []);
  assert.match(MIG, /SELECT cron\.schedule\(\s+'agenda-guest-reminder',\s+'0 12 \* \* \*',\s+\$cron\$SELECT public\._agenda_guest_reminder_cron\(\);\$cron\$\s+\);/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_reminder_cron\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._trg_event_agenda_guest_lifecycle\(\) FROM PUBLIC, anon, authenticated;/);
});

// ── D ─────────────────────────────────────────────────────────────────────────────────
test('#2593 C3a: textos aprovados pelo GP em 16/10, nos 3 idiomas, sem travessão', () => {
  const raw = readFileSync(join(MIG_DIR, MIG_FILE[0]), 'utf8');
  for (const trecho of [
    "'Atualizado: {{block_title}} na Reunião Geral do Núcleo IA & GP, {{date}}'",
    'A Reunião Geral em que você vai participar mudou. Os dados atualizados do seu bloco:',
    'O convite em anexo atualiza o horário na sua agenda. Se não puder participar no novo horário, responda a este e-mail.',
    "'Amanhã: {{block_title}} na Reunião Geral do Núcleo IA & GP'",
    'Lembrete: o seu bloco na Reunião Geral do Núcleo IA & GP é amanhã.',
    'Se algo mudou do seu lado, responda a este e-mail.',
    "'Updated: {{block_title}}", "'Actualizado: {{block_title}}", "'Tomorrow: {{block_title}}", "'Mañana: {{block_title}}",
  ]) {
    assert.ok(raw.includes(trecho), `texto aprovado ausente: ${trecho}`);
  }
  const textos = raw.slice(raw.indexOf('DO $templates$'), raw.indexOf('$templates$;'));
  assert.doesNotMatch(textos, /—/, 'sem travessão longo nos textos');
  // o lembrete não promete anexo
  const lembrete = textos.slice(textos.indexOf('v_rem'));
  assert.doesNotMatch(lembrete.slice(0, lembrete.indexOf('r record;')), /anexo|attach|adjunt/i);
  // o rodapé vem do avulso, uma fonte só
  assert.match(MIG, /SELECT body_html, body_text INTO v_base FROM public\.campaign_templates WHERE slug = 'avulso-corpo-livre';/);
});

// ── E ─────────────────────────────────────────────────────────────────────────────────
function violacoesEF(ef) {
  const v = [];
  if (!/const agendaGuestKind = String\(send\.audience_filter\?\.kind \?\? ''\)\s+if \(isAgendaGuest && \['invite', 'update', 'reminder'\]\.includes\(agendaGuestKind\)\) \{\s+const \{ data: blk \}/.test(ef)) {
    v.push('atualização/lembrete de bloco não confirmado sairiam');
  }
  if (!/if \(agendaGuestKind !== 'reminder'\) \{\s+try \{\s+const icsText = buildAgendaIcs\(\{/.test(ef)) v.push('o lembrete sairia com ICS');
  const a = ef.indexOf('if (res.ok) {');
  const ok = ef.slice(a, ef.indexOf('errors.push(`${toEmail}: ${rt}`)', a));
  if (!/if \(isAgendaGuest && !sandbox && send\.audience_filter\?\.kind === 'invite' && send\.audience_filter\?\.block_id\)/.test(ok)) {
    v.push('só o convite carimba o aviso');
  }
  return v;
}

test('#2593 C3a EF: confirmado para todos os tipos, lembrete sem ICS, só o convite carimba', () => {
  assert.deepEqual(violacoesEF(EF), []);
});

// ── F ─────────────────────────────────────────────────────────────────────────────────
const MUT_ENVIO = [
  ['update sem exigir aviso', (b) => b.replace("IF p_kind IN ('update', 'reminder') AND (v_b.status <> 'confirmed' OR v_b.guest_notified_at IS NULL) THEN", "IF p_kind IN ('update', 'reminder') AND v_b.status <> 'confirmed' THEN")],
  ['lembrete sem trava de horário', (b) => b.replace("AND s.audience_filter->'variables'->>'start_utc' = v_start_utc", '')],
  ['tipo novo recusado', (b) => b.replace("IF p_kind NOT IN ('invite', 'cancel', 'update', 'reminder') THEN", "IF p_kind NOT IN ('invite', 'cancel') THEN")],
];
const MUT_GATILHO = [
  ['cancelamento vira atualização', (b) => b.replace("v_kind := 'cancel';", "v_kind := 'update';")],
  ['link deixa de contar', (b) => b.replace('OR NEW.meeting_link IS DISTINCT FROM OLD.meeting_link', '')],
  ['falha trava o evento', (b) => b.replace(/EXCEPTION WHEN OTHERS THEN\s+RAISE WARNING[^;]+;/, '')],
  ['avisa quem não recebeu convite', (b) => b.replace(' AND b.guest_notified_at IS NOT NULL', '')],
];
const MUT_CRON = [
  ['lembrete inclui reunião cancelada', (b) => b.replace("AND e.status IS DISTINCT FROM 'cancelled'", '')],
  ['lembrete no dia errado', (b) => b.replace('::date + 1', '::date')],
];
const MUT_EF = [
  ['lembrete com ICS', (s) => s.replace("if (agendaGuestKind !== 'reminder') {", 'if (true) {')],
  ['atualização sem checar confirmado', (s) => s.replace("['invite', 'update', 'reminder'].includes(agendaGuestKind)", "agendaGuestKind === 'invite'")],
];

for (const [lista, nomeFn, fn] of [
  [MUT_ENVIO, '_agenda_guest_send', violacoesEnvio],
  [MUT_GATILHO, '_trg_event_agenda_guest_lifecycle', violacoesGatilho],
  [MUT_CRON, '_agenda_guest_reminder_cron', violacoesCron],
]) {
  for (const [nome, mutar] of lista) {
    test(`#2593 C3a: reprova — ${nome}`, () => {
      const b = body(nomeFn);
      const m = mutar(b);
      assert.notEqual(m, b, `a mutação "${nome}" não mudou o corpo`);
      assert.ok(fn(m).length > 0, `o guard não reprovou "${nome}"`);
    });
  }
}
for (const [nome, mutar] of MUT_EF) {
  test(`#2593 C3a EF: reprova — ${nome}`, () => {
    const m = mutar(EF);
    assert.notEqual(m, EF);
    assert.ok(violacoesEF(m).length > 0);
  });
}

// ── G ─────────────────────────────────────────────────────────────────────────────────
test('#2593 C3a db: corpos VIVOS batem com as capturas, e o cron está agendado', { skip: dbGated ? false : skipMsg }, async () => {
  // Texto normalizado, sem hash: _agenda_guest_send lê segredo do vault, e o CodeQL trata md5 sobre esse corpo como
  // criptografia fraca sobre dado sensível (o mesmo alerta que a #2709 recebeu).
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const norm = (s) => s.replace(/\s+/g, ' ');
  for (const name of ['_agenda_guest_send', '_trg_event_agenda_guest_lifecycle', '_agenda_guest_reminder_cron']) {
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: name });
    assert.ifError(error);
    assert.equal((data ?? []).length, 1, `${name}: esperava 1 viva, achei ${(data ?? []).length}`);
    const c = latestFunctionCapture(ROOT, name);
    assert.equal(norm(data[0].prosrc), norm(c.body), `${name}: corpo vivo divergiu de ${c.file}`);
  }
  // O agendamento do cron é conferido pela pós-condição da migration, no apply (nenhuma RPC expõe cron.job).
});
