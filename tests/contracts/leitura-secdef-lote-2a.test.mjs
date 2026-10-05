/**
 * Funções de leitura SECURITY DEFINER seguem a política de leitura das tabelas (lote 2a).
 *
 * Mesma regra de leitura-secdef-segue-politica-das-tabelas.test.mjs: a quem chama pela API
 * (public._request_is_rest_caller(), #684), a leitura segue a política da tabela, membro com vínculo
 * vigente (rls_is_authoritative_member()), com a recusa no formato que a função já usava.
 *
 * O QUE ESTE GUARD AFIRMA, na captura VIGENTE de cada função:
 *   - a regra existe e vem antes da primeira leitura de dado;
 *   - nas linhas do tempo de eventos, a ata só sai com vínculo vigente (o resto segue a política de
 *     events, aberta a quem tem cadastro de membro); no radar, só as publicações exigem vínculo.
 *
 * get_board_activities tem duas assinaturas numa migration antiga, e latestFunctionCapture recusa
 * nome ambíguo (#1932); para ela, a captura vigente é resolvida pela assinatura.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const REGRA = String.raw`public\._request_is_rest_caller\(\) AND NOT public\.rls_is_authoritative_member\(\)`;
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Última captura de uma função por assinatura, para nomes com sobrecarga. */
function latestBySignature(name, sigPrefix) {
  const dir = join(ROOT, 'supabase/migrations');
  const head = new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\(\\s*${esc(sigPrefix)}`, 'g');
  let last = null;
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(dir, f), 'utf8'));
    let m;
    while ((m = head.exec(sql)) !== null) {
      const open = sql.indexOf('$function$', m.index) + '$function$'.length;
      const close = sql.indexOf('$function$', open);
      last = sql.slice(m.index, close + '$function$'.length);
    }
  }
  assert.ok(last, `${name}(${sigPrefix}...) tem captura`);
  return last;
}

const cap = (name) =>
  name === 'get_board_activities'
    ? latestBySignature('get_board_activities', 'p_board_id uuid, p_assignee_filter uuid')
    : maskLineComments(latestFunctionCapture(ROOT, name).block);

/** [função, retorno de recusa (texto literal depois de THEN), marcador da primeira leitura] */
const CASOS = [
  ['get_board_activities', "RETURN jsonb_build_object('activities', '[]'::jsonb, 'total', 0, 'completed', 0, 'pending', 0);", 'IF NOT public.rls_can_see_board(p_board_id)'],
  ['get_board_drive_links', "RETURN jsonb_build_object('board_id', p_board_id, 'drive_links', '[]'::jsonb, 'fetched_at', now());", 'IF NOT public.rls_can_see_board(p_board_id)'],
  ['get_board_lifecycle_log', "RETURN jsonb_build_object('events', '[]'::jsonb, 'count', 0); END IF;", 'SELECT COALESCE(jsonb_agg(row_to_json(evt)'],
  ['get_board_tags', "RETURN '[]'::jsonb; END IF;", 'SELECT jsonb_agg(DISTINCT tag'],
  ['get_card_full_history', "RETURN jsonb_build_object('error', 'card_not_found'); END IF;", 'SELECT bi.id, bi.title'],
  ['get_cpmai_leaderboard', "RETURN '[]'::jsonb; END IF;", 'SELECT jsonb_agg(row_data'],
  ['get_event_tags', 'RETURN; END IF;', 'RETURN QUERY'],
  ['get_event_tags_batch', 'RETURN; END IF;', 'RETURN QUERY'],
  ['get_initiative_drive_links', "RETURN jsonb_build_object('error', 'Initiative not found');", 'IF NOT public.rls_can_see_initiative(p_initiative_id)'],
  ['get_item_curation_history', "RETURN jsonb_build_object('reviews', '[]'::jsonb, 'assignments', '[]'::jsonb, 'sla_config', '{}'::jsonb);", 'IF NOT public.rls_can_see_item(p_item_id)'],
  ['get_mirror_target_boards', 'RETURN; END IF;', 'RETURN QUERY'],
  ['get_tribe_housekeeping', "RAISE EXCEPTION 'Not authorized'; END IF;", 'IF p_initiative_id IS NOT NULL THEN'],
  ['get_webinar_lifecycle', "RETURN '[]'::jsonb; END IF;", 'SELECT COALESCE(jsonb_agg(row_to_json(r)'],
  ['list_active_boards', 'RETURN; END IF;', 'RETURN QUERY'],
  ['list_card_drive_files', "RETURN jsonb_build_object('error', 'Card not found');", 'IF NOT public.rls_can_see_board(v_board_id)'],
  ['list_card_partners', 'RETURN; END IF;', 'RETURN QUERY'],
  ['list_partner_cards', 'RETURN; END IF;', 'RETURN QUERY'],
  ['search_partner_cards', 'RETURN; END IF;', 'RETURN QUERY'],
  ['list_meetings_with_notes', "RETURN jsonb_build_object('meetings', '[]'::jsonb, 'total', 0, 'limit', p_limit, 'offset', p_offset);", 'SELECT count(*) INTO v_total'],
  ['list_project_boards', 'RETURN; END IF;', 'RETURN QUERY'],
];

for (const [name, recusa, marcador] of CASOS) {
  test(`${name}: aplica a regra da tabela antes de ler`, () => {
    const b = cap(name);
    const g = b.search(new RegExp(`IF ${REGRA} THEN\\s+${esc(recusa)}`));
    assert.ok(g >= 0, `${name}: a regra com a recusa "${recusa.slice(0, 40)}" está no corpo`);
    const r = b.indexOf(marcador, g);
    assert.ok(r > g, `${name}: a regra vem antes de "${marcador.slice(0, 40)}"`);
  });
}

for (const name of ['get_initiative_events_timeline', 'get_tribe_events_timeline']) {
  test(`${name}: a ata só sai com vínculo vigente`, () => {
    const b = cap(name);
    assert.match(b, /v_full boolean := NOT public\._request_is_rest_caller\(\) OR public\.rls_is_authoritative_member\(\);/, 'v_full é a regra da tabela');
    assert.match(b, /'minutes_text', CASE WHEN v_full THEN e\.minutes_text END/, 'a ata depende de v_full');
    assert.doesNotMatch(b, /'minutes_text', e\.minutes_text/, 'a ata não sai solta');
  });
}

test('list_radar_global: as publicações exigem vínculo vigente; os webinars seguem a política de events', () => {
  const b = cap('list_radar_global');
  const pubs = b.slice(b.indexOf("= 'publications_submissions'"), b.indexOf('INTO v_publications') > 0 ? b.length : b.length);
  assert.match(pubs, /AND \(NOT public\._request_is_rest_caller\(\) OR public\.rls_is_authoritative_member\(\)\)\s+ORDER BY bi\.updated_at DESC/, 'o filtro está na consulta das publicações');
  const web = b.slice(0, b.indexOf("= 'publications_submissions'"));
  assert.doesNotMatch(web, /rls_is_authoritative_member/, 'a consulta dos webinars não ganhou a regra');
});
