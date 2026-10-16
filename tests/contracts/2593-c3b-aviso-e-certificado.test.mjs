/**
 * #2593, fatia C3b — aviso interno de convidado externo ainda sem convite, e certificado do convidado a partir do
 * bloco.
 *
 * Medido em 16/10/2026: um bloco com convidado externo ficou 9 dias reservado e sem e-mail sem que ninguém soubesse
 * (o cron de pendências só olha reunião passada); e issue_event_guest_certificate não tinha tela nem usava a pessoa
 * do bloco.
 *
 * O que este arquivo prova:
 *   (A) o aviso pega só convidado externo de reunião futura em até 7 dias, sem convite entregue, e vai ao dono e a
 *       quem tem manage_event, sem repetir em 2 dias; catalogado como sino;
 *   (B) o certificado do bloco exige autoridade ANTES de ler o e-mail, só para bloco confirmado depois do início
 *       da reunião, e usa o e-mail do vínculo;
 *   (C) a tela só oferece o certificado em reunião concluída, bloco confirmado com convidado externo;
 *   (D) as asserções mordem; (E) camada viva.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const MIG_DIR = join(ROOT, 'supabase/migrations');
const MIG_FILE = readdirSync(MIG_DIR).filter((f) => /_2593_c3b_/.test(f));
const MIG = MIG_FILE.length === 1 ? maskLineComments(readFileSync(join(MIG_DIR, MIG_FILE[0]), 'utf8')) : '';
const CATALOG = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
const PANEL = maskJsComments(readFileSync(resolve(ROOT, 'src/components/admin/AdminAgendaVivaPanel.tsx'), 'utf8'));

const body = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);

function violacoesLinhas(b) {
  const v = [];
  if (!/WHERE b\.external_guest AND b\.status IN \('reserved', 'confirmed'\) AND b\.guest_notified_at IS NULL\s+AND e\.status IS DISTINCT FROM 'cancelled' AND e\.time_start IS NOT NULL\s+AND \(e\.date \+ e\.time_start\) AT TIME ZONE COALESCE\(e\.timezone, 'America\/Sao_Paulo'\) > now\(\)\s+AND e\.date <= \(now\(\) AT TIME ZONE COALESCE\(e\.timezone, 'America\/Sao_Paulo'\)\)::date \+ 7/.test(b)) {
    v.push('o recorte não é: convidado externo sem convite entregue, reunião futura em até 7 dias, não cancelada');
  }
  if (!/WHEN NOT EXISTS \(SELECT 1 FROM public\.person_external_links l\s+WHERE l\.purpose = 'agenda_guest' AND l\.source_id = b\.id AND l\.contact_email IS NOT NULL\)\s+THEN 'sem_email'\s+WHEN b\.status = 'reserved' THEN 'nao_confirmado'/.test(b)) {
    v.push('o motivo não distingue sem e-mail de não confirmado');
  }
  return v;
}

function violacoesAviso(b) {
  const v = [];
  if (!/JOIN public\.members m ON m\.is_active = true\s+AND \(m\.id = a\.owner_member_id OR public\._can_anywhere\(m\.person_id, 'manage_event'\)\)/.test(b)) {
    v.push('o aviso não vai ao dono e à coordenação');
  }
  if (!/WHERE n\.recipient_id = m\.id AND n\.type = 'agenda_guest_attention' AND n\.source_id = a\.block_id\s+AND n\.created_at >= now\(\) - interval '2 days'/.test(b)) {
    v.push('o aviso repete sem a trava de 2 dias');
  }
  if (!/public\._delivery_mode_for\('agenda_guest_attention'\)/.test(b)) v.push('o modo de entrega não vem do catálogo');
  if (!/IF public\._request_is_rest_caller\(\) THEN\s+RAISE EXCEPTION/.test(b)) v.push('o cron fica chamável pela API');
  return v;
}

function violacoesCert(b) {
  const v = [];
  const iAuth = b.search(/IF NOT \(public\.can\(v_caller_person, 'manage_event', 'organization', v_b\.organization_id\)\s+OR public\.can\(v_caller_person, 'manage_platform', 'organization', v_b\.organization_id\)\) THEN\s+RETURN jsonb_build_object\('error', 'Unauthorized/);
  const iEmail = b.indexOf('SELECT l.contact_email INTO v_email');
  if (iAuth < 0) v.push('o certificado não exige manage_event/manage_platform');
  if (iAuth > 0 && iEmail > 0 && iAuth > iEmail) v.push('lê o e-mail do convidado antes de checar a autoridade');
  if (!/IF NOT v_b\.external_guest OR v_b\.status <> 'confirmed' THEN\s+RETURN jsonb_build_object\('error', 'block_not_confirmed_external_guest'\);/.test(b)) v.push('emite para bloco não confirmado');
  if (!/IF v_b\.start_at > now\(\) THEN\s+RETURN jsonb_build_object\('error', 'meeting_not_started'\);/.test(b)) v.push('emite antes da reunião');
  if (!/'guest_email', v_email,/.test(b)) v.push('não usa o e-mail do vínculo do bloco');
  return v;
}

function violacoesTela(src) {
  const v = [];
  if (!/\{ev\.is_past && b\.status === 'confirmed' && b\.external_guest && \(\s+<button onClick=\{\(\) => issueGuestCert\(b\)\}/.test(src)) {
    v.push('a tela oferece o certificado fora de reunião concluída com bloco confirmado de convidado externo');
  }
  if (!/run\(`cert-\$\{b\.id\}`, 'issue_agenda_guest_certificate', \{ p_block_id: b\.id \}/.test(src)) v.push('o certificado não passa pelo run (rpcChecked)');
  return v;
}

// ── A ─────────────────────────────────────────────────────────────────────────────────
test('#2593 C3b: o aviso pega só convidado sem convite, em reunião próxima', () => {
  assert.deepEqual(violacoesLinhas(body('_agenda_guest_attention_rows')), []);
  assert.deepEqual(violacoesAviso(body('_agenda_guest_attention_cron')), []);
  assert.match(MIG, /SELECT cron\.schedule\(\s+'agenda-guest-attention',\s+'5 12 \* \* \*',\s+\$cron\$SELECT public\._agenda_guest_attention_cron\(\);\$cron\$\s+\);/);
});

test('#2593 C3b: catalogado como sino, no SQL e no ADR-0022', () => {
  assert.match(body('_delivery_mode_for'), /WHEN 'agenda_guest_attention'\s+THEN 'suppress'/);
  assert.equal(CATALOG.types.agenda_guest_attention?.delivery_mode, 'suppress');
});

// ── B ─────────────────────────────────────────────────────────────────────────────────
test('#2593 C3b: certificado do bloco com autoridade antes do e-mail, só depois da reunião', () => {
  assert.deepEqual(violacoesCert(body('issue_agenda_guest_certificate')), []);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.issue_agenda_guest_certificate\(uuid\) FROM PUBLIC, anon;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_attention_cron\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._agenda_guest_attention_rows\(\) FROM PUBLIC, anon, authenticated;/);
});

// ── C ─────────────────────────────────────────────────────────────────────────────────
test('#2593 C3b: a tela só oferece o certificado quando faz sentido, e as chaves existem nos 3 idiomas', () => {
  assert.deepEqual(violacoesTela(PANEL), []);
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(resolve(ROOT, `src/i18n/${loc}.ts`), 'utf8');
    for (const k of ['comp.agendaViva.issueGuestCertCta', 'comp.agendaViva.issueGuestCertSuccess']) {
      assert.ok(dict.includes(`'${k}':`), `${loc} sem ${k}`);
    }
  }
});

// ── D ─────────────────────────────────────────────────────────────────────────────────
const MUTACOES = [
  ['aviso inclui quem já recebeu convite', '_agenda_guest_attention_rows', violacoesLinhas, (b) => b.replace(' AND b.guest_notified_at IS NULL', '')],
  ['aviso inclui reunião passada', '_agenda_guest_attention_rows', violacoesLinhas, (b) => b.replace("AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo') > now()", "AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo') > now() - interval '30 days'")],
  ['aviso sem trava de 2 dias', '_agenda_guest_attention_cron', violacoesAviso, (b) => b.replace("AND n.created_at >= now() - interval '2 days'", '')],
  ['aviso só ao dono', '_agenda_guest_attention_cron', violacoesAviso, (b) => b.replace(" OR public._can_anywhere(m.person_id, 'manage_event')", '')],
  ['certificado sem autoridade', 'issue_agenda_guest_certificate', violacoesCert, (b) => b.replace(/IF NOT \(public\.can\(v_caller_person, 'manage_event'[\s\S]*?END IF;/, '')],
  ['certificado antes da reunião', 'issue_agenda_guest_certificate', violacoesCert, (b) => b.replace("IF v_b.start_at > now() THEN", 'IF false THEN')],
  ['certificado para bloco reservado', 'issue_agenda_guest_certificate', violacoesCert, (b) => b.replace("IF NOT v_b.external_guest OR v_b.status <> 'confirmed' THEN", 'IF NOT v_b.external_guest THEN')],
];
for (const [nome, fn, check, mutar] of MUTACOES) {
  test(`#2593 C3b: reprova — ${nome}`, () => {
    const b = body(fn);
    const m = mutar(b);
    assert.notEqual(m, b, `a mutação "${nome}" não mudou o corpo`);
    assert.ok(check(m).length > 0, `o guard não reprovou "${nome}"`);
  });
}
test('#2593 C3b: reprova — tela oferece certificado em reunião futura', () => {
  const m = PANEL.replace("{ev.is_past && b.status === 'confirmed' && b.external_guest && (", "{b.status === 'confirmed' && b.external_guest && (");
  assert.notEqual(m, PANEL);
  assert.ok(violacoesTela(m).length > 0);
});

// ── E ─────────────────────────────────────────────────────────────────────────────────
test('#2593 C3b db: corpos VIVOS batem com as capturas', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const norm = (s) => s.replace(/\s+/g, ' ');
  for (const name of ['_delivery_mode_for', '_agenda_guest_attention_cron', '_agenda_guest_attention_rows', 'issue_agenda_guest_certificate']) {
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: name });
    assert.ifError(error);
    assert.equal((data ?? []).length, 1, `${name}: esperava 1 viva, achei ${(data ?? []).length}`);
    const c = latestFunctionCapture(ROOT, name);
    assert.equal(norm(data[0].prosrc), norm(c.body), `${name}: corpo vivo divergiu de ${c.file}`);
  }
});

test('#2593 C3b db: o certificado do bloco recusa quem chega sem sessão', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('issue_agenda_guest_certificate', { p_block_id: '00000000-0000-0000-0000-000000000000' });
  assert.ifError(error);
  assert.equal(data?.error, 'Not authenticated');
});
