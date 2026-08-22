/**
 * Contract #1932 — o guard-do-guard: nenhum guard NOVO pode fixar uma migration vencida.
 *
 * CLASSE. Migration é história imutável. Um guard que fixa `supabase/migrations/<v>_*.sql` e
 * afirma propriedades sobre aquele texto prova "a propriedade valia na versão <v>". Quando uma
 * migration posterior redefine a mesma função, o arquivo fixado não muda e o guard segue VERDE
 * descrevendo um corpo que a produção não executa mais. **O modo de falha é não avisar:** se a
 * migration posterior tivesse AFROUXADO o portão, o guard teria ficado verde do mesmo jeito.
 *
 * INSTÂNCIA PROVADA. `568-consent-records-lgpd-read.test.mjs` afirma, com a mensagem "admin read
 * gated on view_pii", o portão `can_by_member(v_caller_id, 'view_pii')` de
 * `admin_list_member_consents`, lendo a migration de 05/08. A definição vigente (20260822120649)
 * usa `can_org_by_member`, que é o portão mais estrito. O guard nunca reprovou.
 *
 * GUARD. A dívida de hoje está congelada em `docs/audit/GUARD_PIN_STALENESS_BASELINE_1932.txt`.
 * Este teste reprova nos DOIS sentidos:
 *   - par (guard, função) novo fora da linha de base  → dívida nova, conserte o guard;
 *   - entrada da linha de base que já não está velha  → desculpa vencida, remova a linha.
 * O segundo sentido é o que faz a lista encolher em vez de virar depósito. É a mecânica de
 * allowlist validado do #1109 e do #938: nunca silenciar, sempre com denominador.
 *
 * ⚠️ PISO DE DENOMINADOR. As asserções finais existem porque a falha mais provável deste guard
 * não é ficar vermelho, é ficar VAZIO: basta a extração parar de casar (uma convenção de caminho
 * nova, um renomear de diretório) para o conjunto medido virar zero e o teste ficar verde para
 * sempre. `[] == []` é verde. Os pisos transformam esse esvaziamento em reprovação.
 *
 * NÃO diz que os 172 pares são 172 buracos. Diz que são 172 pontos sem contato com a definição
 * vigente; cada um só é buraco se a migration posterior mexeu justamente na propriedade afirmada.
 * Fixar continua certo para "esta migration entregou X"; é errado para afirmar invariante
 * corrente de segurança, LGPD ou autoridade.
 *
 * Offline (lê repo, não fala com banco). Refs #1932, #1910, #1931.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { scanStalePins, parseBaseline, pairKey } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const BASELINE_PATH = 'docs/audit/GUARD_PIN_STALENESS_BASELINE_1932.txt';

// Este arquivo cita caminhos de migration na documentação acima; se ele se varresse, entraria no
// próprio denominador.
const SELF = new Set(['tests/contracts/1932-guard-fixa-captura-vencida.test.mjs']);

const scan = scanStalePins(ROOT, SELF);
const baseline = parseBaseline(readFileSync(resolve(ROOT, BASELINE_PATH), 'utf8'));
const baselineSet = new Set(baseline);
const currentSet = new Set(scan.pairs.map((p) => pairKey(p.guard, p.fn)));

test('#1932: nenhum par (guard, função) NOVO fixa migration vencida', () => {
  const novos = scan.pairs.filter((p) => !baselineSet.has(pairKey(p.guard, p.fn)));

  const detalhe = novos
    .map((p) => `  ${p.guard}\n    afirma ${p.fn}, cuja definição mais nova está em ${p.newestFile}`)
    .join('\n');

  assert.equal(
    novos.length,
    0,
    `${novos.length} guard(s) passaram a afirmar sobre uma captura vencida:\n${detalhe}\n\n` +
      'Conserte o guard (leia a captura mais nova, ou afirme contra a definição vigente). ' +
      `Adicionar a linha em ${BASELINE_PATH} só é aceitável com justificativa escrita na PR: ` +
      'a lista existe para encolher.',
  );
});

test('#1932: a linha de base não guarda desculpa vencida', () => {
  const resolvidos = baseline.filter((k) => !currentSet.has(k));

  assert.equal(
    resolvidos.length,
    0,
    `${resolvidos.length} entrada(s) da linha de base já não estão desatualizadas — ` +
      `remova-as de ${BASELINE_PATH}:\n${resolvidos.map((k) => `  ${k}`).join('\n')}\n\n` +
      'Uma lista que só cresce mede o passado. Esta encolhe.',
  );
});

test('#1932: toda entrada da linha de base aponta para um guard que existe', () => {
  const guardsNoDisco = new Set(scan.pairs.map((p) => p.guard));
  // Um arquivo apagado some do scan e cairia no teste anterior como "resolvido", o que leria como
  // progresso. Separar as duas mensagens evita confundir guard consertado com guard removido.
  const orfas = baseline.filter((k) => {
    const guard = k.split('|')[0];
    if (guardsNoDisco.has(guard)) return false;
    try {
      readFileSync(resolve(ROOT, guard), 'utf8');
      return false;
    } catch {
      return true;
    }
  });

  assert.deepEqual(
    orfas,
    [],
    `linha de base cita guard(s) que não existem mais: ${orfas.join(', ')}. ` +
      'Se o guard foi removido de propósito, remova também a entrada.',
  );
});

test('#1932: o denominador não pode esvaziar (piso contra guard verde por vácuo)', () => {
  // Medidos em 22/08/2026: 294 arquivos fixam migration, 1701 migrations, 1269 funções no
  // catálogo. Os pisos ficam abaixo do medido com folga, para tolerarem remoção legítima sem
  // tolerarem colapso da extração.
  assert.ok(
    scan.filesPinning >= 200,
    `só ${scan.filesPinning} arquivos de teste fixam migration (piso 200). ` +
      'A extração provavelmente parou de casar; este guard estaria medindo o vazio.',
  );
  assert.ok(
    scan.migrationFileCount >= 1000,
    `só ${scan.migrationFileCount} migrations lidas (piso 1000) — diretório mudou de lugar?`,
  );
  assert.ok(
    scan.catalogSize >= 800,
    `só ${scan.catalogSize} funções no catálogo (piso 800) — o cabeçalho CREATE OR REPLACE ` +
      'deixou de casar?',
  );
});

test('#1932: a instância provada continua detectável (controle positivo)', () => {
  // Sem um controle positivo, os quatro testes acima passam tanto porque não há dívida nova
  // quanto porque o scanner deixou de achar qualquer coisa. Este ancora o guard num caso que
  // sabemos ser verdadeiro, e reprova se a detecção morrer.
  const alvo = pairKey(
    'tests/contracts/568-consent-records-lgpd-read.test.mjs',
    'admin_list_member_consents',
  );
  assert.ok(
    currentSet.has(alvo),
    'a instância provada do #1932 deixou de ser detectada. Ou o guard 568 foi corrigido ' +
      `(então remova a entrada de ${BASELINE_PATH} e este controle), ou o scanner quebrou.`,
  );
});
