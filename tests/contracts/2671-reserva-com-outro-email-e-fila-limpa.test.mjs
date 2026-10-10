/**
 * #2671 — reserva de entrevista feita com e-mail diferente do da candidatura; e a fila de exceção sem ruído.
 *
 * Hermético: lê a migration, a tela /admin/selection e os três dicionários. Cada asserção amarra a CONDIÇÃO ao
 * RESULTADO dentro do bloco que decide (CLAUDE.md, regra de guard), com comentários mascarados:
 *  - a fila nunca mostra e-mail de membro ou de quem tem login;
 *  - "acionável" é só o buraco real de HOJE: sem candidatura, aberta, não suprimida e com horário por vir;
 *  - suprimida ou passada fica oculta, salvo pedido explícito;
 *  - sugestão só para reserva sem candidatura, só candidatura de ciclo aberto e ainda em seleção;
 *  - o vínculo manual tem portão (comissão do ciclo da candidatura, ou manage_member/manage_platform), segue as
 *    regras do webhook, escolhe a reserva pelo par (evento, convidado) e resolve a reserva;
 *  - a tela pede as ocultas à parte, conta só o acionável no título e confirma antes de vincular.
 * O arquivo da migration é achado pelo nome, para o guard sobreviver ao renome da aplicação.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const migName = readdirSync(resolve(ROOT, 'supabase/migrations'))
  .filter((f) => f.endsWith('_2671_vincular_reserva_e_limpar_fila_de_excecao.sql'));
const MIG = maskLineComments(read(`supabase/migrations/${migName[0]}`));
const PAGE = maskJsComments(read('src/pages/admin/selection.astro'));

/** Corpo de uma função da migration: do CREATE até o $function$; que fecha o corpo. */
function fnBody(name) {
  const start = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(start >= 0, `a migration precisa definir ${name}`);
  const open = MIG.indexOf('$function$', start);
  const close = MIG.indexOf('$function$;', open + 10);
  return MIG.slice(open, close);
}

/** Corpo de uma função da tela: do `function nome(` até a próxima função de mesmo nível. */
function pageFn(name, next) {
  const start = PAGE.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `a tela precisa definir ${name}`);
  const end = PAGE.indexOf(next, start + 10);
  assert.ok(end > start, `fim de ${name} não achado`);
  return PAGE.slice(start, end);
}

test('#2671 há exatamente uma migration da #2671', () => {
  assert.equal(migName.length, 1, `esperava 1 arquivo, achei ${migName.length}`);
});

test('#2671 fila: e-mail de membro, secundário, member_emails ou de pessoa com login nunca aparece', () => {
  const q = fnBody('get_booking_exception_queue');
  const cte = q.slice(q.indexOf('member_addresses AS ('), q.indexOf('base AS ('));
  assert.match(cte, /SELECT lower\(m\.email\) AS e FROM public\.members m/);
  assert.match(cte, /unnest\(m\.secondary_emails\)/);
  assert.match(cte, /FROM public\.member_emails me/);
  assert.match(cte, /FROM public\.persons p WHERE p\.legacy_member_id IS NOT NULL OR p\.auth_id IS NOT NULL/);
  assert.match(q, /WHERE \(p_include_resolved OR ba\.resolved_at IS NULL\)\s+AND NOT EXISTS \(SELECT 1 FROM member_addresses ma WHERE ma\.e = lower\(ba\.guest_email\)\)/);
});

test('#2671 fila: acionável é sem candidatura, aberta, não suprimida e não passada', () => {
  assert.match(
    fnBody('get_booking_exception_queue'),
    /\(b\.last_outcome = 'no_application' AND b\.resolved_at IS NULL\s+AND b\.suppressed_at IS NULL AND NOT b\.past\) AS actionable/,
  );
});

test('#2671 fila: passada é horário anterior a agora; oculta é suprimida ou passada', () => {
  const q = fnBody('get_booking_exception_queue');
  assert.match(q, /\(ba\.last_scheduled_at IS NOT NULL AND ba\.last_scheduled_at < now\(\)\) AS past/);
  assert.match(q, /\(b\.suppressed_at IS NOT NULL OR b\.past\) AS hidden/);
});

test('#2671 fila: a oculta só vem quando pedida', () => {
  assert.match(
    fnBody('get_booking_exception_queue'),
    /WHERE p_include_hidden OR NOT \(b\.suppressed_at IS NOT NULL OR b\.past\)\s+ORDER BY/,
  );
});

