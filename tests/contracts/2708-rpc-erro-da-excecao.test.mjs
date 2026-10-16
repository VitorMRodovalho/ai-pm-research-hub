/**
 * #2708 — o front não pode dizer "ok" quando a RPC recusou com EXCEÇÃO.
 *
 * A #2704 cobriu as funções que recusam no corpo. Esta é a outra classe: funções que gravam e
 * recusam com RAISE. O supabase-js não lança, devolve `{ data: null, error }`, então a tela que faz
 * `await sb.rpc(...)` dentro de `try/catch`, ou não lê o `error`, mostra sucesso numa recusa.
 * Medido em 16/10/2026: 221 chamadas a essas funções, 42 sem ler o `error`.
 *
 * Regra: toda chamada a uma dessas funções lê o `error` amarrado à variável do resultado, em
 * posição que decide, ou passa por `rpcChecked`. Fora disso, só com nome numa das listas abaixo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { exceptionWriters, bodyErrorWriters, scanUncheckedErrorCalls, readsError } from '../helpers/rpc-body-error-scan.mjs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();

// A corrigir na próxima PR da #2708 (membro e páginas públicas; webhook de calendário).
// `arquivo|função#ordem`. Só diminui: chamada corrigida que continuar aqui reprova.
const EXCECOES = [
  'src/pages/api/calendar-webhook.ts|record_booking_attempt#1',
  'src/pages/api/calendar-webhook.ts|record_booking_attempt#2',
  'src/pages/help.astro|dismiss_onboarding#1',
  'src/pages/profile.astro|grant_public_map_consent#1',
  'src/pages/profile.astro|revoke_public_map_consent#1',
  'src/pages/profile.astro|member_self_update#1',
  'src/pages/profile.astro|member_self_update#2',
  'src/pages/publications/submissions/[id].astro|update_publication_submission_status#1',
  'src/pages/publications/submissions/[id].astro|update_publication_submission#1',
  'src/pages/publications/submissions/[id].astro|add_publication_submission_author#1',
  'src/pages/publications/submissions/[id].astro|remove_publication_submission_author#1',
];

// Melhor-esforço por desenho: nenhuma tela afirma sucesso sobre estas chamadas.
const MELHOR_ESFORCO = {
  'src/components/nav/Nav.astro|try_auto_link_ghost#1': 'só usa o resultado se vier; sem vínculo a pessoa segue como visitante',
  'src/components/nav/Nav.astro|try_auto_link_ghost#2': 'idem, no caminho do evento de sessão',
  'src/layouts/BaseLayout.astro|record_member_activity#1': 'telemetria de página, disparada sem esperar',
  'src/pages/blog/[slug].astro|increment_blog_view#1': 'contador de visualização',
  'src/pages/publications.astro|increment_publication_view#1': 'contador de visualização',
  'src/pages/publications/[slug].astro|increment_publication_view#1': 'contador de visualização',
};

// A chamada fica numa arrow ou num helper e o `error` é lido por quem a chama; cada uma tem
// asserção própria abaixo.
const LIDO_NO_CHAMADOR = [
  'src/pages/attendance.astro|drop_event_instance#1',
  'src/pages/admin/member/[id].astro|admin_update_member#1',
];

const TARGETS = exceptionWriters(ROOT);

test('#2708 a classificação enxerga as funções que gravam e recusam com exceção', () => {
  // Controle contra vacuidade: se o parser de migrations quebrar, o conjunto esvazia e tudo passa.
  assert.ok(TARGETS.size >= 300, `só ${TARGETS.size} funções classificadas`);
  for (const fn of ['mark_member_present', 'mark_member_excused', 'set_site_config', 'update_event_duration', 'set_event_audience']) {
    assert.ok(TARGETS.has(fn), `${fn} grava e recusa com exceção; a classificação perdeu`);
  }
  const body = bodyErrorWriters(ROOT);
  const sobrepostas = [...TARGETS].filter((f) => body.has(f) || f.startsWith('get_'));
  assert.deepEqual(sobrepostas, [], 'a classe da #2704 e as leituras ficam fora desta');
});

test('#2708 nenhuma chamada nova ignora o error, e as listas só diminuem', () => {
  const { offenders, checked } = scanUncheckedErrorCalls(ROOT, TARGETS);
  assert.ok(checked >= 150, `só ${checked} chamadas conformes achadas: a varredura parou de ver o front`);
  const conhecidas = new Set([...EXCECOES, ...Object.keys(MELHOR_ESFORCO), ...LIDO_NO_CHAMADOR]);
  const novos = offenders.filter((o) => !conhecidas.has(o));
  assert.deepEqual(novos, [],
    'chamada a RPC que grava sem ler o error: leia `{ error }` e decida por ele, ou use rpcChecked (src/lib/rpc-checked.ts)');
  const vencidas = [...conhecidas].filter((e) => !offenders.includes(e));
  assert.deepEqual(vencidas, [], 'estas entradas já não são necessárias: tire-as da lista');
});

test('#2708 controle: a varredura reprova a chamada que não lê o error e aprova a leitura que decide', () => {
  const dir = mkdtempSync(join(tmpdir(), 'g2708-'));
  mkdirSync(join(dir, 'src'));
  mkdirSync(join(dir, 'supabase/migrations'), { recursive: true });
  writeFileSync(join(dir, 'supabase/migrations/20990101000000_x.sql'),
    "CREATE OR REPLACE FUNCTION public.f_grava(p uuid) RETURNS void LANGUAGE plpgsql AS $$\n" +
    "BEGIN IF p IS NULL THEN RAISE EXCEPTION 'x'; END IF; UPDATE public.t SET a = 1 WHERE id = p; END $$;\n" +
    "CREATE OR REPLACE FUNCTION public.f_corpo(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$\n" +
    "BEGIN IF p IS NULL THEN RETURN jsonb_build_object('error','x'); END IF; DELETE FROM public.t WHERE id = p; RETURN '{}'; END $$;\n" +
    "CREATE OR REPLACE FUNCTION public.get_semeia(p uuid) RETURNS void LANGUAGE sql AS $$ INSERT INTO public.t VALUES (p) $$;\n");
  writeFileSync(join(dir, 'src/a.ts'), [
    "async function solto(sb) { try { await sb.rpc('f_grava', { p: 1 }); ok(); } catch (e) { err(e); } }",
    "async function boa(sb) { const { error } = await sb.rpc('f_grava', { p: 1 }); if (error) throw error; ok(); }",
    "async function renomeada(sb) { const { error: e1 } = await sb.rpc('f_grava', {}); if (e1) return; }",
    "async function so_data(sb) { const { data } = await sb.rpc('f_grava', {}); ok(data); }",
    "async function inteira(sb) { const r = await sb.rpc('f_grava', {}); if (r.error) return; }",
    "async function outra_var(sb) { const { error: e2 } = await sb.rpc('f_grava', {}); if (error) return; }",
    "async function corpo(sb) { await sb.rpc('f_corpo', {}); }",
    "async function leitura(sb) { await sb.rpc('get_semeia', {}); }",
  ].join('\n'));
  const t = exceptionWriters(dir);
  assert.deepEqual([...t], ['f_grava'], 'só a que grava e recusa com exceção; a do corpo e a get_* ficam fora');
  const { offenders, checked } = scanUncheckedErrorCalls(dir, t);
  // `outra_var` lê `error`, mas o resultado foi para `e2`: a leitura tem de ser da MESMA variável.
  assert.deepEqual(offenders, ['src/a.ts|f_grava#1', 'src/a.ts|f_grava#4', 'src/a.ts|f_grava#6']);
  assert.equal(checked, 3);
});

test('#2708 controle do leitor: throwOnError conta, leitura só em log não', () => {
  const ok = "await sb.rpc('f', {}).throwOnError();\nshow();";
  assert.equal(readsError(ok, ok.indexOf('.rpc(')), true);
  const log = "const { data, error } = await sb.rpc('f', {});\nconsole.log(error);\nshow();";
  assert.equal(readsError(log, log.indexOf('.rpc(')), false);
  // O caso que escapou na mutação do auto check-in: `res?.error` e a string 'error' não são o `error`.
  const prop = "const { data: res, error } = await sb.rpc('f', {});\nif (res?.success) ok();\nelse toast(res?.error || 'Erro', 'error');";
  assert.equal(readsError(prop, prop.indexOf('.rpc(')), false);
});

test('#2708 presença: o excluir definitivo lê o error de quem chama o doDelete', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/pages/attendance.astro'), 'utf8'));
  assert.match(src,
    /const doDelete = async \(force: boolean\) => sb\.rpc\('drop_event_instance', \{[\s\S]{0,200}?let \{ data, error \} = await doDelete\(false\);[\s\S]{0,700}?\(\{ data, error \} = await doDelete\(true\)\);\s+\}\s+if \(error\) throw error;/,
    'o excluir definitivo deixou de ler o error depois das duas tentativas');
});

test('#2708 presença: tags e público viram aviso próprio, sem lançar para quem criou o evento', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/pages/attendance.astro'), 'utf8'));
  const i = src.indexOf('async function assignEventTagsAndAudience(');
  assert.ok(i > 0, 'não achei o helper de tags e público');
  const bloco = src.slice(i, src.indexOf('\n  }\n', i) + 4);
  assert.match(bloco, /const \{ error: tagErr \} = await sb\.rpc\('assign_event_tags'[^;]+;\s+if \(tagErr\) throw tagErr;/);
  assert.match(bloco, /const \{ error: audErr \} = await sb\.rpc\('set_event_audience'[^;]+;\s+if \(audErr\) throw audErr;/);
  assert.match(bloco, /\} catch \(err: any\) \{\s+toast\(`\$\{I18N\.msgTagsAudienceSaveError\}: /,
    'a recusa de tags ou público tem de virar aviso com o motivo');
});

test('#2708 presença: a duração recusada avisa sem desfazer o registro das presenças', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/components/workspace/AttendanceForm.tsx'), 'utf8'));
  assert.match(src,
    /const \{ error: durErr \} = await sb\.rpc\('update_event_duration', \{[\s\S]{0,160}?\}\);\s+if \(durErr\) \{\s+\(window as any\)\.toast\?\.\(`\$\{t\('comp\.attendance\.durationSaveError'/,
    'a recusa da duração tem de virar aviso próprio');
});

test('#2708 presença: o desfazer da grade não engole a recusa', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/components/tribes/TribeAttendanceTab.tsx'), 'utf8'));
  assert.match(src,
    /const \{ error: undoErr \} = await sb\.rpc\('mark_member_present'[^;]+;\s+if \(undoErr\) throw undoErr;\s+await refreshGrid\(\);\s+\} catch \(e: any\) \{\s+\(window as any\)\.toast\?\.\(e\?\.message \|\| 'Erro', 'error'\);/,
    'o desfazer voltou a engolir o erro');
});

test('#2708 admin: a ficha do membro lê o error que o helper devolve antes de dizer "Salvo"', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/pages/admin/member/[id].astro'), 'utf8'));
  const i = src.indexOf('async function adminUpdateMemberCompat(');
  assert.ok(i > 0, 'não achei o helper do formulário de edição');
  assert.match(src.slice(i, src.indexOf('\n  }\n', i)),
    /const res = await sb\.rpc\('admin_update_member', \{[\s\S]*?\}\);\s+return \{ mode: 'v2', data: res\.data, error: res\.error \};/,
    'o helper deixou de devolver o error da chamada');
  assert.match(src,
    /const compat = await adminUpdateMemberCompat\([^)]*\);[\s\S]{0,200}?result = compat\.error \? \{ error: [^}]+\} : compat\.data;\s+\}\s+if \(result\?\.error\) \{ \(window as any\)\.toast\?\.\(result\.error, 'error'\); return; \}\s+\(window as any\)\.toast\?\.\(T\.toast\.saved,'success'\);/,
    'o "Salvo" voltou a sair sem olhar o error do helper');
});

test('#2708 admin: o status depois de criar a iniciativa vira aviso próprio, sem lançar', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/pages/admin/initiatives.astro'), 'utf8'));
  assert.match(src,
    /const \{ error: statusErr \} = await sb\.rpc\('update_initiative', \{[\s\S]{0,160}?\}\);\s+if \(statusErr\) \(window as any\)\.toast\?\.\(`\$\{T\.statusNotApplied\}: \$\{statusErr\.message\}`, 'error'\);/,
    'a recusa do status tem de virar aviso, e lançar deixaria o modal aberto para criar outra');
});

test('#2708 admin: a atribuição recusada não aparece na tela', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/components/board/CardDetail.tsx'), 'utf8'));
  assert.match(src,
    /const \{ error \} = await sb\.rpc\('assign_checklist_item', \{[\s\S]{0,200}?\}\);\s+if \(error\) \{\s+\(window as any\)\.toast\?\.\([^;]+;\s+return;[^\n]*\n\s+\}\s+setChecklist\(/,
    'a lista local não pode mudar antes de o banco aceitar a atribuição');
});
