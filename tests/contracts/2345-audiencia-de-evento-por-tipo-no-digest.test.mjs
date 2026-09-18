// tests/contracts/2345-audiencia-de-evento-por-tipo-no-digest.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2345 — as reunioes institucionais eram invisiveis no digest.
 *
 * `events_upcoming` decidia por lista branca no corpo:
 *   AND ( i.legacy_tribe_id = v_member_tribe_id OR e.type IN ('plenaria','webinar','workshop_geral') )
 *
 * Dois defeitos numa clausula, medidos em 17/09:
 *   1. **13 eventos futuros invisiveis** — `lideranca` (7) e `geral` (6) nao tem `initiative_id`,
 *      entao o ramo da tribo nunca casava, e nao estavam na lista. Mesma classe da #2286, na secao
 *      VIZINHA da mesma funcao.
 *   2. **Dois tercos da lista eram FANTASMAS** — `plenaria` e `workshop_geral` tem ZERO eventos na
 *      base (controle: `webinar` tem 6, e ha 11 tipos vivos). Classe do #2341.
 *
 * ⚠️ O DEFAULT AQUI E O INVERSO DO DA #2286, de proposito. Lá o `ELSE` fazia todo tipo novo
 * APARECER, seguro porque notificacao nasce endereçada. Aqui `entrevista` tem 151 eventos e `1on1`
 * tem 22, ambos privados: mostrar o nao-declarado exporia entrevista de selecao a 99 membros. Entao
 * tipo nao declarado NAO aparece (JOIN, nao LEFT JOIN), e quem impede o silencio de se instalar e a
 * assercao DA VOLTA aqui embaixo — a que faltou na #2286 e na #2341.
 *
 * Cross-ref: #2345, #2286, #2341, ADR-0022.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = latestFunctionCapture(ROOT, 'get_weekly_member_digest');
