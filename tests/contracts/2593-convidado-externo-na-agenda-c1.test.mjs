/**
 * #2593, fatia C1 — convidado externo da Agenda Viva com identidade, prazo de guarda e remoção (sem envio).
 *
 * Hermético: lê a migration (achada pelo sufixo, para sobreviver ao renome da aplicação), a ilha de reserva,
 * a agenda pública, o painel admin e os três dicionários. Cada asserção amarra a CONDIÇÃO ao RESULTADO dentro
 * do bloco que decide, com comentários mascarados:
 *  - a pessoa do convidado vem do caminho único de pessoa externa, com vínculo até a data do evento + 365;
 *  - convidado externo exige nome e e-mail válido na reserva e na edição;
 *  - trocar o e-mail troca a pessoa; deixar de ser externo, remover o convidado ou cancelar apaga o vínculo;
 *  - o nome do convidado externo é público só no bloco confirmado E já avisado; guest_name cru e e-mail nunca vão
 *    ao anônimo;
 *  - o e-mail mostrado é o DIGITADO (mora no vínculo, que some no prazo), nunca o principal de outra pessoa;
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
    /v_person := public\._external_person_upsert\(p_email, p_name, 'agenda_guest', p_block_id, v_date \+ 365\);/);
  assert.match(fnBody('_agenda_guest_attach'), /SELECT e\.date INTO v_date\s+FROM public\.event_agenda_blocks b JOIN public\.events e ON e\.id = b\.event_id\s+WHERE b\.id = p_block_id;/);
});

test('#2593 o vínculo do bloco guarda o e-mail digitado, para qualquer pessoa, no mesmo prazo', () => {
  assert.match(fnBody('_agenda_guest_attach'),
    /INSERT INTO public\.person_external_links \(person_id, purpose, source_id, retention_until, contact_email\)\s+VALUES \(v_person, 'agenda_guest', p_block_id, v_date \+ 365, lower\(btrim\(p_email\)\)\)\s+ON CONFLICT \(person_id, purpose, source_id\) DO UPDATE\s+SET contact_email = EXCLUDED\.contact_email,/);
  assert.match(MIG, /ALTER TABLE public\.person_external_links ADD COLUMN IF NOT EXISTS contact_email text;/);
  // o bloco não guarda e-mail: o gatilho de auditoria copia a linha inteira do bloco e nunca é limpo
  assert.doesNotMatch(MIG, /ALTER TABLE public\.event_agenda_blocks[^;]*guest_email/);
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
    /PERFORM public\._agenda_guest_detach\(v_block_id\);\s+IF v_external THEN\s+v_person := public\._agenda_guest_attach\(v_block_id, p_guest_name, v_email\);\s+END IF;\s+UPDATE public\.event_agenda_blocks SET guest_person_id = v_person, guest_notified_at = NULL, guest_language = v_lang\s+WHERE id = v_block_id;/);
});

test('#2593 edição: remover convidado e material é explícito, e campo nulo mantém o atual', () => {
  const f = fnBody('update_agenda_block');
  assert.match(f, /v_external := CASE WHEN COALESCE\(p_clear_guest, false\) THEN false\s+ELSE COALESCE\(p_external_guest, v_block\.external_guest\) END;/);
  assert.match(f, /v_name := CASE WHEN COALESCE\(p_clear_guest, false\) THEN NULL\s+ELSE COALESCE\(NULLIF\(btrim\(p_guest_name\), ''\), v_block\.guest_name\) END;/);
  assert.match(f, /material_url\s+= CASE WHEN COALESCE\(p_clear_material, false\) THEN NULL\s+ELSE COALESCE\(p_material_url, material_url\) END,/);
  assert.match(f, /guest_name\s+= v_name,[\s\S]{0,200}?external_guest = v_external,/);
});

test('#2593 edição: o e-mail atual é o digitado (vínculo), e convidado diferente ainda não foi avisado', () => {
  const f = fnBody('update_agenda_block');
  assert.match(f, /SELECT l\.contact_email INTO v_cur_email FROM public\.person_external_links l\s+WHERE l\.purpose = 'agenda_guest' AND l\.source_id = p_block_id/);
  assert.doesNotMatch(f, /FROM public\.persons p WHERE p\.id = v_block\.guest_person_id/, 'o e-mail atual não pode vir do principal da pessoa');
  assert.match(f, /guest_notified_at = CASE WHEN v_external AND v_name IS NOT DISTINCT FROM v_block\.guest_name\s+AND v_email IS NOT DISTINCT FROM v_cur_email\s+THEN guest_notified_at ELSE NULL END\s+WHERE id = p_block_id;/);
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

test('#2593 leitura: nome do convidado externo público só no bloco confirmado e depois do aviso', () => {
  assert.match(fnBody('get_geral_agenda_viva'),
    /\|\| CASE WHEN bk\.external_guest AND bk\.status = 'confirmed' AND bk\.guest_notified_at IS NOT NULL\s+AND bk\.guest_name IS NOT NULL\s+THEN jsonb_build_object\('guest_public_name', bk\.guest_name\)\s+ELSE '\{\}'::jsonb END/);
});

test('#2593 leitura: o dono vê o próprio convidado; manage_event ganha o e-mail; o anônimo não vê nada disso', () => {
  const f = fnBody('get_geral_agenda_viva');
  assert.match(f, /\|\| CASE WHEN v_caller IS NOT NULL AND bk\.owner_member_id = v_caller\s+THEN jsonb_build_object\('guest_name', bk\.guest_name, 'guest_email', bk\.guest_email,\s+'guest_language', bk\.guest_language\)/);
  assert.match(f, /CASE WHEN v_is_admin\s+THEN jsonb_build_object\(\s+'owner_member_id', bk\.owner_member_id,\s+'owner_full_name', bk\.owner_full_name,\s+'guest_name', bk\.guest_name,\s+'guest_email', bk\.guest_email,\s+'guest_language', bk\.guest_language\)/);
  // o e-mail vem do vínculo do bloco (o digitado), nunca de persons
  assert.match(f, /LEFT JOIN LATERAL \(\s+SELECT l\.contact_email FROM public\.person_external_links l\s+WHERE l\.purpose = 'agenda_guest' AND l\.source_id = b\.id[\s\S]{0,80}?\) gl ON true/);
  assert.match(f, /gl\.contact_email AS guest_email/);
  assert.doesNotMatch(f, /JOIN public\.persons/, 'a leitura não pode tirar e-mail de persons');
  // guest_name e guest_email só aparecem nos dois ramos com sessão
  assert.equal((f.match(/'guest_email', bk\.guest_email/g) || []).length, 2);
  assert.equal((f.match(/'guest_name', bk\.guest_name/g) || []).length, 2);
});

test('#2593 grants: auxiliares fora do alcance de quem chama a RPC; escrita fora do anônimo', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_attach\(uuid, text, text\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_detach\(uuid\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.reserve_agenda_block\(uuid, text, text, integer, text, text, boolean, text, text\) FROM PUBLIC, anon;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.update_agenda_block\(uuid, text, text, integer, text, text, boolean, text, text, boolean, boolean\) FROM PUBLIC, anon;/);
  assert.match(MIG, /DROP FUNCTION IF EXISTS public\.reserve_agenda_block\(uuid, text, text, integer, text, text, boolean\);/);
  assert.match(MIG, /DROP FUNCTION IF EXISTS public\.update_agenda_block\(uuid, text, text, integer, text, text, boolean\);/);
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\._agenda_guest_(attach|detach)\([^)]*\)[^;]*\b(anon|authenticated)\b/.test(MIG));
});

test('#2593 pós-condição: a leitura sem sessão não vaza nome cru nem e-mail', () => {
  assert.match(MIG, /v_anon := public\.get_geral_agenda_viva\(6, NULL, 'both'\);\s+IF v_anon::text ~ '"\(guest_name\|guest_email\|owner_full_name\|owner_member_id\)"' THEN\s+RAISE EXCEPTION/);
});

test('#2593 pós-condição: controle desfeito — nome público só depois do aviso, e-mail nunca ao anônimo', () => {
  assert.match(MIG, /IF v_seen \? 'guest_public_name' THEN\s+RAISE EXCEPTION '#2593: nome público antes do aviso';\s+END IF;\s+UPDATE public\.event_agenda_blocks SET guest_notified_at = now\(\) WHERE id = v_block;/);
  assert.match(MIG, /IF v_seen IS NULL OR v_seen->>'guest_public_name' IS DISTINCT FROM 'Controle 2593' THEN\s+RAISE EXCEPTION/);
  assert.match(MIG, /IF v_seen::text ~ '"\(guest_name\|guest_email\)"' OR v_seen::text ~ 'controle-2593@' THEN\s+RAISE EXCEPTION/);
  // a subtransação é desfeita de propósito, e só o marcador é engolido
  assert.match(MIG, /RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__2593_rollback__';\s+END IF;\s+EXCEPTION WHEN raise_exception THEN\s+IF SQLERRM <> '__2593_rollback__' THEN RAISE; END IF;/);
});

test('#2593 tela: e-mail do convidado vai só com convidado externo, e a remoção é explícita', () => {
  assert.match(ISLAND, /p_guest_email: d\.external_guest \? d\.guest_email\.trim\(\) \|\| null : null,/);
  assert.match(ISLAND, /p_guest_email: !d\.clear_guest && d\.external_guest \? d\.guest_email\.trim\(\) \|\| null : null,\s+p_guest_language: !d\.clear_guest && d\.external_guest \? d\.guest_language : null,\s+p_clear_guest: !!d\.clear_guest, p_clear_material: !!d\.clear_material,/);
  assert.match(ISLAND, /const external = d\.external_guest && !d\.clear_guest;/);
  assert.match(ISLAND, /\{external && \(\s+<label className="block" htmlFor=\{ids\.email\}>[\s\S]{0,200}?fGuestEmail/);
  // remover marca a intenção; os valores ficam para o Desfazer, e quem decide é a marca no envio
  assert.match(ISLAND, /onClick=\{\(\) => set\(\{ clear_guest: true \}\)\}/);
  assert.match(ISLAND, /onClick=\{\(\) => set\(\{ clear_guest: false, clear_material: false \}\)\}/);
});

test('#2593 tela: a edição abre com o convidado atual do dono', () => {
  assert.match(ISLAND, /guest_name: b\.guest_name \|\| '', material_url: b\.material_url \|\| '', external_guest: b\.external_guest,\s+guest_email: b\.guest_email \|\| '',/);
});

test('#2593 tela: a mensagem de convidado incompleto sai antes da ida ao banco, nas duas ações', () => {
  assert.match(ISLAND, /const gp = guestProblem\(d\); if \(gp\) \{ setDraft\(eventId, \{ attempted: true \}\); toast\(errMsg\(gp\), 'error'\); return; \}/);
  assert.match(ISLAND, /const gp = guestProblem\(d\); if \(gp\) \{ setEdit\(blockId, \{ attempted: true \}\); toast\(errMsg\(gp\), 'error'\); return; \}/);
  // e o erro aparece no campo, ligado por aria
  assert.match(ISLAND, /aria-invalid=\{nameErr \|\| undefined\}\s+aria-describedby=\{nameErr \? ids\.nameErr : undefined\}/);
  assert.match(ISLAND, /aria-invalid=\{emailErr \|\| undefined\}\s+aria-describedby=\{emailErr \? `\$\{ids\.emailErr\} \$\{ids\.hint\}` : ids\.hint\}/);
  assert.match(ISLAND, /guest_name_required: 'errGuestNameRequired', guest_email_required: 'errGuestEmailRequired',\s+invalid_guest_email: 'errInvalidGuestEmail',/);
});

test('#2593 tela: a agenda pública mostra só o nome público; o admin vê o e-mail', () => {
  assert.match(PUBLIC, /\{b\.guest_public_name \? <> · \{t\('comp\.agendaViva\.withGuest', 'com'\)\} \{b\.guest_public_name\}<\/> : null\}/);
  assert.doesNotMatch(PUBLIC, /b\.guest_name\b|b\.guest_email\b/, 'a agenda pública não pode ler o nome cru nem o e-mail');
  assert.match(ADMIN, /\{b\.guest_email \? ` \(\$\{b\.guest_email\}\)` : ''\}/);
});

test('#2593 idioma do convite: coluna com padrão pt-BR, só as três tags, e normalizada na escrita', () => {
  assert.match(MIG, /ALTER TABLE public\.event_agenda_blocks ADD COLUMN IF NOT EXISTS guest_language text NOT NULL DEFAULT 'pt-BR';/);
  assert.match(MIG, /CHECK \(guest_language IN \('pt-BR', 'en-US', 'es-LATAM'\)\);/);
  assert.match(fnBody('reserve_agenda_block'), /v_lang\s+text := public\.normalize_platform_language\(p_guest_language\);/);
  assert.match(fnBody('update_agenda_block'), /guest_language = CASE WHEN p_guest_language IS NULL THEN guest_language\s+ELSE public\.normalize_platform_language\(p_guest_language\) END,/);
  // a pós-condição afirma o padrão e o domínio
  assert.match(MIG, /AND column_default LIKE '''pt-BR''%' AND is_nullable = 'NO';\s+IF v_n <> 1 THEN RAISE EXCEPTION/);
  assert.match(MIG, /WHERE guest_language NOT IN \('pt-BR', 'en-US', 'es-LATAM'\);\s+IF v_n <> 0 THEN RAISE EXCEPTION/);
});

test('#2593 idioma do convite na tela: seletor só com convidado externo, já com o idioma de quem reserva', () => {
  assert.match(ISLAND, /const emptyDraft = \(format_slug: string, duration_min: number, lang: Lang\): DraftState => \(\{[\s\S]{0,200}?guest_language: lang,/);
  assert.match(ISLAND, /p_guest_language: d\.external_guest \? d\.guest_language : null,/);
  assert.match(ISLAND, /guest_email: b\.guest_email \|\| '', guest_language: b\.guest_language \|\| lang,/);
  assert.match(ISLAND, /\{external && \(\s+<label className="block" htmlFor=\{ids\.lang\}>[\s\S]{0,300}?GUEST_LANGS\.map/);
});

test('#2593 MCP agenda_blocks: convidado externo leva e-mail e idioma até a RPC, e falta de e-mail é recusada antes da prévia', () => {
  const MCP = maskJsComments(read('supabase/functions/nucleo-mcp/index.ts'));
  const a = MCP.indexOf('"agenda_blocks",');
  assert.ok(a > 0, 'a tool agenda_blocks sumiu');
  const tool = MCP.slice(a, MCP.indexOf('mcp.tool(', a + 20));
  assert.match(tool, /guest_email: z\.string\(\)\.optional\(\)/);
  assert.match(tool, /guest_language: z\.enum\(\["pt-BR", "en-US", "es-LATAM"\]\)\.optional\(\)/);
  assert.match(tool, /p_external_guest: params\.external_guest \?\? false,\s+p_guest_email: params\.guest_email \?\? null,\s+p_guest_language: params\.guest_language \?\? null,/);
  assert.match(tool, /if \(params\.external_guest && \(!params\.guest_email \|\| !String\(params\.guest_email\)\.trim\(\)\)\) return invalid\(/);
  // a prévia repassa os dois campos na next_call
  assert.match(tool, /\.\.\.\(params\.guest_email \? \{ guest_email: params\.guest_email \} : \{\}\),\s+\.\.\.\(params\.guest_language \? \{ guest_language: params\.guest_language \} : \{\}\),/);
});

test('#2593 i18n: as chaves novas existem nos três dicionários', () => {
  const keys = ['fGuestEmail', 'fGuestEmailPlaceholder', 'fGuestEmailHint', 'errGuestNameRequired', 'errGuestEmailRequired',
    'errInvalidGuestEmail', 'removeGuest', 'removeMaterial', 'withGuest', 'fGuestLegend', 'fGuestExternalName',
    'removalGuestPending', 'removalMaterialPending', 'undoRemoval', 'fGuestLanguage', 'lang.pt-BR', 'lang.en-US', 'lang.es-LATAM'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${lang}.ts`);
    for (const k of keys) assert.match(dict, new RegExp(`'comp\\.agendaViva\\.${k.replace(/[.*+?^${}()|[\]\\-]/g, '\\$&')}': '`), `${lang} sem ${k}`);
  }
});