test('#2671 fila: o portão de antes continua (membro, comissão ou autoridade)', () => {
  assert.match(
    fnBody('get_booking_exception_queue'),
    /IF NOT EXISTS \(SELECT 1 FROM public\.selection_committee sc WHERE sc\.member_id = v_caller\.id\)\s+AND NOT public\.can_by_member\(v_caller\.id, 'manage_platform'::text\)\s+AND NOT public\.can_by_member\(v_caller\.id, 'manage_member'::text\)\s+AND NOT public\.can_by_member\(v_caller\.id, 'view_internal_analytics'::text\)\s+THEN\s+RAISE EXCEPTION/,
  );
});

test('#2671 sugestão: só para reserva sem candidatura, de ciclo aberto, ainda em seleção, até 3', () => {
  const q = fnBody('get_booking_exception_queue');
  assert.match(q, /CASE WHEN b\.last_outcome <> 'no_application' THEN '\[\]'::jsonb ELSE/);
  assert.match(q, /WHERE c\.status IN \('open', 'active'\)\s+AND a\.status = ANY \(v_allow\)\s+AND a\.anonymized_at IS NULL/);
  assert.match(q, /ORDER BY x\.rank, x\.score DESC\s+LIMIT 3\) s/);
});

test('#2671 sugestão: e-mail secundário vem antes; o resto precisa de nome parecido', () => {
  const q = fnBody('get_booking_exception_queue');
  assert.match(q, /CASE WHEN alt\.hit THEN 0 ELSE 1 END AS rank/);
  assert.match(q, /AND \(alt\.hit OR similarity\(lower\(a\.applicant_name\),[\s\S]{0,120}?\) > 0\.2\)/);
});

test('#2671 vínculo: portão é comissão (lead/evaluator) do ciclo DA candidatura, ou manage_member/manage_platform', () => {
  assert.match(
    fnBody('link_booking_to_application'),
    /IF NOT EXISTS \(SELECT 1 FROM public\.selection_committee sc\s+WHERE sc\.cycle_id = v_app\.cycle_id AND sc\.member_id = v_caller AND sc\.role IN \('lead', 'evaluator'\)\)\s+AND NOT public\.can_by_member\(v_caller, 'manage_member'\)\s+AND NOT public\.can_by_member\(v_caller, 'manage_platform'\) THEN\s+RAISE EXCEPTION/,
  );
});

test('#2671 vínculo: sem membro, recusa', () => {
  assert.match(
    fnBody('link_booking_to_application'),
    /SELECT m\.id INTO v_caller FROM public\.members m WHERE m\.auth_id = auth\.uid\(\);\s+IF v_caller IS NULL THEN\s+RAISE EXCEPTION/,
  );
});

test('#2671 vínculo: a reserva é o par (evento, convidado), aberta e travada', () => {
  assert.match(
    fnBody('link_booking_to_application'),
    /WHERE ba\.calendar_event_id = p_calendar_event_id AND lower\(ba\.guest_email\) = lower\(btrim\(p_guest_email\)\)\s+AND ba\.resolved_at IS NULL\s+FOR UPDATE;\s+IF NOT FOUND THEN\s+RAISE EXCEPTION/,
  );
});

test('#2671 vínculo: só reserva sem candidatura e com horário', () => {
  const f = fnBody('link_booking_to_application');
  assert.match(f, /IF v_attempt\.last_outcome <> 'no_application' THEN\s+RAISE EXCEPTION/);
  assert.match(f, /IF v_attempt\.last_scheduled_at IS NULL THEN\s+RAISE EXCEPTION/);
});

test('#2671 vínculo: mesmas regras do webhook (ciclo aberto, status em seleção, fase objetiva, evento livre)', () => {
  const f = fnBody('link_booking_to_application');
  assert.match(f, /IF v_app\.cycle_status NOT IN \('open', 'active'\) OR NOT \(v_app\.status = ANY \(v_allow\)\) THEN\s+RAISE EXCEPTION/);
  assert.match(f, /IF v_app\.objective_score_avg IS NULL THEN\s+RAISE EXCEPTION/);
  assert.match(f, /IF EXISTS \(SELECT 1 FROM public\.selection_interviews si WHERE si\.calendar_event_id = p_calendar_event_id\) THEN\s+RAISE EXCEPTION/);
  assert.match(f, /WHERE a\.id = p_application_id AND a\.anonymized_at IS NULL;\s+IF NOT FOUND THEN\s+RAISE EXCEPTION/);
});

