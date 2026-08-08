// tests/contracts/pii-nenhum-dado-pessoal-versionado.test.mjs
//
// PII em repositorio PUBLICO: a barreira contra reincidencia.
//
// O ACHADO, medido em 08/08/2026. Este repo e publico, e a propria regra da casa diz "nenhum
// candidato ou membro nomeado, so contagens". Uma varredura de tudo o que esta versionado
// encontrou:
//
//   e-mails pessoais ......... 342 ocorrencias, 89 enderecos distintos, 52 arquivos
//   telefones reais .......... 52 ocorrencias (uma seed de ciclo inteira)
//   contato de seguranca ..... o SECURITY.md publicava um gmail pessoal, que e o endereco que um
//                              pesquisador usaria para reportar vulnerabilidade
//   assinaturas de termo ..... 92 voluntarios, 181 registros, 3 CPFs em Common Name de certificado
//                              digital, em `scripts/docusign-signers-extracted.json`
//
// A limpeza foi feita. Este arquivo existe porque limpeza sem barreira reacumula - e a lição que o
// #1437 ja tinha pago uma vez com dado de teste alcancavel.
//
// A REGRA E ALLOW-LIST, NAO DENY-LIST. Uma lista de dominios proibidos (gmail, hotmail, ...) deixa
// passar o proximo dominio que ninguem previu, e falha para o lado silencioso. Aqui, um endereco so
// pode existir em arquivo versionado se for (a) de dominio reservado por RFC 2606 / RFC 6761, ou
// (b) uma caixa de PAPEL explicitamente listada abaixo, com motivo. Endereco novo = decisao
// consciente de uma linha, que e exatamente o atrito que se quer.
//
// ⚠️ ESCOPO DECLARADO: este guard cobre e-mail e telefone. NOMES ficaram de fora de proposito - a
// varredura mediu 1.566 ocorrencias em 336 arquivos (160 deles migrations, 20 testes de contrato,
// 30 ADRs), e o banco continua com os nomes reais, entao varrer so o lado do repo quebra todo teste
// que compara os dois. Isso e trabalho dimensionado a parte, nao um item de checklist.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

/** Dominios reservados por RFC 2606 / RFC 6761: e-mail para eles nunca alcanca uma pessoa. */
export const DOMINIO_RESERVADO =
  /@(?:[^@]*\.)?(?:example\.(?:com|org|net)|test|invalid|localhost)$/i;

/**
 * Caixas de PAPEL e enderecos tecnicos que podem viver em arquivo versionado. Cada entrada e uma
 * decisao, nao um acidente. Ordenado por motivo.
 */
export const PERMITIDOS = new Set([
  // — contato institucional do Nucleo e dos capitulos —
  'nucleoia@pmigo.org.br',
  'contato@pmigo.org.br',
  'dpo@pmigo.org.br',
  'presidencia@pmiam.org', 'presidencia@pmiba.org.br', 'presidencia@pmice.org.br',
  'presidencia@pmies.org.br', 'presidencia@pmigo.org.br', 'presidencia@pmimg.org.br',
  'presidencia@pmipe.org.br', 'presidencia@pmirio.org.br', 'presidencia@pmirs.org.br',
  'presidencia@pmisc.org.br', 'presidencia@pmise.org.br', 'presidencia@pmisp.org.br',
  'noreply@nucleoia.org',
  // — contato do mantenedor, em dominio proprio (o SECURITY.md PRECISA de um endereco que
  //   funcione: um placeholder ali impediria alguem de reportar vulnerabilidade) —
  'vitor@vitormr.dev',
  // — remetentes automaticos e caixas de fornecedor —
  'donotreply@pmi.org', 'noreply@pmi.org',
  'security@supabase.io', 'onboarding@resend.dev', 'support@airmeet.com',
  'noreply@anthropic.com', 'noreply@openai.com', 'git@github.com',
  // — organizacoes parceiras, caixa de papel —
  'info@pmairevolution.com', 'contato@fernandalongato.com',
  // — placeholders de UI e de teste que nao estao em dominio reservado —
  'seu@email.com', 'you@email.com', 'tu@email.com', 'other@email.com', 'otro@email.com',
  'outro@email.com', 'voce@exemplo.com', 'tu@ejemplo.com', 'sua-conta@dominio.ics',
  'a@b.com', 'a@b.org', 'c@d.com', 'e@x.com', 'x@x.com', 'x@y.com', 'z@w.com', 'bad@host.com',
  // — marcadores de anonimizacao ja aplicada —
  'anon@removed.local', 'fbressiani@unknown.com', 'giovanni.brandao@historical.nucleo',
  // — id de evento do Google Calendar, que tem forma de e-mail —
  'bsb4n49e06al6cj95mdivgqkp8@google.com',
]);

