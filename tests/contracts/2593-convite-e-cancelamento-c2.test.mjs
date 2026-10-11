/**
 * #2593, fatia C2 — convite e cancelamento ao convidado externo da Agenda Viva, com ICS, e sino ao dono.
 *
 * Hermético: lê a migration (achada pelo sufixo), a EF send-campaign e o catálogo do ADR-0022. Cada asserção
 * amarra a CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados:
 *  - o texto do convite e do cancelamento é o aprovado pelo GP, nos 3 idiomas, e o rodapé vem do template avulso;
 *  - só convida quem está confirmado, ainda não avisado, com reunião futura, e-mail no vínculo e sem descadastro;
 *    um convite por convidado por bloco; cancelamento só para quem foi avisado, e antes de o vínculo sair;
 *  - o envio guardado não leva e-mail nem nome do convidado; o destinatário leva, no idioma do bloco;
 *  - a EF escapa os valores no HTML, anexa o ICS, respeita o descadastro e só carimba o aviso quando o provedor
 *    aceita o convite (nunca em sandbox);
 *  - o sino ao dono é só no aplicativo (suppress) e não cai no ELSE.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const migName = readdirSync(resolve(ROOT, 'supabase/migrations'))
  .filter((f) => f.endsWith('_2593_convite_e_cancelamento_com_ics_c2.sql'));
const RAW = migName.length ? read(`supabase/migrations/${migName[0]}`) : '';
const MIG = maskLineComments(RAW);
const EF = maskJsComments(read('supabase/functions/send-campaign/index.ts'));
const CATALOG = JSON.parse(read('docs/adr/ADR-0022-notification-types-catalog.json'));

/** Corpo de uma função da migration: do CREATE até o $function$; que fecha ESTE corpo. */
function fnBody(name) {
  const a = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(a >= 0, `a migration precisa definir ${name}`);
  return MIG.slice(a, MIG.indexOf('$function$;', MIG.indexOf('$function$', a) + 10));
}

test('#2593 C2: há exatamente uma migration da C2', () => {
  assert.equal(migName.length, 1, `esperava 1 arquivo, achei ${migName.length}`);
});

test('#2593 C2: textos aprovados do convite e do cancelamento, nos 3 idiomas', () => {
  // lido do arquivo cru: o mascarador de comentário não entende "--" dentro de string
  for (const phrase of [
    'confirmou a sua participação na Reunião Geral do Núcleo IA &amp; GP.',
    'O convite em anexo reserva o horário na sua agenda. Se não puder participar, responda a este e-mail.',
    'has confirmed your participation in the AI &amp; PM Research Hub (Núcleo IA &amp; GP) General Meeting.',
    'The attached invitation holds the time in your calendar. If you cannot attend, reply to this e-mail.',
    'confirmó tu participación en la Reunión General del Núcleo IA &amp; GP.',
    'La invitación adjunta reserva el horario en tu agenda. Si no puedes participar, responde a este correo.',
    'foi cancelado. O arquivo em anexo libera o horário na sua agenda.',
    'has been cancelled. The attached file frees the time in your calendar.',
    'fue cancelado. El archivo adjunto libera el horario en tu agenda.',
  ]) {
    // cada frase aprovada tem de estar no HTML (com &amp;) E no texto (com &): as duas versões vão no e-mail
    const textForm = phrase.replace(/&amp;/g, '&');
    const count = (needle) => RAW.split(needle).length - 1;
    const both = textForm === phrase ? count(phrase) >= 2 : count(phrase) >= 1 && count(textForm) >= 1;
    assert.ok(both, `texto aprovado ausente do HTML ou do texto: ${phrase}`);
  }
  assert.ok(RAW.includes("'subject', 'Convite: {{block_title}} na Reunião Geral do Núcleo IA & GP, {{date}}'"));
  assert.ok(RAW.includes("'subject', 'Cancelado: {{block_title}} na Reunião Geral do Núcleo IA & GP, {{date}}'"));
});

test('#2593 C2: o rodapé de pessoa externa vem do template avulso, numa fonte só', () => {
  assert.match(MIG, /SELECT body_html, body_text INTO v_base FROM public\.campaign_templates WHERE slug = 'avulso-corpo-livre';\s+IF NOT FOUND THEN RAISE EXCEPTION/);
  assert.match(MIG, /v_html := v_html \|\| jsonb_build_object\(k, replace\(v_base\.body_html->>k, '\{\{content_html\}\}', r\.txt->k->>'html'\)\);/);
  assert.match(MIG, /v_text := v_text \|\| jsonb_build_object\(k, replace\(v_base\.body_text->>k, '\{\{content_text\}\}', r\.txt->k->>'text'\)\);/);
  assert.match(MIG, /IF strpos\(v_base\.body_html->>k, '\{\{content_html\}\}'\) = 0 OR strpos\(v_base\.body_text->>k, '\{\{content_text\}\}'\) = 0 THEN\s+RAISE EXCEPTION/);
});

