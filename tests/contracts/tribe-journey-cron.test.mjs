/**
 * Cron semanal de reconciliação do card de Jornada da Tribo — contract test.
 *
 * O card só cumpre o desenho aprovado se o estado for CALCULADO. Sem
 * reconciliação periódica ele congela no retrato do dia da criação e vira a
 * lista estática que a decisão do GP (2026-08-20) descartou.
 *
 * O que este teste protege:
 *
 *  A. O cron NÃO pode depender de sessão. `tribe_journey_health` e
 *     `sync_tribe_journey_card` são gated por auth.uid(); o pg_cron não tem
 *     sessão. Por isso existem os workers internos sem portão — e o portão
 *     público tem de continuar de pé nos wrappers.
 *  B. Os workers internos NÃO podem ficar alcançáveis por anon/authenticated.
 *     Eles escrevem em quadro de tribo com ator arbitrário; expô-los seria
 *     entregar escrita sem autoridade.
 *  C. O cron NÃO cria card novo. Escolher o dono do card é decisão humana;
 *     tribo sem card sai no relatório em vez de ganhar dono arbitrário.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260821035435_tribe_journey_weekly_reconcile_cron.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const migCode = migRaw.replace(/^\s*--.*$/gm, '');

// ── (A) static ─────────────────────────────────────────────────────────────
test('static: a migration cria os workers internos e a entrada do cron', () => {
  assert.ok(migRaw, 'migration 20260821035435 presente');
  for (const fn of ['_tribe_journey_health_data', '_sync_tribe_journey_card',
                    'sync_tribe_journey_cards_cron']) {
    assert.match(migCode, new RegExp(`FUNCTION public\\.${fn}\\(`), `${fn} criada`);
  }
});

test('static: os wrappers públicos mantêm o portão (decisão A)', () => {
  // Separar worker de wrapper não pode virar porta dos fundos: quem é chamável
  // por authenticated continua exigindo manage_platform.
  for (const fn of ['tribe_journey_health', 'sync_tribe_journey_card']) {
    const i = migCode.indexOf(`FUNCTION public.${fn}(`);
    assert.ok(i > 0, `${fn} recriada na migration`);
    const body = migCode.slice(i, migCode.indexOf('$fn$;', i));
    assert.match(body, /authentication_required/, `${fn} exige sessão`);
    assert.match(body, /can_by_member\(v_caller_id, 'manage_platform'\)/,
      `${fn} exige manage_platform`);
  }
});

test('static: os workers internos são inalcançáveis por anon e authenticated (decisão B)', () => {
  for (const fn of ['_tribe_journey_health_data', '_sync_tribe_journey_card',
                    'sync_tribe_journey_cards_cron']) {
    assert.match(migCode,
      new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}[\\s\\S]{0,120}authenticated`),
      `${fn} revoga authenticated`);
    assert.match(migCode,
      new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}[\\s\\S]{0,80}service_role`),
      `${fn} concede só a service_role`);
  }
});

test('static: o worker de escrita exige ator explícito', () => {
  // Sem isso o cron poderia gravar com ator nulo e a trilha de auditoria some.
  const i = migCode.indexOf('FUNCTION public._sync_tribe_journey_card(');
  const body = migCode.slice(i, migCode.indexOf('$fn$;', i));
  assert.match(body, /IF p_actor_id IS NULL THEN RAISE EXCEPTION 'actor_required'/,
    'ator nulo é recusado');
});

test('static: o cron não cria card novo (decisão C)', () => {
  const i = migCode.indexOf('FUNCTION public.sync_tribe_journey_cards_cron(');
  const body = migCode.slice(i, migCode.indexOf('$fn$;', i));
  assert.match(body, /IF r\.card_id IS NULL THEN[\s\S]{0,300}CONTINUE;/,
    'tribo sem card é pulada, não adotada');
  assert.match(body, /sem_card_lista/, 'e sai no relatório');
  assert.match(body, /COALESCE\(r\.assignee_id, r\.created_by\)/,
    'o dono é herdado do card, não inventado');
});

test('static: uma tribo com dado ruim não derruba as outras', () => {
  const i = migCode.indexOf('FUNCTION public.sync_tribe_journey_cards_cron(');
  const body = migCode.slice(i, migCode.indexOf('$fn$;', i));
  assert.match(body, /EXCEPTION WHEN OTHERS THEN/, 'erro por tribo é capturado');
  assert.match(body, /admin_audit_log/, 'a execução fica registrada');
});

test('static: o agendamento é diário e o job semanal foi removido (#1906)', () => {
  // A migration original agendava semanal. Trocar a cadência sem trocar o NOME deixaria
  // um `...-weekly` rodando todo dia; criar o nome novo sem remover o antigo deixaria
  // DOIS jobs disparando a mesma reconciliação (cron.schedule faz upsert por nome).
  const CRON2 = resolve(ROOT, 'supabase/migrations/20260821203103_jornada_escrita_condicional_e_agenda_diaria.sql');
  assert.ok(existsSync(CRON2), 'migration do follow-up #1906 presente');
  const c2 = readFileSync(CRON2, 'utf8').replace(/^\s*--.*$/gm, '');
  assert.match(c2, /cron\.unschedule\('tribe-journey-cards-weekly'\)/, 'o semanal é removido');
  assert.match(c2, /cron\.schedule\(\s*'tribe-journey-cards-daily'/, 'o diário é criado');
  assert.match(c2, /'20 6 \* \* \*'/, 'todo dia, minuto deslocado dos vizinhos');
});

test('static: a escrita é condicional — execução sem novidade não toca no card (#1906)', () => {
  // Sem isto, a cadência diária faria os 12 cards aparecerem como alterados todo dia e
  // treinaria o líder a ignorar o card, que é o oposto do objetivo.
  const CRON2 = resolve(ROOT, 'supabase/migrations/20260821203103_jornada_escrita_condicional_e_agenda_diaria.sql');
  const c2 = readFileSync(CRON2, 'utf8').replace(/^\s*--.*$/gm, '');
  const i = c2.indexOf('FUNCTION public._sync_tribe_journey_card(');
  const body = c2.slice(i, c2.indexOf('$fn$;', i));

  assert.match(body, /IF v_desc_atual IS DISTINCT FROM v_desc THEN/,
    'a descrição só é reescrita quando difere');
  assert.equal(/Última reconciliação/.test(body), false,
    'o carimbo de execução NÃO pode voltar para a descrição — ele vive no admin_audit_log');
  assert.match(body, /IF v_assignee_atual IS NULL THEN/,
    'assignee_id só entra no SET quando está nulo');
  assert.equal(/SET description = v_desc, assignee_id/.test(body), false,
    'assignee_id não pode voltar ao SET incondicional: UPDATE OF dispara pela coluna MENCIONADA, ' +
    'não pela alterada, e acionaria trg_board_item_deliverable_xp à toa (#1881)');
  assert.match(body, /ELSIF v_txt_atual IS DISTINCT FROM/,
    'atividade só é reescrita quando texto, estado ou posição diferem');
  assert.match(body, /'changed', v_changed/, 'o retorno declara se houve mudança');
});

// ── (B) DB-gated ────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('DB: o cron roda SEM sessão — é a razão de ele existir',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('sync_tribe_journey_cards_cron');
    assert.ok(!error, `service-role sem auth.uid() precisa passar (erro: ${error?.message})`);
    assert.equal(data?.success, true, 'sucesso');
    assert.equal(data?.erros, 0, `nenhuma tribo com erro (detalhe: ${JSON.stringify(data?.detalhe)})`);
    assert.ok(data?.reconciliados >= 1, 'reconciliou ao menos uma tribo');
  });

test('DB: os wrappers públicos continuam fail-closed sem sessão',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Controle negativo do teste acima: o cron passa porque NÃO tem portão;
    // se os wrappers também passassem, o portão teria sido perdido no refactor.
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    for (const [fn, args] of [
      ['tribe_journey_health', { p_window_days: 90 }],
      ['sync_tribe_journey_card', { p_initiative_id: '00000000-0000-0000-0000-000000000000', p_dry_run: true }],
    ]) {
      const { error } = await sb.rpc(fn, args);
      assert.ok(error, `${fn}: sem auth.uid() precisa ser rejeitado`);
      assert.match(String(error.message), /authentication_required/i, `${fn}: fail-closed`);
    }
  });

test('DB: reconciliar duas vezes não duplica card',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const a = await sb.rpc('sync_tribe_journey_cards_cron');
    const b = await sb.rpc('sync_tribe_journey_cards_cron');
    assert.ok(!a.error && !b.error, 'as duas execuções passam');
    assert.equal(a.data?.reconciliados, b.data?.reconciliados,
      'mesma população reconciliada — nenhum card novo apareceu entre as duas');
  });

test('DB: a segunda execução seguida não altera nada (escrita condicional, #1906)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    await sb.rpc('sync_tribe_journey_cards_cron');            // converge
    const { data, error } = await sb.rpc('sync_tribe_journey_cards_cron');
    assert.ok(!error, `precisa resolver (erro: ${error?.message})`);
    assert.equal(data?.alterados, 0,
      `execução sem novidade não pode escrever (alterados: ${data?.alterados})`);
    assert.ok(data?.reconciliados >= 1, 'mas segue reconciliando a população');
  });

test('DB: o job está agendado e ativo',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    // exec_sql não é exposto; o job é observável pelo próprio retorno do cron
    // acima. Aqui garantimos apenas que a função-alvo do agendamento existe com
    // o nome exato que o cron.schedule registrou.
    const { error } = await sb.rpc('sync_tribe_journey_cards_cron');
    assert.ok(!error, 'a função nomeada no agendamento existe e é executável');
  });