/**
 * Isencao por ARQUIVO, sempre com motivo. Diferente de `PERMITIDOS`, que libera um endereco em
 * qualquer lugar, isto libera um arquivo inteiro - entao a lista tem de ser curta e cada entrada
 * tem de doer um pouco de escrever.
 */
/** Caminho deste proprio arquivo, relativo a raiz do repo. */
const ESTE_ARQUIVO = 'tests/contracts/pii-nenhum-dado-pessoal-versionado.test.mjs';

/**
 * As fixtures dos controles. Elas SAO enderecos de dominio pessoal - tem de ser, senao o controle
 * positivo nao controla nada - e por isso este arquivo se isenta da varredura. A isencao e segura
 * porque o teste logo abaixo afirma que os enderecos aqui dentro sao EXATAMENTE estes: esconder um
 * endereco real no arquivo do guard fica vermelho.
 */
const FIXTURES_DE_CONTROLE = new Set([
  'fulano.sobrenome@gmail.com',
  'fulano@hotmail.com',
  'alguem@outlook.com',
  'pessoa@yahoo.com.br',
  'alguem@umdominioqualquer.com.br',
]);

export const ARQUIVOS_ISENTOS = new Map([
  [
    ESTE_ARQUIVO,
    'O arquivo do proprio guard. Os controles precisam conter enderecos de dominio pessoal para ' +
      'terem dentes. A isencao e estreita: o teste "as fixtures de controle sao exatamente as ' +
      'declaradas" impede que um endereco real se esconda aqui.',
  ],
  [
    'public/legacy-assets/governance/Manual de Governança e Operações (Nucleo) - R2.pdf',
    'Documento de governanca PUBLICADO (R2). Os 3 enderecos sao da cadeia de governanca em ' +
      'capacidade institucional, e o PDF e um binario que nao da para editar por script sem ' +
      'arriscar corromper. Decisao do PM em 08/08/2026: isentar com motivo escrito, em vez de ' +
      'remover um documento que foi deliberadamente publicado. Se um R3 redigido for gerado, ' +
      'esta entrada sai.',
  ],
]);

const RE_EMAIL = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;

/**
 * Telefone brasileiro. So placeholder pode existir versionado: sequencia repetida (99999...),
 * sequencia crescente (91234-5678) ou o prefixo de redacao `+5500`.
 */
const RE_FONE = /\+55[\s.-]?\d{2}[\s.-]?9?\d{4}[\s.-]?\d{4}/g;
const FONE_PLACEHOLDER = [
  /^\+5500/,                       // prefixo de redacao usado no scrub
  /(\d)\1{6,}/,                    // 7+ digitos repetidos
  /1234[\s.-]?5678/,               // sequencia crescente
];

/** `true` se o endereco pode viver num arquivo versionado. */
export function emailPermitido(addr) {
  const a = addr.toLowerCase();
  return DOMINIO_RESERVADO.test(a) || PERMITIDOS.has(a);
}

/** `true` se o telefone e claramente sintetico. */
export function fonePermitido(fone) {
  const so = fone.replace(/[\s.-]/g, '');
  return FONE_PLACEHOLDER.some((re) => re.test(so) || re.test(fone));
}

/** Arquivos rastreados pelo git, que e exatamente o que vai para o GitHub. */
function arquivosVersionados() {
  return execFileSync('git', ['ls-files', '-z'], { maxBuffer: 64 * 1024 * 1024 })
    .toString('utf8')
    .split('\0')
    .filter(Boolean);
}

function ler(f) {
  try { return readFileSync(f, 'utf8'); } catch { return null; }   // binario/ausente
}

