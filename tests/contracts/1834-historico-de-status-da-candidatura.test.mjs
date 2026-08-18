/**
 * #1834 — o status da candidatura tem histórico próprio, escrito por trigger de TABELA.
 *
 * Por que trigger e não auditoria por função, medido em 17/08/2026: vinte funções de
 * `public` escrevem `selection_applications.status` e apenas seis auditam a mudança. E o
 * evento que originou a issue não passou por função nenhuma — nenhuma escreve `imported_at`
 * por UPDATE, e 152 linhas pré-existentes o receberam entre 13:03:46 e 13:05:50 UTC —, então
 * veio de SQL direto com `service_role`. Conserto por função não alcança esse caminho.
 *
 * O que este guard protege, em ordem de importância:
 *
 *   1. **A honestidade do carimbo.** `changed_at` é NOT NULL quando a linha veio do trigger e
 *      NULO quando é a base semeada. Preencher a base com `updated_at` reproduziria exatamente
 *      o erro que criou a issue: `updated_at` é o relógio da LINHA, não do fato.
 *   2. **A guarda de no-op.** UPDATE que não mexe no status não pode virar linha, senão o
 *      histórico enche de transições que não existiram e a contagem mente para o outro lado.
 *   3. **O caminho de escrita é único.** Sem policy de INSERT/UPDATE/DELETE e sem grant, só o
 *      trigger SECURITY DEFINER escreve.
 *   4. **Cobertura.** Toda candidatura tem ao menos uma linha; zero é o piso e só pode subir.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
const MIG = '20260817234948_1834_historico_de_status_da_candidatura.sql';
const SQL = existsSync(join(MIGRATIONS_DIR, MIG))
  ? readFileSync(join(MIGRATIONS_DIR, MIG), 'utf8')
  : '';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const semDb = !SUPABASE_URL || !SERVICE_KEY;

const auth = () => ({ apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` });

describe('#1834 A — camada estática (a migration diz o que precisa dizer)', () => {
  it('a migration existe no timestamp canônico', () => {
    assert.ok(SQL.length > 0, `${MIG} não encontrada — apply_migration cria o timestamp e o arquivo local usa ELE`);
  });

  it('o trigger cobre INSERT e UPDATE, por linha, DEPOIS do fato', () => {
    assert.match(
      SQL,
      /CREATE TRIGGER trg_record_application_status_change\s+AFTER INSERT OR UPDATE ON public\.selection_applications\s+FOR EACH ROW/,
      'o trigger precisa ser AFTER INSERT OR UPDATE ... FOR EACH ROW em selection_applications',
    );
  });

  it('UPDATE que não mexe no status NÃO vira linha (guarda de no-op)', () => {
    assert.match(
      SQL,
      /IF TG_OP = 'UPDATE' AND OLD\.status IS NOT DISTINCT FROM NEW\.status THEN\s+RETURN NEW;/,
      'sem a guarda, qualquer escrita na candidatura viraria "transição" e o histórico mentiria',
    );
  });

  it('changed_at é obrigatório no trigger e PROIBIDO na base semeada', () => {
    assert.match(
      SQL,
      /CHECK \(\(source = 'trigger'\s+AND changed_at IS NOT NULL\)\s+OR \(source = 'baseline_seed' AND changed_at IS NULL\)\)/,
      'a honestidade do carimbo tem de ser imposta pelo banco, não por convenção',
    );
    // e a semeadura precisa de fato gravar NULL, não now()
    assert.doesNotMatch(
      SQL,
      /'seed', NULL, a\.status, (now\(\)|a\.updated_at)/,
      'semear com now() ou updated_at inventaria a data da decisão — é o defeito que originou a issue',
    );
  });

  it('a semeadura é idempotente (rodar de novo não duplica)', () => {
    assert.match(SQL, /NOT EXISTS \(\s*SELECT 1 FROM public\.selection_application_status_history h\s+WHERE h\.application_id = a\.id/);
  });

  it('só o trigger escreve: RLS ligada, nenhuma policy de escrita, sem grant de escrita', () => {
    assert.match(SQL, /ALTER TABLE public\.selection_application_status_history ENABLE ROW LEVEL SECURITY/);
    assert.match(SQL, /REVOKE ALL ON public\.selection_application_status_history FROM PUBLIC, anon, authenticated/);
    assert.match(SQL, /GRANT SELECT ON public\.selection_application_status_history TO authenticated/);
    assert.doesNotMatch(
      SQL,
      /CREATE POLICY[^;]*FOR (INSERT|UPDATE|DELETE|ALL)[^;]*selection_application_status_history/i,
      'uma policy de escrita abriria um segundo caminho e o histórico deixaria de ser fiel',
    );
  });

  it('a função de trigger não fica alcançável por PUBLIC nem anon', () => {
    assert.match(
      SQL,
      /REVOKE ALL ON FUNCTION public\._trg_record_application_status_change\(\) FROM PUBLIC, anon, authenticated/,
      'CREATE FUNCTION concede EXECUTE a PUBLIC; trigger não precisa de grant para disparar',
    );
  });

  it('as duas colunas de status nascem com domínio declarado, e igual ao da candidatura', () => {
    const domCandidatura = readdirSync(MIGRATIONS_DIR)
      .filter((f) => f.endsWith('.sql'))
      .map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'))
      .join('\n')
      .match(/CONSTRAINT selection_applications_status_check[\s\S]{0,900}?\)\)/);

    const valores = (s) => new Set((s.match(/'([a-z_]+)'::text/g) || []).map((x) => x.slice(1, -7)));

    const meuTo = SQL.match(/CONSTRAINT sash_to_status_check[\s\S]*?\]\)\)/);
    const meuFrom = SQL.match(/CONSTRAINT sash_from_status_check[\s\S]*?\]\)\)/);
    assert.ok(meuTo && meuFrom, 'os dois CHECK de status precisam existir');

    const setTo = valores(meuTo[0]);
    const setFrom = valores(meuFrom[0]);
    assert.deepEqual([...setTo].sort(), [...setFrom].sort(), 'from_status e to_status têm de aceitar o MESMO domínio');
    assert.ok(setTo.size >= 15, `dominio de status pequeno demais (${setTo.size}) — provavelmente truncado`);

    if (domCandidatura) {
      const setApp = valores(domCandidatura[0]);
      const faltando = [...setApp].filter((v) => !setTo.has(v));
      assert.deepEqual(faltando, [], `o histórico rejeitaria status que a candidatura aceita: ${faltando.join(', ')}`);
    }
  });
});

describe('#1834 B — camada DB-aware', { skip: semDb ? 'sem SUPABASE_URL + SERVICE_ROLE_KEY' : false }, () => {
  // Não há porta genérica de SQL para inspecionar pg_trigger daqui, e uma sonda que não
  // consegue falhar seria cobertura de mentira. A propriedade que importa é a de baixo: se o
  // trigger sumisse, candidatura nova ficaria sem linha de histórico e o ratchet acende.

  it('RATCHET — nenhuma candidatura sem linha de histórico (piso 0, só pode subir)', async () => {
    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/selection_applications?select=id,selection_application_status_history(id)`,
      { headers: auth() },
    );
    assert.equal(r.status, 200, `leitura falhou: HTTP ${r.status}`);
    const linhas = await r.json();
    assert.ok(Array.isArray(linhas) && linhas.length > 0, 'o guard precisa examinar linhas (senão está cego)');

    const semHistorico = linhas
      .filter((a) => !Array.isArray(a.selection_application_status_history) || a.selection_application_status_history.length === 0)
      .map((a) => a.id);

    assert.deepEqual(
      semHistorico,
      [],
      `${semHistorico.length} de ${linhas.length} candidaturas sem histórico de status — ` +
        'ou o trigger não disparou, ou a semeadura não alcançou a linha',
    );
  });

  it('toda linha semeada tem changed_at NULO, e toda linha de trigger tem carimbo', async () => {
    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/selection_application_status_history?select=source,changed_at`,
      { headers: auth() },
    );
    assert.equal(r.status, 200, `leitura falhou: HTTP ${r.status}`);
    const linhas = await r.json();
    assert.ok(linhas.length > 0, 'histórico vazio — o guard estaria cego');

    const erradas = linhas.filter(
      (l) =>
        (l.source === 'baseline_seed' && l.changed_at !== null) ||
        (l.source === 'trigger' && l.changed_at === null),
    );
    assert.equal(
      erradas.length,
      0,
      'linha semeada com carimbo inventado, ou linha de trigger sem carimbo: ' +
        `${erradas.length} de ${linhas.length}`,
    );
  });
});
