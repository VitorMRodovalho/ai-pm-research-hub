/**
 * #2677 (b) — a /privacy declara a retenção de candidatura que a regra tem.
 *
 * A linha 6 da seção 6 dizia "3 anos após candidatura". Decisão do GP (10/10/2026, cenário B do #905):
 * 2 anos para rejeitada e 1 ano para desistência, com o executor ligado; data_retention_policy
 * (selection_applications/anonymize) passa a 730 dias. O executor (list_premember_anonymization_candidates)
 * conta de COALESCE(cycle_decision_date, created_at).
 * O texto diz as duas metades do COALESCE ("após a decisão, ou após a candidatura quando a decisão não foi
 * registrada"): medido em 10/10, nenhuma candidatura terminal tem cycle_decision_date, então hoje vale a
 * segunda. Dizer só "após a decisão" seria verdade como teto e falso como descrição (conselho, 10/10).
 *
 * Estático: o texto nos 3 idiomas tem os dois números e as duas âncoras. Com banco: o número da rejeitada é
 * o retention_days vivo em anos, o corpo vivo do executor ancora no COALESCE, e a política está coberta (job
 * ligado): a página não pode declarar uma regra que nada executa. Fica vermelho até a migration do #905.
 * O "1 ano se desistiu" só tem lastro estático (o comando do job no arquivo da migration): nenhuma RPC
 * alcançável expõe cron.job.command, e o auditor de cobertura compara só p_years.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const read = (p) => readFileSync(resolve(process.cwd(), p), 'utf8');
const LANGS = {
  'pt-BR': /^(\d+) anos após a decisão da candidatura, ou após a candidatura quando a decisão não foi registrada \((\d+) ano se a pessoa desistiu\)$/,
  'en-US': /^(\d+) years after the decision on the application, or after the application when no decision was recorded \((\d+) year if the person withdrew\)$/,
  'es-LATAM': /^(\d+) años después de la decisión sobre la candidatura, o después de la candidatura cuando no se registró la decisión \((\d+) año si la persona desistió\)$/,
};

/** Escapa todo metacaractere de regex (inclusive a barra invertida) para casar o texto literal. */
const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Valor literal de uma chave do dicionário, ou null. */
function value(src, key) {
  const m = src.match(new RegExp(`'${reEsc(key)}': '((?:[^'\\\\]|\\\\.)*)'`));
  return m ? m[1] : null;
}

/** Anos declarados na linha 6, por idioma ({ rejected, withdrawn }); reprova se o texto perder a âncora na decisão. */
function declaredYears() {
  const out = {};
  for (const [lang, re] of Object.entries(LANGS)) {
    const v = value(read(`src/i18n/${lang}.ts`), 'privacy.s6ret.row6.retention');
    assert.ok(v, `${lang}: sem privacy.s6ret.row6.retention`);
    const m = v.match(re);
    assert.ok(m, `${lang}: a retenção de candidatura tem de dizer "N … após a decisão (M … desistiu)" (veio: ${v})`);
    out[lang] = { rejected: Number(m[1]), withdrawn: Number(m[2]) };
  }
  return out;
}

test('#2677 a linha 6 declara o mesmo prazo nos 3 idiomas, contado da decisão', () => {
  const y = declaredYears();
  assert.equal(new Set(Object.values(y).map((v) => JSON.stringify(v))).size, 1, `idiomas divergem: ${JSON.stringify(y)}`);
  assert.deepEqual(y['pt-BR'], { rejected: 2, withdrawn: 1 });
});

test('#2677 a linha 6 continua na tabela da página', () => {
  assert.match(read('src/pages/privacy.astro'), /const S6_ROWS = \[1,2,3,4,5,6,/);
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#2677 DB: o prazo declarado é o retention_days vivo da política de candidaturas', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().from('data_retention_policy')
    .select('retention_days, cleanup_type, executor')
    .eq('table_name', 'selection_applications').eq('is_active', true);
  assert.ifError(error);
  assert.equal(data.length, 1, `esperava 1 política ativa de selection_applications, achei ${data.length}`);
  const years = data[0].retention_days / 365;
  assert.ok(Number.isInteger(years), `retention_days ${data[0].retention_days} não é um número inteiro de anos`);
  for (const [lang, y] of Object.entries(declaredYears())) {
    assert.equal(y.rejected, years, `${lang} declara ${y.rejected} anos e a política tem ${data[0].retention_days} dias`);
  }
});

test('#2677 DB: a política de candidaturas está coberta (job ligado e horizonte batendo)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_retention_policy_coverage');
  assert.ifError(error);
  const row = data.find((r) => r.politica === 'selection_applications/anonymize');
  assert.ok(row, 'a política de candidaturas sumiu do auditor');
  assert.equal(row.coberta, true, `a página declara uma retenção que nada executa: ${row.motivo}`);
});

