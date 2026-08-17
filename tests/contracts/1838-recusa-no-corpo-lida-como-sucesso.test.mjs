/**
 * #1838 — recusa no CORPO com HTTP 200 lida como sucesso pela tela.
 *
 * Contexto medido em 17/08/2026: um avaliador do comitê (tem `view_pii`, não tem
 * `manage_platform` nem `manage_member`) chamou `update_application_contact`. A RPC
 * devolveu `{"error":"Unauthorized"}` com **HTTP 200**, o handler destruturava só o
 * `error` de transporte (nulo, porque a requisição foi bem-sucedida), e a tela mostrou
 * "Contato atualizado", fechou o modal e recarregou — **sem ter gravado nada**.
 *
 * Havia 4 pontos cegos no mesmo arquivo, não 1: `update_application_contact`,
 * `manage_selection_committee` (remover do comitê) e DUAS varreduras em lote de
 * `admin_update_application`, onde a linha recusada entrava no contador de SUCESSO.
 *
 * Este guard é o irmão do de #1594 (que cobre a convenção `success:false`) para a
 * convenção `{'error': ...}`. Duas camadas:
 *
 *   A — a classe é DERIVADA das capturas de migration (não de lista de nomes na mão):
 *       função cujo corpo mais recente tem um `RETURN ..._build_object('error', ...)`.
 *       Todo ponto de chamada dela na tela precisa ler `data.error`.
 *
 *   B — nenhum ponto novo pode destruturar SÓ `{ error }`, salvo os que recusam
 *       exclusivamente por `RAISE` (chegam como HTTP 400 e o `error` de transporte
 *       pega). Esses ficam num allowlist explícito, hoje de tamanho 1, e cada entrada
 *       é conferida contra a captura: se a função passar a recusar no corpo, a
 *       justificativa cai junto.
 *
 * Limite conhecido e declarado: o predicado de A vê a recusa DIRETA
 * (`RETURN ..._build_object('error', ...)`). Uma que monte o objeto numa variável e
 * devolva a variável escapa. B é o que cobre esse flanco, porque não olha a semântica
 * da RPC e sim a forma do handler.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseMigration } from '../helpers/rpc-body-drift-parser.mjs';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
const ADMIN_PATH = 'src/pages/admin/selection.astro';
const ADMIN_SRC = existsSync(ADMIN_PATH) ? readFileSync(ADMIN_PATH, 'utf8') : '';

/** Recusa DIRETA no corpo: um RETURN cujo statement carrega a chave 'error'. */
const BODY_REFUSAL_RE = /\bRETURN\s[^;]*'error'/i;

/**
 * A classe é de ESCRITA. O defeito do #1838 é a tela confirmar uma GRAVAÇÃO que não
 * aconteceu; uma RPC de leitura que recusa no corpo degrada para painel vazio, que é
 * outro defeito (mais brando) e não deve andar de carona neste guard, senão ele fica
 * ruidoso e alguém o enfraquece depois.
 */
