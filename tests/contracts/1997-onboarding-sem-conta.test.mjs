/**
 * #1997 — quem não tem conta na plataforma para de ser cobrado por uma jornada que não
 * consegue abrir, e o admin passa a enxergar essa diferença.
 *
 * O caso: Farhad Abdollahyan, aprovado como líder em 14/08, 16 passos de onboarding, 0 feitos,
 * `members.auth_id` NULL. Três passos já `overdue` — um deles chamado literalmente
 * `platform_access`. O detector marcou atraso no passo "conseguir acesso" e cobrou a pessoa por
 * isso numa notificação in-app, cujo link (`/workspace`, para onde `/onboarding` redireciona)
 * exige exatamente a sessão que falta.
 *
 * O guard é derivado da CAPTURA VIGENTE de cada função (a última migration que a define) e, no
 * lado do frontend, da IDENTIDADE que o próprio `AuthModal.astro` escuta — não de lista de nomes.
 * Uma migration nova que redefina a função vira o alvo sozinha; um rename do evento no modal
 * reaponta a varredura sozinho.
 *
 * Cinco garantias:
 *   (A) o detector separa "atrasado" de "impedido", e não suprime o registro;
 *   (B) `get_application_onboarding_pct` não volta a filtrar por uma chave que ninguém escreve —
 *       com o portão da #1838 intacto como controle negativo;
 *   (C) as asserções MORDEM (reinjeção do defeito tem de reprovar);
 *   (D) todo despacho de abertura do modal de login usa a identidade que o modal escuta;
 *   (E) os corpos vivos são os corpos capturados, com mensagens separadas para DDL-lag e regressão.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { parseMigration, normalizeBody } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const SRC = join(ROOT, 'src');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/**
 * Captura VIGENTE de uma função: o ÚLTIMO bloco CREATE [OR REPLACE] FUNCTION que a define,
 * varrendo as migrations em ordem cronológica de nome. Delimitador-agnóstico ($$ ou $function$).
 */
function capturaVigente(fn) {
  const files = readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort();
  let found = null;
  for (const f of files) {
    for (const b of parseMigration(f, readFileSync(join(MIGRATIONS, f), 'utf8'))) {
      if (b.name === fn) found = b;
    }
  }
  assert.ok(found, `nenhuma migration captura ${fn} — o guard ficaria vazio, não verde`);
  return found;
}

const conta = (haystack, needle) => haystack.split(needle).length - 1;

/**
 * Remove comentários `--` do corpo, preservando literais entre aspas simples (a alternância
 * consome a string ANTES de procurar `--`, então um traço duplo dentro de literal sobrevive).
 * As asserções abaixo julgam CÓDIGO: um guard que também reprovasse a palavra no comentário
 * proibiria a migration de explicar a própria correção.
 */
const semComentarios = (body) =>
  body.replace(/'(?:[^']|'')*'|--[^\n]*/g, (m) => (m.startsWith('--') ? '' : m));

// ── (A) o detector separa atrasado de impedido ────────────────────────────────

