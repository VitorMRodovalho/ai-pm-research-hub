// tests/contracts/2325-cobranca-do-termo-nao-nasce-suprimida.test.mjs
// Registrar nas whitelists "test:behavioural" E "test:contracts" do package.json (#1109).
// (DB-aware: a camada D abre conexão. As A, B e C são estáticas.)
/**
 * #2325 — a cobrança do Termo de Voluntariado deixa de nascer suprimida.
 *
 * O DEFEITO: `notify_pending_volunteer_agreements` emitia com `p_type => 'system'`, e o catálogo
 * ADR-0022 define `system` como "Internal system events. In-app only." → `suppress`. A cobrança
 * nunca saía da plataforma. Medido em 16/09: 26 linhas, 16 pessoas, 08/07 a 14/09, 0 entregues.
 *
 * ⚠️ A ASSERÇÃO QUE IMPORTA É A CAMADA B, e ela não olha um nome fixo. Ela extrai do corpo do
 * emissor o tipo que ele REALMENTE emite e pergunta ao catálogo se aquilo entrega. Um guard que
 * só afirmasse "o tipo é volunteer_term_pending" ficaria verde no dia em que alguém trocasse o
 * tipo por outro que também é suprimido — que é exatamente a forma do defeito original.
 *
 * O guard adr-0022-delivery-mode já cobre a paridade catálogo ↔ helper SQL. Este cobre o elo que
 * faltava: o EMISSOR e o modo de entrega do que ele emite.
 *
 * Camadas:
 *   A (estático) o catálogo declara o tipo, e não como `suppress`.
 *   B (estático) o tipo que o emissor emite entrega de fato (extraído do corpo, não presumido).
 *   C (estático) a janela de dedup existe — ela nasceu junto com a entrega real, porque enquanto
 *                nada saía o clique repetido era inofensivo.
 *   D (vivo)     o helper concorda com o catálogo para o tipo novo, E `system` segue `suppress`
 *                (controle de não-regressão: a correção errada seria afrouxar `system`, que
 *                também é emitido por _alert_sweep_cron e _selection_consistency_cron).
 *
 * Cross-ref: #2325, #2286, #2323, ADR-0022.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const CATALOG = resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json');
const EMISSOR = 'notify_pending_volunteer_agreements';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const catalogo = JSON.parse(readFileSync(CATALOG, 'utf8'));

/** Corpo do emissor, na ÚLTIMA migration que o define (CREATE OR REPLACE faz a última vencer). */
function corpoDoEmissor() {
  const achados = readdirSync(MIGRATIONS)
    .filter(f => f.endsWith('.sql'))
    .sort()
    .map(f => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .filter(src => src.includes(`CREATE OR REPLACE FUNCTION public.${EMISSOR}(`));
  assert.ok(achados.length >= 1,
    `nenhuma migration define ${EMISSOR}: o guard ficaria verde por não achar nada, que é o modo ` +
    'de falhar mais silencioso que existe');
  const src = achados[achados.length - 1];
  const i = src.indexOf(`CREATE OR REPLACE FUNCTION public.${EMISSOR}(`);
  const resto = src.slice(i);
  const fim = resto.indexOf('$function$;');
  assert.ok(fim > 0, `corpo de ${EMISSOR} não fecha com $function$;`);
  return resto.slice(0, fim);
}

/** O tipo que o emissor passa a create_notification, lido do corpo. */
function tipoEmitido(corpo) {
  const m = corpo.match(/p_type\s*=>\s*'([a-z_]+)'/);
  assert.ok(m, `não consegui ler o p_type que ${EMISSOR} emite — se a notação mudou, este guard ` +
    'parou de medir o que diz medir (e ficaria verde por não achar nada)');
  return m[1];
}

// ═══════════════════════════════════════════════════════════════════════════
test('A · o catálogo declara o tipo da cobrança, e não como suppress', () => {
  const t = catalogo.types.volunteer_term_pending;
  assert.ok(t, 'volunteer_term_pending sumiu do catálogo ADR-0022. Sem entrada, o helper cai no ' +
    'ELSE (digest_weekly), que carimba como entregue o que nenhuma seção renderiza (#2286)');
  assert.notEqual(t.delivery_mode, 'suppress',
    'a cobrança voltou a ser suprimida no catálogo, que é literalmente o defeito da #2325');
  assert.equal(t.delivery_mode, 'transactional_immediate');
});

test('B · o tipo que o emissor REALMENTE emite entrega — extraído do corpo, não presumido', () => {
  const tipo = tipoEmitido(corpoDoEmissor());
  const entrada = catalogo.types[tipo];
  assert.ok(entrada,
    `${EMISSOR} emite '${tipo}', que o catálogo ADR-0022 não declara. Sem entrada o helper cai no ` +
    'ELSE (digest_weekly) e a notificação é carimbada como entregue sem renderizar (#2286).');
  assert.notEqual(entrada.delivery_mode, 'suppress',
    `${EMISSOR} emite '${tipo}', que o catálogo manda SUPRIMIR. É a forma exata do defeito da ` +
    '#2325: o botão do painel responde ok:true e nada sai da plataforma. Medido em 16/09 com ' +
    "type='system': 26 avisos, 16 pessoas, 0 entregues.");
});

test('C · a janela de dedup existe, porque agora a cobrança sai de verdade', () => {
  const corpo = corpoDoEmissor();
  assert.match(corpo, /interval\s+'7 days'/,
    'a janela de deduplicação sumiu. Enquanto o tipo era suprimido o clique repetido era ' +
    'inofensivo; entregando de verdade, ele vira e-mail repetido — o histórico tinha até 6 ' +
    'avisos para a mesma pessoa em dois meses');
  assert.match(corpo, /skipped_recent/,
    'o retorno precisa separar o que foi pulado pela janela, senão o silêncio parece falha');
});

// ═══════════════════════════════════════════════════════════════════════════
test('D · o helper vivo concorda com o catálogo, e `system` NÃO foi afrouxado',
  { skip: !dbGated && skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const modo = async (t) => {
    const { data, error } = await sb.rpc('_delivery_mode_for', { p_type: t });
    assert.equal(error, null, `_delivery_mode_for('${t}') falhou: ${error?.message}`);
    return data;
  };
  assert.equal(await modo('volunteer_term_pending'), 'transactional_immediate',
    'o helper vivo discorda do catálogo para o tipo da cobrança');
  // O controle de não-regressão: a correção ERRADA seria afrouxar `system`, que também é emitido
  // por _alert_sweep_cron e _selection_consistency_cron como alerta interno de gestor. Afrouxá-lo
  // transformaria esses em e-mail.
  assert.equal(await modo('system'), 'suppress',
    '`system` deixou de ser suppress. A #2325 se corrige trocando o TIPO do emissor, nunca ' +
    'afrouxando `system` — há outros dois emissores legítimos dele.');
});
