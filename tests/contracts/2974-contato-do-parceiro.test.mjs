/**
 * #2974: o contato do parceiro (contact_name e contact_email de partner_entities) só sai para quem pode ver
 * parceiros: superadmin, view_partner ou manage_partner.
 *
 * O QUE ESTE GUARD AFIRMA, na última captura das migrations:
 *   1. a policy de leitura direta (partners_read_members) pede exatamente essas três condições;
 *   2. list_card_partners calcula a regra no SELECT do chamador e só põe o contato na coluna por ela;
 *   3. toda função cuja definição mais nova lê o contato da tabela está numa lista fechada, e cada uma pergunta a
 *      ação antes de ler. Uma função nova que leia o contato reprova até entrar na lista com o seu portão.
 * Controles: a captura anterior à migration da regra é a de antes (o extrator sabe dizer "diferente"), e a
 * varredura do item 3 acha exatamente a lista, nem menos.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments, buildNewestDefinitions } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const REGRA = "public.rls_is_superadmin() OR public.rls_can('view_partner') OR public.rls_can('manage_partner')";

const mask = (sql) => maskLineComments(sql).replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
const files = () => readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();

/** USING (...) da última ALTER/CREATE POLICY partners_read_members, com parênteses balanceados. */
function usingDaPolicy(excluir = new Set()) {
  let hit = null;
  for (const f of files()) {
    if (excluir.has(f)) continue;
    const sql = mask(readFileSync(join(MIG_DIR, f), 'utf8'));
    const re = /\b(?:ALTER|CREATE)\s+POLICY\s+"?partners_read_members"?\s+ON\s+public\.partner_entities\b/gi;
    let m;
    while ((m = re.exec(sql)) !== null) {
      const fim = sql.indexOf(';', m.index);
      const stmt = sql.slice(m.index, fim);
      const u = stmt.search(/\bUSING\s*\(/i);
      if (u < 0) continue;
      const abre = stmt.indexOf('(', u);
      let nivel = 0, i = abre;
      for (; i < stmt.length; i++) {
        if (stmt[i] === '(') nivel++;
        else if (stmt[i] === ')' && --nivel === 0) break;
      }
      hit = { file: f, stmt, using: stmt.slice(abre + 1, i).replace(/\s+/g, ' ').trim() };
    }
  }
  return hit;
}

test('partners_read_members pede superadmin, view_partner ou manage_partner, e nada além', () => {
  const p = usingDaPolicy();
  assert.ok(p, 'a policy partners_read_members tem captura');
  assert.equal(p.using, REGRA, `${p.file}: USING da leitura direta`);
  if (/^CREATE/i.test(p.stmt)) assert.match(p.stmt, /FOR\s+SELECT\s+TO\s+authenticated/i, 'a policy é de SELECT para authenticated');
});

test('controle: sem a migration da regra, a captura é a de antes', () => {
  const atual = usingDaPolicy();
  const antes = usingDaPolicy(new Set([atual.file]));
  assert.ok(antes, 'há captura anterior');
  assert.notEqual(antes.using, REGRA, 'o extrator distingue a regra nova da anterior');
  assert.equal(antes.using, 'public.rls_is_authoritative_member()');
});

test('list_card_partners: o contato sai só pela regra, calculada para o chamador', () => {
  const c = latestFunctionCapture(ROOT, 'list_card_partners');
  const b = mask(c.block);
  assert.match(b, /RETURNS TABLE\([^)]*partner_status text, partner_contact_name text\)/, 'assinatura igual');
  assert.match(
    b,
    /SELECT m\.id,\s*\(coalesce\(m\.is_superadmin, false\)\s*OR public\.can_by_member\(m\.id, 'view_partner'\)\s*OR public\.can_by_member\(m\.id, 'manage_partner'\)\)\s*INTO v_member_id, v_ve_contato\s*FROM public\.members m\s*WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true;/,
    'v_ve_contato é a regra, para o membro ativo do auth.uid()',
  );
  const i = b.indexOf('RETURN QUERY');
  const j = b.indexOf('FROM public.partner_cards pc', i);
  assert.ok(i > 0 && j > i, 'a lista do RETURN QUERY foi recortada');
  // A migration da regra reescreve a função; o guard 785 fixa a migration 275, então o portão de confidencial da
  // captura vigente é afirmado aqui.
  const conf = b.search(/IF NOT public\.rls_can_see_item\(p_board_item_id\) THEN RETURN; END IF;/);
  assert.ok(conf > 0 && conf < i, 'o portão de confidencial vem antes do RETURN QUERY');
  const lista = b.slice(i, j);
  assert.match(lista, /pe\.status,\s*CASE WHEN v_ve_contato THEN pe\.contact_name END\s*$/, 'a última coluna depende da regra');
  assert.equal((lista.match(/pe\.contact_name/g) || []).length, 1, 'o contato não sai solto em outra coluna');
  assert.doesNotMatch(lista, /contact_email/, 'o e-mail não sai');
});

/** Portão que tem de vir antes da primeira leitura da tabela, por função da lista. */
const LISTA = {
  get_partner_pipeline: /IF NOT public\.can_by_member\(v_caller_id, 'view_partner'\) THEN/,
  admin_manage_partner_entity: /IF NOT public\.can_by_member\(v_caller_id, 'manage_partner'\) THEN/,
  list_card_partners: /CASE WHEN v_ve_contato THEN pe\.contact_name END/,
};

/** Todos os blocos CREATE de uma função num texto de migration (uma por sobrecarga), até o fecho do dollar-quote. */
function blocosNoArquivo(txt, nome) {
  const out = [];
  const re = new RegExp(`\\bCREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:"?public"?\\s*\\.\\s*)?"?${nome}"?\\s*\\(`, 'gi');
  let m;
  while ((m = re.exec(txt)) !== null) {
    const tag = txt.slice(m.index).match(/\bAS\s+(\$[a-z_]*\$)/i);
    if (!tag) continue;
    const ini = m.index + tag.index + tag[0].length;
    const fim = txt.indexOf(tag[1], ini);
    out.push(txt.slice(m.index, fim < 0 ? txt.length : fim));
  }
  return out;
}

test('quem lê o contato da tabela está na lista, com o portão antes da leitura', () => {
  const { newest } = buildNewestDefinitions(MIG_DIR);
  const cache = new Map();
  const achadas = [];
  for (const [nome, { file }] of newest) {
    if (!cache.has(file)) cache.set(file, mask(readFileSync(join(MIG_DIR, file), 'utf8')));
    const txt = cache.get(file);
    if (!/partner_entities/.test(txt) || !/contact_(name|email)/.test(txt)) continue;
    // Cada sobrecarga da migration mais nova conta: um nome com duas assinaturas não escapa por ser ambíguo.
    const le = blocosNoArquivo(txt, nome).some((b) => /\bpartner_entities\b/.test(b) && /\bcontact_(name|email)\b/.test(b));
    if (le) achadas.push(nome);
  }
  assert.deepEqual(achadas.sort(), Object.keys(LISTA).sort(), 'funções que leem o contato de partner_entities');
  for (const [nome, portao] of Object.entries(LISTA)) {
    const b = mask(latestFunctionCapture(ROOT, nome).block);
    const g = b.search(portao);
    assert.ok(g >= 0, `${nome}: o portão está no corpo`);
    if (nome !== 'list_card_partners') {
      const r = b.search(/\bpartner_entities\b/);
      assert.ok(g < r, `${nome}: o portão vem antes da primeira leitura da tabela`);
    }
  }
});