/** Violações do corpo de detect_onboarding_overdue. Vazio = saudável. */
function violacoesDetector(bodyRaw) {
  const body = semComentarios(bodyRaw);
  const v = [];

  if (!/LEFT JOIN public\.members m ON m\.id = op\.member_id/.test(body)) {
    v.push(
      'o laço não junta members: sem isso não há como saber se a pessoa alcança a plataforma. ' +
      'A junção precisa ser LEFT — member_id é nullable em onboarding_progress, e uma linha ' +
      'órfã não pode virar "tem conta" por acidente de junção.'
    );
  }
  if (!/\(m\.auth_id IS NOT NULL\) AS has_platform_account/.test(body)) {
    v.push('o laço não deriva has_platform_account de m.auth_id');
  }
  if (!/IF v_overdue\.has_platform_account THEN/.test(body)) {
    v.push('não há ramo separado para quem tem conta e quem não tem');
  }

  // O registro NÃO pode sumir: suprimir a notificação criaria ausência indistinguível de
  // "ninguém estava atrasado". São DOIS create_notification, um por ramo.
  const notifs = conta(body, 'public.create_notification(');
  if (notifs !== 2) {
    v.push(
      `esperava 2 chamadas de create_notification (uma por ramo), achei ${notifs}. ` +
      'Um só significa que o ramo sem conta ou sumiu, ou voltou a mandar todo mundo para o ' +
      'mesmo destino; zero no ramo bloqueado apaga o registro em vez de redirecioná-lo.'
    );
  }

  // Uma notificação por PESSOA, não por passo: para quem está estruturalmente impedido a
  // mensagem é sempre a mesma, e repeti-la por etapa vencida empilha ruído idêntico.
  if (!/IF NOT \(v_overdue\.member_id = ANY\(v_blocked_people\)\) THEN/.test(body)) {
    v.push('o ramo bloqueado voltou a notificar uma vez por PASSO em vez de uma vez por PESSOA');
  }

  // O destino do ramo bloqueado tem de ser público.
  if (conta(body, "'/guia-pre-onboarding'") !== 1) {
    v.push(
      'o ramo sem conta não aponta para /guia-pre-onboarding, a única página pública que ' +
      'explica como criar o acesso (passo 2 do guia: "entre com o MESMO e-mail do PMI").'
    );
  }
  // ...e o de quem TEM conta continua sendo /workspace: o conserto não pode desviar todo mundo.
  if (conta(body, "'/workspace'") !== 1) {
    v.push('quem TEM conta precisa continuar sendo mandado para /workspace (exatamente 1 ocorrência)');
  }

  // Série própria — sem ela o painel soma "não fez" com "não pode fazer".
  for (const chave of ['blocked_no_account_steps', 'blocked_no_account_people']) {
    if (!body.includes(chave)) v.push(`o retorno não expõe a série própria \`${chave}\``);
  }
  // E as séries antigas continuam de pé (a #1997 acrescenta, não substitui).
  for (const chave of ['steps_marked_overdue', 'notifications_sent']) {
    if (!body.includes(chave)) v.push(`a série pré-existente \`${chave}\` sumiu do retorno`);
  }

  // O SLA continua sendo a verdade: o passo é marcado overdue nos DOIS ramos.
  if (!/sla_deadline\s*<\s*now\(\)/.test(body)) {
    v.push('o predicado de SLA vencido saiu do laço');
  }
  if (!/UPDATE public\.onboarding_progress[\s\S]*?SET status = 'overdue'/.test(body)) {
    v.push('o passo deixou de ser marcado overdue — a verdade do SLA não pode mudar');
  }
  return v;
}

test('#1997 static: o detector separa "atrasado" de "impedido" sem apagar o registro', () => {
  const cap = capturaVigente('detect_onboarding_overdue');
  const v = violacoesDetector(cap.body);
  assert.deepEqual(v, [], `captura ${cap.file}:\n - ${v.join('\n - ')}`);
});

test('#1997 static: o portão de autoridade do detector fica intocado (controle negativo)', () => {
  const { body, file } = capturaVigente('detect_onboarding_overdue');
  assert.match(body, /can_by_member\(v_caller_id, 'manage_platform'\)/,
    `${file}: o gate manage_platform do chamador humano tem de continuar de pé`);
  assert.match(body, /auth\.role\(\) NOT IN \('service_role'\)/,
    `${file}: o bypass de contexto cron (ADR-0028 p89) tem de continuar de pé`);
});

// ── (B) o filtro que selecionava conjunto vazio não volta ─────────────────────

function violacoesPct(bodyRaw) {
  const body = semComentarios(bodyRaw);
  const v = [];
  if (/metadata\s*->>\s*'phase'/.test(body)) {
    v.push(
      "o filtro por metadata->>'phase' voltou. Nenhuma das linhas de onboarding_progress " +
      'carrega essa chave (quem a escreveria, seed_pre_onboarding_steps, não tem chamador), ' +
      'então ele seleciona conjunto vazio e a RPC devolve -1 para TODA candidatura com jornada ' +
      '— a coluna "Onboarding" do /admin/selection fica "—" para todo mundo, sempre.'
    );
  }
  if (!/status IN \('completed', 'skipped'\)/.test(body)) {
    v.push("o numerador deixou de contar 'skipped' como resolvido; um passo dispensado derruba a barra para sempre");
  }
  return v;
}

test('#1997 static: get_application_onboarding_pct mede a jornada que a candidatura tem', () => {
  const cap = capturaVigente('get_application_onboarding_pct');
  const v = violacoesPct(cap.body);
  assert.deepEqual(v, [], `captura ${cap.file}:\n - ${v.join('\n - ')}`);
});

