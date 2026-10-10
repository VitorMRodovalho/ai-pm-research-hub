/**
 * #2677 (b) — a /privacy declara a retenção de candidatura que a regra tem.
 *
 * A linha 6 da seção 6 dizia "3 anos após candidatura", e a política registrada (data_retention_policy,
 * selection_applications/anonymize) é de 1825 dias, ancorada na decisão: o executor
 * (list_premember_anonymization_candidates) conta de COALESCE(cycle_decision_date, created_at).
 * "Após a decisão" é o texto que não fica falso: sem data de decisão, a âncora cai na candidatura, que é
 * anterior, e a anonimização vem ANTES do prometido; o inverso ("após a candidatura") prometeria menos
 * do que a regra guarda quando a decisão for registrada.
 *
 * Estático: o texto nos 3 idiomas tem o número e a âncora. Com banco: o número é o retention_days vivo
 * em anos, e o corpo vivo do executor ancora na decisão. O job está dormente até o parecer legal (#905);
 * isto afirma o que a regra É, não que ela roda.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const read = (p) => readFileSync(resolve(process.cwd(), p), 'utf8');
const LANGS = {
  'pt-BR': /^(\d+) anos após a decisão da candidatura$/,
  'en-US': /^(\d+) years after the decision on the application$/,
  'es-LATAM': /^(\d+) años después de la decisión sobre la candidatura$/,
};

/** Escapa todo metacaractere de regex (inclusive a barra invertida) para casar o texto literal. */
const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Valor literal de uma chave do dicionário, ou null. */
function value(src, key) {
  const m = src.match(new RegExp(`'${reEsc(key)}': '((?:[^'\\\\]|\\\\.)*)'`));
  return m ? m[1] : null;
}

/** Anos declarados na linha 6, por idioma; reprova se o texto perder a âncora na decisão. */
function declaredYears() {
  const out = {};
  for (const [lang, re] of Object.entries(LANGS)) {
    const v = value(read(`src/i18n/${lang}.ts`), 'privacy.s6ret.row6.retention');
    assert.ok(v, `${lang}: sem privacy.s6ret.row6.retention`);
    const m = v.match(re);
    assert.ok(m, `${lang}: a retenção de candidatura tem de dizer "N … após a decisão" (veio: ${v})`);
    out[lang] = Number(m[1]);
  }
  return out;
}

test('#2677 a linha 6 declara o mesmo prazo nos 3 idiomas, contado da decisão', () => {
  const y = declaredYears();
  assert.equal(new Set(Object.values(y)).size, 1, `idiomas divergem: ${JSON.stringify(y)}`);
  assert.equal(y['pt-BR'], 5);
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
    assert.equal(y, years, `${lang} declara ${y} anos e a política tem ${data[0].retention_days} dias`);
  }
});

test('#2677 DB: o executor ancora na decisão (e na candidatura só quando falta a decisão)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: 'list_premember_anonymization_candidates' });
  assert.ifError(error);
  assert.equal(data?.length, 1, 'esperava exatamente uma versão do executor');
  assert.match(data[0].prosrc, /AND COALESCE\(sa\.cycle_decision_date, sa\.created_at\)\s+< \(now\(\) - make_interval\(years =>/,
    'o corte de retenção não conta mais da decisão: o texto "após a decisão" ficou sem lastro');
});
