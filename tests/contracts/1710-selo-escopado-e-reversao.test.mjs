/**
 * Contract: #1710 — o selo tem ESCOPO, tem REVERSAO, e a grade diz que ele existe.
 *
 * O #1657 tirou o "sem linha = falta" e, com isso, transferiu todo o peso para o ato de SELAR:
 * hoje selar e o unico jeito de a plataforma afirmar que alguem faltou. Medido em 13/08/2026:
 * 510 eventos passados, 0 selados; 55 alcancaveis no ciclo corrente; 111 faltas materializaveis
 * sobre 44 pessoas. O mecanismo estava pronto e inerte — e e por estar inerte que tres defeitos
 * nao doiam ainda:
 *
 * 1. ESCOPO. `seal_event_attendance` gateava em `can_by_member(caller, 'manage_event')`, um gate
 *    SEM recurso. Medido impersonando os 14 portadores: **622 pares (lider, evento)** passavam por
 *    ele e nao pelo gate escopado — cada um dos 12 lideres de tribo alcancava de 49 a 55 eventos de
 *    OUTRAS tribos, e selar grava falta em massa. Mesma classe do #1728. Dar botao a este ato sem
 *    trocar o gate seria publicar a porta.
 *
 * 2. REVERSAO. O PM exigiu reversao por evento; `unseal` nao existia. Sem ela, "confirme antes de
 *    executar" e a UNICA barreira entre um clique e o historico de 44 pessoas.
 *
 * 3. CARIMBO NA GRADE. As duas grades JA liam `roster_sealed_at` para decidir entre 'unrecorded' e
 *    'absent', e nenhuma o publicava: a tela mostrava a consequencia do selo sem nunca dizer que o
 *    selo existe.
 *
 * Provado ao vivo em transacao abortada (13/08/2026), atuando como um lider de tribo:
 *   evento de outra tribo -> {"error":"Acesso negado: requer manage_event neste evento"}
 *   painel do lider       -> 46 eventos, contra 244 visiveis no ciclo
 *   dry-run previu 1 falta; o selo gravou 1 (coorte 2, 1 ja registrado); linhas 1 -> 2
 *   reversao              -> removeu 1, preservou 0, linhas 2 -> 1, carimbo de volta a NULL
 *
 * Camadas: A estatica sobre a captura de migration, com a INVERSA de cada afirmacao; A' md5 do
 * corpo vivo contra a captura; C o invariante ao vivo — hoje VACUO por ausencia de uso (0 linhas
 * com o carimbo), e isso esta dito no proprio teste, porque populacao zero le como verde.
 *
 * Migration: 20260813144320_1710_selo_escopado_reversao_e_carimbo_na_grade.sql
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
  _roster_seal_marker: '_roster_seal_marker@',
  seal_event_attendance: 'seal_event_attendance@p_event_id uuid',
  // #1710 onda D: a escrita em massa e a auditoria do SELO passaram para um nucleo compartilhado
  // com o cron (que nao tem `auth.uid()`); a RPC ficou com os gates e a delegacao. A reversao nao
  // se moveu: ela so tem caminho humano.
  _seal_event_attendance_apply: '_seal_event_attendance_apply@p_event_id uuid, p_actor_id uuid, p_dry_run boolean',
  unseal_event_attendance: 'unseal_event_attendance@p_event_id uuid',
  preview_seal_attendance: 'preview_seal_attendance@p_cycle_start date',
  get_attendance_grid: 'get_attendance_grid@p_tribe_id integer, p_event_type text',
  get_tribe_attendance_grid: 'get_tribe_attendance_grid@p_tribe_id integer, p_event_type text',
  get_initiative_attendance_grid: 'get_initiative_attendance_grid@p_initiative_id uuid, p_event_type text',
};

/** As TRES grades de presenca. Duas seriam a metade do problema: a terceira aplica a mesma regra do
 *  #1657 e serve a tela de iniciativa. A lista vive aqui porque e ela que o teste varre — varrer por
 *  nome de familia foi como o #1728 perdeu duas RPCs da propria classe. */