test('#2593 C2: só envia com reunião futura, e-mail no vínculo e sem descadastro', () => {
  const f = fnBody('_agenda_guest_send');
  assert.match(f, /IF NOT FOUND OR NOT v_b\.external_guest OR v_b\.time_start IS NULL OR v_b\.start_at <= now\(\) THEN\s+RETURN NULL;/);
  assert.match(f, /SELECT l\.contact_email INTO v_email FROM public\.person_external_links l\s+WHERE l\.purpose = 'agenda_guest' AND l\.source_id = p_block_id[\s\S]{0,80}?IF v_email IS NULL THEN RETURN NULL; END IF;/);
  assert.match(f, /IF cardinality\(public\.email_suppressed_among\(ARRAY\[v_email\], true\)\) > 0 THEN RETURN NULL; END IF;/);
});

test('#2593 C2: convite só para confirmado ainda não avisado; cancelamento só para quem foi avisado', () => {
  const f = fnBody('_agenda_guest_send');
  assert.match(f, /IF p_kind = 'invite' AND \(v_b\.status <> 'confirmed' OR v_b\.guest_notified_at IS NOT NULL\) THEN\s+RETURN NULL;/);
  assert.match(f, /IF p_kind = 'cancel' AND v_b\.guest_notified_at IS NULL THEN\s+RETURN NULL;/);
});

test('#2593 C2: um convite por convidado por bloco', () => {
  assert.match(fnBody('_agenda_guest_send'),
    /IF p_kind = 'invite' AND EXISTS \(\s+SELECT 1 FROM public\.campaign_sends s\s+WHERE s\.audience_filter->>'source' = 'agenda_guest' AND s\.audience_filter->>'kind' = 'invite'\s+AND s\.audience_filter->>'block_id' = p_block_id::text\s+AND s\.audience_filter->>'guest_person_id' IS NOT DISTINCT FROM v_b\.guest_person_id::text\s+AND s\.status IS DISTINCT FROM 'failed'\) THEN\s+RETURN NULL;/);
});

test('#2593 C2: o envio guardado não leva e-mail nem nome do convidado; o destinatário leva, no idioma do bloco', () => {
  const f = fnBody('_agenda_guest_send');
  const filt = f.slice(f.indexOf('INSERT INTO public.campaign_sends'), f.indexOf('INSERT INTO public.campaign_recipients'));
  assert.ok(filt.length > 0);
  assert.doesNotMatch(filt, /v_email|guest_name/, 'o audience_filter não pode guardar contato do convidado');
  assert.match(f, /INSERT INTO public\.campaign_recipients \(send_id, member_id, external_email, external_name, person_id, language\)\s+VALUES \(v_send_id, NULL, v_email, v_b\.guest_name, v_b\.guest_person_id, v_b\.guest_language\);/);
  assert.match(filt, /'uid', 'agenda-block-' \|\| p_block_id::text \|\| '@nucleoia\.vitormr\.dev'/);
  assert.match(filt, /'sequence', \(extract\(epoch FROM now\(\)\) \/ 60\)::bigint/);
});

test('#2593 C2: despacho só quando pedido (a pós-condição monta sem enviar)', () => {
  assert.match(fnBody('_agenda_guest_send'), /IF p_dispatch THEN\s+BEGIN\s+SELECT ds\.decrypted_secret INTO v_key[\s\S]{0,300}?net\.http_post\(/);
});

test('#2593 C2: confirmar convida o convidado ainda não avisado; o sino vai ao dono só na transição e por outra pessoa', () => {
  const f = fnBody('confirm_agenda_block');
  assert.match(f, /IF v_block\.external_guest AND v_block\.guest_notified_at IS NULL THEN\s+v_invite := public\._agenda_guest_send\(p_block_id, 'invite', v_caller, true\);/);
  assert.match(f, /IF v_block\.status IS DISTINCT FROM 'confirmed' AND v_block\.owner_member_id <> v_caller THEN\s+PERFORM public\._agenda_block_owner_notice\(p_block_id, 'agenda_block_confirmed'\);/);
  // o convite sai depois da linha virar confirmed (a função de envio lê o estado novo)
  assert.ok(f.indexOf("SET status = 'confirmed'") < f.indexOf("_agenda_guest_send(p_block_id, 'invite'"));
});

test('#2593 C2: cancelar avisa o convidado já convidado ANTES de o vínculo sair, e o dono pelo sino', () => {
  const f = fnBody('cancel_agenda_block');
  assert.match(f, /IF v_block\.external_guest AND v_block\.guest_notified_at IS NOT NULL THEN\s+PERFORM public\._agenda_guest_send\(p_block_id, 'cancel', v_caller, true\);\s+END IF;/);
  assert.ok(f.indexOf("_agenda_guest_send(p_block_id, 'cancel'") < f.indexOf('PERFORM public._agenda_guest_detach(p_block_id);'),
    'o cancelamento tem de sair antes de o vínculo (com o e-mail) ser apagado');
  assert.match(f, /IF v_block\.owner_member_id <> v_caller THEN\s+PERFORM public\._agenda_block_owner_notice\(p_block_id, 'agenda_block_cancelled'\);/);
});

test('#2593 C2: o sino é só no aplicativo e catalogado (não cai no ELSE)', () => {
  const f = fnBody('_delivery_mode_for');
  assert.match(f, /WHEN 'agenda_block_confirmed'\s+THEN 'suppress'/);
  assert.match(f, /WHEN 'agenda_block_cancelled'\s+THEN 'suppress'/);
  assert.match(f, /ELSE 'digest_weekly'\s+END;/);
  assert.equal(CATALOG.types.agenda_block_confirmed?.delivery_mode, 'suppress');
  assert.equal(CATALOG.types.agenda_block_cancelled?.delivery_mode, 'suppress');
  assert.match(fnBody('_agenda_block_owner_notice'), /PERFORM public\.create_notification\(\s+v_b\.owner_member_id, p_type,/);
});

test('#2593 C2: auxiliares de envio fora do alcance de quem chama a RPC', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_send\(uuid, text, uuid, boolean\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_block_owner_notice\(uuid, text\) FROM PUBLIC, anon, authenticated;/);
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\._agenda_(guest_send|block_owner_notice)\([^)]*\)[^;]*\b(anon|authenticated)\b/.test(MIG));
});

