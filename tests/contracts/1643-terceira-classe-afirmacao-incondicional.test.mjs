// tests/contracts/1643-terceira-classe-afirmacao-incondicional.test.mjs
//
// #1643 — terceira classe: AFIRMAÇÃO INCONDICIONAL SOBRE TRATAMENTO CONDICIONAL.
//
// As duas primeiras classes da issue são gates (sem consentimento, não trata / não avança). A
// terceira não bloqueia nada: informa errado a um TERCEIRO sobre o que foi feito com o dado de
// outra pessoa. A instância medida foi o `peer_review_request`, que dizia ao avaliador
// "Pré-análise IA concluída" nas 3 línguas, num template cujas 5 variáveis declaradas não incluem
// IA nenhuma — a frase era fixa, e a análise depende de consentimento opcional.
//
// A migration `20260807001000_coerencia_o_email_prometia_round_robin.sql` removeu a frase e
// registrou a decisão do PM: a informação sobre a sugestão de IA pertence à TELA, que a mostra
// quando ela existe, e não ao e-mail, que não tem como saber. Este arquivo trava essa decisão.
//
// ⚠️ POR QUE A GUARDA É NECESSÁRIA: a correção vive numa LINHA DE DADOS, não em código. O template
// é editável pela UI do admin, a migration verificou o efeito por contagem de linhas no momento em
// que rodou, e o teste do #1642 tranca só o `pmi_consent_nudge` e só a afirmação dirigida ao
// TITULAR. Sem este arquivo, a frase volta por edição e nenhum CI reclama.
//
// Camada A (estática, SEMPRE roda): prova que o predicado tem dentes, com controles positivos
//   (a frase removida) e negativos (o nome da organização). Nada aqui lê arquivo de migration:
//   um guard ancorado num arquivo fica verde com o mecanismo inerte.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): o mundo vivo.
//   ⚠️ um SKIP silencioso lê como verde. Conferir o número de skips, não só `fail 0`.
//
// Refs #1643, #1591, #1642

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

// ─────────────────────────────────────────────────────────────────────────────
// O predicado
// ─────────────────────────────────────────────────────────────────────────────

/**
 * O nome da organização contém "IA" e "Inteligência Artificial". Procurar a sigla crua devolve
 * a base inteira: no sweep de 08/08 o predicado ingênuo (`ILIKE '%IA%'`) casou 34 dos 50
 * templates, todos pela assinatura. A marca sai ANTES de qualquer casamento.
 */
const MARCA = [
  /Núcleo de Intelig[êe]ncia Artificial\s*&\s*Gerenciamento de Projetos/gi,
  /Núcleo de IA\s*&\s*GP/gi,
  /Núcleo IA\s*&\s*GP/gi,
  /Núcleo IA/gi,
];

function semMarca(texto) {
  return MARCA.reduce((acc, re) => acc.replace(re, ' '), String(texto ?? ''));
}

/**
 * Menção a pré-análise/triagem de IA sobre uma candidatura. O invariante é mais forte que
 * "não afirmar que ela está concluída": o e-mail não fala do artefato, ponto. Um predicado que
 * tentasse distinguir afirmação de negação teria de acertar a negativa em 3 línguas
 * ("Sem pré-análise disponível") para não acusar o texto CORRETO — mais superfície de erro do
 * que a regra que o PM de fato decidiu.
 */
const TRATAMENTO_IA = [
  /pr[ée]\s*-?\s*an[áa]lise/i, // pt
  /pre\s*-?\s*an[áa]lisis/i, // es
  /pre\s*-?\s*analysis/i, // en
  /an[áa]lise\s+(por|de|da)\s+IA/i,
  /an[áa]lisis\s+(por|de|de la)\s+IA/i,
  /AI\s+analysis/i,
  /triagem\s+(por|de)\s+IA/i,
  /IA\s+(j[áa]\s+)?(analisou|avaliou)/i,
];

