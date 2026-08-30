// tests/contracts/1960-fronteira-de-nome-no-bloco-816.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1960: o bloco de reunioes/pautas/briefings do #816 cobre nome com PREFIXO, e nao engole `DATA_`.
 *
 * Medido em 29/08/2026, com `docs/` em 1031 arquivos:
 *
 *   docs/**\/ATA_*  docs/**\/PAUTA_*  docs/**\/BRIEFING_*  docs/**\/DEMO_SCRIPT_*
 *
 * cobriam **0** deles. O bloco existe desde o #816 e estava verde por vacuidade: a convencao da
 * casa prefixa data (`2026-08-07_ata_lideranca_...`) e as vezes projeto (`p269_briefing_...`), e
 * um padrao ancorado no INICIO do nome nunca alcanca isso. Tres arquivos que o bloco existe para
 * barrar (duas atas de lideranca e um briefing de planejamento) estavam untracked e sem padrao
 * nenhum, num repositorio PUBLICO, a um `git add -A` de virar commit.
 *
 * ⚠️ A CORRECAO OBVIA E ERRADA, E O ERRO E SILENCIOSO.
 * O reflexo e trocar por `docs/**\/*ATA_*`. **"DATA_" contem "ATA_".** Esse padrao passa a casar
 * seis arquivos que nada tem a ver com atas, cinco deles rastreados e publicos de proposito
 * (`docs/legal/`, `docs/specs/`, `docs/archive/`). O proprio bloco #816 avisa que `docs/legal/` e
 * a SSOT publica de compliance e "Do NOT add it here". `.gitignore` nao desrastreia o que ja esta
 * rastreado, entao o estrago imediato seria zero e ninguem perceberia; o custo apareceria depois,
 * quando a proxima adicao em `docs/legal/` sumisse em silencio.
 *
 * Por isso este teste tem as DUAS metades. O controle positivo prova que o padrao alcanca; o
 * negativo prova que ele nao alarga. Um sem o outro deixa passar exatamente um dos dois defeitos.
 *
 * Cross-ref: #816 (origem do bloco), #938 (guard do que ja esta rastreado, com baseline propria),
 * #1940 (os handoffs de docs/planning), e a memoria
 * `reference-check-ignore-nao-avalia-o-padrao-em-arquivo-rastreado`.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();

/**
 * Pergunta ao git, com a engine dele, se o caminho seria ignorado.
 *
 * `--no-index` e obrigatorio: sem ele o `check-ignore` responde sobre o RASTREIO em vez de avaliar
 * o PADRAO, e um arquivo ja rastreado responde "nao ignorado" mesmo casando a linha. Com ele o
 * caminho nem precisa existir em disco, que e o que permite os controles sinteticos abaixo.
 */
function ignorado(caminho) {
  try {
    execFileSync('git', ['check-ignore', '--no-index', '-q', caminho], { cwd: ROOT, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

test('#1960 controle do proprio teste: o harness distingue os dois lados', () => {
  // Sem isto, um `check-ignore` quebrado (flag errada, cwd errado) devolveria false para tudo e as
  // asserções negativas passariam por vácuo, enquanto as positivas falhariam por um motivo falso.
  assert.equal(ignorado('docs/drafts/p269_qualquer_coisa_inventada.txt'), true,
    'linha preexistente `docs/drafts/p269_*` deveria casar; o harness nao esta medindo nada');
  assert.equal(ignorado('src/pages/index.astro'), false,
    'um arquivo de codigo comum nao pode aparecer como ignorado');
});

test('#1960 CONTROLE POSITIVO: o token alcanca nome com prefixo de data e de projeto', () => {
  const devemCasar = [
    // os tres que estavam expostos em 29/08
    'docs/planning/2026-08-07_ata_lideranca_06ago_action_items_governanca.md',
    'docs/planning/2026-08-07_ata_lideranca_23jul_retroativa.md',
    'docs/planning/2026-08-12_BRIEFING_SESSAO_PLANEJAMENTO_ADMIN_SELECAO.md',
    // a forma antiga, sem prefixo, que ja funcionava e nao pode regredir
    'docs/planning/ATA_reuniao_lideranca.md',
    'docs/planning/PAUTA_comite.md',
    'docs/planning/BRIEFING_sessao.md',
    // as duas caixas, porque .gitignore e case-sensitive por padrao
    'docs/planning/2026-01-01_pauta_lideranca.md',
    'docs/planning/2026-01-01_ATA_lideranca.md',
    'docs/qualquer/subpasta/p999_briefing_reuniao_x.pdf',
    'docs/planning/2026-01-01_demo_script_da_plataforma.md',
  ];
  const escaparam = devemCasar.filter((f) => !ignorado(f));
  assert.deepEqual(escaparam, [],
    'estes sao exatamente a classe que o bloco #816 existe para barrar, e o padrao nao os alcanca');
});

test('#1960 CONTROLE NEGATIVO: "DATA_" contem "ATA_", e nao pode ser engolido', () => {
  const naoPodemCasar = [
    // rastreados e publicos de proposito: um `*ATA_*` ingenuo pegaria todos
    'docs/archive/DATA_SANITATION_LOG.md',
    'docs/archive/HARDCODED_DATA_AUDIT.md',
    'docs/legal/641_MANUAL_R3_DATA_PROTECTION_ANNEX_DRAFT.md',
    'docs/legal/INSTITUTIONAL_EXPORT_DATA_DICTIONARY.md',
    'docs/specs/DATA_COLLECTION_GOVERNANCE.md',
    // a SSOT publica de compliance, que o comentario do bloco manda NAO adicionar
    'docs/legal/ROPA.md',
    'docs/legal/638_PI_EXCLUSION_RUNBOOK.md',
    // um documento comum de planejamento nao pode ser confundido com ata
    'docs/planning/2026-08-04_handoff_auditoria_modulo_admin.md',
    'docs/reference/V4_AUTHORITY_MODEL.md',
  ];
  const bloqueados = naoPodemCasar.filter((f) => ignorado(f));
  assert.deepEqual(bloqueados, [],
    'o padrao alargou e passou a esconder documento publico; `docs/legal/` e SSOT de compliance '
    + 'sob contract test proprio, e o bloco #816 diz explicitamente para nao adiciona-lo aqui');
});

test('#1960: o bloco declara por que nao pode ser "simplificado"', () => {
  // O padrao correto parece redundante para quem chega depois, e a "limpeza" obvia (`*ATA_*`)
  // reintroduz o defeito sem quebrar nada visivel. A defesa e o teste acima, e o aviso e o que
  // faz alguem procurar o teste antes de mexer.
  const gi = readFileSync(resolve(ROOT, '.gitignore'), 'utf8');
  assert.match(gi, /DATA_.*CONTAINS.*ATA_/i,
    'o .gitignore precisa dizer por que `*ATA_*` esta proibido, onde quem for editar vai ler');
  assert.match(gi, /1960/, 'o bloco precisa apontar para a issue que mediu o buraco');
});
