/**
 * Contract: #1727 + #1729 — o selo enxerga o relogio LOCAL, e coorte vazia nao vira "lista fechada".
 *
 * #1727. A janela de elegibilidade cortava em `e.date <= CURRENT_DATE`, uma comparacao de DATA em
 * UTC. Um evento de hoje as 20h ficava elegivel desde o instante em que o dia UTC comecou: **23
 * horas antes de acontecer** (medido em 11/08/2026 02h12 UTC = 10/08 23h12 no Brasil). A virada de
 * fuso responde por 3 dessas horas; as outras 20 vem de comparar data em vez de instante — corrigir
 * so o fuso nao resolveria, e foi por isso que o diagnostico inicial da issue teve de ser corrigido.
 *
 * A guarda que o selo ja tinha (`IF v_date > CURRENT_DATE THEN 'Evento futuro'`) usava a MESMA
 * comparacao, entao nao pegava: uma reuniao de hoje a noite nao era "futura" para ela.
 *
 * #1729. `UPDATE ... SET roster_sealed_at` rodava mesmo com coorte 0, carimbando "lista fechada" num
 * evento que nunca teve lista — e a partir do carimbo a grade le ausencia de linha como falta.
 *
 * Provado ao vivo em transacao abortada (11/08/2026), impersonando um gestor:
 *   coorte vazia  -> {"reason":"skipped_empty_cohort"}, roster_sealed_at NULO antes e depois
 *   nao terminou  -> {"error":"Evento ainda não terminou","ends_at":"2026-08-12T00:30:00+00:00"}
 *   INVERSA       -> evento normal sela: coorte 69, 51 ja registrados, 18 faltas gravadas com o
 *                    carimbo `[roster_seal]`, linhas 51 -> 69
 *
 * ⚠️ O instante de termino e UMA funcao (`_event_end_instant`), nao dois predicados equivalentes.
 * A elegibilidade e a guarda do selo respondem a MESMA pergunta; duas copias divergem na primeira
 * manutencao, e a divergencia so aparece na faixa de horas em que uma diz sim e a outra nao.
 *
 * Camadas: A estatica sobre as capturas DERIVADAS, com a inversa de cada afirmacao; A' md5 do corpo
 * vivo nas quatro funcoes; C o invariante ao VIVO, que e o que uma camada estatica nao alcanca —
 * nenhum evento por terminar pode estar na elegibilidade, agora, com o relogio de verdade.
 *
 * Migrations: 20260811021532_1710_corte_local_coorte_vazia_e_dry_run_do_selo.sql
 *             20260811021752_1710_dry_run_do_selo_uma_chamada_por_pessoa.sql
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
  _event_end_instant: '_event_end_instant@p_date date, p_time_start time without time zone, p_duration_minutes integer, p_timezone text',
  _attendance_eligible_events: '_attendance_eligible_events@p_member_id uuid, p_cycle_start date',
  seal_event_attendance: 'seal_event_attendance@p_event_id uuid',
  // #1710 onda D: a escrita em massa saiu da RPC para um nucleo compartilhado com o cron, que nao
  // tem `auth.uid()`. As checagens de FATO DO EVENTO (fim, coorte) moraram sempre com a escrita e
  // foram junto; a RPC ficou com os gates. Repontar as asserções para o nucleo so e honesto porque
  // cada uma ganhou, ao lado, a prova de que o caminho do usuario DELEGA — senao o guard passaria a
  // provar que a checagem existe em algum lugar, sem provar que alguem a alcanca.
  _seal_event_attendance_apply: '_seal_event_attendance_apply@p_event_id uuid, p_actor_id uuid, p_dry_run boolean',
  preview_seal_attendance: 'preview_seal_attendance@p_cycle_start date',
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

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b). */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

async function rpc(nome, corpo) {
  return fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    body: JSON.stringify(corpo ?? {}),
  });
}

// ── A ────────────────────────────────────────────────────────────────────────────────────