const corpo = maskLineComments(cap?.block ?? '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** Recorta o bloco de `events_upcoming` — a assercao vale dentro de quem decide, nao no corpo todo. */
function blocoEventos() {
  const m = corpo.match(/'events_upcoming',\s*COALESCE\(\([\s\S]*?\), '\[\]'::jsonb\)/);
  return m ? m[0] : '';
}

// ── ESTATICO ──────────────────────────────────────────────────────────────────────────

test('#2345 static: a lista branca de type saiu do corpo', () => {
  const b = blocoEventos();
  assert.ok(b, 'precisa existir o bloco de events_upcoming');
  assert.doesNotMatch(b, /e\.type\s+IN\s*\(\s*'/i,
    'voltou a decidir audiencia por lista de type no corpo — era metade do defeito da #2345, ' +
    'e dois dos tres nomes da lista antiga nem existiam na base');
  assert.match(b, /JOIN\s+public\.event_type_digest_audience/i,
    'a audiencia tem de vir da tabela declarada');
});

test('#2345 static: e JOIN, nao LEFT JOIN — tipo nao declarado NAO aparece', () => {
  const b = blocoEventos();
  // Privacidade: `entrevista` (151 eventos) e `1on1` (22) nao podem vazar por default.
  assert.doesNotMatch(b, /LEFT\s+JOIN\s+public\.event_type_digest_audience/i,
    'LEFT JOIN faria tipo nao declarado aparecer; `entrevista` tem 151 eventos privados');
  assert.match(b, /a\.audience\s*<>\s*'suppressed'/i, 'suppressed nunca entra');
  assert.match(b, /a\.retired_at\s+IS\s+NULL/i, 'tipo aposentado nao entra');
});

test('#2345 static: cada audiencia amarra a CONDICAO que a habilita', () => {
  // Regra do CLAUDE.md (17/09): amarrar condicao ao resultado dentro do bloco que decide.
  const b = blocoEventos();
  assert.match(b, /a\.audience\s*=\s*'initiative_members'\s+AND\s+i\.legacy_tribe_id\s*=\s*v_member_tribe_id/i,
    'initiative_members tem de exigir a tribo do membro');
  assert.match(b, /a\.audience\s*=\s*'leadership'\s+AND\s+v_is_leadership/i,
    'leadership tem de exigir o papel — sem isso a reuniao de lideranca vai para os 99 membros');
  assert.match(b, /a\.audience\s*=\s*'all_members'/i, 'all_members entra sem condicao extra');
});

test('#2345 static: v_is_leadership deriva de engagements ATIVOS, nao de lista', () => {
  assert.match(corpo, /v_is_leadership/, 'declara a variavel');
  const m = corpo.match(/SELECT EXISTS \([\s\S]*?\) INTO v_is_leadership/);
  assert.ok(m, 'precisa derivar o papel de uma consulta');
  assert.match(m[0], /public\.engagements/i, 'a fonte e engagements — acompanha entrada e desligamento');
  assert.match(m[0], /en\.status\s*=\s*'active'/i, 'so engajamento ATIVO conta');
});

test('#2345 static: o que a #2286 garantiu segue intacto', () => {
  // Redefinir a funcao inteira e a forma mais facil de apagar em silencio invariante de outra issue.
  assert.match(corpo, /ELSE\s+'other_notifications'\s*\n?\s*END\s+AS\s+secao/i, '#2286: o ELSE do CASE');
  const leituras = [...corpo.matchAll(/FROM\s+public\.notifications\b/gi)].length;
  assert.equal(leituras, 1, `#2286: UMA leitura de notifications, achei ${leituras}`);
  assert.match(corpo, /'consumed_notification_ids',\s*v_consumed/, '#2286: carimbo derivado');
  assert.match(corpo, /COALESCE\(gp\.occurred_at, gp\.created_at\) >= v_window_start/, '#1470: xp_delta');
});

// ── DB: A ASSERCAO DA VOLTA (a que faltou na #2286 e na #2341) ────────────────────────

test('#2345 db: TODO type de evento vivo tem audiencia declarada',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Esta e a assercao que impede o defeito de voltar. Como tipo nao declarado NAO aparece
    // (default seguro por privacidade), o silencio so nao se instala se alguem exigir a volta:
    // nao basta declarar bem os tipos de hoje, todo tipo NOVO tem de ser declarado antes de nascer
    // invisivel. Faltou exatamente isso na #2286 (27 tipos sem secao) e na #2341 (cron removido).
    const { data, error } = await sb().rpc('_audit_event_type_digest_coverage');
    assert.ifError(error);
    const linhas = data ?? [];
    // Controle positivo: sem isto, uma RPC que devolvesse [] passaria por vacuo.
    assert.ok(linhas.length >= 11, `esperava >=11 tipos no cruzamento, achei ${linhas.length}`);
    const vivosSemDeclaracao = linhas.filter((l) => l.eventos_na_base > 0 && !l.declarado);
    assert.deepEqual(vivosSemDeclaracao.map((l) => l.event_type), [],
      `type de evento vivo sem audiencia declarada: ${vivosSemDeclaracao.map((l) => l.event_type).join(', ')}. ` +
      'Enquanto nao houver linha em event_type_digest_audience, esses eventos NAO aparecem no ' +
      'digest de ninguem — e nada avisa (#2345).');
  });

test('#2345 db: os dois tipos privados estao suprimidos, com razao escrita',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb()
      .from('event_type_digest_audience')
      .select('event_type, audience, rationale')
      .in('event_type', ['entrevista', '1on1']);
    assert.ifError(error);
    assert.equal((data ?? []).length, 2, 'entrevista e 1on1 precisam estar declarados');
    for (const l of data) {
      assert.equal(l.audience, 'suppressed',
        `${l.event_type} tem de ser suppressed — sao 151 entrevistas de selecao e conversas 1on1`);
      assert.match(l.rationale, /privacidade/i, `${l.event_type}: a razao tem de estar escrita`);
    }
  });

test('#2345 db: aposentar SEM motivo e RECUSADO pelo banco (exercido)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const alvo = '__fixture-2345-sem-motivo';
    const { error } = await sb().from('event_type_digest_audience').insert({
      event_type: alvo, audience: 'all_members', rationale: 'fixture do guard #2345',
      retired_at: new Date().toISOString(), retired_reason: null,
    });
    if (!error) await sb().from('event_type_digest_audience').delete().eq('event_type', alvo);
    assert.ok(error, 'retired_at sem retired_reason tem de ser recusado');
    // Checa o TIPO do erro: na #2341 um rename fez o insert falhar por coluna inexistente, e um
    // `assert.ok(error)` generico teria afirmado que o CHECK barrou.
    assert.match(String(error.message + ' ' + (error.code ?? '')), /23514|check|violates/i,
      `esperava violacao de CHECK, veio: ${error.code} ${error.message}`);
  });
