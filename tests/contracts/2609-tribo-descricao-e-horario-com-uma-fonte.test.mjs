/**
 * #2609 — descrição e horário da tribo com uma fonte só.
 *
 * Hermético. Antes: a descrição pública vinha dos dicionários (data.tribeN.desc), a página da tribo
 * mostrava tribes.notes (nota interna) para membro logado, e o horário estava em três lugares
 * (regra recorrente, tribes.meeting_schedule e data.tribeN.meetings). Agora:
 *  - descrição e entregáveis: initiatives.description_i18n / deliverables_i18n, editados por
 *    update_initiative_public_profile com a autoridade do painel de reuniões recorrentes;
 *  - horário: só a regra recorrente (tribe_meeting_slots), lido por get_tribe_public_profiles;
 *  - o dicionário fica só como fallback da descrição quando a RPC falha.
 * Cada asserção amarra a condição ao resultado no bloco que decide; comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import {
  formatMeetingSlots, profileDescription, profileDeliverables,
} from '../../src/lib/tribes/public-profile.ts';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const MIG = maskLineComments(read('supabase/migrations/29991231000002_2609_descricao_e_horario_da_tribo_com_uma_fonte.sql'));

function fnBody(name) {
  const start = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(start >= 0, `a migration precisa definir ${name}`);
  const open = MIG.indexOf('$function$', start);
  return MIG.slice(open, MIG.indexOf('$function$;', open + 10));
}

test('#2609 edição: só manage_platform ou a liderança da iniciativa (mesma autoridade do painel de reuniões)', () => {
  assert.match(
    fnBody('update_initiative_public_profile'),
    /IF v_member IS NULL OR NOT public\._can_manage_recurring_rule\(v_member, p_initiative_id\) THEN\s+RAISE EXCEPTION 'Unauthorized/,
  );
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.update_initiative_public_profile\(uuid, jsonb, jsonb\) FROM PUBLIC, anon;/);
  assert.doesNotMatch(MIG, /GRANT EXECUTE ON FUNCTION public\.update_initiative_public_profile\([^)]*\) TO[^;]*\banon\b/);
});

test('#2609 edição: chamada sem nenhum campo é recusada antes de gravar auditoria', () => {
  assert.match(
    fnBody('update_initiative_public_profile'),
    /IF p_description_i18n IS NULL AND p_deliverables_i18n IS NULL THEN\s+RAISE EXCEPTION 'Nothing to update/,
  );
});

test('#2609 a tela pergunta ao servidor quem edita, pelo mesmo portão da escrita', () => {
  assert.match(
    fnBody('can_edit_initiative_public_profile'),
    /SELECT COALESCE\(public\._can_manage_recurring_rule\(\s+\(SELECT m\.id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\)\), p_initiative_id\), false\)/,
  );
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.can_edit_initiative_public_profile\(uuid\) FROM PUBLIC, anon;/);
});

test('#2609 edição: português obrigatório e trilha de auditoria', () => {
  const body = fnBody('update_initiative_public_profile');
  assert.match(body, /IF NOT \(v_desc \? 'pt'\) THEN\s+RAISE EXCEPTION 'description_i18n\.pt is required'/);
  assert.match(body, /INSERT INTO public\.admin_audit_log \(actor_id, action, target_type, target_id, changes, metadata\)\s+VALUES \(v_member, 'initiative\.public_profile_updated', 'initiative', p_initiative_id,/);
});

test('#2609 leitura pública: tribo ativa, portão confidencial e horário só da regra', () => {
  const body = fnBody('get_tribe_public_profiles');
  assert.match(body, /WHERE t\.is_active = true\s+AND public\.rls_can_see_initiative\(i\.id\)/);
  assert.match(body, /FROM public\.tribe_meeting_slots s\s+WHERE s\.tribe_id = t\.id AND s\.is_active = true/);
  assert.doesNotMatch(body, /meeting_schedule|notes/);
  // uma linha por tribo, mesmo que exista iniciativa duplicada; a pós-condição conta tribos distintas
  assert.match(body, /SELECT DISTINCT ON \(t\.id\)[\s\S]*ORDER BY t\.id, \(i\.status = 'active'\) DESC/);
  assert.match(MIG, /SELECT count\(DISTINCT tribe_id\) INTO v_n FROM public\.get_tribe_public_profiles\(\);/);
});

test('#2609 seed: as 13 tribos ativas, sem sobrescrever o que a liderança já editou', () => {
  const seeds = MIG.match(/UPDATE public\.initiatives SET description_i18n = \$j\$\{"pt":[\s\S]*?WHERE id = '[0-9a-f-]{36}' AND legacy_tribe_id = \d+ AND description_i18n IS NULL;/g) ?? [];
  assert.equal(seeds.length, 13);
});

const HOME = maskJsComments(read('src/components/sections/TribesSection.astro'));
const PAGE = maskJsComments(read('src/pages/tribe/[id].astro'));

test('#2609 home: descrição e entregáveis do banco, dicionário só como fallback', () => {
  assert.match(HOME, /const profilesRequest = sbAnonForStats\.rpc\('get_tribe_public_profiles'\);/);
  assert.match(HOME, /const \{ data: profiles \} = await profilesRequest;/);
  assert.match(HOME, /description: profileDescription\(p, lang\) \|\| tr\.description,/);
  // com linha no banco, os entregáveis dele valem mesmo vazios (quem apagou não vê o dicionário voltar)
  assert.match(HOME, /deliverables: profileDeliverables\(p, lang\),/);
});

test('#2609 home: horário da regra, "a definir" sem regra, e nunca tribes.notes', () => {
  assert.match(HOME, /scheduleByTribe\.set\(tr\.id, formatMeetingSlots\(p\.slots, lang\)\);/);
  assert.match(HOME, /\{scheduleByTribe\.get\(tr\.id\)\s+\? <span>\{scheduleByTribe\.get\(tr\.id\)\}<\/span>\s+: <span[^>]*>\{t\('tribes\.scheduleTbd', lang\)\}<\/span>\}/);
  assert.doesNotMatch(HOME, /notesMap|tr\.meetingSchedule|\.select\([^)]*\bnotes\b/);
});

test('#2609 página da tribo: descrição do perfil, nunca tribes.notes', () => {
  assert.match(PAGE, /tribeDesc: profileDescription\(tribeProfile, lang\) \|\| staticFallback\?\.description \|\| '',/);
  assert.match(PAGE, /const tribeDescription = I18N\.tribeDesc \|\| '—';/);
  assert.doesNotMatch(PAGE, /_tribe\?\.notes/);
});

test('#2609 página da tribo: horário só da regra, e o texto livre não é lido nem gravado', () => {
  assert.match(PAGE, /scheduleText: formatMeetingSlots\(tribeProfile\?\.slots, lang\),/);
  assert.match(PAGE, /const scheduleHtml = I18N\.scheduleText\s+\? escapeHtml\(String\(I18N\.scheduleText\)\)\s+: `<span[^`]*\$\{escapeHtml\(I18N\.scheduleTbd/);
  assert.doesNotMatch(PAGE, /meeting_schedule/);
});

test('#2609 página da tribo: o editor grava pela RPC com portão', () => {
  assert.match(PAGE, /await sb\.rpc\('update_initiative_public_profile', \{\s+p_initiative_id: INITIATIVE_ID,/);
  assert.match(PAGE, /const \{ data \} = await sb\.rpc\('can_edit_initiative_public_profile', \{ p_initiative_id: INITIATIVE_ID \}\);\s+canEditProfile = data === true;/);
  assert.doesNotMatch(PAGE, /canEditProfile = (isHighManagement|true)/);
});

test('#2609 editor: valida o português antes de enviar e separa recusa de permissão de erro comum', () => {
  assert.match(PAGE, /if \(!description\.pt\) \{ showProfileError\(I18N\.profilePtRequired \|\| ''\); return; \}/);
  assert.match(PAGE, /showProfileError\(error\.code === '42501' \? \(I18N\.profileForbidden \|\| ''\) : \(I18N\.profileSaveError \|\| ''\)\);/);
});

test('#2609 catálogo estático e dicionários sem horário de tribo', () => {
  assert.doesNotMatch(read('src/data/tribes.ts'), /meetingSchedule/);
  assert.doesNotMatch(read('src/data/tribesViewModel.ts'), /meetingSchedule/);
  for (const f of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.doesNotMatch(read(`src/i18n/${f}.ts`), /'data\.tribe\d+\.meetings'/, f);
  }
});

const SLOTS = [
  { day_of_week: 1, time_start: '21:00:00', time_end: '22:00:00' },
  { day_of_week: 4, time_start: '19:00:00', time_end: '20:30:00' },
];

test('#2609 horário formatado na língua da página, vazio sem regra', () => {
  assert.equal(formatMeetingSlots(SLOTS, 'pt-BR'), 'seg. 21:00–22:00 · qui. 19:00–20:30');
  assert.equal(formatMeetingSlots(SLOTS, 'en-US'), 'Mon 21:00–22:00 · Thu 19:00–20:30');
  assert.equal(formatMeetingSlots([], 'pt-BR'), '');
  assert.equal(formatMeetingSlots(null, 'pt-BR'), '');
});

test('#2609 sem tradução, descrição e entregáveis caem no português', () => {
  const p = { tribe_id: 1, description_i18n: { pt: 'Texto' }, deliverables_i18n: { pt: ['A', 'B'], en: [] }, slots: [] };
  assert.equal(profileDescription(p, 'es-LATAM'), 'Texto');
  assert.deepEqual(profileDeliverables(p, 'en-US'), ['A', 'B']);
  assert.equal(profileDescription(null, 'pt-BR'), '');
});