test('#1997 static: o portão da #1838 sobrevive à mudança do corpo (controle negativo)', () => {
  const { body, file } = capturaVigente('get_application_onboarding_pct');
  assert.match(body, /can_by_member\(v_caller_id, 'manage_platform'\)/, `${file}: gate manage_platform`);
  assert.match(body, /is_selection_committee_member\(v_caller_id, sa\.cycle_id\)/, `${file}: gate do comitê do ciclo`);
  assert.match(body, /can_by_member\(v_caller_id, 'view_pii'\)/, `${file}: gate view_pii`);
});

test('#1997 static: a lista bloqueada existe e é gateada por manage_platform', () => {
  const { body, file } = capturaVigente('get_onboarding_blocked_cohort');
  assert.match(body, /WHERE m\.auth_id IS NULL/, `${file}: a coorte é definida por auth_id nulo`);
  assert.match(body, /can_by_member\(v_caller_id, 'manage_platform'\)/,
    `${file}: devolve PII de vários ciclos — o portão é manage_platform inteiro`);
  assert.match(body, /HAVING count\(\*\) FILTER \(WHERE op\.status NOT IN \('completed', 'skipped'\)\) > 0/,
    `${file}: quem já concluiu tudo não está bloqueado por nada e não pode entrar na lista`);
});

// ── (C) as asserções MORDEM ───────────────────────────────────────────────────

test('#1997 static: a asserção do detector reprova o corpo com o defeito reinjetado', () => {
  const { body } = capturaVigente('detect_onboarding_overdue');
  assert.deepEqual(violacoesDetector(body), [], 'pré-condição: o corpo real está saudável');

  // O defeito original: um único create_notification, sempre para /workspace. Recortado por
  // índice (e não por regex frouxa) para que uma injeção que erre o alvo apareça como falha
  // aqui, e não como um verde silencioso que seria lido como "a asserção não pega".
  const ini = body.indexOf('IF v_overdue.has_platform_account THEN');
  const fim = body.indexOf('\n  END LOOP;');
  assert.ok(ini > 0 && fim > ini, 'não achei o bloco de ramificação para adulterar');
  const adulterado =
    body.slice(0, ini) +
    "PERFORM public.create_notification(v_overdue.member_id, 'selection_onboarding_overdue', " +
    "'Etapa de Onboarding Atrasada', 'x', '/workspace', 'onboarding_progress', " +
    'v_overdue.progress_id);\n    v_notified := v_notified + 1;' +
    body.slice(fim);
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');

  const v = violacoesDetector(adulterado);
  assert.ok(v.length > 0, 'a asserção tem de reprovar o corpo adulterado, senão ela não pega nada');
  assert.ok(v.some((m) => m.includes('ramo separado')),
    `a violação nomeada tem de ser a do ramo ausente, e veio: ${JSON.stringify(v)}`);
});

test('#1997 static: a asserção do pct reprova o corpo com o filtro de phase reinjetado', () => {
  const { body } = capturaVigente('get_application_onboarding_pct');
  assert.deepEqual(violacoesPct(body), [], 'pré-condição: o corpo real está saudável');

  const adulterado = body.replace(
    'WHERE application_id = p_application_id;',
    "WHERE application_id = p_application_id\n  AND metadata->>'phase' = 'pre_onboarding';"
  );
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');

  const v = violacoesPct(adulterado);
  assert.ok(v.some((m) => m.includes("metadata->>'phase' voltou")),
    `a asserção tem de reprovar o filtro reinjetado, e veio: ${JSON.stringify(v)}`);
});

// ── (D) a identidade do modal de login, derivada do próprio modal ──────────────

function walkSrc(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walkSrc(full, out);
    else if (/\.(astro|ts|tsx|js|jsx)$/.test(name)) out.push(full);
  }
  return out;
}

