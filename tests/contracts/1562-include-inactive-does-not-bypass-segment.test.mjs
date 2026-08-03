/**
 * Contract: #1562 — "incluir inativos" não pode anular a segmentação da campanha.
 *
 * A cláusula de audiência de `admin_send_campaign` punha `v_include_inactive` no MESMO `OR` dos
 * filtros de segmento, o que tornava a cláusula inteira verdadeira e descartava papel, designação
 * e capítulo. Medido em 2026-08-03 contra os dados reais:
 *
 *   chapter_liaison + incluir inativos ...... 121 (a base inteira) em vez de 11
 *   filtro VAZIO   + incluir inativos ....... 121 em vez de 0
 *
 * Alcançável por um clique em /admin/campaigns, com o teto de 90 envios/dia da lane no caminho.
 *
 * Duas camadas, porque uma sozinha não segura:
 *
 *  (A) ESTRUTURAL sobre o corpo VIVO — a assinatura do defeito é `v_include_inactive` aparecer na
 *      mesma disjunção de `v_all`. Checa o corpo em produção, não o arquivo de migration: afirmar
 *      o local da definição barraria uma refatoração legítima, e o que importa é o que está no
 *      banco.
 *
 *  (B) COMPORTAMENTAL — replica o predicado das duas dimensões contra os dados reais e confere as
 *      combinações. Isto NÃO prova por si só que a função usa este predicado (a função é gateada
 *      por auth.uid() e não pode ser chamada com service_role); é a camada (A) que amarra o
 *      predicado ao corpo vivo. Juntas, cobrem tanto "alguém reescreveu a cláusula" quanto
 *      "a cláusula continua lá mas os dados mudaram de forma".
 *
 * A combinação que mais importa é o filtro VAZIO: é a que transformava um clique acidental em
 * disparo para a base inteira.
 */

import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

const RESERVED_DOMAIN = /@(?:[^@]*\.)?(?:example\.(?:com|org|net)|test|invalid|localhost)$/i;

async function rpc(name, body = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) assert.fail(`rpc ${name} failed: HTTP ${res.status} — ${await res.text()}`);
  return await res.json();
}

async function rest(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
  if (!res.ok) assert.fail(`GET ${path} failed: HTTP ${res.status} — ${await res.text()}`);
  return await res.json();
}

test('#1562 (A): o corpo vivo não põe include_inactive na disjunção do segmento', { skip: !canRun && skipMsg }, async () => {
  // `_audit_function_source` (#1562) devolve o prosrc; `_audit_list_public_function_bodies` só dá
  // md5 e tamanho, com os quais não se pode afirmar nada sobre o CONTEÚDO. Sem corpo, este teste
  // falha alto em vez de retornar cedo — um guard que se auto-desliga quando a introspecção some é
  // exatamente a defesa decorativa que ele deveria impedir.
  const rows = await rpc('_audit_function_source', { p_proname: 'admin_send_campaign' });
  assert.ok(Array.isArray(rows) && rows.length > 0, 'admin_send_campaign não encontrada no schema vivo');

  const body = rows[0]?.prosrc;
  assert.ok(typeof body === 'string' && body.length > 0, 'introspecção não devolveu o corpo da função');

  const flat = body.replace(/\s+/g, ' ');
  for (const bad of ['v_all OR v_include_inactive', 'v_include_inactive OR v_all']) {
    assert.ok(
      !flat.includes(bad),
      `o corpo vivo contém "${bad}": include_inactive voltou a anular a segmentação (#1562)`
    );
  }

  // E a dimensão de atividade tem de continuar existindo — a separação não pode ter virado
  // "ignorar include_inactive", que passaria no teste acima e quebraria a funcionalidade.
  assert.ok(
    flat.includes('v_include_inactive AND (m.is_active = false OR m.current_cycle_active = false)'),
    'a cláusula de atividade sumiu: include_inactive deixou de ampliar a audiência'
  );
});

test('#1562 (B): include_inactive amplia a atividade DENTRO do segmento, e filtro vazio não seleciona ninguém', { skip: !canRun && skipMsg }, async () => {
  const members = await rest(
    'members?select=email,is_active,current_cycle_active,operational_role'
  );

  // Réplica exata das duas dimensões do corpo vivo.
  const audience = ({ all = false, includeInactive = false, roles = [] }) =>
    members.filter((m) => {
      if (!m.email || RESERVED_DOMAIN.test(m.email)) return false;
      const activeNow = m.is_active === true && m.current_cycle_active === true;
      const activity = activeNow || (includeInactive && !activeNow);
      const segment = all || (roles.length > 0 && roles.includes(m.operational_role));
      return activity && segment;
    }).length;

  const todos = audience({ all: true });
  const todosComInativos = audience({ all: true, includeInactive: true });

  // O caso que motivou a issue: um segmento real não pode virar a base inteira.
  const papel = 'chapter_liaison';
  const soSegmento = audience({ roles: [papel] });
  const segmentoComInativos = audience({ roles: [papel], includeInactive: true });

  assert.ok(soSegmento > 0, `fixture vazia: nenhum membro com operational_role=${papel}`);
  assert.ok(
    segmentoComInativos >= soSegmento,
    'include_inactive tem de AMPLIAR o segmento (união), nunca reduzi-lo'
  );
  assert.ok(
    segmentoComInativos < todosComInativos,
    `segmento+inativos (${segmentoComInativos}) alcançou a base inteira (${todosComInativos}) — ` +
      'include_inactive voltou a anular a segmentação (#1562)'
  );

  // Decisão (a) do owner: filtro vazio sem `all` seleciona ninguém, com ou sem o checkbox. É o
  // pior caso do defeito — um clique acidental disparando para todo mundo.
  assert.equal(audience({}), 0, 'filtro vazio sem `all` não pode selecionar ninguém');
  assert.equal(
    audience({ includeInactive: true }),
    0,
    'filtro vazio + include_inactive não pode selecionar ninguém (era a base inteira antes de #1562)'
  );

  // Sanidade: `all` continua sendo o "sem segmento".
  assert.ok(todos > 0 && todosComInativos >= todos, 'all=true deve selecionar a base ativa');
});