const GRADES = [
  CHAVES.get_attendance_grid,
  CHAVES.get_tribe_attendance_grid,
  CHAVES.get_initiative_attendance_grid,
];

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

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b). E este corpo
 *  EXPLICA, em comentario, exatamente o predicado que deixou de existir. */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

async function rpc(nome, corpo) {
  return fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    body: JSON.stringify(corpo ?? {}),
  });
}

// ── A ────────────────────────────────────────────────────────────────────────────────────

test('#1710 A: selar e gateado por RECURSO, e o gate sem recurso nao coexiste', () => {
  const { body, file } = captura(CHAVES.seal_event_attendance);
  const codigo = achatado(body);

  assert.match(codigo, /IF NOT public\._can_manage_event\(p_event_id\) THEN/,
    `${file}: sem o gate por recurso, quem pode gerir algum evento pode selar qualquer um`);
  // A INVERSA, que e o defeito: o gate amplo nao pode voltar NEM como segunda porta. Um OR entre os
  // dois devolveria os 622 pares medidos.
  assert.doesNotMatch(codigo, /can_by_member\(v_caller_id, 'manage_event'\)/,
    `${file}: o gate SEM recurso voltou; ele alcanca evento de qualquer tribo`);

  // Onda D: o gate ficou aqui e a escrita saiu. As duas coisas tem de continuar ligadas — um gate
  // que nao delega nao gateia nada, e uma delegacao sem gate e o buraco de volta.
  assert.match(codigo, /public\._seal_event_attendance_apply\(p_event_id, v_caller_id, false\)/,
    `${file}: a RPC gateada deixou de delegar ao nucleo que escreve`);
  assert.doesNotMatch(codigo, /INSERT INTO public\.attendance/,
    `${file}: a escrita em massa voltou para a RPC; agora existem duas copias dela`);
});

test('#1710 A: o dry-run tem a MESMA fronteira do ato', () => {
  const { body, file } = captura(CHAVES.preview_seal_attendance);
  const codigo = achatado(body);

  // Um ensaio mais largo que o ato lista botao que erra; um ensaio mais estreito esconde trabalho.
  assert.match(codigo, /AND public\._can_manage_event\(e\.id\)/,
    `${file}: o preview precisa filtrar pelo mesmo gate por recurso que o selo aplica`);
});

test('#1710 A: escrita e reversao leem o carimbo da MESMA funcao', () => {
  const selo = captura(CHAVES._seal_event_attendance_apply);
  const rev = captura(CHAVES.unseal_event_attendance);

  for (const [nome, cap] of [['o nucleo do selo', selo], ['unseal', rev]]) {
    const codigo = achatado(cap.body);
    assert.match(codigo, /public\._roster_seal_marker\(\)/,
      `${cap.file}: ${nome} precisa chamar _roster_seal_marker()`);
    // A INVERSA: duas copias do literal divergem na primeira manutencao, e a reversao vira um
    // DELETE que nao casa nada — verde, silencioso e inutil.
    assert.doesNotMatch(codigo, /\[roster_seal\]/,
      `${cap.file}: ${nome} embutiu o literal do carimbo em vez de derivar da funcao`);
  }
});

test('#1710 A: a reversao preserva a linha em que alguem encostou', () => {
  const { body, file } = captura(CHAVES.unseal_event_attendance);
  const codigo = achatado(body);

  const iDel = codigo.indexOf('DELETE FROM public.attendance');
  assert.ok(iDel > -1, `${file}: a reversao precisa apagar as linhas que o selo criou`);
  const recorte = codigo.slice(iDel, iDel + 400);
  assert.match(recorte, /a\.present = false/,
    `${file}: sem o predicado de present, reverter apaga presenca marcada DEPOIS do selo`);
  assert.match(recorte, /a\.excused = false/,
    `${file}: sem o predicado de excused, reverter apaga a justificativa dada DEPOIS do selo`);
  // E o carimbo do evento tem de cair junto: apagar as linhas e deixar roster_sealed_at preenchido
  // devolveria a grade ao defeito do #1657 — evento "fechado" sem nenhuma linha, tudo lido como falta.
  assert.match(codigo, /UPDATE public\.events SET roster_sealed_at = NULL/,
    `${file}: reverter precisa limpar roster_sealed_at, senao a grade volta a acusar por ausencia`);
});

