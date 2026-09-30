/**
 * #2524, etapas 1 e 2: a regra de recorrência leva as mudanças às reuniões futuras, e a divergência que
 * sobrar é detectada toda semana.
 *
 * Medido em 29/09/2026: a regra da Tribo 5 mudava, e as 8 reuniões futuras e o card da home não. O detector
 * get_recurring_meeting_drift existia sem nenhum chamador.
 *
 * O que este guard amarra, condição junto do resultado:
 *   banco:
 *     1. cada campo que mudou vai só para a reunião futura agendada da série que ainda tem o valor ANTIGO;
 *     2. mudança de cadência apaga só ocorrência da regra antiga que a nova não gera E sem registro; a com
 *        registro fica e volta na resposta; depois o reconcile gera o dia novo além da última que saiu;
 *     3. o dia antigo sai da tabela de horários;
 *     4. p_dry_run roda o mesmo bloco e o desfaz: a resposta é montada ANTES do raise que desfaz;
 *     5. a autoridade é conferida na regra ANTIGA, antes de qualquer escrita;
 *     6. a assinatura nova volta sem anon;
 *     7. o cron não tem portão de sessão, só ACL; avisa só quando há divergência; registra toda rodada.
 *   tela: as duas telas pedem a prévia antes de gravar, e o botão Salvar não passa o evento de clique como
 *     "confirmado".
 *   catálogo e dicionários.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const body = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);
const fileOf = (name) => maskLineComments(readFileSync(join(DIR, latestFunctionCapture(ROOT, name).file), 'utf8'));
const U = body('update_recurring_meeting_rule');
const C = body('detect_recurring_meeting_drift_cron');

// ── banco: propagação ─────────────────────────────────────────────────────────────────────────
for (const [field, extra] of [['time_start', ''], ['duration_minutes', '[\\s\\S]*?'], ['meeting_link', ''], ['title', ''], ['timezone', '']]) {
  test(`#2524: ${field} mudado vai só para a futura agendada que ainda tem o valor antigo`, () => {
    const re = new RegExp(
      `IF v_rule\\.${field} IS DISTINCT FROM v_old\\.${field} THEN\\s+` +
      `UPDATE public\\.events e SET ${field} = v_rule\\.${field},${extra}\\s*(?:updated_at = now\\(\\))?[\\s\\S]*?` +
      `WHERE e\\.recurrence_group = v_rule\\.recurrence_group AND e\\.date >= current_date AND e\\.status = 'scheduled'\\s+` +
      `AND e\\.${field} IS NOT DISTINCT FROM v_old\\.${field};`,
    );
    assert.match(U, re);
  });
}

test('#2524: a duração leva junto a duração realizada só quando ela ainda é a antiga', () => {
  assert.match(U, /duration_actual = CASE WHEN e\.duration_actual IS NOT DISTINCT FROM v_old\.duration_minutes\s+THEN v_rule\.duration_minutes ELSE e\.duration_actual END/);
});

test('#2524: mudança de cadência apaga só ocorrência antiga, que a nova não gera, sem registro; a com registro volta', () => {
  const cad = U.slice(U.indexOf('IF v_rule.day_of_week IS DISTINCT FROM v_old.day_of_week'));
  assert.match(cad, /^IF v_rule\.day_of_week IS DISTINCT FROM v_old\.day_of_week\s+OR v_rule\.frequency IS DISTINCT FROM v_old\.frequency\s+OR v_rule\.anchor_date IS DISTINCT FROM v_old\.anchor_date THEN/);
  assert.match(cad, /AND extract\(isodow FROM e\.date\)::int = v_old\.day_of_week\s+AND \(v_old\.frequency = 'weekly' OR \(e\.date - v_old\.anchor_date\) % 14 = 0\)\s+AND NOT \(extract\(isodow FROM e\.date\)::int = v_rule\.day_of_week\s+AND e\.date >= v_rule\.anchor_date\s+AND \(v_rule\.frequency = 'weekly' OR \(e\.date - v_rule\.anchor_date\) % 14 = 0\)\)/,
    'ocorrência da regra antiga E não da nova');
  assert.match(cad, /SELECT array_agg\(s\.id\) FILTER \(WHERE NOT s\.has_record\),\s+coalesce\(jsonb_agg\([^;]*?\) FILTER \(WHERE s\.has_record\), '\[\]'::jsonb\),\s+max\(s\.date\)\s+INTO v_drop_ids, v_kept, v_last_stale/);
  assert.match(cad, /IF v_drop_ids IS NOT NULL THEN\s+DELETE FROM public\.events WHERE id = ANY \(v_drop_ids\);/);
  assert.match(cad, /v_rec := public\.reconcile_recurring_meeting\(v_rule\.id, GREATEST\(current_date \+ 60, coalesce\(v_last_stale, current_date\)\)\);/);
  assert.doesNotMatch(cad.slice(0, cad.indexOf('v_rec := ')), /UPDATE public\.events[^;]*status\s*=\s*'cancelled'/, 'nada é cancelado: o que tem registro fica intocado');
});

test('#2524: "registro" cobre presença, textos e toda tabela que aponta para a reunião, menos etiqueta e audiência', () => {
  const rec = U.slice(U.indexOf(') AS has_record') - 2000, U.indexOf(') AS has_record'));
  for (const t of ['attendance', 'event_agenda_blocks', 'meeting_action_items', 'board_item_event_links', 'event_invited_members',
    'meeting_artifacts', 'cost_entries', 'webinars', 'event_showcases', 'event_guest_certificates', 'drive_file_discoveries']) {
    assert.match(rec, new RegExp(`EXISTS \\(SELECT 1 FROM public\\.${t} x WHERE`), `${t} conta como registro`);
  }
  assert.match(rec, /EXISTS \(SELECT 1 FROM public\.events x WHERE x\.rescheduled_from = e\.id\)/);
  for (const c of ['minutes_text', 'agenda_text', 'notes']) assert.match(rec, new RegExp(`coalesce\\(btrim\\(e\\.${c}\\), ''\\) <> ''`));
  assert.doesNotMatch(rec, /event_tag_assignments|event_audience_rules/, 'etiqueta e audiência são recriadas pelos gatilhos');
});

test('#2524: o dia antigo sai da tabela de horários quando o dia muda', () => {
  assert.match(U, /IF v_old\.day_of_week IS DISTINCT FROM v_rule\.day_of_week THEN\s+UPDATE public\.tribe_meeting_slots SET is_active = false, updated_at = now\(\)\s+WHERE tribe_id = v_rule\.tribe_id AND day_of_week = \(v_old\.day_of_week % 7\);/);
});

test('#2524: p_dry_run desfaz o mesmo bloco, e a resposta é montada antes do desfazer', () => {
  const start = U.indexOf('BEGIN\n    UPDATE public.recurring_meeting_rules SET');
  const prop = U.indexOf('IF v_rule.time_start IS DISTINCT FROM v_old.time_start');
  const cad = U.indexOf('IF v_rule.day_of_week IS DISTINCT FROM v_old.day_of_week');
  const undo = U.indexOf("RAISE EXCEPTION 'dry run' USING ERRCODE = 'RR001'");
  assert.ok(start !== -1 && start < prop && prop < cad && cad < undo, 'atualização da regra, propagação e cadência dentro do bloco que o dry run desfaz');
  assert.match(U, /v_res := jsonb_build_object\([\s\S]*?\);\s+IF p_dry_run THEN\s+RAISE EXCEPTION 'dry run' USING ERRCODE = 'RR001';\s+END IF;\s+EXCEPTION WHEN SQLSTATE 'RR001' THEN\s+NULL;\s+END;\s+RETURN v_res;/);
});

test('#2524: a autoridade é conferida na regra antiga, antes de qualquer escrita', () => {
  const gate = U.indexOf('NOT public._can_manage_recurring_rule(v_member, v_old.initiative_id)');
  const firstWrite = U.indexOf('UPDATE public.recurring_meeting_rules SET');
  assert.ok(gate !== -1 && gate < firstWrite);
});

test('#2524: a assinatura nova volta só para authenticated e service_role', () => {
  const f = fileOf('update_recurring_meeting_rule');
  assert.match(f, /DROP FUNCTION public\.update_recurring_meeting_rule\(uuid, jsonb\);\s+CREATE FUNCTION public\.update_recurring_meeting_rule\(p_rule_id uuid, p_patch jsonb, p_dry_run boolean DEFAULT false\)/);
  assert.match(f, /REVOKE ALL ON FUNCTION public\.update_recurring_meeting_rule\(uuid, jsonb, boolean\) FROM PUBLIC, anon;/);
  assert.match(f, /GRANT EXECUTE ON FUNCTION public\.update_recurring_meeting_rule\(uuid, jsonb, boolean\) TO authenticated, service_role;/);
});

// ── banco: detecção ───────────────────────────────────────────────────────────────────────────
test('#2524: o cron não tem portão de sessão; quem protege é o ACL, e ele está agendado', () => {
  assert.doesNotMatch(C, /auth\.uid\(\)|request\.jwt/, 'sob pg_cron não há JWT (#2285)');
  const f = fileOf('detect_recurring_meeting_drift_cron');
  assert.match(f, /REVOKE ALL ON FUNCTION public\.detect_recurring_meeting_drift_cron\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(f, /GRANT EXECUTE ON FUNCTION public\.detect_recurring_meeting_drift_cron\(\) TO service_role;/);
  assert.match(f, /cron\.schedule\('recurring-meeting-drift-weekly', '0 7 \* \* 1', 'SELECT public\.detect_recurring_meeting_drift_cron\(\);'\)/);
});

test('#2524: o cron conta regra ativa divergente e iniciativa ativa parada, e avisa só quando há algo', () => {
  assert.match(C, /FROM public\.get_recurring_meeting_drift\(NULL\) d\s+WHERE d\.status = 'active'\s+AND \(d\.time_mismatch > 0 OR d\.link_mismatch > 0 OR d\.missing_future > 0\);/);
  assert.match(C, /WHERE i\.status = 'active'\s+AND NOT EXISTS \(\s+SELECT 1 FROM public\.events f\s+WHERE f\.initiative_id = i\.id AND f\.date >= current_date[^)]*\)\)\s+AND \(SELECT count\(\*\) FROM public\.events e\s+WHERE e\.initiative_id = i\.id AND e\.date >= current_date - 90 AND e\.date < current_date[\s\S]*?\) >= 2;/);
  assert.match(C, /IF v_rules > 0 OR v_idle > 0 THEN\s+INSERT INTO public\.notifications/);
  assert.match(C, /'recurring_meeting_drift',[\s\S]*?'digest_weekly'[\s\S]*?public\.can_by_member\(m\.id, 'manage_platform'\)[\s\S]*?n\.type = 'recurring_meeting_drift'\s+AND n\.created_at >= now\(\) - interval '6 days'/);
  const endIf = C.indexOf('GET DIAGNOSTICS v_inserted = ROW_COUNT;\n  END IF;');
  const audit = C.indexOf("'cron.detect_recurring_meeting_drift_run'");
  assert.ok(endIf !== -1 && audit > endIf, 'o registro da rodada fica fora do IF: toda rodada deixa linha');
});

test('#2524: o tipo de aviso está no catálogo da ADR-0022 como digest', () => {
  const cat = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
  assert.equal(cat.types.recurring_meeting_drift?.delivery_mode, 'digest_weekly');
});

// ── tela ──────────────────────────────────────────────────────────────────────────────────────
for (const f of ['src/components/initiative/InitiativeRecurringMeetingsPanel.tsx', 'src/components/admin/RecurringAgendaIsland.tsx']) {
  test(`#2524: ${f.split('/').pop()} pede a prévia antes de gravar e só grava depois da confirmação`, () => {
    const s = maskJsComments(readFileSync(resolve(ROOT, f), 'utf8'));
    assert.match(s, /if \(!confirmed\) \{\s+const \{ data: dry, error: dryErr \} = await sb\.rpc\('update_recurring_meeting_rule', \{ \.\.\.args, p_dry_run: true \}\);\s+if \(dryErr\) throw dryErr;\s+const preview = impactOf\(dry\);\s+if \(impactTotal\(preview\) > 0\) \{ setImpact\(preview\); return; \}\s+\}\s+const \{ data, error \} = await sb\.rpc\('update_recurring_meeting_rule', args\);/);
    assert.match(s, /<button onClick=\{\(\) => save\(true\)\}/, 'o botão da caixa confirma');
    assert.match(s, /<button onClick=\{\(\) => save\(false\)\}/, 'o Salvar pede a prévia');
    assert.doesNotMatch(s, /onClick=\{save\}/, 'o evento de clique não pode chegar como "confirmado"');
    assert.match(s, /useEffect\(\(\) => \{ setImpact\(null\); \}, \[form\]\);/, 'mudou o formulário, a prévia antiga cai');
  });
}

test('#2524: a prévia mostra a data das reuniões mantidas por terem registro', () => {
  const s = maskJsComments(readFileSync(resolve(ROOT, 'src/lib/recurring-impact.ts'), 'utf8'));
  assert.match(s, /if \(i\.kept\.length > 0\) \{\s+out\.push\(`\$\{t\('comp\.recurringAgenda\.impactKept'[^`]*`\);/);
  assert.match(s, /kept: Array\.isArray\(f\.kept_with_records\) \? f\.kept_with_records : \[\]/);
});

test('#2524: as chaves da prévia existem nos 3 dicionários', () => {
  const keys = ['impactHeading', 'impactTime', 'impactDuration', 'impactLink', 'impactTitle', 'impactTimezone',
    'impactRemoved', 'impactCreated', 'impactKept', 'impactPast', 'impactBack', 'impactConfirm', 'impactApplied']
    .map((k) => `comp.recurringAgenda.${k}`);
  for (const f of ['pt-BR', 'en-US', 'es-LATAM']) {
    const lines = readFileSync(resolve(ROOT, `src/i18n/${f}.ts`), 'utf8').split('\n').map((l) => l.trim());
    const has = (k) => lines.some((l) => l.startsWith(`'${k}': '`) && l.endsWith("',") && l.length > `'${k}': '',`.length);
    assert.deepEqual(keys.filter((k) => !has(k)), [], `${f}: faltam chaves`);
  }
});
