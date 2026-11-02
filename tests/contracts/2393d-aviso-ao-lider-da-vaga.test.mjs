/**
 * Contract: #2393, fatia 3 (ADR-0134, decisão do GP em 02/11/2026) — aviso ao líder da vaga quando chega
 * candidatura.
 *
 * Um cron de hora em hora (`_selection_opening_new_applications_cron`) manda 1 aviso por (líder, vaga), com a
 * contagem e a vaga, nunca com dado de candidato. Os destinatários saem do MESMO portão da leitura por vaga.
 * `opening_alert_processed_at` carimba toda linha tratada; o estoque anterior à coluna nasce carimbado.
 *
 * Camadas:
 *   S  estática, na captura vigente:
 *      - a coluna nasce com default now() e o perde em seguida (o estoque carimbado, a linha nova NULL);
 *      - o retrato da rodada, a contagem (vaga com iniciativa, não anonimizada, submitted ou screening), os
 *        destinatários (portão da leitura por vaga e conflito de interesse) e o carimbo do mesmo retrato;
 *      - INVERSA: nada de dado de candidato no corpo, nada de _v4_leader_member_ids, nada de uuid fixo;
 *      - o tipo no catálogo e no _delivery_mode_for como digest_weekly; o cron só para service_role e agendado.
 *   L  viva: anon recebe 42501 no cron.
 * O efeito (quem recebe, quantos avisos, idempotência) é a verificação do pacote, com vaga sintética.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const CRON = '_selection_opening_new_applications_cron';
const TIPO = 'selection_opening_new_applications';

function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}
const sqlDe = (file) => maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');

test('#2393d S: a coluna nasce carimbando o estoque e perde o default na mesma migration', () => {
  const { file } = captura(CRON);
  const sql = sqlDe(file);
  const add = sql.search(/ALTER TABLE public\.selection_applications ADD COLUMN IF NOT EXISTS opening_alert_processed_at timestamptz DEFAULT now\(\);/);
  const drop = sql.search(/ALTER TABLE public\.selection_applications ALTER COLUMN opening_alert_processed_at DROP DEFAULT;/);
  assert.ok(add !== -1, 'a coluna não nasce com default now(), e o estoque ficaria NULL');
  assert.ok(drop !== -1, 'a coluna não perde o default, e a candidatura nova nasceria carimbada');
  assert.ok(add < drop, 'o DROP DEFAULT vem antes do ADD COLUMN');
});

test('#2393d S: o cron tira o retrato das linhas não tratadas e carimba só esse retrato', () => {
  const { corpo } = captura(CRON);
  assert.match(corpo, /SELECT array_agg\(sa\.id\) INTO v_ids FROM public\.selection_applications sa WHERE sa\.opening_alert_processed_at IS NULL;/,
    'o retrato não é das linhas ainda não tratadas');
  assert.match(corpo, /UPDATE public\.selection_applications SET opening_alert_processed_at = now\(\) WHERE id = ANY \(v_ids\) AND opening_alert_processed_at IS NULL;/,
    'o carimbo não é do mesmo retrato');
  assert.equal((corpo.match(/v_ids :=|INTO v_ids/g) || []).length, 1, 'o retrato é refeito no meio da rodada');
});

test('#2393d S: só conta candidatura nova de vaga com iniciativa, não anonimizada, em submitted ou screening', () => {
  const { corpo } = captura(CRON);
  assert.match(corpo,
    /JOIN public\.vep_opportunities vo ON vo\.opportunity_id = sa\.vep_opportunity_id WHERE sa\.id = ANY \(v_ids\) AND vo\.initiative_id IS NOT NULL AND sa\.anonymized_at IS NULL AND sa\.status IN \('submitted', 'screening'\) GROUP BY vo\.id,/,
    'a contagem do aviso mudou de população');
});

test('#2393d S: os destinatários saem do portão da leitura por vaga, menos o conflito de interesse', () => {
  const { corpo } = captura(CRON);
  assert.match(corpo,
    /SELECT m\.id FROM public\.members m WHERE m\.is_active = true AND public\.can_by_member\(m\.id, 'view_opening_applications', 'initiative', v_grupo\.initiative_id\) AND NOT public\.selection_coi_recused\(m\.id, v_grupo\.cycle_id\) LOOP PERFORM public\.create_notification\(/,
    'os destinatários não são os do portão da leitura por vaga');
  assert.match(corpo, /PERFORM public\.create_notification\( v_dest\.id, 'selection_opening_new_applications', v_titulo, v_corpo, '\/minhas-vagas\?vaga=' \|\| v_grupo\.opportunity_id, 'vep_opportunity', v_grupo\.vaga_id \);/,
    'o aviso não é o do tipo novo com o link para Minhas vagas');
  assert.equal((corpo.match(/create_notification\(/g) || []).length, 1, 'há outro aviso no cron');
});

test('#2393d S (INVERSA): o aviso não leva dado de candidato, nem lista fixa, nem o atalho de líderes', () => {
  const { corpo } = captura(CRON);
  for (const proibido of ['applicant_name', 'email', 'first_name', 'last_name', 'phone', 'motivation', 'resume']) {
    assert.ok(!corpo.includes(proibido), `o cron lê ${proibido}`);
  }
  assert.doesNotMatch(corpo, /_v4_leader_member_ids/, 'o cron usa o atalho de líderes, que não exige vínculo autoritativo');
  assert.doesNotMatch(corpo, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, 'o cron tem um uuid fixo');
  const titulo = corpo.match(/v_titulo := ([^;]*);/);
  assert.ok(titulo && !/sa\.|v_dest/.test(titulo[1]), 'o título do aviso usa outra coisa além da contagem');
  const corpoAviso = corpo.match(/v_corpo := ([^;]*);/);
  assert.ok(corpoAviso && !/sa\./.test(corpoAviso[1]) && /v_grupo\.opportunity_id/.test(corpoAviso[1]),
    'o corpo do aviso usa dado da candidatura');
});

test('#2393d S: o tipo é digest_weekly no catálogo e explícito no _delivery_mode_for', () => {
  const cat = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
  assert.equal(cat.types[TIPO]?.delivery_mode, 'digest_weekly', 'o catálogo não declara o tipo como digest_weekly');
  const { corpo } = captura('_delivery_mode_for');
  assert.match(corpo, new RegExp(`WHEN '${TIPO}' THEN 'digest_weekly'`), 'o helper não tem o tipo explícito como digest_weekly');
});

function semGrantDepois(file, funcao, papeis) {
  const re = new RegExp(`GRANT[^;]*ON FUNCTION public\\.${funcao}\\b[^;]*\\b(${papeis})\\b`, 'i');
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= file)) {
    assert.doesNotMatch(maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')), re, `${f}: devolve ${funcao} a ${papeis}`);
  }
}

test('#2393d S: o cron é só do service_role, SECURITY DEFINER com search_path vazio, e está agendado', () => {
  const { file, corpo } = captura(CRON);
  assert.match(corpo, /RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS/, 'o cron perdeu SECURITY DEFINER ou o search_path vazio');
  const sql = sqlDe(file);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._selection_opening_new_applications_cron\(\) FROM PUBLIC, anon, authenticated;/, 'o cron não é revogado de PUBLIC, anon e authenticated');
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\._selection_opening_new_applications_cron\(\) TO service_role;/, 'o cron não é concedido ao service_role');
  semGrantDepois(file, CRON, 'anon|PUBLIC|authenticated');
  assert.match(sql, /SELECT cron\.schedule\( 'selection-opening-new-applications-hourly', '23 \* \* \* \*', \$cron\$ SELECT public\._selection_opening_new_applications_cron\(\) \$cron\$ \);/,
    'o cron não está agendado de hora em hora');
});

// ─── L: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('#2393d L: anon recebe 42501 no cron (e não 404, que seria a função ausente)',
  { skip: URL_BASE && KEY && ANON ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${CRON}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    const texto = await r.text();
    assert.ok([401, 403].includes(r.status), `anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
    assert.match(texto, /"code":"42501"/, `a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
  });