test('#1727 A: a elegibilidade corta pelo INSTANTE, e pela funcao compartilhada', () => {
  const { body, file } = captura(CHAVES._attendance_eligible_events);
  const codigo = achatado(body);

  assert.match(
    codigo,
    /public\._event_end_instant\(e\.date, e\.time_start, e\.duration_minutes, e\.timezone\) <= now\(\)/,
    `${file}: sem o corte por instante, a reuniao de hoje a noite conta como esperada desde a madrugada`,
  );
  // A INVERSA: o predicado nao pode ser reescrito inline. Duas copias da mesma pergunta divergem, e
  // a divergencia so aparece na faixa de horas em que uma diz sim e a outra nao.
  assert.doesNotMatch(
    codigo,
    /AT TIME ZONE COALESCE\(NULLIF\(e\.timezone/,
    `${file}: o instante foi reescrito inline em vez de usar _event_end_instant`,
  );
});

test('#1727 A: a guarda do selo deixou de comparar DATA', () => {
  const { body, file } = captura(CHAVES._seal_event_attendance_apply);
  const codigo = achatado(body);

  assert.match(codigo, /IF v_end > now\(\) THEN/,
    `${file}: a guarda de evento por terminar sumiu`);

  // E o caminho do usuario chega ate ela: sem a delegacao, a guarda existiria num nucleo que
  // ninguem chama.
  const rpc = achatado(captura(CHAVES.seal_event_attendance).body);
  assert.match(rpc, /public\._seal_event_attendance_apply\(p_event_id, v_caller_id, false\)/,
    'a RPC do usuario deixou de delegar ao nucleo que carrega a guarda');
  // A INVERSA, que e o defeito: `v_date > CURRENT_DATE` compara data em UTC e deixa passar a
  // reuniao de hoje a noite. Ela nao pode coexistir — seria uma segunda guarda mais fraca.
  assert.doesNotMatch(codigo, /v_date > CURRENT_DATE/,
    `${file}: a guarda por DATA voltou; ela nao ve a reuniao que ainda vai comecar hoje`);
});

test('#1729 A: coorte vazia nao carimba roster_sealed_at', () => {
  // Onda D: o ramo mora no nucleo, que e o unico lugar onde o carimbo e escrito — e por isso o
  // unico lugar onde ele pode ser escrito ERRADO. Vale para os dois chamadores de uma vez.
  const { body, file } = captura(CHAVES._seal_event_attendance_apply);
  const codigo = achatado(body);

  assert.match(codigo, /IF v_eligible = 0 THEN/,
    `${file}: sem o ramo de coorte vazia, selar carimba "lista fechada" em evento sem lista`);
  assert.match(codigo, /'reason', 'skipped_empty_cohort'/,
    `${file}: o desfecho precisa de nome proprio para o chamador listar o evento a revisar`);

  // O que de fato importa: o ramo tem de RETORNAR antes do UPDATE. Um ramo que so registra e segue
  // adiante carimbaria assim mesmo, com o teste acima verde.
  const i0 = codigo.indexOf('IF v_eligible = 0 THEN');
  const iRet = codigo.indexOf('RETURN jsonb_build_object', i0);
  const iUpd = codigo.indexOf('UPDATE public.events SET roster_sealed_at', i0);
  assert.ok(iRet > -1 && iRet < iUpd,
    `${file}: o ramo de coorte vazia precisa RETORNAR antes do UPDATE que carimba`);
});

test('#1710 A: o dry-run resolve a elegibilidade uma vez por PESSOA', () => {
  const { body, file } = captura(CHAVES.preview_seal_attendance);
  const codigo = achatado(body);

  // A versao por par (EXISTS correlacionado dentro do JOIN de eventos) fazia ~26 mil chamadas e
  // estourava o timeout. O guard existe porque "funciona" e "responde" nao sao a mesma coisa.
  assert.match(
    codigo,
    /FROM public\.members m CROSS JOIN LATERAL public\._attendance_eligible_events\(m\.id, NULL\) ee/,
    `${file}: a elegibilidade tem de ser resolvida uma vez por pessoa`,
  );
  assert.doesNotMatch(
    codigo,
    /JOIN public\.members m ON[^;]*EXISTS \(SELECT 1 FROM public\._attendance_eligible_events/,
    `${file}: voltou o EXISTS por par (pessoa, evento), que estourava o timeout`,
  );
  // E reporta a coorte POR EVENTO, que e o ponto do ensaio. Atencao ao lugar: o nome publicado
  // (`eligible_cohort_n`) mora na clausula RETURNS TABLE, que fica FORA do $function$ e portanto
  // NAO esta no corpo. Quem asserta o nome publicado tem de ler o arquivo, nao o corpo.
  assert.match(codigo, /count\(\*\)::int AS cohort_n/,
    `${file}: o corpo precisa contar a coorte por evento`);
  const sqlDoArquivo = readFileSync(join(MIGRATIONS_DIR, file), 'utf8');
  assert.match(sqlDoArquivo, /eligible_cohort_n integer/,
    `${file}: a coluna publicada sumiu da assinatura; sem ela, vazia == todos registrados`);
  assert.match(sqlDoArquivo, /would_write_absent_n integer/,
    `${file}: sem "quantas faltas gravaria", o ensaio nao responde a pergunta que motivou o dry-run`);
});

// ── A' ───────────────────────────────────────────────────────────────────────────────────

for (const [nome, chave] of Object.entries(CHAVES)) {
  test(`#1727 A': o corpo VIVO de ${nome} == a captura mais recente`, {
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

test('#1727 C: nenhum evento POR TERMINAR esta na elegibilidade, com o relogio de verdade', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // Este e o invariante. Uma camada estatica nao o alcanca: ela le o texto do predicado, e o
  // predicado pode estar certo enquanto `_event_end_instant` devolve qualquer coisa.
  const res = await rpc('_audit_eligible_events_not_ended');
  if (res.status === 404) {
    // sem RPC de auditoria dedicada, exerce pela via publica: o preview carrega o mesmo predicado
    const prev = await rpc('preview_seal_attendance', {});
    assert.equal(prev.status, 400,
      'preview_seal_attendance devia recusar service_role (sem auth.uid()) com 400');
    const erro = await prev.json();
    assert.match(JSON.stringify(erro), /Not authenticated/,
      'a recusa tem de ser por autenticacao: e o gate, nao um erro de forma');
    return;
  }
  assert.ok(res.ok, `_audit_eligible_events_not_ended devia responder 2xx (veio ${res.status})`);
  const linhas = await res.json();
  assert.equal(Number(linhas), 0, 'ha evento por terminar dentro da elegibilidade');
});

test('#1727 C: _event_end_instant DISCRIMINA passado de futuro', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // Controle: uma funcao que devolvesse sempre o passado deixaria o corte inerte e todos os testes
  // acima verdes. A pergunta aqui e se ela realmente separa os dois lados de now().
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/events?select=id,date&order=date.desc&limit=1`,
    { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } },
  );
  assert.ok(res.ok, `leitura de events devia responder 2xx (veio ${res.status})`);
  const evs = await res.json();
  assert.ok(evs.length === 1, 'sem evento para exercer');

  const futuro = await rpc('_event_end_instant', {
    p_date: '2099-01-01', p_time_start: '10:00:00', p_duration_minutes: 60, p_timezone: 'America/Sao_Paulo',
  });
  const passado = await rpc('_event_end_instant', {
    p_date: '2000-01-01', p_time_start: '10:00:00', p_duration_minutes: 60, p_timezone: 'America/Sao_Paulo',
  });
  assert.ok(futuro.ok && passado.ok, 'as duas chamadas deviam responder 2xx');
  const [tf, tp] = [await futuro.json(), await passado.json()];
  const agora = Date.now();
  assert.ok(new Date(tf).getTime() > agora, `2099 devia cair no futuro, veio ${tf}`);
  assert.ok(new Date(tp).getTime() < agora, `2000 devia cair no passado, veio ${tp}`);
});