test('#1710 A: os dois atos deixam rastro em admin_audit_log', () => {
  for (const [acao, chave] of [['attendance.roster_sealed', CHAVES._seal_event_attendance_apply],
                               ['attendance.roster_unsealed', CHAVES.unseal_event_attendance]]) {
    const { body, file } = captura(chave);
    const codigo = achatado(body);
    assert.match(codigo, /INSERT INTO public\.admin_audit_log/,
      `${file}: escrita em massa no historico de gente real sem registro deixa o dano como unica evidencia`);
    assert.ok(codigo.includes(`'${acao}'`), `${file}: a acao registrada tem de ser ${acao}`);
  }
});

test('#1710 A: as TRES grades publicam roster_sealed_at', () => {
  for (const chave of GRADES) {
    const { body, file } = captura(chave);
    const codigo = achatado(body);
    assert.match(codigo, /'roster_sealed_at', ge\.roster_sealed_at/,
      `${file}: a grade le roster_sealed_at para decidir a celula e nao o publica; a tela mostra a
       consequencia do selo sem poder dizer que ele existe`);
    // Controle: a leitura que decide a celula continua la. Publicar o carimbo sem manter a regra
    // deixaria a coluna nova enfeitando uma grade que voltou a acusar por ausencia.
    assert.match(codigo, /roster_sealed_at IS NULL THEN 'unrecorded'/,
      `${file}: a regra do #1657 saiu junto com a mudanca`);
  }
});

// ── A' ───────────────────────────────────────────────────────────────────────────────────

for (const [nome, chave] of Object.entries(CHAVES)) {
  test(`#1710 A': o corpo VIVO de ${nome} == a captura mais recente`, {
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

test('#1710 C: a reversao existe e recusa quem nao esta autenticado', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // service_role nao tem auth.uid(): o desfecho esperado e a recusa POR AUTENTICACAO, nao um erro
  // de forma. E o mesmo controle do #1727 C sobre o preview — prova que a funcao esta publicada e
  // que o primeiro portao dela responde.
  const res = await rpc('unseal_event_attendance', { p_event_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(res.ok, `unseal_event_attendance devia estar publicada (veio ${res.status})`);
  const corpo = await res.json();
  assert.equal(corpo.success, false, 'service_role nao pode reverter selo');
  assert.match(String(corpo.error), /Not authenticated/,
    'a recusa tem de ser por autenticacao, e nao por evento inexistente');
});

test('#1710 C: nenhuma linha do selo sobrevive a um evento nao selado', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // ⚠️ VACUO HOJE: 0 linhas carregam o carimbo, porque 0 de 510 eventos foram selados. Populacao
  // zero le como verde, e este teste diria "passou" com o mecanismo inteiro desligado. Ele existe
  // para o dia em que o cron da janela rodar: a partir dai, carimbo sem selo significa que uma
  // reversao apagou o `roster_sealed_at` e esqueceu as linhas, que e o estado do #1657 de volta.
  const marcador = await rpc('_roster_seal_marker');
  assert.ok(marcador.ok, `_roster_seal_marker devia responder 2xx (veio ${marcador.status})`);
  const texto = await marcador.json();
  assert.match(String(texto), /^\[roster_seal\]/,
    'o carimbo precisa do prefixo que distingue linha do selo de falta registrada por gente');

  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/attendance?select=event_id,events!inner(roster_sealed_at)`
    + `&notes=eq.${encodeURIComponent(String(texto))}&events.roster_sealed_at=is.null`,
    { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } },
  );
  assert.ok(res.ok, `leitura de attendance devia responder 2xx (veio ${res.status})`);
  const linhas = await res.json();
  assert.equal(linhas.length, 0,
    `ha linha com o carimbo do selo em evento sem roster_sealed_at: ${JSON.stringify(linhas.slice(0, 3))}`);
});
