// tests/contracts/1813-alerta-com-destinatario.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C / #1109) — an unwired contract file is silently skipped.
/**
 * #1813 — o alerta diario de consistencia da selecao so alcancava quem tem role='lead',
 * e o ciclo aberto tem zero leads.
 *
 * Medido em 16/08/2026: o ciclo aberto tem 0 leads e 7 membros de comite (evaluator +
 * observer); os 3 leads da plataforma inteira estao todos em ciclos FECHADOS. O laco de
 * notificacao do cron nao rodava nenhuma vez -- o alerta disparava e nao chegava a ninguem.
 *
 * NAO E O MESMO BUG DO #1809. La, 'member' estava fora do dominio do CHECK e o predicado
 * `role IN ('lead','member')` valia lead sozinho -- literal morto. Aqui 'lead' esta no
 * dominio e o predicado faz o que diz. O que falta e destinatario.
 *
 * DECISAO DO PM (16/08): fallback ESTRUTURAL. Nomear um lead resolveria hoje e voltaria a
 * falhar calado no proximo ciclo que abrisse sem lead -- contencao por dado nao e contencao
 * por estrutura.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations', '20260816191212_1813_alerta_com_destinatario.sql'),
  'utf8',
);

// Prosa sai antes do assert: os comentarios CITAM o predicado antigo, e guard que le prosa
// acusa a propria documentacao (licao do #1801/#1805/#1809).
const SQL = MIG
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

test('#1813 mig: a resolucao do destinatario saiu de dentro do cron', () => {
  assert.match(SQL, /CREATE OR REPLACE FUNCTION public\._selection_consistency_recipients\(\)/);
  // o cron passa a chamar a funcao, e nao a carregar o predicado solto
  assert.match(SQL, /SELECT r\.member_id, r\.via FROM public\._selection_consistency_recipients\(\) r/);
  assert.doesNotMatch(SQL, /FOR v_lead IN\s*\n\s*SELECT DISTINCT sc\.member_id/,
    'o predicado cru nao pode continuar dentro do cron');
});

test('#1813 mig: o fallback so vale quando NAO ha lead — nunca em paralelo', () => {
  // se os dois ramos valessem juntos, o alerta iria para o GP mesmo havendo lead responsavel
  assert.match(SQL, /WHERE NOT EXISTS \(SELECT 1 FROM leads\)/);
  // e o ramo de lead segue com o predicado de ciclo em andamento fixado no #1805
  assert.match(SQL, /WHERE c\.status NOT IN \('draft','closed'\)/);
  assert.match(SQL, /AND sc\.role = 'lead'/);
});

test('#1813 mig: a audiencia de fallback usa o padrao canonico da plataforma', () => {
  // o mesmo de _alert_sweep_cron — autoridade por can_by_member, nunca por lista de papeis
  assert.match(SQL, /m\.is_active\s*\n?\s*AND public\.can_by_member\(m\.id, 'manage_platform'\)/);
  assert.doesNotMatch(SQL, /operational_role\s*=\s*'/, 'autoridade nao se decide por rotulo de papel');
});

test('#1813 mig: a entrega vira fato registrado, nao suposicao', () => {
  // sem isto, "alertou" e indistinguivel de "nao tinha para quem alertar" — que e exatamente
  // como este defeito passou despercebido
  assert.match(SQL, /RETURNING id INTO v_audit_id/);
  assert.match(SQL, /jsonb_build_object\('notified_count', v_notified, 'notified_via', v_via\)/);
  assert.match(SQL, /v_notified := v_notified \+ 1;/);
});

test('#1813 mig: a funcao nova nasce fechada (CREATE FUNCTION concede a PUBLIC)', () => {
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\._selection_consistency_recipients\(\) FROM PUBLIC, anon, authenticated/i);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\._selection_consistency_recipients\(\) TO service_role/i);
});

// ─── portao de DB ────────────────────────────────────────────────────────────────────────────────

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1813 DB: o alerta NUNCA fica sem destinatario', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_selection_consistency_recipients');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0,
    'a resolucao devolveu conjunto vazio — o alerta diario voltaria a disparar para ninguem, calado');
});

test('#1813 DB: a resolucao escolhe UM caminho, nunca os dois ao mesmo tempo', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_selection_consistency_recipients');
  assert.ifError(error);
  const caminhos = [...new Set(data.map(r => r.via))];
  assert.equal(caminhos.length, 1,
    `resolucao misturou caminhos (${caminhos.join(' + ')}): havendo lead responsavel, o alerta ` +
    'nao pode ir tambem para o GP');
  assert.ok(['lead', 'manage_platform'].includes(caminhos[0]), `caminho inesperado: ${caminhos[0]}`);
});

test('#1813 DB: enquanto nao houver lead em ciclo em andamento, quem recebe e o GP', { skip: dbGated ? false : skipMsg }, async () => {
  // Medido em 16/08/2026: 0 leads em ciclo em andamento, 2 membros ativos com manage_platform.
  // Este teste NAO fixa o numero (a plataforma nomeia lead quando quiser) — fixa a implicacao:
  // sem lead, o caminho tem de ser o do GP; com lead, tem de ser o do lead.
  const cli = sb();
  const [{ data: dest, error: e1 }, { data: leads, error: e2 }] = await Promise.all([
    cli.rpc('_selection_consistency_recipients'),
    cli.from('selection_committee').select('member_id, selection_cycles!inner(status)').eq('role', 'lead'),
  ]);
  assert.ifError(e1);
  assert.ifError(e2);

  const temLeadEmAndamento = (leads ?? []).some(
    r => r.member_id && !['draft', 'closed'].includes(r.selection_cycles?.status));

  assert.equal(dest[0].via, temLeadEmAndamento ? 'lead' : 'manage_platform',
    temLeadEmAndamento
      ? 'ha lead em ciclo em andamento, mas o alerta caiu no fallback'
      : 'nao ha lead em ciclo em andamento, e o alerta nao caiu no fallback — volta a nao ter destinatario');
});

test('#1813 DB: a resolucao nao e alcancavel por chamador anonimo', { skip: dbGated ? false : skipMsg }, async () => {
  const anon = createClient(process.env.SUPABASE_URL, process.env.PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY ?? 'sem-chave', { auth: { persistSession: false } });
  const { error } = await anon.rpc('_selection_consistency_recipients');
  assert.ok(error, 'a resolucao expoe ids de membro e nao pode responder a anonimo');
});
