/**
 * #2593, fatia 6 — coapresentador membro separado do convidado externo, com o mesmo crédito de protagonismo.
 *
 * Medido em 16/10/2026: guest_name servia ao convidado de fora e ao membro que apresentava junto (ou no lugar do
 * dono). Nos 6 blocos em que o nome era de outro membro, o XP da confirmação foi só para o dono. Decisões do GP em
 * 16/10: o coapresentador membro recebe o mesmo cálculo do dono (o dono mantém o dele), só se presente; o passado
 * migra com XP retroativo.
 *
 * Os corpos SQL são lidos pela captura MAIS NOVA de cada função (latestFunctionCapture), porque o que se afirma
 * aqui é invariante corrente, não "a migration fez X" (#1932). Cada asserção amarra a condição ao resultado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const fn = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);
const migName = readdirSync(resolve(ROOT, 'supabase/migrations'))
  .filter((f) => f.endsWith('_2593_fatia6_coapresentador_membro.sql'));
const MIG = migName.length ? maskLineComments(read(`supabase/migrations/${migName[0]}`)) : '';
const ISLAND = maskJsComments(read('src/components/agenda/AgendaVivaReservationIsland.tsx'));
const PUBLIC = maskJsComments(read('src/components/agenda/AgendaVivaPublic.tsx'));
const ADMIN = maskJsComments(read('src/components/admin/AdminAgendaVivaPanel.tsx'));
const MCP = maskJsComments(read('supabase/functions/nucleo-mcp/index.ts'));

test('#2593 f6 há exatamente uma migration da fatia 6', () => {
  assert.equal(migName.length, 1, `esperava 1 migration *_2593_fatia6_coapresentador_membro.sql, achei ${migName.length}`);
});

test('#2593 f6 a tabela de coapresentadores é deny-all e o guest_name só existe com convidado externo', () => {
  assert.match(MIG, /ALTER TABLE public\.event_agenda_block_copresenters ENABLE ROW LEVEL SECURITY;/);
  assert.match(MIG, /REVOKE ALL ON TABLE public\.event_agenda_block_copresenters FROM PUBLIC, anon, authenticated;/);
  assert.doesNotMatch(MIG, /CREATE POLICY[^;]*event_agenda_block_copresenters/, 'deny-all: acesso só pelas RPCs SECURITY DEFINER');
  assert.match(MIG, /ADD CONSTRAINT eab_guest_name_only_external CHECK \(guest_name IS NULL OR external_guest\);/);
});

test('#2593 f6 a regra da lista: até 3, membro ativo, nunca o dono', () => {
  const f = fn('_agenda_copresenter_ids_problem');
  assert.match(f, /\(SELECT count\(DISTINCT x\) FROM unnest\(p_ids\) AS x\) > 3 THEN 'too_many_copresenters'/);
  assert.match(f, /WHERE x IS NULL OR x = p_owner\) THEN 'invalid_copresenter'/);
  assert.match(f, /NOT EXISTS \(SELECT 1 FROM public\.members m WHERE m\.id = x AND m\.is_active\)\) THEN 'invalid_copresenter'/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_copresenter_ids_problem\(uuid\[\], uuid\) FROM PUBLIC, anon, authenticated;/);
});

test('#2593 f6 reservar: guest_name sem externo é recusado, e a lista é validada contra o chamador', () => {
  const f = fn('reserve_agenda_block');
  assert.match(f, /IF NOT v_external AND NULLIF\(btrim\(COALESCE\(p_guest_name, ''\)\), ''\) IS NOT NULL THEN\s+RETURN jsonb_build_object\('error', 'guest_name_requires_external'\);/);
  assert.match(f, /v_problem := public\._agenda_copresenter_ids_problem\(p_copresenter_ids, v_caller\);\s+IF v_problem IS NOT NULL THEN\s+RETURN jsonb_build_object\('error', v_problem\);/);
  // o nome só é gravado quando há convidado externo, nos dois caminhos (linha reativada e linha nova)
  assert.match(f, /guest_name = CASE WHEN v_external THEN p_guest_name END,/);
  assert.match(f, /CASE WHEN v_external THEN p_guest_name END, p_material_url, v_external, v_sort, 'reserved', v_caller/);
  // a linha reativada não herda os coapresentadores de antes
  assert.match(f, /DELETE FROM public\.event_agenda_block_copresenters WHERE block_id = v_block_id;\s+INSERT INTO public\.event_agenda_block_copresenters \(block_id, member_id, added_by\)/);
});

test('#2593 f6 editar: deixar de ser externo apaga o nome, e no bloco confirmado quem sai tem estorno e quem entra é creditado', () => {
  const f = fn('update_agenda_block');
  assert.match(f, /IF NOT v_external AND NULLIF\(btrim\(COALESCE\(p_guest_name, ''\)\), ''\) IS NOT NULL THEN\s+RETURN jsonb_build_object\('error', 'guest_name_requires_external'\);\s+END IF;\s+IF NOT v_external THEN\s+v_name := NULL;/);
  assert.match(f, /v_problem := public\._agenda_copresenter_ids_problem\(p_copresenter_ids, v_block\.owner_member_id\);\s+IF v_problem IS NOT NULL THEN\s+RETURN jsonb_build_object\('error', v_problem\);/);
  assert.match(f, /PERFORM public\._reverse_agenda_block_member_xp\(p_block_id, c\.member_id, v_caller, 'removido do bloco'\)\s+FROM public\.event_agenda_block_copresenters c\s+WHERE c\.block_id = p_block_id AND NOT \(c\.member_id = ANY \(p_copresenter_ids\)\)\s+AND v_block\.status = 'confirmed';/);
  assert.match(f, /IF v_block\.status = 'confirmed' THEN\s+PERFORM public\._grant_agenda_block_copresenters_xp\(p_block_id\);/);
});

test('#2593 f6 o crédito do coapresentador: só de quem está no bloco, presente, uma vez', () => {
  const f = fn('_grant_agenda_block_member_xp');
  assert.match(f, /IF v_block\.id IS NULL OR p_member_id IS NULL OR v_block\.status <> 'confirmed' THEN\s+RETURN;/);
  assert.match(f, /IF NOT EXISTS \(\s+SELECT 1 FROM public\.event_agenda_block_copresenters c\s+WHERE c\.block_id = p_block_id AND c\.member_id = p_member_id\s+\) THEN\s+RETURN;/);
  assert.match(f, /IF NOT EXISTS \(\s+SELECT 1 FROM public\.attendance a\s+WHERE a\.event_id = v_block\.event_id AND a\.member_id = p_member_id AND a\.present = true\s+\) THEN\s+RETURN;/);
  assert.match(f, /IF EXISTS \(\s+SELECT 1 FROM public\.gamification_points\s+WHERE ref_id = p_block_id AND category = 'agenda_block_protagonismo'\s+AND member_id = p_member_id\s+\) THEN\s+RETURN;/);
  assert.match(f, /VALUES \(p_member_id, v_total, v_reason, 'agenda_block_protagonismo', p_block_id, v_org,\s+\(v_block\.event_date \+ time '12:00'\) AT TIME ZONE 'America\/Sao_Paulo'\);/);
  // estorno é linha negativa, nunca DELETE (ADR-0081)
  const r = fn('_reverse_agenda_block_member_xp');
  assert.match(r, /SELECT gp\.member_id, gp\.organization_id, -SUM\(gp\.points\), gp\.category,[\s\S]{0,300}?AND gp\.member_id = p_member_id\s+GROUP BY gp\.member_id, gp\.organization_id, gp\.category\s+HAVING SUM\(gp\.points\) <> 0;/);
  assert.doesNotMatch(r, /DELETE FROM public\.gamification_points/);
});

test('#2593 f6 confirmar credita os coapresentadores fora do portão da presença do dono', () => {
  assert.match(fn('confirm_agenda_block'),
    /IF v_present THEN\s+PERFORM public\._grant_agenda_block_xp\(p_block_id\);\s+END IF;\s+PERFORM public\._grant_agenda_block_copresenters_xp\(p_block_id\);/);
  assert.match(fn('confirm_event_blocks'),
    /IF v_present THEN\s+PERFORM public\._grant_agenda_block_xp\(v_block\.id\);\s+v_credited := v_credited \+ 1;\s+END IF;\s+PERFORM public\._grant_agenda_block_copresenters_xp\(v_block\.id\);/);
});

test('#2593 f6 não realizado estorna todo crédito de protagonismo do bloco, não só o do dono', () => {
  const f = fn('revoke_agenda_block_xp');
  assert.match(f, /WHERE gp\.ref_id = p_block_id\s+AND gp\.category = 'agenda_block_protagonismo'\s+GROUP BY gp\.member_id, gp\.organization_id, gp\.category/);
});

test('#2593 f6 as agendas: primeiro nome pela regra do dono (PD-5); id e nome completo só para o dono e manage_event', () => {
  const g = fn('get_geral_agenda_viva');
  assert.match(g, /'copresenter_first_names', CASE\s+WHEN public\._agenda_block_owner_visible\(\s+bk\.status,\s+\(v_caller IS NOT NULL AND bk\.owner_member_id = v_caller\),\s+v_is_admin\)\s+THEN public\._agenda_block_copresenters_json\(bk\.id, false\)\s+ELSE '\[\]'::jsonb/);
  assert.match(g, /\|\| CASE WHEN \(v_caller IS NOT NULL AND bk\.owner_member_id = v_caller\) OR v_is_admin\s+THEN jsonb_build_object\('copresenters', public\._agenda_block_copresenters_json\(bk\.id, true\)\)\s+ELSE '\{\}'::jsonb END/);
  const m = fn('get_meeting_preparation');
  assert.match(m, /'copresenter_first_names', CASE\s+WHEN public\._agenda_block_owner_visible\(\s+b\.status, \(b\.owner_member_id = v_caller_id\), v_is_admin\)\s+THEN public\._agenda_block_copresenters_json\(b\.id, false\)/);
  assert.match(m, /\|\| CASE WHEN v_is_admin\s+THEN jsonb_build_object\('copresenters', public\._agenda_block_copresenters_json\(b\.id, true\)\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_block_copresenters_json\(uuid, boolean\) FROM PUBLIC, anon, authenticated;/);
});

test('#2593 f6 a tela: nome só com convidado externo, lista de coapresentadores nas duas RPCs', () => {
  assert.match(ISLAND, /p_guest_name: d\.external_guest \? d\.guest_name\.trim\(\) \|\| null : null,/);
  assert.match(ISLAND, /p_guest_name: d\.clear_guest \|\| !d\.external_guest \? null : d\.guest_name\.trim\(\) \|\| null,/);
  assert.match(ISLAND, /p_guest_language: d\.external_guest \? d\.guest_language : null,\s+p_copresenter_ids: d\.copresenter_ids,/);
  assert.match(ISLAND, /p_clear_guest: !!d\.clear_guest, p_clear_material: !!d\.clear_material,\s+p_copresenter_ids: d\.copresenter_ids,/);
  assert.match(ISLAND, /\{external && \(\s+<label className="block" htmlFor=\{ids\.name\}>/, 'o campo do nome só aparece com "convidado externo" marcado');
  assert.match(ISLAND, /copresenter_ids: \(b\.copresenters \|\| \[\]\)\.map\(\(c\) => c\.member_id\),/, 'a edição abre com os coapresentadores atuais');
  assert.match(ISLAND, /members\.filter\(\(m\) => m\.id !== selfId && !d\.copresenter_ids\.includes\(m\.id\)/, 'a busca não oferece o próprio dono nem quem já está');
  assert.match(ISLAND, /\{d\.copresenter_ids\.length < MAX_COPRESENTERS && \(/);
  assert.match(ISLAND, /invalid_copresenter: 'errInvalidCopresenter', too_many_copresenters: 'errTooManyCopresenters',\s+guest_name_requires_external: 'errGuestNameRequiresExternal',/);
  assert.match(PUBLIC, /\{b\.copresenter_first_names\?\.length \? <> · \{t\('comp\.agendaViva\.withGuest', 'com'\)\} \{b\.copresenter_first_names\.join\(', '\)\}<\/> : null\}/);
  assert.doesNotMatch(PUBLIC, /b\.copresenters\b/, 'a agenda pública não lê a lista com id e nome completo');
  assert.match(ADMIN, /\{b\.copresenters\?\.length \? ` \+ \$\{b\.copresenters\.map\(\(c\) => c\.name\)\.join\(', '\)\}` : ''\}/);
});

test('#2593 f6 o MCP: coapresentador por id, guest_name só para externo', () => {
  assert.match(MCP, /copresenter_member_ids: z\.array\(z\.string\(\)\)\.optional\(\)/);
  assert.match(MCP, /if \(!params\.external_guest && params\.guest_name && String\(params\.guest_name\)\.trim\(\)\) return invalid\("guest_name e so para convidado externo/);
  assert.match(MCP, /if \(new Set\(coIds\)\.size > 3\) return invalid\(/);
  assert.match(MCP, /p_copresenter_ids: coIds\.length \? coIds : null,/);
});

test('#2593 f6 as chaves novas existem nos três dicionários', () => {
  const keys = ['fCopresenterLegend', 'fCopresenterSearch', 'fCopresenterResults', 'fCopresenterHint', 'removeCopresenter',
    'errInvalidCopresenter', 'errTooManyCopresenters', 'errGuestNameRequiresExternal'];
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${loc}.ts`);
    for (const k of keys) assert.ok(dict.includes(`'comp.agendaViva.${k}':`), `${loc} sem comp.agendaViva.${k}`);
  }
});