/** Devolve o padrão que casou, ou null. Devolver O QUE casou faz a falha ensinar. */
function citaPreAnaliseIa(texto) {
  const limpo = semMarca(texto);
  for (const re of TRATAMENTO_IA) {
    const m = limpo.match(re);
    if (m) return m[0];
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Camada A — o predicado tem dentes
// ─────────────────────────────────────────────────────────────────────────────

// A frase exata que saiu, e as formas que ela teria nas outras duas línguas.
const CONTROLES_POSITIVOS = [
  'Pré-análise IA concluída. Sua avaliação humana é o próximo passo crítico.',
  'Pre-analise IA concluida. Sua avaliacao humana e o proximo passo.',
  'AI pre-analysis complete. Your human evaluation is the next critical step.',
  'Preanálisis de IA concluido. Su evaluación humana es el próximo paso.',
  'A análise por IA desta candidatura já está disponível no painel.',
  'A triagem por IA classificou este candidato como forte.',
];

// Texto que DEVE passar: o corpo vivo corrigido, a assinatura e o nome por extenso.
const CONTROLES_NEGATIVOS = [
  'A candidatura de Fulano (Capítulo, vaga de Pesquisador) está na fila de avaliação do comitê.\n\n' +
    'A fila é compartilhada: qualquer avaliador do comitê pode assumir.\n\nNúcleo IA & GP — Comitê de Seleção',
  "The application is in the committee's review queue. The queue is shared.\n\nNúcleo IA & GP — Selection Committee",
  'Você está em processo seletivo no Núcleo de Inteligência Artificial & Gerenciamento de Projetos.',
  'Equipe GP — Núcleo IA & GP',
];

// O texto legítimo do `pmi_consent_nudge`: fala de "análise por IA" COM O TITULAR, para dizer que
// o consentimento é opcional (#1642). O predicado o acusa, e é por isso que a isenção da camada B
// é por SLUG e não por refinamento do predicado — ver `ISENTOS`.
const TEXTO_LEGITIMO_DO_TITULAR =
  'O consentimento para análise por IA é opcional, e não concedê-lo não tem efeito sobre o processo seletivo.';

describe('#1643 A — o predicado distingue a AFIRMAÇÃO da MARCA', () => {
  for (const frase of CONTROLES_POSITIVOS) {
    it(`acusa: ${frase.slice(0, 48)}…`, () => {
      assert.ok(
        citaPreAnaliseIa(frase),
        `o predicado deixou passar uma afirmação sobre pré-análise: ${frase}`,
      );
    });
  }

  for (const frase of CONTROLES_NEGATIVOS) {
    it(`não acusa: ${frase.slice(0, 48)}…`, () => {
      const casou = citaPreAnaliseIa(frase);
      assert.equal(casou, null, `falso positivo em "${frase}" (casou: ${casou})`);
    });
  }

  it('o predicado ACUSA o texto legítimo do titular — e é por isso que a isenção é por slug', () => {
    // Este teste documenta um limite conhecido em vez de o esconder. Distinguir "afirma que a
    // análise foi feita" de "explica que consentir é opcional" exigiria acertar a negativa em 3
    // línguas; errar isso acusaria o texto CORRETO do #1642. A isenção nominal é a escolha
    // deliberada, e ela só é segura porque o slug isento tem guarda própria.
    assert.ok(
      citaPreAnaliseIa(TEXTO_LEGITIMO_DO_TITULAR),
      'o predicado deixou de acusar o texto do nudge: a isenção por slug virou redundante e a ' +
        'camada B passou a depender de um predicado mais esperto do que ele é',
    );
  });

  it('a marca sozinha nunca dispara, em nenhuma das formas usadas na base', () => {
    for (const marca of [
      'Núcleo IA & GP',
      'Núcleo IA&GP',
      'Núcleo de Inteligência Artificial & Gerenciamento de Projetos',
      'Núcleo IA',
    ]) {
      assert.equal(citaPreAnaliseIa(marca), null, `a marca "${marca}" disparou o predicado`);
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada B — o mundo vivo
// ─────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SUPABASE_SRK);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = dbGated
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

const LINGUAS = ['pt', 'en', 'es'];

/**
 * O único slug isento, e o motivo: o nudge de consentimento fala de "análise por IA" COM O
 * TITULAR, para dizer que o consentimento é opcional e sem consequência (#1642). Suprimir a
 * palavra ali seria o defeito inverso. Quem tranca esse texto é o teste do #1642.
 */
const ISENTOS = new Set(['pmi_consent_nudge']);

describe('#1643 B — nenhum e-mail vivo afirma pré-análise de IA a um terceiro', () => {
  it('varre os 3 idiomas de assunto, corpo-texto e corpo-HTML de TODO template', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb
      .from('campaign_templates')
      .select('slug, subject, body_text, body_html');
    assert.ifError(error);

    // Falhar ALTO: uma varredura sobre zero linha passa por vazio, não por limpeza.
    assert.ok(Array.isArray(data) && data.length > 0, 'a varredura não recebeu template algum');

    const achados = [];
    for (const t of data) {
      if (ISENTOS.has(t.slug)) continue;
      for (const lang of LINGUAS) {
        for (const campo of ['subject', 'body_text', 'body_html']) {
          const casou = citaPreAnaliseIa(t[campo]?.[lang]);
          if (casou) achados.push(`${t.slug}.${campo}.${lang} → "${casou}"`);
        }
      }
    }

    assert.deepEqual(
      achados,
      [],
      'template vivo voltou a falar de pré-análise de IA para quem não é o titular do dado:\n' +
        `${achados.join('\n')}\n` +
        'A análise depende de consentimento OPCIONAL: o e-mail não sabe se ela existe, e a tela ' +
        'já a mostra quando existe (decisão registrada em 20260807001000).',
    );
  });

  it('o `peer_review_request` continua existindo e com as 3 línguas preenchidas', { skip: dbGated ? false : skipMsg }, async () => {
    // Sem isto, esvaziar o template passaria no teste acima: ausência de texto não é ausência de
    // afirmação, é ausência de e-mail.
    const { data, error } = await sb
      .from('campaign_templates')
      .select('body_text, body_html')
      .eq('slug', 'peer_review_request')
      .single();
    assert.ifError(error);
    assert.ok(data, 'o template do convite de avaliação sumiu da base');

    for (const lang of LINGUAS) {
      assert.ok(
        (data.body_text?.[lang] ?? '').length > 80,
        `body_text.${lang} do peer_review_request está vazio ou truncado`,
      );
      assert.ok(
        (data.body_html?.[lang] ?? '').length > 80,
        `body_html.${lang} do peer_review_request está vazio ou truncado`,
      );
    }
  });

  it('o despacho ainda RAMIFICA por contexto de IA, em vez de afirmar', { skip: dbGated ? false : skipMsg }, async () => {
    // O e-mail não carrega a condição (recebe 5 variáveis, nenhuma sobre IA). Quem a carrega é o
    // sino in-app, via `v_no_ai_context`. Se alguém achatar esse ramo numa frase fixa, a terceira
    // classe volta pela porta que sobrou — e é esta linha que fala.
    const { data, error } = await sb.rpc('_audit_functions_matching', { p_pattern: 'v_no_ai_context' });
    assert.ifError(error);
    const nomes = (data ?? []).map((r) => r.proname);
    assert.ok(
      nomes.includes('dispatch_peer_review_invitations'),
      'dispatch_peer_review_invitations deixou de ramificar por v_no_ai_context: a nota sobre a ' +
        'pré-análise voltou a ser incondicional, ou o ramo foi removido',
    );
  });
});
