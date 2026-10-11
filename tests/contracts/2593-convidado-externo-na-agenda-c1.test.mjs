/**
 * #2593, fatia C1 — convidado externo da Agenda Viva com identidade, prazo de guarda e remoção (sem envio).
 *
 * Hermético: lê a migration (achada pelo sufixo, para sobreviver ao renome da aplicação), a ilha de reserva,
 * a agenda pública, o painel admin e os três dicionários. Cada asserção amarra a CONDIÇÃO ao RESULTADO dentro
 * do bloco que decide, com comentários mascarados:
 *  - a pessoa do convidado vem do caminho único de pessoa externa, com vínculo até a data do evento + 365;
 *  - convidado externo exige nome e e-mail válido na reserva e na edição;
 *  - trocar o e-mail troca a pessoa; deixar de ser externo, remover o convidado ou cancelar apaga o vínculo;
 *  - o nome do convidado externo é público só no bloco confirmado; guest_name cru e e-mail nunca vão ao anônimo;
 *  - o dono vê o próprio convidado; os auxiliares não são chamáveis por quem usa a RPC.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const migName = readdirSync(resolve(ROOT, 'supabase/migrations'))
  .filter((f) => f.endsWith('_2593_convidado_externo_na_agenda_c1.sql'));
const MIG = migName.length ? maskLineComments(read(`supabase/migrations/${migName[0]}`)) : '';
const ISLAND = maskJsComments(read('src/components/agenda/AgendaVivaReservationIsland.tsx'));
const PUBLIC = maskJsComments(read('src/components/agenda/AgendaVivaPublic.tsx'));
const ADMIN = maskJsComments(read('src/components/admin/AdminAgendaVivaPanel.tsx'));

/** Corpo de uma função da migration: do CREATE até o $function$; que fecha ESTE corpo. */
function fnBody(name) {
  const a = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(a >= 0, `a migration precisa definir ${name}`);
  return MIG.slice(a, MIG.indexOf('$function$;', MIG.indexOf('$function$', a) + 10));
}

test('#2593 há exatamente uma migration da C1', () => {
  assert.equal(migName.length, 1, `esperava 1 arquivo, achei ${migName.length}`);
});

test('#2593 o bloco aponta para a pessoa, e a pessoa apagada só zera o ponteiro', () => {
  assert.match(MIG, /ALTER TABLE public\.event_agenda_blocks\s+ADD COLUMN IF NOT EXISTS guest_person_id uuid REFERENCES public\.persons\(id\) ON DELETE SET NULL;/);
});

test('#2593 a pessoa do convidado sai do caminho único de pessoa externa, até o evento + 365', () => {
  assert.match(fnBody('_agenda_guest_attach'),
    /RETURN public\._external_person_upsert\(p_email, p_name, 'agenda_guest', p_block_id, v_date \+ 365\);/);
  assert.match(fnBody('_agenda_guest_attach'), /SELECT e\.date INTO v_date\s+FROM public\.event_agenda_blocks b JOIN public\.events e ON e\.id = b\.event_id\s+WHERE b\.id = p_block_id;/);
});

test('#2593 desligar o convidado apaga só o vínculo daquele bloco', () => {
  assert.match(fnBody('_agenda_guest_detach'),
    /DELETE FROM public\.person_external_links l\s+WHERE l\.purpose = 'agenda_guest' AND l\.source_id = p_block_id;/);
});

test('#2593 reserva: convidado externo exige nome e e-mail válido', () => {
  const f = fnBody('reserve_agenda_block');
  assert.match(f, /IF v_external THEN\s+IF p_guest_name IS NULL OR btrim\(p_guest_name\) = '' THEN\s+RETURN jsonb_build_object\('error', 'guest_name_required'\);\s+END IF;\s+IF v_email IS NULL THEN\s+RETURN jsonb_build_object\('error', 'guest_email_required'\);\s+END IF;\s+IF length\(v_email\) > 254 OR v_email !~ '\^\[a-z0-9\._%\+-\]\+@\[a-z0-9-\]\+\(\\\.\[a-z0-9-\]\+\)\+\$' THEN\s+RETURN jsonb_build_object\('error', 'invalid_guest_email'\);/);
  assert.match(f, /v_external boolean := COALESCE\(p_external_guest, false\);/);
});