const WRITES_RE = /\b(INSERT\s+INTO|UPDATE\s+[a-z_."]+\s+SET|DELETE\s+FROM)\b/i;

/**
 * Leitura da recusa no corpo. Aceita QUALQUER identificador, não o literal `data`:
 * os handlers renomeiam no destructure (`const { data: dashboard }`) e um regex preso
 * em `data.error` acusa código correto — foi o que aconteceu ao escrever este guard.
 */
const READS_BODY_ERROR_RE = /\b[A-Za-z_$][\w$]*\s*\??\.\s*error\b/;

/** Último corpo capturado por nome de função (arquivo mais recente vence). */
function latestBodiesByName() {
  const byName = new Map();
  for (const f of readdirSync(MIGRATIONS_DIR).filter((x) => x.endsWith('.sql')).sort()) {
    for (const b of parseMigration(f, readFileSync(join(MIGRATIONS_DIR, f), 'utf8'))) {
      byName.set(b.name, { body: b.body, file: f });
    }
  }
  return byName;
}

/**
 * Todo ponto de chamada de `sb.rpc(...)` na tela, com o trecho que vai da chamada até
 * a chamada SEGUINTE. O corte na chamada seguinte é essencial: uma janela de N linhas
 * fixas empresta a checagem do handler vizinho e o guard fica verde por acidente.
 */
function callSites(src) {
  const re = /sb\.rpc\(\s*'([a-z_][a-z0-9_]*)'/g;
  const hits = [];
  let m;
  while ((m = re.exec(src)) !== null) hits.push({ name: m[1], start: m.index });
  return hits.map((h, i) => ({
    name: h.name,
    line: src.slice(0, h.start).split('\n').length,
    block: src.slice(h.start, i + 1 < hits.length ? hits[i + 1].start : src.length),
    // o que vem imediatamente ANTES da chamada, para ver a forma do destructure
    prefix: src.slice(Math.max(0, h.start - 60), h.start),
  }));
}

/** RPCs que recusam SÓ por RAISE, onde destruturar apenas `{ error }` está correto. */
const EXCEPTION_ONLY_ALLOWLIST = new Set(['submit_interview_scores']);

describe('#1838 — a tela não pode confirmar gravação que a RPC recusou', () => {
  it('a tela de seleção existe e tem pontos de chamada para examinar (senão o guard é cego)', () => {
    assert.ok(ADMIN_SRC.length > 0, `${ADMIN_PATH} não foi lido`);
    assert.ok(callSites(ADMIN_SRC).length > 0, 'nenhum sb.rpc() encontrado — parser quebrado');
  });

  it('A — todo handler de RPC de ESCRITA que recusa no CORPO lê o error do corpo', () => {
    const bodies = latestBodiesByName();
    const sites = callSites(ADMIN_SRC);

    // Devolve cada um dos examinados com um booleano: lista vazia não se distingue de cegueira.
    const examined = sites
      .filter((s) => {
        const cap = bodies.get(s.name);
        return cap && BODY_REFUSAL_RE.test(cap.body) && WRITES_RE.test(cap.body);
      })
      .map((s) => ({
        rpc: s.name,
        line: s.line,
        readsBodyError: READS_BODY_ERROR_RE.test(s.block),
      }));

    assert.ok(
      examined.length > 0,
      'nenhuma RPC da classe "recusa no corpo" foi encontrada nesta tela — ' +
        'o predicado ou a captura de migration mudou de forma; o guard estaria cego',
    );

    const blind = examined.filter((e) => !e.readsBodyError);
    assert.deepEqual(
      blind,
      [],
      `handler(s) confirmando gravação que a RPC pode ter recusado no corpo (HTTP 200):\n` +
        blind.map((b) => `  ${ADMIN_PATH}:${b.line} → ${b.rpc}`).join('\n') +
        `\n(examinados: ${examined.length})`,
    );
  });

  it('B — nenhum handler novo descarta o data, salvo quem recusa só por RAISE', () => {
    const sites = callSites(ADMIN_SRC);
    const discardsData = sites.filter((s) =>
      /const\s*\{\s*error\s*\}\s*=\s*await\s+$/.test(s.prefix),
    );

    // O allowlist só vale se ele estiver realmente sendo exercido; se a forma do
    // destructure mudar e NADA casar, este guard silencia sem avisar.
    assert.ok(
      discardsData.length > 0,
      'nenhum handler casou a forma "const { error } = await sb.rpc(" — ' +
        'o padrão mudou e este guard pararia de examinar qualquer coisa',
    );

    const unjustified = discardsData
      .filter((s) => !EXCEPTION_ONLY_ALLOWLIST.has(s.name))
      .map((s) => `${ADMIN_PATH}:${s.line} → ${s.name}`);

    assert.deepEqual(
      unjustified,
      [],
      'handler(s) destruturando só o error de transporte sem justificativa no allowlist:\n  ' +
        unjustified.join('\n  '),
    );
  });

  it('B — cada entrada do allowlist realmente recusa só por RAISE (senão a justificativa caiu)', () => {
    const bodies = latestBodiesByName();
    const stale = [];

    for (const name of EXCEPTION_ONLY_ALLOWLIST) {
      const cap = bodies.get(name);
      assert.ok(cap, `${name} está no allowlist e não tem captura em migration nenhuma`);
      if (BODY_REFUSAL_RE.test(cap.body)) stale.push(`${name} (captura: ${cap.file})`);
      assert.match(
        cap.body,
        /\bRAISE\s+EXCEPTION/i,
        `${name} está no allowlist como "recusa por RAISE" e não tem RAISE EXCEPTION`,
      );
    }

    assert.deepEqual(
      stale,
      [],
      'entrada(s) do allowlist passaram a recusar no CORPO — o handler correspondente ' +
        'precisa ler data.error e sair do allowlist:\n  ' + stale.join('\n  '),
    );
  });
});
