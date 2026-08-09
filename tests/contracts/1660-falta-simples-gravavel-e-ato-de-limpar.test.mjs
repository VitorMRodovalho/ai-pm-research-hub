/**
 * #1660 (Onda 1, épica #1652) - "faltou" volta a ser gravável, e "tirar presença" vira ato próprio.
 *
 * O p199-c (2026-05-19) fez `mark_member_present(p_present := false)` APAGAR a linha. A partir daí
 * a plataforma não conseguia mais afirmar uma falta simples: medido em 09/08/2026, 3 linhas
 * `present=false, excused=false` em 2.029, todas anteriores àquela data.
 *
 * Não era ausência de capacidade, era CONTORNO: `mark_member_excused(p_excused := false)` faz
 * `UPDATE ... SET excused = false` sem tocar `present`, então justificar e desjustificar deixa uma
 * falta simples. O ato DIRETO é que apagava.
 *
 * Prova comportamental, corrida em 09/08/2026 contra produção numa transação desfeita por
 * `RAISE EXCEPTION` (as duas triggers de `attendance` são SQL puro, sem chamada externa):
 *
 *   mark_member_present(evento, membro, false)  ->  present=f excused=f reason_null=t
 *   clear_member_attendance(evento, membro)     ->  {"success": true, "cleared": 1}, restantes=0
 *
 * Nada persistiu (2.029 linhas e 3 faltas simples antes e depois).
 *
 * Por que este guard não tem camada comportamental automatizada: as duas RPCs resolvem o chamador
 * por `auth.uid()` e recusam `service_role` com 'Not authenticated'. Exercê-las da suíte exigiria
 * um harness de chamador autenticado que não existe (mesma limitação declarada no #1476 e no
 * #1653). A camada B abaixo é o que impede a asserção estática de virar afirmação sobre um
 * arquivo: ela compara o corpo VIVO das três funções com a captura sobre a qual as asserções
 * rodam, então DDL aplicada fora de migration, ou uma migration posterior que traga o `DELETE` de
 * volta, deixa a suíte vermelha.
 *
 * Ponteiro para a captura DERIVADO de `loadLatestCaptures`, nunca um caminho de migration escrito
 * à mão (lição do #1682/#569: um guard que persegue captura hardcoded fica vermelho por trabalho
 * correto na terceira recaptura).
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

// nome -> assinatura canônica normalizada (a chave que `loadLatestCaptures` produz)
const FUNCOES = {
  mark_member_present: 'p_event_id uuid, p_member_id uuid, p_present boolean',
  clear_member_attendance: 'p_event_id uuid, p_member_id uuid',
  admin_bulk_mark_attendance: 'p_event_id uuid, p_member_ids uuid[], p_present boolean',
};

/** Captura mais recente de cada função, com o arquivo derivado do parser. */
function capturas() {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const out = {};
  for (const [nome, args] of Object.entries(FUNCOES)) {
    const chave = `${nome}@${args}`;
    const entrada = latest.get(chave);
    assert.ok(
      entrada,
      `nenhuma captura para ${chave}. Chaves vistas: ${[...latest.keys()]
        .filter((k) => k.startsWith(`${nome}@`))
        .join(' | ')}`
    );
    const sql = readFileSync(join(MIGRATIONS_DIR, entrada.file), 'utf8');
    const bloco = parseMigration(entrada.file, sql).find((b) => b.name === nome);
    assert.ok(bloco, `${entrada.file} deveria conter o bloco de ${nome}`);
    out[nome] = { ...bloco, sqlDoArquivo: sql };
  }
  return out;
}