test('#2593 reserva: só o convidado de agora fica ligado ao bloco (linha reativada perde o vínculo antigo)', () => {
  assert.match(fnBody('reserve_agenda_block'),
    /PERFORM public\._agenda_guest_detach\(v_block_id\);\s+IF v_external THEN\s+v_person := public\._agenda_guest_attach\(v_block_id, p_guest_name, v_email\);\s+END IF;\s+UPDATE public\.event_agenda_blocks SET guest_person_id = v_person WHERE id = v_block_id;/);
});

test('#2593 edição: remover convidado e material é explícito, e campo nulo mantém o atual', () => {
  const f = fnBody('update_agenda_block');
  assert.match(f, /v_external := CASE WHEN COALESCE\(p_clear_guest, false\) THEN false\s+ELSE COALESCE\(p_external_guest, v_block\.external_guest\) END;/);
  assert.match(f, /v_name := CASE WHEN COALESCE\(p_clear_guest, false\) THEN NULL\s+ELSE COALESCE\(NULLIF\(btrim\(p_guest_name\), ''\), v_block\.guest_name\) END;/);
  assert.match(f, /material_url   = CASE WHEN COALESCE\(p_clear_material, false\) THEN NULL\s+ELSE COALESCE\(p_material_url, material_url\) END,/);
  assert.match(f, /guest_name     = v_name,[\s\S]{0,200}?external_guest = v_external\s+WHERE id = p_block_id;/);
});

test('#2593 edição: convidado externo exige nome e e-mail, inclusive o e-mail já salvo', () => {
  const f = fnBody('update_agenda_block');
  assert.match(f, /v_email := COALESCE\(NULLIF\(lower\(btrim\(COALESCE\(p_guest_email, ''\)\)\), ''\), v_cur_email\);\s+IF v_external THEN\s+IF v_name IS NULL OR btrim\(v_name\) = '' THEN\s+RETURN jsonb_build_object\('error', 'guest_name_required'\);[\s\S]{0,120}?IF v_email IS NULL THEN\s+RETURN jsonb_build_object\('error', 'guest_email_required'\);[\s\S]{0,200}?RETURN jsonb_build_object\('error', 'invalid_guest_email'\);/);
});

test('#2593 edição: e-mail novo troca a pessoa; deixar de ser externo apaga o vínculo', () => {
  const f = fnBody('update_agenda_block');
  assert.match(f, /IF v_external THEN\s+IF v_block\.guest_person_id IS NULL OR v_email IS DISTINCT FROM v_cur_email THEN\s+PERFORM public\._agenda_guest_detach\(p_block_id\);\s+v_person := public\._agenda_guest_attach\(p_block_id, v_name, v_email\);\s+UPDATE public\.event_agenda_blocks SET guest_person_id = v_person WHERE id = p_block_id;\s+END IF;\s+ELSIF v_block\.guest_person_id IS NOT NULL THEN\s+PERFORM public\._agenda_guest_detach\(p_block_id\);\s+UPDATE public\.event_agenda_blocks SET guest_person_id = NULL WHERE id = p_block_id;/);
});

test('#2593 cancelamento apaga o vínculo e o ponteiro junto com o status', () => {
  assert.match(fnBody('cancel_agenda_block'),
    /PERFORM public\._agenda_guest_detach\(p_block_id\);\s+UPDATE public\.event_agenda_blocks\s+SET status = 'cancelled', cancelled_by = v_caller, cancelled_reason = p_reason, guest_person_id = NULL\s+WHERE id = p_block_id;/);
});

test('#2593 leitura: nome do convidado externo público só no bloco confirmado', () => {
  assert.match(fnBody('get_geral_agenda_viva'),
    /\|\| CASE WHEN bk\.external_guest AND bk\.status = 'confirmed' AND bk\.guest_name IS NOT NULL\s+THEN jsonb_build_object\('guest_public_name', bk\.guest_name\)\s+ELSE '\{\}'::jsonb END/);
});

test('#2593 leitura: o dono vê o próprio convidado; manage_event ganha o e-mail; o anônimo não vê nada disso', () => {
  const f = fnBody('get_geral_agenda_viva');
  assert.match(f, /\|\| CASE WHEN v_caller IS NOT NULL AND bk\.owner_member_id = v_caller\s+THEN jsonb_build_object\('guest_name', bk\.guest_name, 'guest_email', bk\.guest_email\)/);
  assert.match(f, /CASE WHEN v_is_admin\s+THEN jsonb_build_object\(\s+'owner_member_id', bk\.owner_member_id,\s+'owner_full_name', bk\.owner_full_name,\s+'guest_name', bk\.guest_name,\s+'guest_email', bk\.guest_email\)/);
  assert.match(f, /LEFT JOIN public\.persons gp ON gp\.id = b\.guest_person_id/);
  // guest_name e guest_email só aparecem nos dois ramos com sessão
  assert.equal((f.match(/'guest_email', bk\.guest_email/g) || []).length, 2);
  assert.equal((f.match(/'guest_name', bk\.guest_name/g) || []).length, 2);
});

