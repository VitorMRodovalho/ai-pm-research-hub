/**
 * Contract: #1710 onda D — o selo passa a acontecer sozinho, e o caminho automatico nao herda
 * autoridade de ninguem.
 *
 * As tres ondas anteriores deram ao ato escopo, reversao, tela e MCP. Esta e a parte
 * IRREVERSIVEL: a partir dela, faltas sao materializadas sem ninguem clicar. Medido em 13/08/2026,
 * antes de ligar: 55 eventos alcancaveis no ciclo, 111 faltas sobre 44 pessoas, e destes 12 eventos
 * / 51 faltas ja fora da carencia de 14 dias — o que a primeira execucao apos o piso vai gravar.
 *
 * Quatro coisas que so um guard segura:
 *
 * 1. UMA escrita em massa, dois chamadores. `seal_event_attendance` resolve o chamador por
 *    `auth.uid()`; o cron nao tem sessao. A saida foi extrair o nucleo — e o risco e alguem
 *    "resolver" o cron copiando o corpo, que e duplicar exatamente a escrita que este item existe
 *    para domesticar.
 *
 * 2. O caminho do usuario nao pode perder os gates na mudanca. Extrair o nucleo move as checagens
 *    de FATO DO EVENTO para fora da RPC; se a delegacao sumir ou o gate ficar para tras, os guards
 *    das ondas anteriores seguiriam verdes lendo o nucleo, sem provar que o caminho do usuario
 *    passa por autoridade nenhuma.
 *
 * 3. O piso corta por data LOCAL. `CURRENT_DATE` e UTC: das 21h a meia-noite de Brasilia o banco ja
 *    virou o dia, e o piso prometido as pessoas seria cruzado horas antes da data anunciada. Mesma
 *    borda que o #1727 ja pagou uma vez, no mesmo mecanismo.
 *
 * 4. O ensaio nao pode falar a lingua do ato. `events_sealed: 12` num dry-run le como "12 eventos
 *    foram selados": numero certo, significado errado — a familia de defeito que este item ja pagou
 *    tres vezes.
 *
 * Camadas: A estatica sobre a captura de migration, com a inversa de cada afirmacao; A' md5 do
 * corpo vivo contra a captura; C ao vivo — o ensaio roda pela MESMA funcao que executa, e nao
 * deixa linha nenhuma.
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

const CHAVES = {
  _seal_event_attendance_apply: '_seal_event_attendance_apply@p_event_id uuid, p_actor_id uuid, p_dry_run boolean',
  seal_event_attendance: 'seal_event_attendance@p_event_id uuid',
  seal_attendance_window_cron: 'seal_attendance_window_cron@p_dry_run boolean',
};

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function captura(chave) {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(chave);
  assert.ok(cap, `sem captura de migration para ${chave}. Chaves vistas: ${[...latest.keys()]
    .filter(k => k.startsWith(chave.split('@')[0] + '@')).join(' | ')}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === chave);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${chave}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: estes corpos EXPLICAM os predicados que o teste procura e os que ele proibe. */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

async function rpc(nome, corpo) {
  return fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    body: JSON.stringify(corpo ?? {}),
  });
}

// ── A ────────────────────────────────────────────────────────────────────────────────────

test('#1710-D A: a RPC do usuario mantem os DOIS gates e DELEGA a escrita', () => {
  const { body, file } = captura(CHAVES.seal_event_attendance);
  const codigo = achatado(body);

  assert.match(codigo, /WHERE m\.auth_id = auth\.uid\(\)/,
    `${file}: a RPC do usuario tem de continuar resolvendo o chamador`);
  assert.match(codigo, /IF NOT public\._can_manage_event\(p_event_id\) THEN/,
    `${file}: o gate por recurso saiu junto com a extracao do nucleo`);
  assert.match(codigo, /public\._seal_event_attendance_apply\(p_event_id, v_caller_id, false\)/,
    `${file}: a RPC precisa delegar ao nucleo, passando o chamador como ator`);

  // A INVERSA, e o ponto inteiro da extracao: a escrita em massa nao pode existir em DOIS lugares.
  assert.doesNotMatch(codigo, /INSERT INTO public\.attendance/,
    `${file}: a RPC voltou a carregar a escrita em massa; agora sao duas copias`);
});

test('#1710-D A: o nucleo carrega os fatos do EVENTO, e nenhum gate de chamador', () => {
  const { body, file } = captura(CHAVES._seal_event_attendance_apply);
  const codigo = achatado(body);

  assert.match(codigo, /IF v_end > now\(\) THEN/, `${file}: a guarda de evento por terminar sumiu`);
  assert.match(codigo, /IF v_eligible = 0 THEN/, `${file}: o ramo de coorte vazia sumiu`);
  assert.match(codigo, /'reason', 'skipped_empty_cohort'/, `${file}: o desfecho perdeu o nome proprio`);
  assert.match(codigo, /public\._roster_seal_marker\(\)/, `${file}: o carimbo deixou de vir da funcao unica`);

  // O nucleo NAO decide autoridade: quem chama e que decide. Um gate aqui dentro faria o cron
  // depender de `auth.uid()`, que ele nao tem — e o caminho automatico morreria em silencio.
  assert.doesNotMatch(codigo, /auth\.uid\(\)|_can_manage_event/,
    `${file}: o nucleo passou a olhar o chamador; o gate e de quem chama`);
});

