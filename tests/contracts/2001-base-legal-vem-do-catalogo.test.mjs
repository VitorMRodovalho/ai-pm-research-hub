// tests/contracts/2001-base-legal-vem-do-catalogo.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2001 — a base legal do vínculo vem do catálogo, e nenhuma linha pode divergir dele.
 *
 * `engagements.legal_basis` é a base LGPD Art. 7 do vínculo. `engagement_kinds.legal_basis` declara
 * a base canônica de cada kind — e, até 28/08/2026, nada comparava os dois: **134 de 293**
 * engajamentos divergiam (106 ativos).
 *
 * TRÊS pontas de escrita erravam, não duas como a issue supunha:
 *   1. o DEFAULT da coluna era `'consent'` — uma AFIRMAÇÃO JURÍDICA por omissão;
 *   2. `seed_member_engagement_by_role` gravava o literal `'contract'` para qualquer kind;
 *   3. `join_initiative` NÃO nomeia a coluna, então herdava o default. Esta terceira apareceu ao
 *      contar quem insere: 8 funções inserem em `engagements`, 7 nomeiam `legal_basis`.
 *
 * ⚠️ POR QUE O CONSERTO É GATILHO, E NÃO REMENDO NOS CHAMADORES. Consertar os 8 deixa o defeito
 * voltar no nono. A base legal é propriedade do KIND, não da linha: divergência por linha É o
 * defeito. Com o catálogo como SSOT via gatilho, a divergência deixa de ser possível por
 * construção, em vez de ser proibida por convenção.
 *
 * A pergunta jurídica que a issue deixou aberta foi respondida por MEDIÇÃO, não por opinião: das 46
 * linhas de `volunteer` que diziam `consent`, **46 de 46** são de pessoas com termo
 * contra-assinado. O backfill afirma algo verificável.
 *
 * Cross-ref: #2001, #1998 (tirou `legal_basis` de dentro de uma tela), #2023 (o parecer que fixou
 * consentimento como base ERRADA para relação contratual).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const TRG = latestFunctionCapture(ROOT, '_trg_engagement_legal_basis_from_catalog');

test('#2001 estático: o gatilho lê o catálogo e recusa kind sem base declarada', () => {
  assert.ok(TRG, '_trg_engagement_legal_basis_from_catalog não foi capturada por nenhuma migration');
  const b = TRG.body;
  assert.match(b, /FROM public\.engagement_kinds/, 'a base tem de sair do catálogo');
  assert.match(b, /NEW\.legal_basis\s*:=\s*v_basis/, 'o gatilho tem de ESCREVER o valor do catálogo');
  // Sem o RAISE, um kind fora do catálogo produziria NULL e a linha morreria no NOT NULL com um erro
  // que não diz a causa. O silêncio aqui é o que produziu as 134 divergências.
  assert.match(b, /RAISE\s+EXCEPTION/i, 'kind sem base no catálogo tem de levantar com causa nomeada');
});

test('#2001 vivo: NENHUM engajamento diverge do catálogo',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  const { data: kinds, error: e1 } = await s.from('engagement_kinds').select('slug, legal_basis');
  assert.ok(!e1, e1?.message);
  const cat = new Map((kinds ?? []).map((k) => [k.slug, k.legal_basis]));
  assert.ok(cat.size > 0, 'catálogo vazio — o guard passaria por vacuidade');

  const { data: rows, error: e2 } = await s
    .from('engagements').select('id, kind, legal_basis').limit(5000);
  assert.ok(!e2, e2?.message);
  assert.ok((rows ?? []).length > 0, 'nenhum engajamento lido — o guard não mediria nada');

  const divergentes = (rows ?? []).filter((r) => cat.has(r.kind) && cat.get(r.kind) !== r.legal_basis);
  assert.deepEqual(divergentes.map((r) => r.id), [],
    `${divergentes.length} engajamentos declaram base legal diferente da do catálogo`);

  // CONTROLE POSITIVO: um zero só vale se o join enxerga. Se NENHUM kind casasse com o catálogo, a
  // lista acima também viria vazia — por vacuidade, não por acerto.
  const casados = (rows ?? []).filter((r) => cat.has(r.kind)).length;
  assert.equal(casados, (rows ?? []).length,
    `${(rows ?? []).length - casados} engajamentos têm kind FORA do catálogo — não são medidos por ` +
    `este guard, e é exatamente onde a divergência voltaria a se esconder`);
});

test('#2001 estático: o gatilho está ligado na tabela, nos eventos certos', () => {
  // ⚠️ Este teste é ESTÁTICO de propósito. `_audit_list_public_function_bodies` — a fonte que os
  // guards de drift usam — NÃO lista funções de gatilho: medido em 28/08, 1230 funções listadas e
  // nenhum `_trg_*` entre elas. Uma asserção "o gatilho está no banco" contra aquela lista passaria
  // por vacuidade ou falharia por ausência estrutural, e em nenhum dos casos mediria o gatilho.
  //
  // O que prova o gatilho VIVO é o teste de divergência zero logo acima, que só se sustenta porque
  // ele roda. Aqui fixamos a FORMA: tabela, eventos e função.
  const src = readFileSync(resolve(ROOT, 'supabase/migrations', TRG.file), 'utf8');
  assert.match(src, /CREATE TRIGGER trg_engagement_legal_basis_from_catalog/,
    'o gatilho precisa ser criado pela mesma migration que define a função');
  assert.match(src, /BEFORE INSERT OR UPDATE OF kind, legal_basis ON public\.engagements/,
    'BEFORE, e nos dois eventos: só INSERT deixaria o UPDATE reintroduzir divergência');
  // O DEFAULT tem de sair. Com ele, "não informei" e "informei consent" são indistinguíveis — foi
  // assim que `join_initiative`, que sequer nomeia a coluna, passou a afirmar consentimento.
  assert.match(src, /ALTER COLUMN legal_basis DROP DEFAULT/,
    'sem tirar o default, a omissão continua inventando base legal');
});

test('#2001 vivo: consentimento só sobra onde o catálogo realmente diz consent',
  { skip: dbGated ? false : skipMsg }, async () => {
  // O parecer jurídico do #2023 foi explícito: consentimento cria direito de revogação. Declará-lo
  // onde a relação é contratual é o erro que este backfill desfez.
  const s = sb();
  const { data: kinds } = await s.from('engagement_kinds').select('slug, legal_basis');
  const consentKinds = new Set((kinds ?? []).filter((k) => k.legal_basis === 'consent').map((k) => k.slug));

  const { data: rows } = await s.from('engagements').select('id, kind, legal_basis').eq('legal_basis', 'consent').limit(5000);
  const indevidos = (rows ?? []).filter((r) => !consentKinds.has(r.kind));
  assert.deepEqual(indevidos.map((r) => r.id), [],
    `${indevidos.length} vínculos declaram CONSENTIMENTO para um kind cujo catálogo diz outra coisa`);
});
