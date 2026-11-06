/**
 * Contract: #2393 (emenda de 06/11/2026 à ADR-0134 §4) — o alerta de divergência da candidatura piloto chega a quem
 * decide.
 *
 *   A emenda trocou controle por auditoria: na objetiva, o líder da vaga avalia com 1 pessoa de fora, e a divergência
 *   grande entre as duas notas é o sinal. O detector por candidatura (#2542) gravava o alerta e ninguém o lia.
 *   (a) o detector avisa a gestão (manage_platform) quando nasce um alerta novo numa candidatura piloto, sem nome de
 *       candidato, num tipo imediato do catálogo da ADR-0022;
 *   (b) o painel leva as partes com alerta aberto só à gestão, e a tela mostra o selo.
 * Camada S (estática): cada asserção casa a condição com o resultado no trecho que decide.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return maskLineComments(cap.block).replace(/\s+/g, ' ');
}

test('#2393p (a): o detector avisa a gestão quando nasce um alerta novo numa candidatura piloto', () => {
  const c = captura('_trg_evaluation_divergence');
  // O detector em si não muda: 30% da média, por tipo, com 2 notas ou mais.
  assert.match(c, /IF v_n >= 2 AND v_mean > 0 AND \(v_max - v_min\) > c_limiar \* v_mean THEN INSERT INTO public\.selection_evaluation_anomalies/,
    'a regra do detector mudou');
  // "Já havia" é lido ANTES de o detector apagar e regravar o alerta aberto; depois do DELETE ele sempre sairia false.
  const leitura = c.indexOf("v_ja_havia := EXISTS (SELECT 1 FROM public.selection_evaluation_anomalies an WHERE an.application_id = NEW.application_id AND an.alert_type = 'high_variance' AND an.resolved_at IS NULL AND an.payload->>'evaluation_type' = NEW.evaluation_type);");
  assert.ok(leitura > 0, 'o detector deixou de ler se já havia alerta aberto daquela parte');
  assert.ok(leitura < c.indexOf('DELETE FROM public.selection_evaluation_anomalies'), 'o "já havia" é lido depois do DELETE e sai sempre false');
  // O aviso fica DENTRO do ramo que grava o alerta, só para o alerta novo e só na candidatura piloto.
  assert.match(c,
    /FROM unnest\(v_ids\) AS ev; IF NOT v_ja_havia AND NOT public\._na_avaliacao_geral\(NEW\.application_id\) THEN SELECT a\.vep_opportunity_id INTO v_vaga FROM public\.selection_applications a WHERE a\.id = NEW\.application_id; PERFORM public\.create_notification\( m\.id, 'selection_pilot_divergence', 'Divergência na candidatura ' \|\| left\(NEW\.application_id::text, 8\), [^;]*'\/admin\/selection', 'selection_application', NEW\.application_id \) FROM public\.members m WHERE m\.is_active AND m\.auth_id IS NOT NULL AND public\.can_by_member\(m\.id, 'manage_platform'\); END IF; END IF; RETURN NEW;/,
    'o aviso saiu do ramo do alerta, perdeu uma condição, mudou de destinatário ou de tipo');
  assert.doesNotMatch(c, /applicant_name|\.email\b/, 'o detector passou a ler nome ou e-mail do candidato');
});

test('#2393p (a): o aviso é imediato, no helper e no catálogo da ADR-0022', () => {
  const d = captura('_delivery_mode_for');
  assert.match(d, /WHEN 'selection_pilot_divergence' THEN 'transactional_immediate'/, 'o modo do aviso não é imediato no helper');
  const cat = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
  assert.equal(cat.types.selection_pilot_divergence?.delivery_mode, 'transactional_immediate', 'o catálogo não registra o aviso como imediato');
});

test('#2393p (b): o painel leva as partes com alerta aberto só à gestão, e só na candidatura piloto', () => {
  const c = captura('get_selection_dashboard');
  assert.match(c,
    /\|\| jsonb_build_object\('divergence_types', CASE WHEN v_ve_piloto AND NOT public\._na_avaliacao_geral\(a\.id\) THEN \( SELECT COALESCE\(jsonb_agg\(DISTINCT an\.payload->>'evaluation_type'\), '\[\]'::jsonb\) FROM public\.selection_evaluation_anomalies an WHERE an\.application_id = a\.id AND an\.alert_type = 'high_variance' AND an\.resolved_at IS NULL\) END\)/,
    'o painel deixou de levar as partes com divergência aberta, ou passou a levá-las a quem não é gestão');
  assert.match(c, /v_ve_piloto := public\.can_by_member\(v_caller_id, 'manage_platform'\);/, 'a gestão deixou de ser quem vê o piloto');
});

test('#2393p (b): a tela mostra o selo a partir de divergence_types, com o texto nas 3 línguas', () => {
  const src = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8')).replace(/\s+/g, ' ');
  assert.match(src,
    /const divergenceCell = Array\.isArray\(r\.divergence_types\) && r\.divergence_types\.length > 0 \? `<div><span [^>]*data-testid="divergence-badge" title="\$\{esc\(T\.divergenceBadgeHint \|\| ''\)\}">⚠ \$\{esc\(T\.divergenceBadge \|\| 'Divergência'\)\}<\/span><\/div>` : '';/,
    'o selo deixou de vir de divergence_types');
  assert.match(src, /title="\$\{esc\(oppTitle\)\}">\$\{oppCell\}\$\{divergenceCell\}<\/td>/, 'a célula da vaga deixou de mostrar o selo');
  assert.match(src, /divergenceBadge: t\('admin\.selection\.divergenceBadge', lang\), divergenceBadgeHint: t\('admin\.selection\.divergenceBadgeHint', lang\),/,
    'a tela deixou de ler o texto do selo do dicionário');
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    for (const k of ['divergenceBadge', 'divergenceBadgeHint']) {
      const linha = d.split('\n').find((l) => l.startsWith(`  'admin.selection.${k}': `));
      assert.ok(linha && /: '[^'\n]{5,}',$/.test(linha), `${lang}: falta admin.selection.${k}`);
      assert.doesNotMatch(linha, /—|–/, `${lang}: travessão em admin.selection.${k}`);
    }
  }
});