test('#2671 vínculo: registra a entrevista, resolve a reserva e deixa trilha', () => {
  const f = fnBody('link_booking_to_application');
  assert.match(f, /INSERT INTO public\.selection_interviews[\s\S]{0,200}?VALUES \(v_app\.id, ARRAY\[\]::uuid\[\], v_attempt\.last_scheduled_at, 30, 'scheduled', p_calendar_event_id\)/);
  assert.match(f, /SET resolved_at = now\(\), last_outcome = 'matched', outcome_changed_at = now\(\)\s+WHERE id = v_attempt\.id;/);
  assert.match(f, /INSERT INTO public\.admin_audit_log[\s\S]{0,120}?'selection\.booking_linked_manually'/);
});

test('#2671 grants: anon não executa nenhuma das duas', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_booking_exception_queue\(boolean, boolean\) FROM PUBLIC, anon;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.link_booking_to_application\(text, text, uuid\) FROM PUBLIC, anon;/);
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.(get_booking_exception_queue|link_booking_to_application)\([^)]*\)[^;]*\banon\b/.test(MIG),
    'REGRESSÃO: fila ou vínculo alcançável por anon');
});

test('#2671 tela: pede as ocultas à parte e só as mostra a pedido', () => {
  const f = pageFn('loadBookingExceptions', 'function renderQuickStats(');
  assert.match(f, /sb\.rpc\('get_booking_exception_queue', \{ p_include_resolved: false, p_include_hidden: true \}\)/);
  assert.match(f, /const rows = data\.filter\(\(r: any\) => bookingShowHidden \|\| !r\.hidden\);/);
});

test('#2671 tela: o título conta só o acionável', () => {
  const f = pageFn('loadBookingExceptions', 'function renderQuickStats(');
  assert.match(f, /const actionable = data\.filter\(\(r: any\) => r\.actionable\)\.length;/);
  assert.match(f, /titleEl\.textContent = `\$\{i18n\.title \?\? '[^']*'\} \(\$\{actionable\}\)`/);
});

test('#2671 tela: vincular pede confirmação (segundo clique) e manda o par (evento, convidado)', () => {
  const f = pageFn('loadBookingExceptions', 'function renderQuickStats(');
  assert.match(f, /if \(bookingPendingLink !== key\) \{ bookingPendingLink = key; loadBookingExceptions\(\); return; \}\s+const \[eventId, appId, \.\.\.rest\] = key\.split\('\|'\);\s+linkBooking\(eventId, rest\.join\('\|'\), appId\);/);
  const l = pageFn('linkBooking', 'async function loadBookingExceptions(');
  assert.match(l, /sb\.rpc\('link_booking_to_application', \{\s+p_calendar_event_id: eventId, p_guest_email: guestEmail, p_application_id: applicationId,\s+\}\)/);
});

test('#2671 tela: só oferece Vincular para candidatura com fase objetiva concluída', () => {
  const f = pageFn('loadBookingExceptions', 'function renderQuickStats(');
  assert.match(f, /const btn = !g\.objective_done\s+\? `[^`]*i18n\.objectivePending[^`]*`\s+: `<button type="button" data-link-booking=/);
});

test('#2671 i18n: as chaves novas existem nos três dicionários', () => {
  const keys = ['HiddenCount', 'ShowHidden', 'HideHidden', 'Past', 'ScheduledFor', 'Suggestions', 'NoSuggestion',
    'BySecondaryEmail', 'ByName', 'ObjectivePending', 'Link', 'ConfirmLink', 'Linked', 'LinkError', 'LinkForbidden'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${lang}.ts`);
    for (const k of keys) {
      assert.match(dict, new RegExp(`'admin\\.selection\\.bookingExceptions${k}': '[^']+'`), `${lang} sem ${k}`);
    }
  }
  for (const k of keys) {
    const camel = k[0].toLowerCase() + k.slice(1);
    assert.match(PAGE, new RegExp(`${camel}: t\\('admin\\.selection\\.bookingExceptions${k}', lang\\)`), `tela sem ${k}`);
  }
});
