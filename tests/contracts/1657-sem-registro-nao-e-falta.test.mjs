/**
 * #1657 (Onda 1, épica #1652) - "sem registro" deixa de ser lido como "faltou".
 *
 * Relatado ao vivo na Reunião de Liderança de 06/08: um líder via falta sua numa reunião que
 * ninguém confirmava ter acontecido, e disse ter ficado com medo de ir marcar presença sem saber
 * se o evento ocorreu. Ele estava certo: não marcar e ter faltado produziam o mesmo pixel.
 *
 * Medido em 09/08/2026 contra `ldrfrvwhxsmgaabwmaik`:
 *
 *   49 eventos passados elegíveis no ciclo, 5 com ZERO linha de presença e 9 com apenas 1 a 3
 *   92 células passaram de 'absent' inferido para 'unrecorded', em 43 membros e 28 eventos
 *   2 pessoas seriam 'detractor' e 5 'at_risk' só por falta inferida; passaram a 0
 *
 * ── O denominador é a metade que quase passou batido ────────────────────────────────────────
 * Trocar a célula SOZINHA colapsaria o `rate`: como não há NENHUMA falta declarada no ciclo
 * (0 linhas `present=false, excused=false`), o denominador `present + absent` viraria só
 * `present`, e 65 de 66 membros iriam a 100%, com a média saltando de 0,779 para 0,985. Uma
 * mentira trocada por outra, na mesma tela. Por isso `unrecorded` PERMANECE no denominador: o que
 * muda é a acusação (a célula e o rótulo detractor), não a métrica agregada.
 *
 * ── Por que não há camada comportamental automatizada ───────────────────────────────────────
 * `get_tribe_attendance_grid` resolve o chamador por `auth.uid()` e recusa `service_role`, então
 * a suíte não consegue exercê-la (mesma limitação declarada no #1476, no #1653 e no #1660). A
 * camada B compara o corpo VIVO com a captura sobre a qual as asserções estáticas rodam.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  loadLatestCaptures,
  parseMigration,
  normalizeBody,
  md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const MIGRATIONS_DIR = join(process.cwd(), 'supabase/migrations');
const FN = 'get_tribe_attendance_grid';
const ARGS_CANONICOS = 'p_tribe_id integer, p_event_type text';

function capturaMaisRecente() {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const entrada = latest.get(`${FN}@${ARGS_CANONICOS}`);
  assert.ok(entrada, `nenhuma captura para ${FN}@${ARGS_CANONICOS}`);
  const sql = readFileSync(join(MIGRATIONS_DIR, entrada.file), 'utf8');
  const bloco = parseMigration(entrada.file, sql).find((b) => b.name === FN);
  assert.ok(bloco, `${entrada.file} deveria conter o bloco de ${FN}`);
  return bloco;
}

describe('#1657 - sem registro não é falta', () => {
  const bloco = capturaMaisRecente();
  const semComentarios = bloco.body.replace(/--.*$/gm, '');

  describe('a célula', () => {
    it('evento NÃO SELADO sem linha vira unrecorded, não absent', () => {
      assert.match(
        semComentarios,
        /WHEN ge\.roster_sealed_at IS NULL THEN 'unrecorded'/,
        'o ramo de "sem linha" precisa consultar roster_sealed_at'
      );
    });

    it('o selo chega até a célula: raw_events e grid_events carregam roster_sealed_at', () => {
      const ocorrencias = (semComentarios.match(/roster_sealed_at/g) || []).length;
      assert.ok(
        ocorrencias >= 3,
        `roster_sealed_at precisa ser selecionado em raw_events, propagado em grid_events e lido em ` +
          `cell_status; achei ${ocorrencias} ocorrências`
      );
    });

    it('evento SELADO sem linha continua sendo falta (o selo materializa a linha)', () => {
      assert.match(semComentarios, /THEN 'unrecorded'\s*\n?\s*ELSE 'absent' END/);
    });

    it('offboardado antes do evento continua fora da conta', () => {
      assert.match(semComentarios, /gm\.offboarded_at::date <= ge\.date THEN 'na'/);
    });
  });

  describe('o denominador, que é onde a correção quase virou outra mentira', () => {
    it('unrecorded PERMANECE no denominador do rate', () => {
      assert.match(
        semComentarios,
        /NULLIF\(COUNT\(\*\) FILTER \(WHERE cs\.status IN \('present', 'absent', 'unrecorded'\)\), 0\)/,
        'tirar unrecorded do denominador levaria 65 de 66 membros a 100%'
      );
    });

    it('unrecorded conta em eligible_count', () => {
      assert.match(
        semComentarios,
        /FILTER \(WHERE cs\.status IN \('present', 'absent', 'excused', 'unrecorded'\)\) AS eligible_count/
      );
    });

    it('a grade EXPÕE quanto do percentual está apoiado em omissão', () => {
      assert.match(semComentarios, /FILTER \(WHERE cs\.status = 'unrecorded'\) AS unrecorded_count/);
      assert.match(semComentarios, /'unrecorded_count', COALESCE\(ms\.unrecorded_count, 0\)/);
      assert.match(semComentarios, /'unrecorded_cells'/);
    });

    it('o rótulo detractor/at_risk só olha falta DECLARADA', () => {
      // detractor_calc filtra explicitamente ('present','absent'); 'unrecorded' fica fora por
      // construção. Sem isto, a acusação voltaria pela porta do rótulo.
      const trecho = semComentarios.slice(semComentarios.indexOf('detractor_calc AS ('));
      assert.ok(!trecho.includes("'unrecorded'"), 'unrecorded não pode entrar em detractor_calc');
      assert.match(trecho, /cs2\.status IN \('present', 'absent'\)/);
    });
  });

  describe('o CTE morto do p124 saiu junto', () => {
    it('event_row_counts não é mais calculado', () => {
      assert.doesNotMatch(
        semComentarios,
        /event_row_counts\s+AS\s*\(/,
        'o CTE alimentava um alias que nenhuma linha lia desde a captura do p209'
      );
    });

    it('e nenhum alias órfão sobrou', () => {
      assert.doesNotMatch(semComentarios, /\berc\b/);
    });
  });

  describe('camada B (viva): o corpo em produção é a captura asseverada acima', () => {
    const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
    const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const gated = SUPABASE_URL && SERVICE_ROLE ? it : it.skip;

    gated('md5 do corpo vivo == md5 da captura', async () => {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_function_bodies`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: SERVICE_ROLE,
          Authorization: `Bearer ${SERVICE_ROLE}`,
        },
        body: JSON.stringify({}),
      });
      assert.ok(res.ok, `RPC de corpos falhou: ${res.status}`);
      const vivas = (await res.json()).filter((r) => r.proname === FN);
      assert.equal(vivas.length, 1);
      assert.equal(
        vivas[0].body_md5,
        md5(normalizeBody(bloco.body)),
        `o corpo vivo de ${FN} não é o capturado em ${bloco.file}`
      );
    });
  });
});

describe('#1705 - limpar registro é ato distinto de marcar falta', () => {
  const TRIBE = readFileSync(join(process.cwd(), 'src/components/tribes/TribeAttendanceTab.tsx'), 'utf8');

  it('a grade de tribo chama clear_member_attendance', () => {
    assert.match(TRIBE, /rpc\('clear_member_attendance'/);
  });

  it('e o ato de marcar falta continua sendo outro (mark_member_present)', () => {
    assert.match(TRIBE, /rpc\('mark_member_present'/);
  });

  it('o botão de limpar não reusa o rótulo de "Ausente"', () => {
    assert.match(TRIBE, /attendance\.grid\.modal\.clear/);
  });
});
