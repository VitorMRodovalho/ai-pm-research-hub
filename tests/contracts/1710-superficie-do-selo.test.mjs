/**
 * Contract: #1710 (superficie) — o selo ganha tela, e a tela diz o NUMERO antes de executar.
 *
 * `seal_event_attendance` grava `present=false` para todo elegivel sem registro. Medido em
 * 13/08/2026: 55 eventos alcancaveis, 111 faltas sobre 44 pessoas, a pior individual com 9. Uma
 * confirmacao generica ("tem certeza?") diante disso e decorativa — o que informa a decisao e
 * quantas linhas serao gravadas, e esse numero tem de vir do MESMO dry-run que o servidor usa.
 *
 * Tres invariantes de desenho, e cada um existe por um defeito concreto:
 *
 * 1. UMA confirmacao, dois pontos de entrada. O quadro de presenca do evento leva ao painel em vez
 *    de abrir uma segunda confirmacao. Duas confirmacoes calculando o numero de jeitos diferentes e
 *    a forma como a UI e o banco divergem sem ninguem perceber.
 *
 * 2. O painel NAO calcula elegibilidade. Ele renderiza `preview_seal_attendance`, que carrega a
 *    mesma coorte e o mesmo gate por recurso do ato. Um painel com regra propria promete o que a
 *    escrita nao cumpre — foi o que o #1722 teve de reconciliar entre a grade e o selo.
 *
 * 3. A grade nomeia o selo. Ela ja decidia entre 'unrecorded' e 'absent' por `roster_sealed_at` e
 *    nunca o mostrava: a tela exibia a consequencia do ato sem dizer que o ato existe.
 *
 * Camada unica (A) sobre o fonte: nao ha aqui o que uma camada viva alcance sem sessao de um
 * portador de `manage_event`. O que e verificavel ao vivo (gate por recurso, ensaio == ato,
 * reversao exata) esta em `1710-selo-escopado-e-reversao.test.mjs`.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAINEL = resolve(ROOT, 'src/components/attendance/SealPanel.tsx');
const PAGINA = resolve(ROOT, 'src/pages/attendance.astro');
const MODAL = resolve(ROOT, 'src/components/attendance/RosterModal.astro');
const GRADE = resolve(ROOT, 'src/components/attendance/AttendanceGridTab.tsx');
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];

/** Sem comentarios: este fonte EXPLICA, em prosa, os predicados que o teste procura e os que ele
 *  proibe. Um guard sobre o texto cru casaria a propria justificativa (#1586b). */
const semComentario = (s) => s
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/^\s*\/\/[^\n]*$/gm, '')
  .replace(/\{\/\*[\s\S]*?\*\/\}/g, '');

function ler(caminho) {
  assert.ok(existsSync(caminho), `arquivo ausente: ${caminho}`);
  return semComentario(readFileSync(caminho, 'utf8'));
}

