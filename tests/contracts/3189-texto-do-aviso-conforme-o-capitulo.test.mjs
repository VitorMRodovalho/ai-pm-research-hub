/**
 * #3189: o aviso de filiação pendente (entry_chapter_action_needed) não diz mais que o capítulo de entrada falta a quem
 * já tem members.entry_chapter_code. Para essas pessoas o texto pede a confirmação da filiação.
 *
 * Trava (sobre a CAPTURA VIGENTE de cada função):
 *   A. affiliation_nudge_text: o topo de cada variante é o texto de sempre (o painel reconhece por ele os avisos antigos),
 *      e cada variante tem 'with_chapter', que não diz que o capítulo falta;
 *   B. affiliation_nudge_deliver, o envio único: depois do dedupe, lê members.entry_chapter_code e só então escolhe a
 *      forma com capítulo; um texto lido, um envio;
 *   C. sem segunda regra: a variante, o plano, o gatilho da aprovação e o cron não leem o capítulo nem escolhem texto;
 *   D. migration: o plano e o texto de antes são guardados antes da redefinição, e a pós-condição prova o plano igual
 *      nos dois sentidos e o topo igual, sem enviar nada.
 *
 * O controle no banco (dois membros na mesma variante, com e sem capítulo, e o dedupe de 30 dias) roda numa transação
 * desfeita pela orquestradora (pacote da #3189): mutar o arquivo não exercita a camada viva.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).body);
const TEXT = cap('affiliation_nudge_text');
const DELIVER = cap('affiliation_nudge_deliver');
const MIG = (() => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const f = readdirSync(dir).filter((n) => /^\d{14}_3189_texto_do_aviso_conforme_o_capitulo\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3189 existe uma vez');
  return maskLineComments(readFileSync(resolve(dir, f[0]), 'utf8'));
})();

// o bloco de uma variante: do seu WHEN até o próximo WHEN de variante ou o END do CASE
const bloco = (v) => {
  const ini = TEXT.indexOf(`WHEN '${v}' THEN jsonb_build_object(`);
  assert.ok(ini > 0, `a variante ${v} existe`);
  const resto = TEXT.slice(ini + 5);
  const fim = resto.search(/\n\s+WHEN '|\n\s+END;/);
  return resto.slice(0, fim);
};

const TOPO = {
  ambiguous: 'Escolha seu capítulo de entrada no Núcleo',
  profile_private: 'Deixe seu perfil PMI público para confirmarmos seu capítulo',
  no_fetch: 'Vincule seu perfil PMI para definir seu capítulo de entrada',
  not_affiliated: 'Confirme sua filiação PMI para definir seu capítulo de entrada',
};

test('A. o topo é o texto de sempre e cada variante tem a forma com capítulo, que não diz que ele falta', () => {
  for (const [v, titulo] of Object.entries(TOPO)) {
    const b = bloco(v);
    assert.ok(b.startsWith(`'${v}' THEN jsonb_build_object(\n      'title', '${titulo}',\n      'body',  '`), `${v}: o topo é o de sempre`);
    const wc = b.match(/'with_chapter', jsonb_build_object\(\s+'title', '([^']+)',\s+'body',\s+'([^']+)'\)\)$/);
    assert.ok(wc, `${v}: a forma com capítulo fecha o bloco da variante`);
    const [, t, corpo] = wc;
    assert.notEqual(t, titulo, `${v}: a forma com capítulo tem outro título`);
    assert.doesNotMatch(`${t} ${corpo}`, /definir (seu|o) capítulo|registrarmos seu capítulo|confirmarmos seu capítulo/,
      `${v}: a forma com capítulo não diz que o capítulo falta`);
    if (v !== 'ambiguous') {
      assert.match(t, /filiação/, `${v}: o título pede a filiação`);
      assert.match(corpo, /^Seu capítulo de entrada no Núcleo já está registrado\. Falta confirmar sua filiação PMI/, `${v}: o corpo diz o que falta`);
    }
  }
  assert.equal((TEXT.match(/'with_chapter'/g) || []).length, 4, 'uma forma com capítulo por variante');
});

test('B. o envio único escolhe a forma pelo capítulo, depois do dedupe', () => {
  const dedupe = DELIVER.indexOf("AND n.created_at > now() - interval '30 days'");
  const le = DELIVER.indexOf('SELECT m.entry_chapter_code IS NOT NULL INTO v_has_entry_chapter');
  const escolhe = DELIVER.indexOf("v_text := v_text -> 'with_chapter';");
  const envia = DELIVER.indexOf('PERFORM public.create_notification(');
  assert.ok(dedupe > 0 && le > dedupe && escolhe > le && envia > escolhe, 'dedupe, capítulo, forma e envio nessa ordem');
  assert.match(DELIVER, /SELECT m\.entry_chapter_code IS NOT NULL INTO v_has_entry_chapter\s+FROM public\.members m WHERE m\.id = p_member_id;/);
  assert.match(
    DELIVER,
    /v_text := public\.affiliation_nudge_text\(p_variant\);\s+IF COALESCE\(v_has_entry_chapter, false\) THEN\s+v_text := v_text -> 'with_chapter';\s+END IF;\s+PERFORM public\.create_notification\(/,
    'com capítulo, a forma com capítulo; sem, o topo',
  );
  assert.equal((DELIVER.match(/affiliation_nudge_text\(/g) || []).length, 1, 'um texto lido');
  assert.equal((DELIVER.match(/v_has_entry_chapter\b/g) || []).length, 3, 'v_has_entry_chapter: declaração, leitura e escolha');
});

test('C. sem segunda regra: só o envio olha o capítulo para escolher o texto', () => {
  for (const n of ['affiliation_nudge_variant', 'affiliation_nudge_plan', 'affiliation_nudge_on_approval', 'nudge_entry_chapter_cohort']) {
    assert.doesNotMatch(cap(n), /entry_chapter_code|with_chapter|affiliation_nudge_text\(/, `${n} não lê o capítulo nem escolhe texto`);
  }
});

test('D. migration: antes guardado antes, plano igual nos dois sentidos, topo igual, sem enviar', () => {
  const plano = MIG.indexOf('CREATE TEMP TABLE _3189_plano_antes AS');
  const texto = MIG.indexOf('CREATE TEMP TABLE _3189_texto_antes AS');
  const redefine = MIG.indexOf('CREATE OR REPLACE FUNCTION public.affiliation_nudge_text(p_variant text)');
  assert.ok(plano > 0 && texto > 0 && redefine > plano && redefine > texto, 'o antes é guardado antes da redefinição');
  assert.doesNotMatch(MIG, /CREATE (OR REPLACE )?FUNCTION public\.affiliation_nudge_(variant|plan)\(/, 'a variante e o plano não são tocados');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.affiliation_nudge_text\(text\) FROM PUBLIC, anon, authenticated;\s+GRANT EXECUTE ON FUNCTION public\.affiliation_nudge_text\(text\) TO service_role;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.affiliation_nudge_deliver\(uuid, text\) FROM PUBLIC, anon, authenticated;\s+GRANT EXECUTE ON FUNCTION public\.affiliation_nudge_deliver\(uuid, text\) TO service_role;/);
  const pos = MIG.slice(MIG.indexOf('DO $postcondition$'));
  assert.match(
    pos,
    /EXCEPT ALL SELECT member_id, variant FROM public\.affiliation_nudge_plan\(\)\)\s+UNION ALL\s+\(SELECT member_id, variant FROM public\.affiliation_nudge_plan\(\)\s+EXCEPT ALL SELECT member_id, variant FROM _3189_plano_antes\)/,
    'a diferença do plano é medida nos dois sentidos',
  );
  assert.match(pos, /IF v_diff <> 0 THEN\s+RAISE EXCEPTION/);
  assert.match(pos, /OR \(public\.affiliation_nudge_text\(v_rec\.variant\) - 'with_chapter'\) IS DISTINCT FROM v_rec\.texto THEN\s+RAISE EXCEPTION/, 'o topo fica igual');
  assert.match(pos, /ILIKE '%definir seu capítulo%' THEN\s+RAISE EXCEPTION/, 'a forma com capítulo não diz que ele falta');
  assert.doesNotMatch(pos, /affiliation_nudge_deliver\((?!uuid, text\))|affiliation_nudge_on_approval\(|nudge_entry_chapter_cohort\(/,
    'a pós-condição não envia: o aviso está ligado em produção');
});