test('#2593 C2: pós-condição monta o convite sem enviar e confere contato, idioma, duplicata e cancelamento', () => {
  assert.match(MIG, /v_send := public\._agenda_guest_send\(v_block, 'invite', v_owner, false\);/);
  assert.match(MIG, /IF v_af::text ~ 'controle-2593-c2@' OR v_af::text ~ 'Controle C2' THEN\s+RAISE EXCEPTION/);
  assert.match(MIG, /IF v_rec\.external_email IS DISTINCT FROM 'controle-2593-c2@example\.org' OR v_rec\.language IS DISTINCT FROM 'es-LATAM' THEN\s+RAISE EXCEPTION/);
  assert.match(MIG, /IF public\._agenda_guest_send\(v_block, 'invite', v_owner, false\) IS NOT NULL THEN\s+RAISE EXCEPTION/);
  assert.match(MIG, /IF public\._agenda_guest_send\(v_block, 'cancel', v_owner, false\) IS NOT NULL THEN\s+RAISE EXCEPTION/);
  assert.match(MIG, /EXCEPTION WHEN raise_exception THEN\s+IF SQLERRM <> '__2593c2_rollback__' THEN RAISE; END IF;/);
  assert.doesNotMatch(MIG, /_agenda_guest_send\(v_block, '(invite|cancel)', v_owner, true\)/, 'a pós-condição não pode despachar e-mail');
});

test('#2593 C2 EF: convite renderizado com escape e anexo ICS, fora do laço {{key}} cru', () => {
  assert.match(EF, /const isAgendaGuest = send\.audience_filter\?\.source === 'agenda_guest'/);
  assert.match(EF, /if \(isAgendaGuest\) \{[\s\S]{0,300}?const rendered = renderAgendaGuestMessage\(\{/);
  assert.match(EF, /const oneOffVars = \(isFreeform \|\| isAgendaGuest \? \{\} : \(send\.audience_filter\?\.variables \?\? \{\}\)\) as Record<string, unknown>/);
  assert.match(EF, /html = html\.split\(k\)\.join\(isFreeform \|\| isAgendaGuest \? escapeHtml\(v\) : v\)/);
  assert.match(EF, /attachments = \[icsAttachment\(icsText, kind\)\]/);
  assert.match(EF, /\.\.\.\(attachments \? \{ attachments \} : \{\}\),/);
  // sem ICS válido o convite não sai
  assert.match(EF, /attachments = \[icsAttachment\(icsText, kind\)\]\s+\} catch \(e: unknown\) \{\s+errors\.push\([\s\S]{0,160}?\)\s+continue\s+\}/);
});

test('#2593 C2 EF: o convidado da agenda respeita o descadastro', () => {
  assert.match(EF, /const agendaToExternal = isAgendaGuest && recipients\.some\(\(r\) => !r\.member_id\)/);
  assert.match(EF, /suppressedAmong\(sb, pendingRows\.map\(addressOf\), !isOneOff \|\| freeformToExternal \|\| agendaToExternal\)/);
});

test('#2593 C2 EF: o aviso só é carimbado quando o provedor aceita o convite, nunca em sandbox', () => {
  assert.match(EF, /if \(res\.ok\) \{[\s\S]{0,1600}?if \(isAgendaGuest && !sandbox && send\.audience_filter\?\.kind === 'invite' && send\.audience_filter\?\.block_id\) \{\s+const \{ error: notifErr \} = await sb\.from\('event_agenda_blocks'\)\s+\.update\(\{ guest_notified_at: new Date\(\)\.toISOString\(\) \}\)\s+\.eq\('id', String\(send\.audience_filter\.block_id\)\)\s+\.is\('guest_notified_at', null\)/);
});