test('#1710 superficie: o painel renderiza o DRY-RUN, nao uma coorte propria', () => {
  const src = ler(PAINEL);

  assert.match(src, /rpc\('preview_seal_attendance'/,
    'o painel tem de ler o ensaio; qualquer outra fonte diverge do ato na primeira manutencao');
  // A INVERSA: o painel nao pode montar a coorte por conta propria. Se ele consultar membros e
  // presencas para decidir quem "vai virar falta", passa a existir uma segunda definicao de
  // elegibilidade — exatamente a divergencia que o #1722 gastou uma sessao reconciliando.
  assert.doesNotMatch(src, /from\('members'\)|from\('attendance'\)|v_member_operational_tiers/,
    'o painel montou coorte propria em vez de usar preview_seal_attendance');
});

test('#1710 superficie: a confirmacao carrega o numero de faltas do proprio evento', () => {
  const src = ler(PAINEL);

  // O CTA precisa dizer quantas linhas serao gravadas. "Confirmar" sozinho nao informa decisao
  // nenhuma sobre uma escrita em massa irreversivel pela RPC.
  assert.match(src, /confirmSealCta[\s\S]{0,200}would_write_absent_n/,
    'o botao de confirmacao nao interpola would_write_absent_n');
  assert.match(src, /confirmSealBody[\s\S]{0,400}would_write_absent_n/,
    'o corpo da confirmacao nao diz quantas faltas serao gravadas');
  // E a confirmacao existe: um caminho que chame a RPC direto do botao da tabela nao passa por ela.
  assert.doesNotMatch(src, /onClick=\{\(\)\s*=>\s*[^}]*rpc\('seal_event_attendance'/,
    'ha um caminho que sela sem passar pela confirmacao');
});

test('#1710 superficie: o quadro do evento NAO tem uma segunda confirmacao', () => {
  const pagina = ler(PAGINA);
  const modal = ler(MODAL);

  assert.match(modal, /data-action="seal-from-roster"/,
    'o quadro de presenca do evento precisa oferecer o ato onde a lista e conferida');

  const i = pagina.indexOf("case 'seal-from-roster'");
  assert.ok(i > -1, 'a pagina nao trata a acao do quadro de presenca');
  const bloco = pagina.slice(i, i + 700);
  assert.match(bloco, /seal:focus/,
    'o quadro tem de delegar ao painel, que e quem conhece o numero');
  // A INVERSA, que e o defeito a evitar: selar direto daqui criaria uma segunda confirmacao (ou
  // nenhuma) e um segundo lugar onde o numero e calculado.
  assert.doesNotMatch(bloco, /seal_event_attendance|unseal_event_attendance/,
    'o quadro de presenca chama a RPC de selo direto, sem a confirmacao que diz o numero');

  const painel = ler(PAINEL);
  assert.match(painel, /addEventListener\('seal:focus'/,
    'o painel nao escuta o foco vindo do quadro de presenca');
});

test('#1710 superficie: a aba de selagem nasce ESCONDIDA e so aparece com autoridade', () => {
  const pagina = ler(PAGINA);

  const i = pagina.indexOf('id="tab-seal-btn"');
  assert.ok(i > -1, 'a aba de selagem nao existe');
  const abertura = pagina.lastIndexOf('<button', i);
  assert.match(pagina.slice(abertura, i), /class="hidden /,
    'a aba de selagem nao nasce escondida: todo mundo veria o ato oferecido');

  // E o unico lugar que a revela e o ramo de autoridade, o mesmo que revela criar evento.
  const j = pagina.indexOf("getElementById('tab-seal-btn')?.classList.remove('hidden')");
  assert.ok(j > -1, 'nada revela a aba de selagem');
  const contexto = pagina.slice(Math.max(0, j - 400), j);
  assert.match(contexto, /if \(CAN_MANAGE\)/,
    'a aba de selagem e revelada fora do ramo de autoridade');
});

test('#1710 superficie: a grade mostra o cadeado a partir de roster_sealed_at', () => {
  const grade = ler(GRADE);

  assert.match(grade, /roster_sealed_at: string \| null;/,
    'GridEvent nao carrega o carimbo que a RPC agora publica');
  assert.match(grade, /ev\.roster_sealed_at/,
    'a grade nao le o carimbo para marcar o evento selado');
  // Controle: marcar o cadeado sem manter a leitura que decide a celula deixaria o icone
  // enfeitando uma grade que voltou a acusar por ausencia (#1657).
  assert.match(grade, /gridSealed|gridUnsealed/,
    'o titulo da coluna nao explica o que o cadeado muda na leitura da celula');
});

test('#1710 superficie: as chaves de i18n existem nos TRES dicionarios', () => {
  const conjuntos = DICTS.map((d) => {
    const bruto = readFileSync(resolve(ROOT, d), 'utf8');
    return new Set(bruto.match(/'comp\.attendance\.seal\.[a-zA-Z.]+'/g) || []);
  });
  const base = [...conjuntos[0]];
  assert.ok(base.length >= 30, `pt-BR tem apenas ${base.length} chaves de selagem`);
  for (let i = 1; i < conjuntos.length; i++) {
    const faltando = base.filter((k) => !conjuntos[i].has(k));
    assert.deepEqual(faltando, [], `${DICTS[i]} nao tem: ${faltando.join(', ')}`);
  }

  // E as chaves usadas SEM fallback (as do Astro, via t(key, lang)) tem de existir: ali uma chave
  // ausente renderiza o proprio nome na tela.
  for (const arquivo of [PAGINA, MODAL]) {
    const usadas = readFileSync(arquivo, 'utf8').match(/t\('(comp\.attendance\.seal\.[a-zA-Z.]+)', lang\)/g) || [];
    for (const uso of usadas) {
      const chave = "'" + uso.match(/'(comp\.attendance\.seal\.[a-zA-Z.]+)'/)[1] + "'";
      assert.ok(conjuntos[0].has(chave), `${arquivo}: ${chave} nao existe em pt-BR`);
    }
  }
});
