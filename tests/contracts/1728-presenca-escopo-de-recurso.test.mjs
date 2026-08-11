/**
 * Contract: #1728 — as duas RPCs de escrita de presenca gateiam pelo RECURSO, nao pelo papel.
 *
 * O defeito. `mark_member_present` e `clear_member_attendance` chamavam
 * `can_by_member(caller,'manage_event')` SEM passar o evento. `public.can()` tem o ramo
 * `OR (p_resource_id IS NULL AND ae.legacy_tribe_id IS NOT NULL)`, entao uma chamada sem recurso
 * casa QUALQUER grant: quem lidera uma tribo passava no gate de um evento de outra. Medido ao vivo
 * em 10/08/2026, em transacao abortada: o lider da tribo 9 marcou presenca em evento da tribo 8 e
 * apagou linha da tribo 11, com `_can_manage_event` devolvendo false nas duas.
 *
 * E a mesma classe que o #1383 fechou em `register_attendance_batch` (_manage_event_scope_ok) e em
 * `admin_bulk_mark_attendance` (_can_manage_event). Estas duas ficaram de fora da varredura porque
 * a auditoria varreu por NOME de familia; o resto da classe (20 RPCs de escrita que recebem um
 * recurso concreto e gateiam sem ele) esta rastreado a parte.
 *
 * Por que estas duas primeiro: o aviso do #1726 roteia a correcao de falta pela primeira, e a
 * segunda APAGA a linha — inclusive a linha gravada pelo selo, que carrega o carimbo
 * `notes = '[roster_seal] ...'`. Sem escopo, `clear_member_attendance` e um unseal silencioso e
 * cross-tribo, num fluxo que nao tem `unseal`.
 *
 * Camadas: A estatica sobre a captura DERIVADA, com a INVERSA de cada afirmacao (a forma
 * resourceless nao pode coexistir); A' md5 do corpo vivo contra a captura; C o helper de escopo
 * existe e discrimina no vivo (uma camada estatica nao percebe um helper que passou a devolver
 * true para tudo — que e exatamente como este guard ficaria verde com o buraco reaberto).
 *
 * Migration: 20260811000816_1727_presenca_escopo_de_recurso_nas_duas_rpcs.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody, md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

const ALVOS = [
  { proname: 'mark_member_present', chave: 'mark_member_present@p_event_id uuid, p_member_id uuid, p_present boolean' },
  { proname: 'clear_member_attendance', chave: 'clear_member_attendance@p_event_id uuid, p_member_id uuid' },
];

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function capturaMaisRecente(chave) {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(chave);
  assert.ok(cap, `sem captura de migration para ${chave}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === chave);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${chave}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b). */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

// ── A ────────────────────────────────────────────────────────────────────────────────────

for (const { proname, chave } of ALVOS) {
  test(`#1728 A: ${proname} gateia pelo evento`, () => {
    const { body, file } = capturaMaisRecente(chave);
    const codigo = achatado(body);

    assert.match(
      codigo,
      /ELSIF NOT public\._can_manage_event\(p_event_id\) THEN/i,
      `${file}: ${proname} sem o gate escopado — qualquer detentor de manage_event alcanca qualquer evento`,
    );

    // A INVERSA, que e o defeito propriamente dito. Nao basta a forma nova ESTAR la: a forma
    // resourceless nao pode sobrar em lugar nenhum do corpo, porque ela e permissiva e um segundo
    // ramo com ela reabre o buraco inteiro com este teste verde.
    assert.doesNotMatch(
      codigo,
      /can_by_member\s*\(\s*\w+\s*,\s*'manage_event'\s*\)/i,
      `${file}: ${proname} voltou a chamar can_by_member sem passar o recurso`,
    );
  });

  test(`#1728 A: ${proname} preserva o ramo de autoatendimento`, () => {
    const { body, file } = capturaMaisRecente(chave);
    const codigo = achatado(body);
    // Marcar/limpar a PROPRIA presenca nunca dependeu de manage_event. Escopar o gate sem manter
    // este ramo trocaria um buraco por uma parede: o membro comum perderia o proprio registro.
    assert.match(
      codigo,
      /IF v_caller_id = p_member_id THEN NULL;/i,
      `${file}: ${proname} perdeu o ramo de autoatendimento`,
    );
  });
}

// ── A' ───────────────────────────────────────────────────────────────────────────────────

for (const { proname, chave } of ALVOS) {
  test(`#1728 A': o corpo VIVO de ${proname} == a captura mais recente`, {
    skip: dbGated ? false : skipMsg,
  }, async () => {
    const { bodyHash, file } = capturaMaisRecente(chave);
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_function_source`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
      body: JSON.stringify({ p_proname: proname }),
    });
    assert.ok(res.ok, `_audit_function_source devia responder 2xx (veio ${res.status})`);
    const linhas = await res.json();
    assert.equal(linhas.length, 1, `esperado exatamente 1 ${proname} em pg_proc`);
    assert.equal(md5(normalizeBody(linhas[0].prosrc)), bodyHash,
      `corpo vivo de ${proname} divergente de ${file}: a mudanca esta so num dos dois lados`);
  });
}

// ── C ────────────────────────────────────────────────────────────────────────────────────

test('#1728 C: o helper de escopo existe e DISCRIMINA no vivo', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // Uma camada estatica fica verde se `_can_manage_event` passar a devolver true para tudo — que e
  // como o buraco voltaria sem tocar em nenhuma das duas RPCs. Aqui a pergunta e outra: o helper
  // ainda separa quem pode de quem nao pode?
  //
  // `_can_manage_event` resolve o chamador por auth.uid(), que o service_role nao tem: chamado
  // assim ele devolve false em TODO evento (nao encontra membro). Isso serve como controle
  // negativo — o que nao serve e um helper que devolvesse true nessas condicoes.
  const evs = await fetch(
    `${SUPABASE_URL}/rest/v1/events?select=id&type=eq.tribo&order=date.desc&limit=3`,
    { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } },
  );
  assert.ok(evs.ok, `leitura de events devia responder 2xx (veio ${evs.status})`);
  const eventos = await evs.json();
  assert.ok(eventos.length > 0, 'sem evento de tribo para exercer o helper');

  for (const ev of eventos) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_can_manage_event`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
      body: JSON.stringify({ p_event_id: ev.id }),
    });
    assert.ok(res.ok, `_can_manage_event devia responder 2xx (veio ${res.status}) — o helper sumiu?`);
    const veredito = await res.json();
    assert.equal(veredito, false,
      'sem auth.uid() o helper tem de RECUSAR; devolver true aqui significa gate inerte');
  }
});
