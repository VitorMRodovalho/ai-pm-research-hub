// tests/contracts/2285-detector-de-contas-nao-ligadas-tem-cron.test.mjs
// Registrar nas whitelists "test:behavioural" E "test:contracts" do package.json (#1109).
// (DB-aware: as camadas D, E e F abrem conexão. As A, B, C e G são estáticas.)
/**
 * #2285 — o detector de contas não ligadas passa a ter quem o acione.
 *
 * O QUE A MEDIÇÃO DE 14/09 MOSTROU, e que este arquivo existe para não deixar regredir:
 *
 *   * `detect_unlinked_accounts()` nasceu na #2273 e nunca teve cron. A consulta
 *     `cron.job WHERE command ILIKE '%detect_unlinked%'` voltava vazia contra 71 jobs
 *     agendados — o vazio era ausência real, não tabela vazia.
 *   * E agendar a RPC direto NÃO resolveria: o portão dela aceita `service_role` (via
 *     `request.jwt.claims`) ou `can_by_member(auth.uid())`, e sob pg_cron os dois são NULOS.
 *     Chamada como `postgres`, ela levanta `Unauthorized: requires manage_platform` na linha
 *     13, antes de ler qualquer coisa. O job falharia em TODA execução.
 *   * O defeito não apareceu em teste porque o contrato F da #2273 chama via
 *     service-role/PostgREST, onde o claim EXISTE. O teste exercitava o caminho que funciona.
 *
 * ⚠️ A ARMADILHA QUE DECIDE O DESENHO: um wrapper de cron não pode ter gate de sessão. É a
 * mesma decisão já registrada na #1548 ("sob pg_cron não há JWT: auth.uid() é NULL, o gate
 * nega, e o job roda VERDE e VAZIO"). A proteção é o ACL, nunca um gate de usuário.
 *
 * As camadas, e por que cada uma precisa existir:
 *
 *   A (estático) o wrapper NÃO tem gate de sessão. É a asserção que teria pego o defeito
 *                original, e ela mede o corpo com os comentários MASCARADOS — a migration
 *                explica `auth.uid()` em prosa, e um guard ingênuo casaria a própria
 *                explicação em vez do código.
 *   B (estático) o ACL: REVOKE de anon E de authenticated, no worker e no wrapper. Sem isso,
 *                tirar o gate de sessão deixaria o detector ao alcance de qualquer um.
 *   C (estático) o agendamento existe e aponta para o WRAPPER, não para a RPC com portão.
 *                Nenhum teste daqui lê `cron.job` (mesma limitação registrada na #1543), então
 *                a afirmação é sobre a migration, e o estado vivo foi conferido à mão.
 *   D (vivo)     o worker é chamável pelo service_role: a porta do cron existe de fato.
 *   E (vivo)     o wrapper roda em `p_dry_run` e NÃO escreve. Sem o dry-run, exercer o caminho
 *                de sucesso mandaria e-mail a pessoas reais em toda rodada de CI e gastaria a
 *                janela de deduplicação de 25 dias, calando o cron de verdade.
 *   F (vivo)     anon não alcança nem o worker nem o wrapper — e barrado por PERMISSÃO, não
 *                por a função ter sumido (controle negativo, igual à camada E da #2273).
 *   G (estático) o tipo está no catálogo ADR-0022 como `transactional_immediate` E aparece no
 *                corpo do helper. Se cair no ELSE (`digest_weekly`), a notificação é carimbada
 *                como entregue sem nunca ser renderizada — medido em 76 de 78 linhas de dois
 *                tipos irmãos (#2286).
 *
 * Cross-ref: #2285, #2273 (o detector), #2286 (o digest que engole), #1548 (a classe do
 * defeito), #1844 (minuto deslocado no agendamento).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const CATALOGO = join(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
// O fallback de nome não é cosmético: o CI exporta `SUPABASE_ANON_KEY` e o `.env` local usa o
// prefixo `PUBLIC_` (mesma razão registrada na #1294).
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** A migration desta onda, achada pelo conteúdo e não por nome fixo: renomear o arquivo não
 *  pode deixar o guard verde por não encontrar nada (um guard que não acha fica vazio, não
 *  vermelho). */