/** Lê do próprio AuthModal quais eventos ele escuta, e em qual alvo. */
function identidadeCanonica() {
  const modal = join(SRC, 'components/ui/AuthModal.astro');
  const sql = readFileSync(modal, 'utf8');
  const nomes = [...sql.matchAll(/(document|window)\.addEventListener\(\s*'([^']+)'/g)]
    .filter(([, , evt]) => evt.startsWith('open-auth'))
    .map(([, alvo, evt]) => ({ alvo, evt }));
  assert.equal(nomes.length, 1,
    `AuthModal.astro precisa ter exatamente 1 ouvinte de abertura, achei ${nomes.length}: ` +
    `${JSON.stringify(nomes)}. Duas identidades para a mesma ação é exatamente o defeito.`);
  return nomes[0];
}

test('#1997 static: todo despacho de abertura do login usa a identidade que o modal escuta', () => {
  const canonica = identidadeCanonica();
  const erradas = [];
  for (const file of walkSrc(SRC)) {
    const txt = readFileSync(file, 'utf8');
    for (const m of txt.matchAll(/(document|window)\.dispatchEvent\(\s*new CustomEvent\(\s*'(open-auth[^']*)'/g)) {
      const [, alvo, evt] = m;
      if (alvo !== canonica.alvo || evt !== canonica.evt) {
        erradas.push(`${relative(ROOT, file)}: ${alvo}.dispatchEvent('${evt}')`);
      }
    }
  }
  assert.deepEqual(erradas, [],
    `despacho que ninguém escuta (o ouvinte é ${canonica.alvo}.addEventListener('${canonica.evt}')):\n` +
    ` - ${erradas.join('\n - ')}\n` +
    'window.dispatchEvent não alcança um addEventListener registrado em document: o botão ' +
    'simplesmente não faz nada. /workspace é o destino do 302 de /onboarding, o endereço que ' +
    'os e-mails de aprovação mandam abrir.');
});

test('#1997 static: /workspace e a home ainda TÊM um botão de login', () => {
  // Controle negativo do teste acima: ele ficaria verde se os botões sumissem.
  const ws = readFileSync(join(SRC, 'pages/workspace.astro'), 'utf8');
  assert.match(ws, /id="wk-login-btn"/, '/workspace perdeu o botão de login');
  assert.match(ws, /getElementById\('wk-login-btn'\)\?\.addEventListener\('click'/, 'o botão de /workspace perdeu o handler');
  const hero = readFileSync(join(SRC, 'components/sections/HomepageHero.astro'), 'utf8');
  assert.match(hero, /id="hero-auth-btn"/, 'a home perdeu o botão de login');
});

// ── (E) i18n: paridade nos 3 dicionários ──────────────────────────────────────

test('#1997 static: as chaves novas existem nos 3 dicionários', () => {
  for (const dic of ['pt-BR', 'en-US', 'es-LATAM']) {
    const txt = readFileSync(join(SRC, `i18n/${dic}.ts`), 'utf8');
    for (const k of ['admin.selection.noAccountBadge', 'admin.selection.noAccountTooltip']) {
      assert.ok(txt.includes(`'${k}'`), `${dic}.ts não tem a chave ${k}`);
    }
  }
});

// ── (F) vivo == capturado ─────────────────────────────────────────────────────

test('#1997 db: os corpos vivos são os corpos capturados', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_function_bodies`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
    },
    body: '{}',
  });
  assert.equal(res.status, 200, `_audit_list_public_function_bodies respondeu ${res.status}`);
  const rows = await res.json();

  for (const fn of ['detect_onboarding_overdue', 'get_application_onboarding_pct', 'get_onboarding_blocked_cohort']) {
    const cap = capturaVigente(fn);
    assert.equal(createHash('md5').update(normalizeBody(cap.body)).digest('hex'), cap.bodyHash,
      `sanidade: o md5 recomputado de ${fn} tem de bater com o do parser`);

    const live = rows.find((r) => r.proname === fn);
    assert.ok(live, `${fn} não existe no inventário vivo — a migration ainda não foi aplicada`);
    assert.equal(live.is_secdef, true, `${fn} precisa ser SECURITY DEFINER`);

    // Duas causas, duas mensagens deliberadamente diferentes: uma manda LANDAR o .sql, a outra
    // manda olhar o que mudou no corpo.
    if (live.body_md5 !== cap.bodyHash) {
      const lag = live.prosrc_len !== cap.body.length;
      assert.fail(
        lag
          ? `DDL-lag: o corpo vivo de ${fn} (${live.prosrc_len} bytes) difere da captura ` +
            `${cap.file} (${cap.body.length} bytes). Alguma DDL foi aplicada sem o .sql ` +
            'correspondente — landar/rebasear a migration que falta, NÃO editar este teste.'
          : `${fn} divergiu da captura ${cap.file} com o MESMO tamanho (${cap.body.length} ` +
            'bytes): alguém trocou o corpo vivo por outro de mesmo comprimento.'
      );
    }
  }
});
