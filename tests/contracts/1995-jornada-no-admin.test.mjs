/**
 * #1995, fatia 1 — a jornada de onboarding de cada pessoa na fila de /admin/filiacao.
 *
 * Pedido do GP em 16/10/2026: ver em que estágio cada pessoa está e se alguém está travado por falha da própria
 * jornada. Decisão de 28/08 na #1995: extensão de /admin/filiacao pela get_affiliation_verification_queue, herdando
 * o portão dela, e a tela explica em vez de só listar. Os sinais de trava foram medidos em 16/10: etapa pendente por
 * dependência (sem tribo) ou que só fecha por clique, separada da pendência real.
 *
 * O corpo SQL é lido pela captura MAIS NOVA (#1932). Cada asserção amarra a condição ao resultado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const Q = maskLineComments(latestFunctionCapture(ROOT, 'get_affiliation_verification_queue').body);
const migName = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('_1995_jornada_no_admin.sql'));
const ISL = maskJsComments(read('src/components/admin/AffiliationQueueIsland.tsx'));

test('#1995 f1 há exatamente uma migration da fatia 1', () => {
  assert.equal(migName.length, 1, `esperava 1 migration *_1995_jornada_no_admin.sql, achei ${migName.length}`);
});

test('#1995 f1 a fila continua atrás do mesmo portão', () => {
  assert.match(Q, /IF NOT \('filiacao_director' = ANY\(COALESCE\(v_caller_designations, '\{\}'::text\[\]\)\)\)\s+AND NOT public\.can_by_member\(v_caller_id, 'manage_member'\) THEN\s+RAISE EXCEPTION/);
});

test('#1995 f1 a jornada é da pessoa, com o Y real dela e só passos do catálogo', () => {
  // #2718 acrescentou o predicado de papel: a jornada só conta etapa que vale para a pessoa
  assert.match(Q, /FROM public\.onboarding_progress op\s+JOIN public\.onboarding_steps s ON s\.id = op\.step_key\s+WHERE op\.member_id = m\.id\s+AND public\.onboarding_step_applies\(s\.applies_to_role, m\.operational_role\)\s+\) ob ON true/);
  assert.match(Q, /SELECT CASE WHEN count\(\*\) = 0 THEN NULL ELSE jsonb_build_object\(\s+'total', count\(\*\),/, 'o denominador é a contagem da pessoa, nunca uma constante');
  assert.match(Q, /'pending', count\(\*\) FILTER \(WHERE op\.status IN \('pending', 'overdue'\)\),/);
  assert.match(Q, /'stage', \(array_agg\(op\.step_key ORDER BY s\.step_order\) FILTER \(WHERE op\.status IN \('pending', 'overdue'\)\)\)\[1\],/);
  assert.match(Q, /'stalled_days', CASE WHEN count\(\*\) FILTER \(WHERE op\.status IN \('pending', 'overdue'\)\) > 0\s+THEN floor\(extract\(epoch FROM now\(\) - COALESCE\(max\(op\.completed_at\), min\(op\.created_at\)\)\) \/ 86400\)::int/);
  assert.match(Q, /'onboarding', c\.onboarding,/);
});

test('#1995 f1 cada sinal sai só da condição que o define', () => {
  assert.match(Q, /bool_or\(op\.step_key = 'meet_tribe' AND op\.status IN \('pending', 'overdue'\)\) AND m\.tribe_id IS NULL\s+THEN 'tribe_blocked_no_tribe'/);
  // #2718: a presença na própria tribo já fecha a etapa, então o sinal exige que nenhuma presença seja dela
  assert.match(Q, /bool_or\(op\.step_key = 'meet_tribe' AND op\.status IN \('pending', 'overdue'\)\) AND m\.tribe_id IS NOT NULL\s+AND EXISTS \(SELECT 1 FROM public\.attendance a WHERE a\.member_id = m\.id AND a\.present\)\s+AND NOT EXISTS \([^)]*legacy_tribe_id = m\.tribe_id\)\s+THEN 'tribe_pending_but_attended'/);
  assert.match(Q, /bool_or\(op\.step_key = 'start_trail' AND op\.status IN \('pending', 'overdue'\)\)\s+AND NULLIF\(btrim\(COALESCE\(m\.credly_url, ''\)\), ''\) IS NULL\s+THEN 'trail_without_credly'/);
  assert.match(Q, /bool_or\(op\.step_key = 'code_of_conduct' AND op\.status IN \('pending', 'overdue'\)\)\s+AND bool_or\(op\.step_key = 'volunteer_term' AND op\.status = 'completed'\)\s+THEN 'conduct_pending_term_signed'/);
  assert.match(Q, /bool_or\(op\.step_key = 'first_meeting' AND op\.status IN \('pending', 'overdue'\)\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.attendance a WHERE a\.member_id = m\.id AND a\.present\)\s+THEN 'never_present'/);
});

test('#1995 f1 a leitura nova entra no registro de acesso a dado pessoal', () => {
  assert.match(Q, /ARRAY\['pmi_id','chapter','membership_status','membership_dates','onboarding_progress','last_sign_in'\],/);
});

test('#1995 f1 a tela: coluna, filtro de parados e sinais traduzidos', () => {
  assert.match(ISL, /<th className="px-3 py-2 text-left">\{t\('comp\.affiliationQueue\.thJourney', 'Jornada'\)\}<\/th>/);
  assert.match(ISL, /<td colSpan=\{9\} className="px-3 py-3">/, 'a linha expandida acompanha a coluna nova');
  assert.match(ISL, /else if \(obFilter === 'stalled'\) list = list\.filter\(r => \(r\.onboarding\?\.pending \?\? 0\) > 0 && \(r\.onboarding\?\.stalled_days \?\? -1\) >= STALLED_DAYS\);/);
  assert.match(ISL, /\{ob\.done\}\/\{ob\.total\}/, 'X/Y vem do servidor');
  assert.match(ISL, /\{t\(`comp\.affiliationQueue\.obSig\.\$\{sig\}`, sig\)\}/);
  const keys = ['thJourney', 'filterObAll', 'obFilterPending', 'obFilterStalled', 'obDone', 'obNone', 'obDaysStalled', 'obLastLogin', 'obNever',
    ...['tribe_blocked_no_tribe', 'tribe_pending_but_attended', 'trail_without_credly', 'conduct_pending_term_signed', 'never_present']
      .flatMap((s) => [`obSig.${s}`, `obSigLong.${s}`])];
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${loc}.ts`);
    for (const k of keys) assert.ok(dict.includes(`'comp.affiliationQueue.${k}':`), `${loc} sem comp.affiliationQueue.${k}`);
  }
});
