// tests/contracts/2970-indice-da-vigilia-no-audit-log.test.mjs
/**
 * #2970: a vigília de efeito da varredura de alertas tem índice que entrega as últimas N linhas por action.
 *
 * _alert_sweep_cron, para cada linha de cron_vitality_watch, lê em admin_audit_log a última linha da action e as
 * últimas max_silent_runs linhas dela (WHERE action = ... ORDER BY created_at DESC LIMIT n). Com índice só em
 * (action) e só em (created_at), o banco trazia todas as linhas da action para ordenar e ficar com n.
 *
 * O guard afirma, sobre o diretório de migrations e o corpo mais novo da função:
 *   1. o último evento sobre idx_audit_log_action_created é a criação (nenhuma migration posterior o apaga);
 *   2. a criação é em public.admin_audit_log, não UNIQUE e sem WHERE (parcial não serviria a toda action);
 *   3. as colunas do índice são as da leitura: a coluna do filtro da vigília primeiro, depois a da ordenação, na
 *      mesma direção. As duas vêm da leitura, não de uma lista escrita aqui: se a função mudar o filtro ou a
 *      ordem, o guard reprova e diz que o índice deixou de servir.
 *
 * O efeito no banco (o plano usar o índice) não é medido aqui: não há RPC que leia o catálogo de índices. A prova
 * viva é o EXPLAIN da verificação do apply.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { maskLineComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = join(ROOT, 'supabase/migrations');
const NOME = 'idx_audit_log_action_created';

const espaco = (s) => s.replace(/\s+/g, ' ').trim();

/** Criações e remoções do índice, na ordem de versão e de posição no arquivo. */
export function historicoDoIndice(dir = DIR) {
  const cria = new RegExp(
    `CREATE\\s+(UNIQUE\\s+)?INDEX\\s+(?:CONCURRENTLY\\s+)?(?:IF\\s+NOT\\s+EXISTS\\s+)?(?:public\\.)?${NOME}\\s+` +
      `ON\\s+(?:ONLY\\s+)?([\\w."]+)\\s*(?:USING\\s+\\w+\\s*)?\\(([^)]*)\\)([^;]*);`,
    'gi',
  );
  const apaga = new RegExp(`DROP\\s+INDEX\\s+(?:CONCURRENTLY\\s+)?(?:IF\\s+EXISTS\\s+)?(?:public\\.)?${NOME}\\b`, 'gi');
  const eventos = [];
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(dir, file), 'utf8'));
    const doArquivo = [];
    for (const m of sql.matchAll(cria)) {
      doArquivo.push({
        pos: m.index, file, tipo: 'cria', unico: !!m[1], tabela: m[2].replace(/"/g, ''),
        colunas: m[3].split(',').map(espaco), resto: espaco(m[4]),
      });
    }
    for (const m of sql.matchAll(apaga)) doArquivo.push({ pos: m.index, file, tipo: 'apaga' });
    eventos.push(...doArquivo.sort((a, b) => a.pos - b.pos));
  }
  return eventos;
}

/** As leituras "últimas N da action" da vigília no corpo: coluna do filtro e coluna/direção da ordenação. */
export function leiturasDaVigilia(body) {
  const c = espaco(maskLineComments(body));
  const re = /FROM public\.admin_audit_log (?:\w+ )?WHERE (?:\w+\.)?(\w+) = v_w\.effect_action ORDER BY (?:\w+\.)?(\w+) (ASC|DESC) LIMIT v_w\.max_silent_runs/g;
  return [...c.matchAll(re)].map((m) => ({ filtro: m[1], ordem: m[2], direcao: m[3] }));
}

const HIST = historicoDoIndice();
const CRIACAO = HIST.filter((e) => e.tipo === 'cria').at(-1);
const SWEEP = latestFunctionCapture(ROOT, '_alert_sweep_cron');

test('o último evento sobre o índice é a criação: nenhuma migration posterior o apaga', () => {
  assert.ok(HIST.length > 0, `nenhuma migration cria ${NOME}`);
  const ultimo = HIST.at(-1);
  assert.equal(ultimo.tipo, 'cria', `${ultimo.file} apaga ${NOME} depois da criação`);
});

test('a criação é em public.admin_audit_log, não UNIQUE e sem WHERE', () => {
  assert.ok(CRIACAO, `nenhuma migration cria ${NOME}`);
  assert.equal(CRIACAO.tabela, 'public.admin_audit_log', `${CRIACAO.file}: o índice está em ${CRIACAO.tabela}`);
  assert.equal(CRIACAO.unico, false, `${CRIACAO.file}: índice UNIQUE recusaria duas linhas da mesma action no mesmo instante`);
  assert.doesNotMatch(CRIACAO.resto, /\bWHERE\b/i, `${CRIACAO.file}: índice parcial não serve a toda action da vigília`);
});

test('as colunas do índice são o filtro e a ordenação da leitura da vigília, na mesma direção', () => {
  assert.ok(CRIACAO, `nenhuma migration cria ${NOME}`);
  const leituras = leiturasDaVigilia(SWEEP.body);
  assert.ok(leituras.length > 0, `${SWEEP.file}: _alert_sweep_cron não lê mais "últimas N da action"; reveja se ${NOME} ainda serve`);
  for (const l of leituras) {
    assert.deepEqual(
      CRIACAO.colunas,
      [l.filtro, `${l.ordem} ${l.direcao}`],
      `${CRIACAO.file}: o índice é (${CRIACAO.colunas.join(', ')}), e a leitura em ${SWEEP.file} filtra por ${l.filtro} e ordena por ${l.ordem} ${l.direcao}`,
    );
  }
});

test('o leitor reconhece as duas formas de leitura e recusa as que o índice não serve', () => {
  const ok = 'SELECT changes FROM public.admin_audit_log WHERE action = v_w.effect_action ORDER BY created_at DESC LIMIT v_w.max_silent_runs';
  assert.deepEqual(leiturasDaVigilia(ok), [{ filtro: 'action', ordem: 'created_at', direcao: 'DESC' }]);
  const comAlias = 'SELECT a.changes FROM public.admin_audit_log a WHERE a.action = v_w.effect_action ORDER BY a.created_at ASC LIMIT v_w.max_silent_runs';
  assert.deepEqual(leiturasDaVigilia(comAlias), [{ filtro: 'action', ordem: 'created_at', direcao: 'ASC' }]);
  const comentada = '-- FROM public.admin_audit_log WHERE action = v_w.effect_action ORDER BY created_at DESC LIMIT v_w.max_silent_runs';
  assert.deepEqual(leiturasDaVigilia(comentada), []);
});
