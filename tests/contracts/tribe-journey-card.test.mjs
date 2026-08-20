/**
 * Card de Jornada da Tribo — contract test.
 *
 * Decisões de desenho que este teste protege (GP, 2026-08-20):
 *
 *  A. ESTADO CALCULADO. O card é reconciliado contra o dado, não escrito à mão —
 *     um card estático vira mentira em dias (no #1900, duas coletas com 10 min de
 *     diferença já divergiram em 3 cards).
 *  B. SEM FREQUÊNCIA INDIVIDUAL. Frequência por pessoa num card que a tribo
 *     inteira lê expõe dado pessoal a terceiros. A RPC não lê `attendance` — e
 *     este teste falha se alguém adicionar essa leitura.
 *  C. `source_type` NÃO é o marcador. É um domínio fechado
 *     (internal/external_partner/external_event) sobre a ORIGEM do trabalho;
 *     a primeira versão tentou usá-lo e bateu no CHECK constraint. O marcador
 *     é `jornada_tribo` em `board_items.tags`.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260820223236_tribe_journey_card.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// Guards de "não use X" precisam olhar CÓDIGO, não prosa: a própria migration
// explica em comentário por que não lê presença, e isso não pode reprovar.
const migCode = migRaw.replace(/^\s*--.*$/gm, '');

// ── (A) static ─────────────────────────────────────────────────────────────
test('static: a migration cria as 3 funções da jornada', () => {
  assert.ok(migRaw, 'migration 20260820230000 presente');
  for (const fn of ['tribe_journey_items', 'tribe_journey_health', 'sync_tribe_journey_card']) {
    assert.match(migRaw, new RegExp(`FUNCTION public\\.${fn}\\(`), `${fn} criada`);
  }
});

test('static: as RPCs são SECDEF gated por manage_platform e negam anon', () => {
  const secdef = migRaw.match(/SECURITY DEFINER/g) || [];
  assert.ok(secdef.length >= 2, 'health e sync são SECURITY DEFINER');
  const gates = migRaw.match(/can_by_member\(v_caller_id, 'manage_platform'\)/g) || [];
  assert.ok(gates.length >= 2, 'ambas gated por manage_platform');
  for (const fn of ['tribe_journey_health', 'sync_tribe_journey_card']) {
    assert.match(migRaw, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}[\\s\\S]{0,80}anon`),
      `${fn} revoga anon`);
  }
});

test('static: nenhuma frequência individual entra no card (decisão B)', () => {
  // O card é lido pela tribo inteira. Ler presença por pessoa aqui exporia dado
  // pessoal a terceiros — vai para o painel do líder e para o 1:1, não para cá.
  assert.equal(/\battendance\b/i.test(migCode), false,
    'a migration não pode ler tabelas de presença (attendance / attendance_records)');
  // Controle positivo: sem isto o guard passaria por vacuidade se o arquivo sumisse.
  assert.ok(migCode.includes('tribe_journey_health'), 'o corpo da migration foi de fato lido');
});

test('static: o marcador do card NÃO usa source_type (decisão C)', () => {
  // `board_items.source_type` tem CHECK (internal|external_partner|external_event)
  // e descreve a origem do trabalho. Usá-lo como flag de automação daria dois
  // significados à mesma coluna — e a primeira versão bateu no constraint.
  assert.match(migRaw, /'jornada_tribo' = ANY\(COALESCE\(/, 'marcador vive em tags[]');
  assert.equal(/source_type\s*=\s*'tribe_journey'/.test(migCode), false,
    'source_type não pode carregar o marcador da automação');
});

test('static: a heurística de tipo ignora o próprio card da automação', () => {
  // O título tem "checklist" -> a heurística do #1900 o classificaria como
  // `ferramenta`, e ele viraria um falso "entregável sem flag" na auditoria.
  const idx = migRaw.indexOf('FUNCTION public.portfolio_suggest_item_type(');
  assert.ok(idx > 0, 'a migration reescreve a heurística com o corte');
  const body = migRaw.slice(idx, idx + 2000);
  const guard = body.indexOf("'jornada_tribo' = ANY(");
  const firstBranch = body.indexOf("THEN 'webinar'");
  assert.ok(guard > 0 && firstBranch > 0, 'corte e ramos presentes');
  assert.ok(guard < firstBranch, 'o corte precisa vir ANTES do primeiro ramo de tipo');
});

test('static: o sync é idempotente por desenho', () => {
  assert.match(migRaw, /ON CONFLICT \(item_id, member_id, role\) DO NOTHING/,
    'a atribuição do líder é idempotente');
  assert.match(migRaw, /text LIKE '\[' \|\| \(v_item->>'key'\) \|\| '\]%'/,
    'as atividades são casadas pelo prefixo [Jn]');
  assert.match(migRaw, /p_dry_run boolean DEFAULT true/,
    'dry_run é o padrão: escrever no quadro de uma tribo precisa ser pedido');
});

// ── (B) DB-gated ────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('DB: as RPCs estão no ar e são fail-closed sem auth.uid()',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    for (const [fn, args] of [
      ['tribe_journey_health', { p_window_days: 90 }],
      ['sync_tribe_journey_card', { p_initiative_id: '00000000-0000-0000-0000-000000000000', p_dry_run: true }],
    ]) {
      const { error } = await sb.rpc(fn, args);
      assert.ok(error, `${fn}: service-role (sem auth.uid()) precisa ser rejeitado`);
      assert.equal(/could not find the function/i.test(error.message), false,
        `${fn}: assinatura precisa estar deployada (erro: ${error.message})`);
      assert.match(String(error.message), /authentication_required/i, `${fn}: fail-closed`);
    }
  });

test('DB: a heurística devolve NULL para um card marcado como jornada',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: comMarcador, error: e1 } = await sb.rpc('portfolio_suggest_item_type', {
      p_title: '🧭 Jornada documentada da tribo — checklist do ciclo', p_tags: ['jornada_tribo'],
    });
    assert.ok(!e1, `heurística precisa resolver (erro: ${e1?.message})`);
    assert.equal(comMarcador, null, 'card da automação nunca sugere tipo');

    // Controle negativo: sem o marcador, o mesmo título CAI no ramo `ferramenta`
    // (por "checklist") — é exatamente esse falso positivo que o corte evita.
    const { data: semMarcador } = await sb.rpc('portfolio_suggest_item_type', {
      p_title: '🧭 Jornada documentada da tribo — checklist do ciclo', p_tags: null,
    });
    assert.equal(semMarcador, 'ferramenta', 'sem o marcador o falso positivo existe — o corte é necessário');
  });

test('DB: os 8 passos saem na ordem e com o prefixo [Jn]',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('tribe_journey_items', {
      p_ev: {
        reunioes_realizadas: 10, reunioes_agendadas_30d: 2, com_link: 10, com_gravacao: 0,
        com_ata: 8, ata_com_acao: 8, cards: 5, cards_com_data: 5,
        cards_com_atividade_completa: 1, entregavel_sem_flag: 0, portfolio_sem_tipo: 0,
      },
    });
    assert.ok(!error, `tribe_journey_items precisa resolver (erro: ${error?.message})`);
    assert.equal(data.length, 8, '8 passos');
    assert.deepEqual(data.map(i => i.key), ['J1','J2','J3','J4','J5','J6','J7','J8'], 'ordem estável');
    for (const i of data) {
      assert.ok(i.text.startsWith(`[${i.key}]`), `${i.key}: prefixo é a chave de idempotência`);
    }
    // Limiar de 80%: link 10/10 fecha, gravação 0/10 não, atividade completa 1/5 não.
    const by = Object.fromEntries(data.map(i => [i.key, i.done]));
    assert.equal(by.J2, true,  'link 10/10 fecha');
    assert.equal(by.J3, false, 'gravação 0/10 não fecha');
    assert.equal(by.J5, true,  'ata->ação 8/8 fecha');
    assert.equal(by.J7, false, 'atividade completa 1/5 não fecha');
    assert.equal(by.J8, true,  'portfólio sem pendência fecha');
  });

test('DB: sem reunião na janela os passos de reunião ficam sem_dados, não reprovados',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Ausência de dado não é o mesmo que descuido — uma tribo recém-criada não
    // pode abrir o card com 4 reprovações que ela não teve como evitar.
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('tribe_journey_items', {
      p_ev: {
        reunioes_realizadas: 0, reunioes_agendadas_30d: 0, com_link: 0, com_gravacao: 0,
        com_ata: 0, ata_com_acao: 0, cards: 0, cards_com_data: 0,
        cards_com_atividade_completa: 0, entregavel_sem_flag: 0, portfolio_sem_tipo: 0,
      },
    });
    assert.ok(!error, `precisa resolver (erro: ${error?.message})`);
    const by = Object.fromEntries(data.map(i => [i.key, i]));
    for (const k of ['J2','J3','J4','J5']) {
      assert.equal(by[k].sem_dados, true, `${k} marcado sem_dados`);
      assert.match(by[k].text, /sem dados na janela/, `${k} diz isso no texto`);
    }
  });