test('#2593 grants: auxiliares fora do alcance de quem chama a RPC; escrita fora do anônimo', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_attach\(uuid, text, text\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_detach\(uuid\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.reserve_agenda_block\(uuid, text, text, integer, text, text, boolean, text\) FROM PUBLIC, anon;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.update_agenda_block\(uuid, text, text, integer, text, text, boolean, text, boolean, boolean\) FROM PUBLIC, anon;/);
  assert.match(MIG, /DROP FUNCTION IF EXISTS public\.reserve_agenda_block\(uuid, text, text, integer, text, text, boolean\);/);
  assert.match(MIG, /DROP FUNCTION IF EXISTS public\.update_agenda_block\(uuid, text, text, integer, text, text, boolean\);/);
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\._agenda_guest_(attach|detach)\([^)]*\)[^;]*\b(anon|authenticated)\b/.test(MIG));
});

test('#2593 pós-condição: a leitura sem sessão não vaza nome cru nem e-mail', () => {
  assert.match(MIG, /v_anon := public\.get_geral_agenda_viva\(6, NULL, 'both'\);\s+IF v_anon::text ~ '"\(guest_name\|guest_email\|owner_full_name\|owner_member_id\)"' THEN\s+RAISE EXCEPTION/);
});

test('#2593 tela: e-mail do convidado vai só com convidado externo, e a remoção é explícita', () => {
  assert.match(ISLAND, /p_guest_email: d\.external_guest \? d\.guest_email\.trim\(\) \|\| null : null,/);
  assert.match(ISLAND, /p_guest_email: !d\.clear_guest && d\.external_guest \? d\.guest_email\.trim\(\) \|\| null : null,\s+p_clear_guest: !!d\.clear_guest, p_clear_material: !!d\.clear_material,/);
  assert.match(ISLAND, /\{d\.external_guest && !d\.clear_guest && \(\s+<label className="block">[\s\S]{0,200}?fGuestEmail/);
});

test('#2593 tela: a edição abre com o convidado atual do dono', () => {
  assert.match(ISLAND, /guest_name: b\.guest_name \|\| '', material_url: b\.material_url \|\| '', external_guest: b\.external_guest,\s+guest_email: b\.guest_email \|\| '',/);
});

test('#2593 tela: a mensagem de convidado incompleto sai antes da ida ao banco, nas duas ações', () => {
  assert.equal((ISLAND.match(/const gp = guestProblem\(d\); if \(gp\) \{ toast\(errMsg\(gp\), 'error'\); return; \}/g) || []).length, 2);
  assert.match(ISLAND, /guest_name_required: 'errGuestNameRequired', guest_email_required: 'errGuestEmailRequired',\s+invalid_guest_email: 'errInvalidGuestEmail',/);
});

test('#2593 tela: a agenda pública mostra só o nome público; o admin vê o e-mail', () => {
  assert.match(PUBLIC, /\{b\.guest_public_name \? <> · \{t\('comp\.agendaViva\.withGuest', 'com'\)\} \{b\.guest_public_name\}<\/> : null\}/);
  assert.doesNotMatch(PUBLIC, /b\.guest_name\b|b\.guest_email\b/, 'a agenda pública não pode ler o nome cru nem o e-mail');
  assert.match(ADMIN, /\{b\.guest_email \? ` \(\$\{b\.guest_email\}\)` : ''\}/);
});

test('#2593 i18n: as chaves novas existem nos três dicionários', () => {
  const keys = ['fGuestEmail', 'fGuestEmailPlaceholder', 'fGuestEmailHint', 'errGuestNameRequired', 'errGuestEmailRequired',
    'errInvalidGuestEmail', 'removeGuest', 'removeMaterial', 'removalPending', 'withGuest'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${lang}.ts`);
    for (const k of keys) assert.match(dict, new RegExp(`'comp\\.agendaViva\\.${k}': '`), `${lang} sem ${k}`);
  }
});