describe('PII — nenhum dado pessoal em arquivo versionado (repo PUBLICO)', () => {
  // ── controles: sem eles a regra abaixo pode passar por vacuidade ──────────
  it('CONTROLE POSITIVO — o predicado ACUSA endereco pessoal', () => {
    for (const ruim of [
      'fulano.sobrenome@gmail.com',
      'Fulano@Hotmail.com',
      'alguem@outlook.com',
      'pessoa@yahoo.com.br',
      'alguem@umdominioqualquer.com.br',   // dominio novo, que uma deny-list deixaria passar
    ]) {
      assert.equal(emailPermitido(ruim), false, `deveria acusar: ${ruim}`);
    }
    assert.equal(fonePermitido('+5562987654321'), false, 'telefone real deveria ser acusado');
  });

  it('CONTROLE NEGATIVO — o predicado ACEITA reservado, caixa de papel e placeholder', () => {
    for (const ok of [
      'qualquer@example.com', 'fixture-1636-x@example.com', 'a@b.test', 'root@localhost',
      'nucleoia@pmigo.org.br', 'vitor@vitormr.dev', 'security@supabase.io', 'seu@email.com',
    ]) {
      assert.equal(emailPermitido(ok), true, `nao deveria acusar: ${ok}`);
    }
    for (const ok of ['+5551999999999', '+55 62 91234-5678', '+5500000000012']) {
      assert.equal(fonePermitido(ok), true, `nao deveria acusar: ${ok}`);
    }
  });

  it('o guard olha o que vai para o GitHub (git ls-files), nao o diretorio de trabalho', () => {
    const fs = arquivosVersionados();
    assert.ok(fs.length > 500, `esperava o repo inteiro, achei ${fs.length} arquivos`);
    // sanidade: um artefato notoriamente NAO versionado nao pode aparecer
    assert.ok(
      !fs.includes('scripts/docusign-signers-extracted.json'),
      'o extrato de assinaturas do Termo (92 pessoas, 3 CPFs) voltou a ser versionado',
    );
    assert.ok(
      !fs.some((f) => f.startsWith('supabase/.temp/')),
      'supabase/.temp/ voltou a ser versionado (o .gitignore nao desrastreia sozinho)',
    );
  });

  // ── a regra ───────────────────────────────────────────────────────────────
  it('toda isencao de arquivo aponta para um arquivo que EXISTE', () => {
    // Isencao orfa e pior do que isencao nenhuma: ela sugere que alguem pensou no caso, e o
    // arquivo pode ter sido renomeado levando o conteudo (e a exposicao) para fora da lista.
    const versionados = new Set(arquivosVersionados());
    const orfas = [...ARQUIVOS_ISENTOS.keys()].filter((f) => !versionados.has(f));
    assert.deepEqual(orfas, [], 'isencao aponta para arquivo que nao esta mais versionado');
  });

  it('as fixtures de controle sao EXATAMENTE as declaradas (a isencao deste arquivo e estreita)', () => {
    // Sem isto, isentar o arquivo do guard abriria um esconderijo: qualquer endereco real colado
    // aqui dentro passaria calado. Medido na propria pele — este guard ficou vermelho no CI
    // acusando as proprias fixtures, porque local elas ainda nao estavam rastreadas e `git
    // ls-files` so as viu depois do `git add`.
    const src = ler(ESTE_ARQUIVO);
    assert.ok(src, `${ESTE_ARQUIVO} nao encontrado — o caminho do proprio guard mudou`);
    const achados = new Set(
      (src.match(RE_EMAIL) ?? []).map((m) => m.toLowerCase()).filter((m) => !emailPermitido(m)),
    );
    assert.deepEqual(
      [...achados].sort(), [...FIXTURES_DE_CONTROLE].sort(),
      'o arquivo do guard tem endereco de dominio pessoal que NAO e fixture de controle declarada',
    );
  });

  it('nenhum e-mail pessoal em arquivo versionado', () => {
    const ofensores = [];
    for (const f of arquivosVersionados()) {
      if (ARQUIVOS_ISENTOS.has(f)) continue;
      const src = ler(f);
      if (src === null) continue;
      for (const m of src.match(RE_EMAIL) ?? []) {
        if (!emailPermitido(m)) ofensores.push(`${f}: ${m.replace(/^(.{1,3}).*@/, '$1***@')}`);
      }
    }
    // Reporta TODOS, iterando: uma checagem existencial passa assim que o primeiro parece ok.
    assert.deepEqual(
      [...new Set(ofensores)], [],
      'e-mail pessoal em repo publico. Se o endereco e legitimo (caixa de papel, fornecedor), ' +
        'acrescente em PERMITIDOS com o motivo; se e de pessoa fisica, ele nao pode entrar.',
    );
  });

  it('nenhum telefone real em arquivo versionado', () => {
    const ofensores = [];
    for (const f of arquivosVersionados()) {
      if (ARQUIVOS_ISENTOS.has(f)) continue;   // inclui este arquivo: o controle usa um numero real-shaped
      const src = ler(f);
      if (src === null) continue;
      for (const m of src.match(RE_FONE) ?? []) {
        if (!fonePermitido(m)) ofensores.push(`${f}: ${m.replace(/\d(?=\d{4})/g, '*')}`);
      }
    }
    assert.deepEqual([...new Set(ofensores)], [], 'telefone de pessoa fisica em repo publico');
  });
});
