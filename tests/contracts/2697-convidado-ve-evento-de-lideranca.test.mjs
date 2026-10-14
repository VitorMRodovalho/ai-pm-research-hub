// tests/contracts/2697-convidado-ve-evento-de-lideranca.test.mjs
/**
 * #2697 — o convidado do próprio evento vê o evento de liderança, e gravar convidados passa a
 * exigir autoridade sobre o evento.
 *
 * SINTOMA (13/10/2026): uma líder de grupo de trabalho, convidada para as reuniões de liderança,
 * recebia `Restricted content` em `get_event_detail`. `manage_event` sem recurso só vale para
 * vínculo com TRIBO, então liderar uma iniciativa que não é tribo não alcança `leadership`.
 *
 * PRECONDIÇÃO: `set_event_invited_members` era SECURITY DEFINER sem portão e executável por anon.
 * Fazer o convite conceder leitura sem fechar a escrita entregaria `leadership` a quem se
 * convidasse. Por isso as duas coisas vivem no mesmo arquivo e nas mesmas asserções.
 *
 * O que este arquivo prova:
 *   (A) a gravação de convidados exige `_manage_event_scope_ok` ANTES de apagar ou inserir;
 *   (B) o convite libera SÓ `leadership`: no detalhe e na regra de 3 argumentos, nunca `gp_only`;
 *   (C) as duas listagens usam a regra de 3 argumentos com o id do evento;
 *   (D) anon/PUBLIC perdem EXECUTE na gravação;
 *   (E) as asserções mordem (reinjeção de cada defeito);
 *   (F) o corpo VIVO é o capturado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const cap = (name) => latestFunctionCapture(ROOT, name);
const MIG_DIR = join(ROOT, 'supabase/migrations');
const MIG = (() => {
  const f = readdirSync(MIG_DIR).filter((x) => /_2697_/.test(x));
  return f.length === 1 ? maskLineComments(readFileSync(join(MIG_DIR, f[0]), 'utf8')) : '';
})();

/** Recorta o IF ... THEN que decide a visibilidade `v` no corpo do detalhe. */
function blocoDeVisibilidade(corpo, v) {
  const sql = maskLineComments(corpo);
  const i = sql.indexOf(`IF v_event.visibility = '${v}'`);
  if (i < 0) return '';
  return sql.slice(i, sql.indexOf('THEN', i) + 4);
}

function violacoesGravacao(corpo) {
  const v = [];
  const sql = maskLineComments(corpo);
  const iGate = sql.search(/IF NOT public\._manage_event_scope_ok\(v_caller_id, p_event_id\) THEN\s+RAISE EXCEPTION/);
  const iDel = sql.indexOf('DELETE FROM public.event_invited_members');
  if (iGate < 0) v.push('a gravação de convidados não exige _manage_event_scope_ok sobre o evento');
  if (iDel < 0) v.push('não achei o DELETE da lista (corpo inesperado)');
  if (iGate > 0 && iDel > 0 && iGate > iDel) v.push('o portão vem DEPOIS do DELETE');
  return v;
}

function violacoesDetalhe(corpo) {
  const v = [];
  const lid = blocoDeVisibilidade(corpo, 'leadership');
  const gp = blocoDeVisibilidade(corpo, 'gp_only');
  if (!/AND NOT public\._caller_is_event_invitee\(p_event_id\)\s+THEN$/.test(lid)) {
    v.push("o bloco 'leadership' do detalhe não aceita o convidado do evento");
  }
  if (/_caller_is_event_invitee/.test(gp)) v.push("o convite passou a liberar 'gp_only'");
  if (!gp) v.push("não achei o bloco 'gp_only' (controle)");
  return v;
}

function violacoesRegra3(corpo) {
  const v = [];
  const sql = maskLineComments(corpo);
  if (!/public\.rls_can_see_event_tier\(p_visibility, p_initiative_id\)\s+OR \(p_visibility = 'leadership'\s+AND p_event_id IS NOT NULL\s+AND public\._caller_is_event_invitee\(p_event_id\)\)/.test(sql)) {
    v.push("a regra de 3 argumentos não amarra o convite a 'leadership'");
  }
  if (/'gp_only'/.test(sql)) v.push("a regra de 3 argumentos menciona 'gp_only'");
  return v;
}

function violacoesListagem(corpo, esperadas) {
  const sql = maskLineComments(corpo);
  const tres = (sql.match(/public\.rls_can_see_event_tier\(e\.visibility, e\.initiative_id, e\.id\)/g) || []).length;
  const dois = (sql.match(/public\.rls_can_see_event_tier\(e\.visibility, e\.initiative_id\)/g) || []).length;
  const v = [];
  if (tres !== esperadas) v.push(`esperava ${esperadas} chamada(s) de 3 argumentos, achei ${tres}`);
  if (dois !== 0) v.push(`sobrou ${dois} chamada(s) de 2 argumentos`);
  return v;
}

