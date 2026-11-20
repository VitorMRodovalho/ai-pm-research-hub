/**
 * #3108: o radar de filiação (v4_notify_expiring_affiliations) lê o vencimento do snapshot VEP.
 *
 * Antes, o radar só lia a última verificação manual (member_affiliation_verifications): quem tinha filiação validada
 * só pela VEP não recebia aviso nenhum, e quem renovou com verificação antiga recebia "venceu". A faixa C (#2152)
 * existia para avisar a Diretoria dessa contradição entre as duas cópias.
 *
 * Trava (sobre a CAPTURA VIGENTE da função):
 *   A. o snapshot é o do portão: lido por affiliation_vep_snapshot (#3107), sem copiar a seleção;
 *   B. o vencimento da VEP é o maior expiryDate de capítulo participante, com o formato guardado (#2152);
 *   C. o vencimento efetivo é o da VEP e, sem ele, o da verificação manual ativa; as três faixas A leem o efetivo;
 *   D. a faixa B (verificação obsoleta) só vale para quem depende da verificação manual;
 *   E. a faixa C saiu, e os links da Diretoria apontam para /admin/filiacao;
 *   F. a população é a de quem tem vínculo ativo que exige termo (a mesma da fila, #3105);
 *   G. o radar não envia nada em ensaio, e a migration tem pós-condição contra consulta independente.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const R = maskLineComments(latestFunctionCapture(ROOT, 'v4_notify_expiring_affiliations').body);

// O bloco de uma faixa: do comentário-rótulo até o END IF que fecha o IF externo da faixa.
function faixa(rotulo) {
  const full = latestFunctionCapture(ROOT, 'v4_notify_expiring_affiliations').body;
  const i = full.indexOf(rotulo);
  assert.ok(i > 0, `faixa ${rotulo} não encontrada`);
  const ifAt = full.indexOf('IF ', i);
  const fim = full.indexOf('\n    END IF;', ifAt);
  return maskLineComments(full.slice(ifAt, fim));
}

test('a migration existe uma vez', () => {
  const f = readdirSync(MIGRATIONS).filter((n) => /^\d{14}_3108_radar_de_filiacao_le_a_vep\.sql$/.test(n));
  assert.equal(f.length, 1);
});

test('A. o snapshot é o do portão: a mesma função, sem copiar a seleção', () => {
  assert.match(
    R,
    /LEFT JOIN LATERAL \(\s+SELECT public\.affiliation_vep_snapshot\(m\.id\) -> 'pmi_memberships' AS pmi_memberships\s+\) snap ON true/,
  );
  assert.doesNotMatch(R, /FROM public\.selection_applications/, 'o radar não copia a seleção do snapshot');
  assert.doesNotMatch(R, /pmi_memberships->0/, 'nada de ler só o primeiro elemento');
});

test('B. o vencimento da VEP: maior expiryDate de capítulo participante, formato guardado', () => {
  assert.match(
    R,
    /max\(CASE WHEN e\.elem->>'expiryDate' ~ '\^\\d\{1,2\} \[A-Za-z\]\{3\} \\d\{4\}\$'\s+THEN to_date\(e\.elem->>'expiryDate', 'DD Mon YYYY'\) END\) AS vep_expira/,
  );
  assert.match(
    R,
    /JOIN public\.chapter_registry cr\s+ON cr\.chapter_code = public\.resolve_br_chapter_code\(e\.elem->>'chapterName'\) AND cr\.is_active/,
    'só capítulo participante (registro ativo)',
  );
});

test('C. o vencimento efetivo: VEP, e sem ela a verificação manual ativa; as faixas A leem o efetivo', () => {
  assert.match(R, /COALESCE\(x\.vep_expira, CASE WHEN x\.man_active THEN x\.man_expira END\) AS expira/);
  assert.match(faixa('-- (A) Expiração D-30'), /^IF r\.expira IS NOT NULL AND \(r\.expira - CURRENT_DATE\) BETWEEN 8 AND 30 THEN/);
  assert.match(faixa('-- (A) Expiração D-7'), /^IF r\.expira IS NOT NULL AND \(r\.expira - CURRENT_DATE\) BETWEEN 0 AND 7 THEN/);
  assert.match(faixa('-- (A) VENCIDA'), /^IF r\.expira IS NOT NULL AND r\.expira < CURRENT_DATE THEN/);
  assert.doesNotMatch(R, /r\.membership_expires_on|r\.days_until_expiry/, 'nenhuma faixa lê a verificação crua');
});

test('D. a faixa B só vale para quem depende da verificação manual', () => {
  assert.match(faixa('-- (B) Verificação obsoleta'), /^IF r\.fonte = 'manual' AND \(CURRENT_DATE - r\.man_created_at::date\) > 330 THEN/);
  assert.match(R, /CASE WHEN x\.vep_expira IS NOT NULL THEN 'vep'\s+WHEN x\.man_created_at IS NOT NULL THEN 'manual'\s+ELSE 'none' END AS fonte/);
});

test('E. a faixa C saiu e os links da Diretoria vão para /admin/filiacao', () => {
  assert.doesNotMatch(R, /affiliation_vep_divergence/);
  assert.doesNotMatch(R, /filter=affiliation/);
  assert.doesNotMatch(R, /\/admin\/members/);
  assert.match(R, /'\/admin\/filiacao', 'affiliation', r\.member_id,/);
});

test('F. a população é quem tem vínculo ativo que exige termo', () => {
  assert.match(
    R,
    /WHERE m\.is_active = true\s+AND EXISTS \(\s+SELECT 1 FROM public\.engagements e\s+JOIN public\.engagement_kinds ek ON ek\.slug = e\.kind AND ek\.requires_agreement IS TRUE\s+WHERE e\.person_id = m\.person_id AND e\.status = 'active'\s+\)\s+\) x/,
  );
});

test('G. todo envio está atrás de NOT p_dry_run, e a migration confere o ensaio', () => {
  const inserts = (R.match(/INSERT INTO public\.notifications/g) || []).length;
  const guardados = (R.match(/IF NOT p_dry_run AND (?:v_filiacao_member_id IS NOT NULL AND )?NOT EXISTS \(/g) || []).length;
  assert.equal(inserts, 4, 'quatro faixas que avisam');
  assert.equal(guardados, inserts, 'cada INSERT atrás de NOT p_dry_run');
  const f = readdirSync(MIGRATIONS).find((n) => /_3108_radar_de_filiacao_le_a_vep\.sql$/.test(n));
  const mig = maskLineComments(readFileSync(resolve(MIGRATIONS, f), 'utf8'));
  assert.match(mig, /v_ensaio := public\.v4_notify_expiring_affiliations\(true\);/);
  assert.match(mig, /RAISE EXCEPTION '#3108: o ensaio \(%\) diverge da consulta independente/);
});