test('#2677 DB: o executor ancora na decisão (e na candidatura só quando falta a decisão)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: 'list_premember_anonymization_candidates' });
  assert.ifError(error);
  assert.equal(data?.length, 1, 'esperava exatamente uma versão do executor');
  assert.match(data[0].prosrc, /AND COALESCE\(sa\.cycle_decision_date, sa\.created_at\)\s+< \(now\(\) - make_interval\(years =>/,
    'o corte de retenção não conta mais da decisão: o texto "após a decisão" ficou sem lastro');
});

// ─── a migration que liga o executor (#905, cenário B) ───────────────────────────────────────────────

const mig905 = readdirSync(resolve(process.cwd(), 'supabase/migrations'))
  .filter((f) => f.endsWith('_905_retencao_de_candidatura_2_e_1_anos_e_executor_ligado.sql'));
const M905 = mig905.length ? maskLineComments(read(`supabase/migrations/${mig905[0]}`)) : '';

test('#905 há exatamente uma migration que liga o executor', () => {
  assert.equal(mig905.length, 1, `esperava 1 arquivo, achei ${mig905.length}`);
});

test('#905 o job vai ligado, com a janela 2 anos / 1 ano e sem ensaio', () => {
  assert.match(M905, /PERFORM cron\.alter_job\(\s+v_jobid,\s+command := \$cron\$SELECT public\.anonymize_premember_applications\(p_dry_run := false, p_years := 2, p_years_withdrawn := 1, p_limit := 500\)\$cron\$,\s+active  := true\s+\);/);
});

test('#905 a tabela de retenção declara o horizonte do job (730 = 2 × 365)', () => {
  assert.match(M905, /UPDATE public\.data_retention_policy\s+SET retention_days = 730,[\s\S]{0,400}?WHERE table_name = 'selection_applications' AND cleanup_type = 'anonymize';/);
});

test('#905 R3: candidatura com vídeo externo ainda apontado é pulada antes de qualquer apagamento', () => {
  const fn = M905.slice(M905.indexOf('CREATE OR REPLACE FUNCTION public.anonymize_premember_applications('), M905.indexOf('$function$;'));
  const trava = fn.indexOf("IF EXISTS (SELECT 1 FROM public.pmi_video_screenings v");
  const apaga = fn.indexOf('v_child := public._erase_application_pii(v_cand.application_id);');
  assert.ok(trava > 0 && apaga > trava, 'a trava tem de vir antes do apagamento');
  assert.match(fn, /WHERE v\.application_id = v_cand\.application_id\s+AND \(v\.drive_file_id IS NOT NULL OR v\.youtube_url IS NOT NULL\)\) THEN\s+v_blocked := v_blocked \+ 1;[\s\S]{0,900}?'lgpd_premember_anonymization_blocked'[\s\S]{0,400}?END IF;\s+CONTINUE;\s+END IF;/);
  assert.match(fn, /'blocked_external_video', v_blocked,/);
  // o registro de bloqueio sai uma vez por candidatura, não a cada rodada mensal
  assert.match(fn, /IF NOT p_dry_run AND NOT EXISTS \(\s+SELECT 1 FROM public\.admin_audit_log al\s+WHERE al\.action = 'lgpd_premember_anonymization_blocked' AND al\.target_id = v_cand\.application_id\) THEN/);
  // e a bloqueada vai para o fim da fila, antes do LIMIT
  assert.match(fn, /ORDER BY EXISTS \(SELECT 1 FROM public\.pmi_video_screenings v\s+WHERE v\.application_id = c\.application_id\s+AND \(v\.drive_file_id IS NOT NULL OR v\.youtube_url IS NOT NULL\)\),\s+c\.retention_anchor\s+LIMIT p_limit/);
  // o sucesso não afirma purga pendente que a trava tornou impossível
  assert.ok(!/'pending_manual_or_ef_purge'/.test(fn), 'rótulo de purga pendente voltou ao registro de sucesso');
});

test('#905 quem ainda concorre no mesmo e-mail espera, antes de qualquer apagamento', () => {
  const fn = M905.slice(M905.indexOf('CREATE OR REPLACE FUNCTION public.anonymize_premember_applications('), M905.indexOf('$function$;'));
  const espera = fn.indexOf('v_waiting := v_waiting + 1;');
  const apaga = fn.indexOf('v_child := public._erase_application_pii(v_cand.application_id);');
  assert.ok(espera > 0 && apaga > espera, 'a espera tem de vir antes do apagamento');
  assert.match(fn, /AND trim\(lower\(o\.email\)\) = trim\(lower\(me\.email\)\)\s+AND o\.anonymized_at IS NULL\s+AND o\.status NOT IN \('rejected', 'withdrawn'\)\s+AND oc\.status IN \('open', 'active'\)\) THEN\s+v_waiting := v_waiting \+ 1;\s+CONTINUE;/);
});

test('#905 pós-condição: ligar não apaga nada hoje e a política fica coberta', () => {
  assert.match(M905, /v_dry := public\.anonymize_premember_applications\(true, 2, 1, 500\);\s+IF \(v_dry->>'processed'\)::int <> 0 OR \(v_dry->>'blocked_external_video'\)::int <> 0 THEN\s+RAISE EXCEPTION/);
  assert.match(M905, /IF NOT FOUND OR v_cov\.coberta IS NOT TRUE OR v_cov\.horizonte_bate IS NOT TRUE THEN\s+RAISE EXCEPTION/);
  assert.match(M905, /WHERE c\.tabela = 'selection_applications' AND c\.tipo = 'anonymize';/);
  assert.match(M905, /AND retention_days = 730;\s+IF v_n <> 1 THEN RAISE EXCEPTION/);
});

test('#905 o anonimizador segue só para service_role', () => {
  assert.match(M905, /REVOKE ALL ON FUNCTION public\.anonymize_premember_applications\(boolean, integer, integer, integer\) FROM PUBLIC, anon, authenticated;/);
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.anonymize_premember_applications\([^)]*\)[^;]*\b(anon|authenticated)\b/.test(M905));
});
