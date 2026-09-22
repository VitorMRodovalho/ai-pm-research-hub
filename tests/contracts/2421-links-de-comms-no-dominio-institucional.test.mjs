// tests/contracts/2421-links-de-comms-no-dominio-institucional.test.mjs
// Registrar em "test:structural" + "test:contracts" (#1109). Este arquivo so LE arquivo,
// nao toca o banco, entao pertence a faixa estrutural (o inverso do que o #1908 exige).
/**
 * O link que chega numa pessoa aponta para o dominio INSTITUCIONAL.
 *
 * O CASO (#2421): todo e-mail sai com remetente `Nucleo IA e GP <nucleoia@pmigo.org.br>` e, ate
 * 22/09/2026, com links em `nucleoia.vitormr.dev` — o dominio pessoal do dono. Envelope de uma
 * instituicao, botao para outro lugar.
 *
 * POR QUE NAO FOI PEGO ANTES: `src/lib/canonical.ts` e o SSOT do host e TEM catraca
 * (`canonical-host-centralization.test.mjs`), mas ela varre **`src/`**. Medido em 22/09: 1 arquivo
 * em `src/` (o proprio SSOT) contra **11 em `supabase/functions/`**. O guard estava verde e nao lia
 * a superficie que chega na pessoa. O cabecalho do `canonical.ts` ate registra a pendencia, e a
 * chama de *"follow-up, not a blocker"* — o que era verdade enquanto todo destinatario era membro
 * interno, e deixou de ser quando o primeiro convite EXTERNO passou a sair por estes templates.
 *
 * DUAS ASSERCOES, porque consertar so uma produz o defeito do outro lado:
 *   1. o `href` aponta para o dominio institucional;
 *   2. o TEXTO VISIVEL da ancora nao pode nomear outro host que o destino. Isto nao e purismo:
 *      na primeira versao deste conserto o `href` virou pmigo e o rotulo continuou dizendo
 *      `nucleoia.vitormr.dev` nos mesmos dois links, e um rotulo que discorda do destino le como
 *      phishing. Arrumar o efeito e deixar o conteudo e a mesma familia de defeito, espelhada.
 *
 * EXCECOES SAO DADO, NAO PROSA. Cada uma carrega o motivo; uma excecao nova tem de ser ESCRITA
 * aqui, e nao simplesmente passar despercebida.
 *
 * Cross-ref: #2421, `src/lib/canonical.ts`, `supabase/functions/_shared/comms-host.ts`,
 *            diretriz do dono de 2026-07-03.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join, relative } from 'node:path';

const ROOT = process.cwd();
const EF_DIR = resolve(ROOT, 'supabase/functions');
const HOST_CANONICO = 'nucleoia.vitormr.dev';
const HOST_COMMS = 'nucleoia.pmigo.org.br';

/**
 * Onde o host canonico PODE aparecer, e por que. Trocar qualquer um destes por
 * `COMMS_ORIGIN` seria um defeito, nao uma melhoria.
 */
const EXCECOES = [
  {
    arquivo: 'supabase/functions/_shared/comms-host.ts',
    motivo: 'e o proprio SSOT: declara PLATFORM_ORIGIN, que precisa do literal.',
  },
  {
    arquivo: 'supabase/functions/pmi-video-init-upload/index.ts',
    motivo:
      'ALLOWED_ORIGIN de CORS. O header `Origin` que o navegador manda carrega o host CANONICO, ' +
      'nunca o alias com 301 — trocar quebraria o upload, e sem erro obvio.',
  },
  {
    arquivo: 'supabase/functions/pmi-video-finalize-upload/index.ts',
    motivo: 'ALLOWED_ORIGIN de CORS, mesmo motivo do init-upload.',
  },
  {
    arquivo: 'supabase/functions/sync-artia/index.ts',
    motivo: 'prosa em descricao de projeto no Artia (ferramenta interna). Texto, nao link clicavel.',
  },
  {
    arquivo: 'supabase/functions/nucleo-mcp/index.ts',
    motivo: 'prosa numa descricao de tool. Texto, nao link clicavel.',
  },
];
const ISENTOS = new Set(EXCECOES.map((e) => e.arquivo));

function arquivosEF() {
  const out = [];
  (function anda(dir) {
    for (const nome of readdirSync(dir)) {
      const p = join(dir, nome);
      if (statSync(p).isDirectory()) anda(p);
      else if (p.endsWith('.ts')) out.push(p);
    }
  })(EF_DIR);
  return out;
}

/**
 * Violacoes. Lista vazia = saudavel.
 *
 * Recebe `[{caminho, corpo}]` como dado puro, de proposito: e a MESMA funcao que julga os arquivos
 * reais e os adulterados do teste de mutacao. Mutacao que nao passa pelo avaliador e parafrase.
 */