test('#2697 static: gravação de convidados exige autoridade antes de mexer na lista', () => {
  assert.deepEqual(violacoesGravacao(cap('set_event_invited_members').body), []);
});

test('#2697 static: o detalhe libera o convidado só em leadership', () => {
  assert.deepEqual(violacoesDetalhe(cap('get_event_detail').body), []);
});

test('#2697 static: a regra de 3 argumentos amarra o convite a leadership', () => {
  const c = latestFunctionCapture(ROOT, 'rls_can_see_event_tier');
  assert.ok(c?.body, 'alguma migration captura rls_can_see_event_tier');
  // a captura mais nova é a de 3 argumentos (#2697)
  assert.deepEqual(violacoesRegra3(c.body), []);
});

test('#2697 static: as listagens usam a regra com o id do evento', () => {
  assert.deepEqual(violacoesListagem(cap('get_events_with_attendance').body, 1), []);
  assert.deepEqual(violacoesListagem(cap('list_meetings_with_notes').body, 2), []);
});

test('#2697 static: anon e PUBLIC perdem EXECUTE na gravação; search_path declarado', () => {
  assert.ok(MIG.length > 0, 'esperava 1 migration da #2697');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.set_event_invited_members\(uuid, jsonb\) FROM PUBLIC, anon;/);
  assert.match(MIG, /FUNCTION public\.set_event_invited_members\(p_event_id uuid, p_members jsonb\)\s+RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS/);
});

// ── E — as asserções mordem ──────────────────────────────────────────────────────────
test('#2697 static: reprova a gravação sem portão', () => {
  const { body } = cap('set_event_invited_members');
  const adulterado = body.replace(/IF NOT public\._manage_event_scope_ok\(v_caller_id, p_event_id\) THEN\s+RAISE EXCEPTION '[^']+';\s+END IF;/, '');
  assert.notEqual(adulterado, body);
  assert.ok(violacoesGravacao(adulterado).some((m) => m.includes('não exige')));
});

test('#2697 static: reprova o detalhe que esquece o convidado', () => {
  const { body } = cap('get_event_detail');
  const adulterado = body.replace('\n     AND NOT public._caller_is_event_invitee(p_event_id) THEN', ' THEN');
  assert.notEqual(adulterado, body);
  assert.ok(violacoesDetalhe(adulterado).some((m) => m.includes("'leadership'")));
});

test('#2697 static: reprova o convite que vaza para gp_only', () => {
  const { body } = cap('get_event_detail');
  const adulterado = body.replace(
    "IF v_event.visibility = 'gp_only'\n     AND NOT public.can_by_member(v_caller.id, 'manage_platform')",
    "IF v_event.visibility = 'gp_only'\n     AND NOT public.can_by_member(v_caller.id, 'manage_platform')\n     AND NOT public._caller_is_event_invitee(p_event_id)",
  );
  assert.notEqual(adulterado, body);
  assert.ok(violacoesDetalhe(adulterado).some((m) => m.includes('gp_only')));
});

test('#2697 static: reprova a regra que solta o convite de leadership', () => {
  const { body } = latestFunctionCapture(ROOT, 'rls_can_see_event_tier');
  const adulterado = body.replace("OR (p_visibility = 'leadership'\n        AND p_event_id IS NOT NULL", 'OR (p_event_id IS NOT NULL');
  assert.notEqual(adulterado, body);
  assert.ok(violacoesRegra3(adulterado).length > 0);
});

test('#2697 static: reprova a listagem que volta a 2 argumentos', () => {
  const { body } = cap('list_meetings_with_notes');
  const adulterado = body.replace('rls_can_see_event_tier(e.visibility, e.initiative_id, e.id)', 'rls_can_see_event_tier(e.visibility, e.initiative_id)');
  assert.notEqual(adulterado, body);
  assert.ok(violacoesListagem(adulterado, 2).length > 0);
});

// ── F — o corpo vivo é o capturado ───────────────────────────────────────────────────
test('#2697 db: corpos VIVOS batem com as capturas e carregam o desenho',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    for (const name of ['set_event_invited_members', 'get_event_detail', 'get_events_with_attendance', 'list_meetings_with_notes', '_caller_is_event_invitee']) {
      const c = cap(name);
      const md5 = createHash('md5').update(c.body.replace(/\s+/g, ' ')).digest('hex');
      const vivas = (data ?? []).filter((f) => f.proname === name);
      assert.equal(vivas.length, 1, `${name}: esperava 1 viva, achei ${vivas.length}`);
      assert.equal(vivas[0].body_md5, md5, `${name}: corpo vivo divergiu de ${c.file}`);
    }
    const src = await sb().rpc('_audit_function_source', { p_proname: 'get_event_detail' });
    assert.ifError(src.error);
    for (const row of src.data ?? []) assert.deepEqual(violacoesDetalhe(row.prosrc), []);
  });