describe('#1660 - falta simples gravável, e limpar o registro como ato distinto', () => {
  const cap = capturas();

  describe('mark_member_present: o ramo falso GRAVA a falta', () => {
    const b = cap.mark_member_present.body;

    it('não apaga mais a linha', () => {
      assert.doesNotMatch(
        b.replace(/--.*$/gm, ''), // o corpo CITA o p199-c num comentário; citar não é fazer
        /DELETE\s+FROM\s+public\.attendance/i,
        'o ramo p_present=false não pode voltar a apagar a linha'
      );
    });

    it('grava present=false, excused=false e limpa a justificativa', () => {
      assert.match(
        b,
        /INSERT INTO public\.attendance \(event_id, member_id, present, excused, excuse_reason\)\s*VALUES \(p_event_id, p_member_id, false, false, NULL\)/,
        'INSERT da falta simples'
      );
      assert.match(
        b,
        /DO UPDATE SET\s*present = false, excused = false, excuse_reason = NULL/,
        'o UPSERT precisa afirmar os três campos, não só inserir'
      );
    });

    it('o ramo verdadeiro e o gate de autoridade continuam intactos', () => {
      assert.match(b, /VALUES \(p_event_id, p_member_id, true, false\)/, 'presença segue gravando true');
      assert.match(b, /IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'/);
      assert.match(b, /IF v_caller_id = p_member_id THEN/, 'auto-marcação continua permitida');
      assert.match(b, /can_by_member\(v_caller_id, 'manage_event'\)/, 'terceiro exige manage_event');
    });
  });

  describe('clear_member_attendance: o ato do p199-c, separado e com a mesma autoridade', () => {
    const b = cap.clear_member_attendance.body;

    it('apaga a linha e informa quantas', () => {
      assert.match(b, /DELETE FROM public\.attendance WHERE event_id = p_event_id AND member_id = p_member_id/);
      assert.match(b, /GET DIAGNOSTICS v_removed = ROW_COUNT/, 'o retorno precisa dizer se havia o que limpar');
      assert.match(b, /'cleared', v_removed/);
    });

    it('carrega o MESMO gate de mark_member_present (não é porta mais larga)', () => {
      assert.match(b, /IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'/);
      assert.match(b, /IF v_caller_id = p_member_id THEN/);
      assert.match(b, /can_by_member\(v_caller_id, 'manage_event'\)/);
    });

    it('a migration revoga de anon e concede só a authenticated/service_role', () => {
      const sql = cap.clear_member_attendance.sqlDoArquivo;
      assert.match(sql, /REVOKE ALL ON FUNCTION public\.clear_member_attendance\(uuid, uuid\) FROM anon/);
      assert.match(
        sql,
        /GRANT EXECUTE ON FUNCTION public\.clear_member_attendance\(uuid, uuid\) TO authenticated, service_role/
      );
    });
  });

  describe('admin_bulk_mark_attendance: o lote diz o mesmo que o ato por membro', () => {
    const b = cap.admin_bulk_mark_attendance.body;

    it('o lote falso grava falta em vez de apagar', () => {
      assert.doesNotMatch(b.replace(/--.*$/gm, ''), /DELETE\s+FROM\s+public\.attendance/i);
      assert.match(b, /VALUES \(p_event_id, v_mid, false, false, NULL, v_caller_id\)/);
    });

    it('o lote verdadeiro AFIRMA present = true em vez de confiar no DEFAULT', () => {
      // Antes do #1660 este ramo inseria só checked_in_at/marked_by e o DO UPDATE não tocava
      // present. Era inofensivo enquanto falta não existia como linha; com falta gravável, marcar
      // o lote como presente deixaria ausente quem já tivesse linha de falta.
      assert.match(b, /VALUES \(p_event_id, v_mid, true, false, now\(\), v_caller_id\)/);
      assert.match(b, /DO UPDATE SET present = true, excused = false/);
    });
  });

  describe('camada B (viva): as três funções em produção são as capturas asseguradas acima', () => {
    const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
    const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const gated = SUPABASE_URL && SERVICE_ROLE ? it : it.skip;

    gated('md5 do corpo vivo == md5 da captura, nas três', async () => {
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
      const linhas = await res.json();

      for (const nome of Object.keys(FUNCOES)) {
        const vivas = linhas.filter((r) => r.proname === nome);
        assert.equal(vivas.length, 1, `esperava 1 ${nome} viva, achei ${vivas.length}`);
        assert.equal(
          vivas[0].body_md5,
          md5(normalizeBody(cap[nome].body)),
          `o corpo vivo de ${nome} não é o capturado em ${cap[nome].file} - DDL fora de migration, ` +
            'ou a captura ficou para trás. As asserções estáticas acima não falam do que está rodando.'
        );
      }
    });
  });
});