export function violacoes(arquivos) {
  const v = [];
  for (const { caminho, corpo } of arquivos) {
    if (!ISENTOS.has(caminho) && corpo.includes(HOST_CANONICO)) {
      v.push(
        `${caminho} crava "${HOST_CANONICO}". Link que chega numa pessoa usa ${HOST_COMMS} ` +
        `(COMMS_ORIGIN de _shared/comms-host.ts). Se for CORS, OAuth ou comparacao exata, ` +
        `use PLATFORM_ORIGIN e declare a excecao em EXCECOES, com o motivo (#2421).`,
      );
    }
    // O rotulo visivel da ancora nao pode nomear um host diferente do destino.
    for (const m of corpo.matchAll(/<a\b[^>]*href="([^"]*)"[^>]*>\s*(nucleoia[^<\s]*)\s*<\/a>/gi)) {
      const [, destino, rotulo] = m;
      const hostDoDestino = destino.includes(HOST_COMMS) ? HOST_COMMS
        : destino.includes(HOST_CANONICO) ? HOST_CANONICO
        : destino.includes('COMMS_ORIGIN') ? HOST_COMMS
        : destino.includes('PLATFORM_ORIGIN') ? HOST_CANONICO : null;
      if (hostDoDestino && rotulo.replace(/\/$/, '') !== hostDoDestino) {
        v.push(
          `${caminho}: o texto visivel do link diz "${rotulo}" e o destino e ${hostDoDestino}. ` +
          `Rotulo que discorda do destino le como phishing (#2421).`,
        );
      }
    }
  }
  return v;
}

test('#2421 — nenhuma Edge Function crava o host canonico fora das excecoes declaradas', () => {
  const arquivos = arquivosEF().map((p) => ({
    caminho: relative(ROOT, p),
    corpo: readFileSync(p, 'utf8'),
  }));

  // Controle positivo: a varredura precisa estar vendo EFs de verdade. Com a lista vazia
  // (diretorio movido, extensao trocada) a lista de violacoes tambem sai vazia, e o verde
  // seria por vacuidade — que e exatamente como este defeito sobreviveu em `src/`.
  assert.ok(arquivos.length >= 40,
    `controle positivo: a varredura achou so ${arquivos.length} arquivos .ts sob supabase/functions`);
  assert.ok(arquivos.some((a) => a.corpo.includes('COMMS_ORIGIN')),
    'controle positivo: nenhuma EF importa COMMS_ORIGIN — o conserto sumiu inteiro');

  assert.deepEqual(violacoes(arquivos), []);
});

test('#2421 — toda excecao declarada existe e ainda contem o literal que ela justifica', () => {
  // Excecao que sobrevive ao arquivo que a motivou vira licenca silenciosa: o dia em que alguem
  // recriar aquele arquivo, ele ja nasce isento sem ninguem decidir isso.
  for (const { arquivo, motivo } of EXCECOES) {
    const corpo = readFileSync(resolve(ROOT, arquivo), 'utf8');
    assert.ok(corpo.includes(HOST_CANONICO),
      `${arquivo} nao contem mais "${HOST_CANONICO}": tire a excecao de EXCECOES (#2421)`);
    assert.ok(motivo.length > 30, `a excecao de ${arquivo} precisa de um motivo escrito`);
  }
});

test('#2421 mutacao — o detector reprova cada defeito, pela MESMA funcao', () => {
  const SAUDAVEL = [{
    caminho: 'supabase/functions/send-x/index.ts',
    corpo: 'const h = `${COMMS_ORIGIN}/profile`\n' +
           '// <a href="${COMMS_ORIGIN}/workspace">nucleoia.pmigo.org.br</a>',
  }];
  assert.deepEqual(violacoes(SAUDAVEL), [], 'controle sem mutacao: o corpo correto nao viola');

  // Mutacao 1 — o estado EXATO de antes do conserto: host cravado numa EF nao isenta.
  const cravado = [{ caminho: 'supabase/functions/send-x/index.ts', corpo: `const h = 'https://${HOST_CANONICO}/profile'` }];
  assert.notEqual(cravado[0].corpo, SAUDAVEL[0].corpo, 'a mutacao 1 precisa ter MUDADO o corpo');
  assert.match(violacoes(cravado).join(' | '), /crava "nucleoia\.vitormr\.dev"/,
    'mutacao 1: o detector tem de achar o host cravado');

  // Mutacao 2 — o href certo e o ROTULO errado, que foi o defeito real desta PR.
  const rotuloErrado = [{
    caminho: 'supabase/functions/send-x/index.ts',
    corpo: '<a href="${COMMS_ORIGIN}/workspace">nucleoia.vitormr.dev</a>',
  }];
  assert.match(violacoes(rotuloErrado).join(' | '), /discorda do destino/,
    'mutacao 2: rotulo que nomeia outro host tem de reprovar');

  // Mutacao 3 — o inverso: destino canonico e rotulo institucional. Tambem discorda.
  const inverso = [{
    caminho: 'supabase/functions/send-x/index.ts',
    corpo: '<a href="${PLATFORM_ORIGIN}/workspace">nucleoia.pmigo.org.br</a>',
  }];
  assert.match(violacoes(inverso).join(' | '), /discorda do destino/,
    'mutacao 3: o detector nao pode enxergar so um sentido');

  // Mutacao 4 — isencao NAO pode ser por nome parecido: um caminho vizinho nao herda a excecao.
  const vizinho = [{ caminho: 'supabase/functions/sync-artia/helper.ts', corpo: `x = '${HOST_CANONICO}'` }];
  assert.match(violacoes(vizinho).join(' | '), /crava "nucleoia\.vitormr\.dev"/,
    'mutacao 4: a isencao e por caminho EXATO, nunca por prefixo');
});
