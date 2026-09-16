// tests/contracts/2323-detector-de-conclusao-de-onboarding-tem-cron.test.mjs
// Registrar nas whitelists "test:behavioural" E "test:contracts" do package.json (#1109).
// (DB-aware: as camadas C e D abrem conexão. As A e B são estáticas.)
/**
 * #2323 — o detector que CONCLUI passo de onboarding passa a ter quem o acione.
 *
 * O QUE A MEDIÇÃO DE 16/09 MOSTROU, e que este arquivo existe para não deixar regredir:
 *
 *   * `auto_detect_onboarding_completions()` nunca teve cron. `cron.job` com filtro de
 *     onboarding devolvia UM job — `detect_onboarding_overdue`, que marca ATRASO e nunca
 *     conclusão. Um detector de atraso sem o detector de conclusão do lado faz a métrica
 *     dizer abandono onde havia trabalho feito.
 *   * `start_trail` estava em 18,9% (20 de 106) com a ÚLTIMA conclusão em 09/04 — cinco meses.
 *     Os outros três passos que esta MESMA função cobre estavam em 85-90%, porque cada um tem
 *     trigger próprio. `start_trail` é o único sem trigger, e por isso o único que expôs a
 *     ausência do agendamento.
 *   * 45 pessoas tinham pontos de `trail` com o passo ainda aberto; 33 delas tinham a trilha
 *     como ÚNICO pendente do onboarding inteiro.
 *
 * ⚠️ POR QUE ESTE GUARD NÃO SE PARECE COM O DA #2285: lá o defeito era gate de SESSÃO (a RPC
 * tinha portão de usuário e sob pg_cron `auth.uid()` é NULL), e a correção foi um wrapper.
 * Aqui a função NÃO tem gate de sessão — a proteção dela já é o ACL. Copiar o wrapper da #2285
 * seria cerimônia sem função. O que as duas ondas têm em comum não é a forma da correção, é a
 * pergunta: QUEM ACIONA ISTO?
 *
 * As camadas:
 *   A (estático) o agendamento existe, por NOME, e o comando chama a função certa.
 *   B (estático) o horário é ANTERIOR ao do detector de atraso. Não é preferência: se a
 *                conclusão rodasse depois, o overdue marcaria como atrasado quem acabou de
 *                concluir, e o alarme nasceria falso.
 *   C (vivo)     a função é chamável pelo service_role: a porta do cron existe de fato.
 *   D (vivo)     anon NÃO alcança — e barrado por PERMISSÃO, não por a função ter sumido
 *                (controle negativo, mesmo desenho da camada F da #2285).
 *
 * Nenhuma camada lê `cron.job`: PostgREST não expõe o schema `cron` (mesma limitação registrada
 * na #1543 e na #2285), então a afirmação é sobre a migration, e o estado vivo foi conferido à
 * mão em 16/09 (jobid 94, `40 12 * * *`, active).
 *
 * Cross-ref: #2323, #2285, #1548, #1844, #1543.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const JOB = 'onboarding-auto-complete-daily';
/** O detector de ATRASO, que é o vizinho de horário que importa. Conferido vivo em 16/09. */
const HORA_DO_OVERDUE = 13;

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** A migration que agenda o job, procurada por CONTEÚDO. Renomear o arquivo não pode deixar o
 *  guard verde por não encontrar nada, que é o modo de falhar mais silencioso que existe. */
function migrationDoAgendamento() {
  const achados = readdirSync(MIGRATIONS)
    .filter(f => f.endsWith('.sql'))
    .sort()
    .map(f => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .filter(src => src.includes(`cron.schedule(\n  '${JOB}'`));
  assert.ok(achados.length >= 1, `nenhuma migration agenda ${JOB}`);
  return achados[achados.length - 1];
}

// ═══════════════════════════════════════════════════════════════════════════
test('A · o cron está agendado por nome e chama a função de CONCLUSÃO', () => {
  const src = migrationDoAgendamento();
  assert.match(src, new RegExp(`cron\\.schedule\\(\\s*\\n?\\s*'${JOB}'`),
    'o job precisa ser agendado por nome (cron.schedule faz upsert por nome, então reaplicar a ' +
    'migration é idempotente)');
  const m = src.match(/\$cron\$([\s\S]*?)\$cron\$/);
  assert.ok(m, 'o comando do job precisa estar em bloco $cron$');
  assert.match(m[1], /public\.auto_detect_onboarding_completions\(\)/,
    'o job tem de chamar a função que CONCLUI passo');
  assert.ok(
    !/detect_onboarding_overdue/.test(m[1]),
    'o job passou a chamar o detector de ATRASO. Esse já tem agendamento próprio, e trocar um ' +
    'pelo outro devolveria exatamente o estado que a #2323 conserta: atraso medido, conclusão não.',
  );
});

test('B · roda ANTES do detector de atraso, e o guard mede a hora em vez de confiar na prosa', () => {
  const src = migrationDoAgendamento();
  const m = src.match(new RegExp(`cron\\.schedule\\(\\s*\\n?\\s*'${JOB}',\\s*\\n?\\s*'([^']+)'`));
  assert.ok(m, `não achei a expressão de agendamento de ${JOB}`);
  const [minuto, hora] = m[1].split(' ');
  assert.ok(Number(hora) < HORA_DO_OVERDUE,
    `o job foi movido para ${m[1]}, que não é antes das ${HORA_DO_OVERDUE}h UTC de ` +
    '`detect-onboarding-overdue-daily`. Rodando depois, o detector de atraso marca como overdue ' +
    'quem acabou de concluir, e o alarme nasce falso.');
  assert.notEqual(minuto, '0',
    'minuto deslocado de propósito (#1844): hora cheia concentra jobs e o pool é compartilhado ' +
    'com tráfego real');
});

// ═══════════════════════════════════════════════════════════════════════════
test('C · a função é chamável pelo service_role (a porta do cron existe)',
  { skip: !dbGated && skipMsg }, async () => {
  const { error } = await sb().rpc('auto_detect_onboarding_completions');
  assert.equal(error, null,
    `auto_detect_onboarding_completions deveria ser chamável pelo service_role: ${error?.message}`);
});

test('D · anon NÃO alcança a função, e é barrado por PERMISSÃO, não por ausência',
  { skip: (!dbGated || !ANON_KEY) && skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('auto_detect_onboarding_completions');
  assert.ok(error, 'anon conseguiu rodar o detector: sem gate de sessão, o ACL é a ÚNICA barreira');
  // O controle negativo: "não existe" (PGRST202) passaria como se fosse proteção. A função tem
  // de EXISTIR e recusar — senão este guard ficaria verde no dia em que alguém a apagasse.
  assert.notEqual(error.code, 'PGRST202',
    'anon foi barrado porque a função sumiu do schema cache, não porque o ACL a protege. ' +
    'Nesse estado o cron também não roda, e o guard estaria verde sobre um detector morto.');
});