test('#1710-D A: o selo automatico nao inventa um ator, e o log sabe distinguir', () => {
  const { body, file } = captura(CHAVES._seal_event_attendance_apply);
  const codigo = achatado(body);

  assert.match(codigo, /'source', CASE WHEN p_actor_id IS NULL THEN 'window_cron' ELSE 'manual' END/,
    `${file}: sem o carimbo, um selo do cron e um selo escrito por teste ficam indistinguiveis `
    + `no audit log — os dois chegam como service_role com ator nulo`);

  const cron = achatado(captura(CHAVES.seal_attendance_window_cron).body);
  assert.match(cron, /_seal_event_attendance_apply\(r\.id, NULL, p_dry_run\)/,
    'o cron precisa passar ator NULO: ninguem marcou aquela falta, e atribui-la a alguem e registrar uma falsidade');
});

test('#1710-D A: o piso corta por data LOCAL, e a carencia vem de configuracao', () => {
  const { body, file } = captura(CHAVES.seal_attendance_window_cron);
  const codigo = achatado(body);

  assert.match(codigo, /now\(\) AT TIME ZONE 'America\/Sao_Paulo'\)::date/,
    `${file}: o piso compara em UTC; das 21h a meia-noite ele cruza a data prometida antes da hora`);
  assert.doesNotMatch(codigo, /v_hoje_local < v_floor.*CURRENT_DATE|CURRENT_DATE < v_floor/,
    `${file}: voltou a comparacao por CURRENT_DATE`);

  assert.match(codigo, /FROM public\.platform_settings WHERE key = 'attendance\.seal_window'/,
    `${file}: a janela virou literal no corpo; mudar a carencia passaria a exigir DDL`);
  // A INVERSA: o numero de dias nao pode estar cravado no predicado.
  assert.doesNotMatch(codigo, /interval '14 days'/,
    `${file}: a carencia foi cravada no corpo em vez de vir da configuracao`);
});

test('#1710-D A: o ensaio nao devolve as chaves do ato', () => {
  const { body, file } = captura(CHAVES.seal_attendance_window_cron);
  const codigo = achatado(body);

  assert.match(codigo, /'events_would_seal'/, `${file}: o ensaio precisa de chaves proprias`);
  assert.match(codigo, /'absences_would_write'/, `${file}: idem para as faltas`);
  // A INVERSA: chaves iguais fazem `events_sealed: 12` num dry-run ler como doze selos reais.
  const iDry = codigo.indexOf('CASE WHEN p_dry_run');
  assert.ok(iDry > -1, `${file}: o retorno nao discrimina ensaio de ato`);
});

// ── A' ───────────────────────────────────────────────────────────────────────────────────

for (const [nome, chave] of Object.entries(CHAVES)) {
  test(`#1710-D A': o corpo VIVO de ${nome} == a captura mais recente`, {
    skip: dbGated ? false : skipMsg,
  }, async () => {
    const { bodyHash, file } = captura(chave);
    const res = await rpc('_audit_function_source', { p_proname: nome });
    assert.ok(res.ok, `_audit_function_source devia responder 2xx (veio ${res.status})`);
    const linhas = await res.json();
    assert.equal(linhas.length, 1, `esperado exatamente 1 ${nome} em pg_proc`);
    assert.equal(md5(normalizeBody(linhas[0].prosrc)), bodyHash,
      `corpo vivo de ${nome} divergente de ${file}: a mudanca esta so num dos dois lados`);
  });
}

// ── C ────────────────────────────────────────────────────────────────────────────────────

test('#1710-D C: o ensaio roda pela mesma funcao que executa, e NAO escreve', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  const antes = await fetch(
    `${SUPABASE_URL}/rest/v1/events?select=id&roster_sealed_at=not.is.null`,
    { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, Prefer: 'count=exact' } },
  );
  const nAntes = Number(antes.headers.get('content-range')?.split('/')?.[1] ?? -1);

  const res = await rpc('seal_attendance_window_cron', { p_dry_run: true });
  assert.ok(res.ok, `o ensaio devia responder 2xx (veio ${res.status})`);
  const corpo = await res.json();
  assert.equal(corpo.success, true, `ensaio falhou: ${JSON.stringify(corpo)}`);
  assert.equal(corpo.dry_run, true, 'o retorno tem de declarar que foi ensaio');
  assert.ok(!('events_sealed' in corpo),
    `o ensaio devolveu a chave do ATO: ${JSON.stringify(corpo)}`);

  const depois = await fetch(
    `${SUPABASE_URL}/rest/v1/events?select=id&roster_sealed_at=not.is.null`,
    { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, Prefer: 'count=exact' } },
  );
  const nDepois = Number(depois.headers.get('content-range')?.split('/')?.[1] ?? -2);
  assert.equal(nDepois, nAntes,
    `o ensaio carimbou evento: ${nAntes} -> ${nDepois}. Ele nao pode escrever nada.`);
});

test('#1710-D C: a configuracao da janela existe e tem os dois campos', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/platform_settings?select=value&key=eq.attendance.seal_window`,
    { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } },
  );
  assert.ok(res.ok, `leitura de platform_settings devia responder 2xx (veio ${res.status})`);
  const linhas = await res.json();
  assert.equal(linhas.length, 1, 'a chave attendance.seal_window nao existe: o cron nao roda sem ela');
  const v = linhas[0].value;
  assert.equal(typeof v.grace_days, 'number', 'grace_days ausente ou nao numerico');
  assert.match(String(v.floor_date), /^\d{4}-\d{2}-\d{2}$/, 'floor_date ausente ou fora do formato');
});