function migrationDaOnda() {
  const achados = readdirSync(MIGRATIONS)
    .filter(f => f.endsWith('.sql'))
    .map(f => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .filter(src => src.includes('CREATE OR REPLACE FUNCTION public.detect_unlinked_accounts_cron('));
  assert.equal(achados.length, 1,
    `esperada exatamente 1 migration definindo detect_unlinked_accounts_cron, achadas ${achados.length}`);
  return achados[0];
}

/** Corpo de uma função, ancorado na assinatura COM o parêntese: `detect_unlinked_accounts` é
 *  prefixo de `detect_unlinked_accounts_cron`, e um indexOf solto pegaria a função errada. */
function corpoDe(src, assinatura) {
  const i = src.indexOf(`CREATE OR REPLACE FUNCTION public.${assinatura}`);
  assert.ok(i >= 0, `${assinatura} não está na migration`);
  const resto = src.slice(i);
  const fim = resto.indexOf('$function$;');
  assert.ok(fim > 0, `corpo de ${assinatura} não fecha com $function$;`);
  return resto.slice(0, fim);
}

// ═══════════════════════════════════════════════════════════════════════════
// A — o wrapper não tem gate de sessão (a asserção que teria pego o defeito)
// ═══════════════════════════════════════════════════════════════════════════
test('A · o wrapper de cron NÃO tem gate de sessão, e a medição ignora os comentários', () => {
  const corpo = maskLineComments(corpoDe(migrationDaOnda(), 'detect_unlinked_accounts_cron('));
  for (const padrao of [/auth\.uid\(\)/, /request\.jwt\.claims/]) {
    assert.ok(
      !padrao.test(corpo),
      `o wrapper voltou a ter gate de sessão (${padrao}). Sob pg_cron não há JWT: auth.uid() e ` +
      'request.jwt.claims são NULOS, o gate nega, e o job falha em toda execução — que é ' +
      'exatamente o defeito que a #2285 conserta. A proteção aqui é o ACL (camada B).',
    );
  }
  // A MORDIDA: sem mascarar comentários este guard reprovaria o código CORRETO, porque a
  // migration cita auth.uid() em prosa para explicar por que ele não pode estar lá. Se esta
  // asserção falhar, a máscara parou de funcionar e a camada A virou decoração.
  const cru = corpoDe(migrationDaOnda(), 'detect_unlinked_accounts_cron(');
  assert.notEqual(cru, maskLineComments(cru),
    'maskLineComments não removeu nada do corpo: ou não há comentário algum, ou a máscara ' +
    'quebrou — e nos dois casos a camada A deixou de discriminar o que diz discriminar');
});

// ═══════════════════════════════════════════════════════════════════════════
// B — o ACL, que é a proteção real
// ═══════════════════════════════════════════════════════════════════════════
test('B · worker e wrapper são revogados de anon E de authenticated', () => {
  const src = migrationDaOnda();
  const alvos = [
    ['public._unlinked_accounts_rows\\(\\)', 'o worker devolve o endereço CRU'],
    ['public.detect_unlinked_accounts_cron\\(boolean\\)', 'o wrapper dispara notificação'],
  ];
  for (const [fn, porque] of alvos) {
    for (const papel of ['anon', 'authenticated']) {
      assert.ok(
        new RegExp(`REVOKE ALL ON FUNCTION ${fn} FROM ${papel};`).test(src),
        `falta REVOKE de ${papel} em ${fn.replace(/\\\\/g, '')}: ${porque}, e sem gate de sessão ` +
        '(camada A) o ACL é a única barreira',
      );
    }
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// C — o agendamento existe e aponta para o wrapper
// ═══════════════════════════════════════════════════════════════════════════
test('C · o cron está agendado e chama o WRAPPER, não a RPC com portão', () => {
  const src = migrationDaOnda();
  assert.match(src, /cron\.schedule\(\s*\n?\s*'unlinked-accounts-detect-weekly'/,
    'o job precisa ser agendado por nome (cron.schedule faz upsert por nome, então reaplicar ' +
    'a migration é idempotente)');
  const m = src.match(/\$cron\$([\s\S]*?)\$cron\$/);
  assert.ok(m, 'o comando do job precisa estar em bloco $cron$');
  const comando = m[1];
  assert.match(comando, /public\.detect_unlinked_accounts_cron\(\)/,
    'o job tem de chamar o WRAPPER');
  assert.ok(
    !/public\.detect_unlinked_accounts\(\)/.test(comando),
    'o job voltou a chamar a RPC COM PORTÃO. Sob pg_cron ela levanta ' +
    '"Unauthorized: requires manage_platform" antes de ler qualquer linha, e o job falharia ' +
    'em toda execução (medido em 14/09).',
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// D — a porta do cron existe de fato
// ═══════════════════════════════════════════════════════════════════════════
test('D · o worker é chamável pelo service_role', { skip: !dbGated && skipMsg }, async () => {
  const { error } = await sb().rpc('_unlinked_accounts_rows');
  assert.equal(error, null,
    `_unlinked_accounts_rows deveria ser chamável pelo service_role: ${error?.message}`);
});

// ═══════════════════════════════════════════════════════════════════════════
// E — o wrapper roda inteiro em dry-run e NÃO escreve
// ═══════════════════════════════════════════════════════════════════════════
test('E · dry_run devolve o resumo e não grava nem auditoria nem notificação',
  { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const contar = async (tabela, filtro) => {
    let q = c.from(tabela).select('*', { count: 'exact', head: true });
    for (const [col, val] of Object.entries(filtro)) q = q.eq(col, val);
    const { count, error } = await q;
    assert.ifError(error);
    return count;
  };
  const auditAntes = await contar('admin_audit_log', { action: 'cron.detect_unlinked_accounts_run' });
  const notifAntes = await contar('notifications', { type: 'unlinked_accounts_detected' });

  const { data, error } = await c.rpc('detect_unlinked_accounts_cron', { p_dry_run: true });
  assert.ifError(error);
  assert.equal(data.dry_run, true, 'o retorno tem de dizer que foi ensaio');
  assert.equal(typeof data.unlinked_total, 'number', 'falta a contagem do detector');
  assert.equal(typeof data.already_signed_in, 'number',
    'a contagem de quem JÁ entrou separa o caso urgente do caso dormente, e é ela que torna ' +
    'o aviso acionável em vez de um número solto');
  assert.ok(data.already_signed_in <= data.unlinked_total,
    'quem já entrou é subconjunto de quem não está ligado; se passar do total, uma das duas ' +
    'contagens está medindo outra população');
  assert.equal(data.notifications_inserted, 0, 'ensaio não pode inserir notificação');

  assert.equal(await contar('admin_audit_log', { action: 'cron.detect_unlinked_accounts_run' }), auditAntes,
    'o ensaio gravou linha de auditoria: p_dry_run deixou de proteger o banco compartilhado');
  assert.equal(await contar('notifications', { type: 'unlinked_accounts_detected' }), notifAntes,
    'o ensaio gravou notificação, e isso manda e-mail a pessoas reais em toda rodada de CI ' +
    'além de gastar a janela de deduplicação de 25 dias, calando o cron de verdade');
});

// ═══════════════════════════════════════════════════════════════════════════
// F — anon não alcança, e é barrado por PERMISSÃO, não por ausência
// ═══════════════════════════════════════════════════════════════════════════
test('F · anon não alcança o worker nem o wrapper',
  { skip: !(dbGated && ANON_KEY) && 'Skipped: ANON_KEY required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  for (const [fn, args] of [['_unlinked_accounts_rows', {}],
                            ['detect_unlinked_accounts_cron', { p_dry_run: true }]]) {
    const { data, error } = await anon.rpc(fn, args);
    assert.ok(error, `anon executou ${fn}, que deveria estar fora do seu alcance (devolveu ${JSON.stringify(data)})`);
    // Barrado por PERMISSÃO, não por a função ter sumido: as duas dão erro, e só uma é o que
    // este teste afirma.
    assert.doesNotMatch(String(error.message), /does not exist|not find the function/i,
      `${fn} não existe mais — o teste estaria verde pela ausência, não pelo portão: ${error.message}`);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// G — o tipo não pode cair no ELSE do helper
// ═══════════════════════════════════════════════════════════════════════════
test('G · o tipo está no catálogo ADR-0022 e no corpo do helper', () => {
  const cat = JSON.parse(readFileSync(CATALOGO, 'utf8'));
  const entrada = cat.types['unlinked_accounts_detected'];
  assert.ok(entrada, 'o tipo não está no catálogo. O próprio catálogo manda: "New types added ' +
    'to notifications must be added here in the same migration."');
  assert.equal(entrada.delivery_mode, 'transactional_immediate',
    'digest_weekly aqui significa nunca entregue: get_weekly_member_digest monta as seções por ' +
    'lista branca de tipos, e consumed_notification_ids NÃO filtra por tipo, então um tipo fora ' +
    'de toda seção é carimbado como entregue sem nunca ser renderizado (#2286)');
  const corpo = corpoDe(migrationDaOnda(), '_delivery_mode_for(');
  assert.match(corpo, /WHEN 'unlinked_accounts_detected'\s+THEN 'transactional_immediate'/,
    'o helper não conhece o tipo, então ele cai no ELSE — que é digest_weekly, o caminho que engole');
});
