// tests/contracts/1642-comunicacao-nao-nega-a-consequencia.test.mjs
//
// #1642 — a comunicação NEGAVA a consequência que existia (LGPD art. 18, VIII).
//
// Enquanto o gate do #1640 esteve vivo, a ausência de consentimento de IA barrava o convite de
// entrevista. Nas três superfícies que o candidato lê, o texto dizia o contrário:
//   - a tela de consentimento vendia o consentimento como acelerador, sem falar de efeito;
//   - o e-mail de nudge mandava "ignorar esta mensagem" quem não quisesse consentir;
//   - a política pública citava DUAS bases legais para a MESMA operação (consentimento e o
//     art. 7º, V, que dispensa consentimento).
//
// Este arquivo afirma o par que torna o texto verdadeiro, e é o par que importa: o texto promete
// ausência de consequência (camada A/B-texto) E o banco não tem gate que crie uma (camada B-mundo).
// Uma metade sozinha não vale nada: um texto correto sobre um gate vivo é a mentira original de
// volta, com o sinal trocado.
//
// ⚠️ ORDEM: por isso o #1642 só podia vir DEPOIS do #1640. Se o gate voltar, é este teste que cai,
// e cai dizendo que a plataforma passou a afirmar ao titular algo que ela não cumpre.
//
// Camada A (estática, sempre roda): dicionários, migration e a página.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): template vivo + ausência de gate.
//   ⚠️ um SKIP silencioso lê como verde. Conferir o número de skips, não só `fail 0`.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const DICTS = {
  'pt-BR': 'src/i18n/pt-BR.ts',
  'en-US': 'src/i18n/en-US.ts',
  'es-LATAM': 'src/i18n/es-LATAM.ts',
};
const PRIVACY_PAGE = 'src/pages/privacy.astro';
const MIGRATION_PATH =
  'supabase/migrations/20260807000400_1642_o_nudge_deixa_de_negar_a_consequencia.sql';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

/**
 * Escapa TODO metacaractere de regex, não só o ponto. Um escapador parcial é pior que nenhum:
 * ele parece defender e não defende (`js/incomplete-sanitization`, apontado pelo CodeQL neste
 * arquivo). Aqui as chaves são literais deste teste, então não havia exploração — mas a forma
 * errada é a que sobrevive por cópia para onde a entrada não é literal.
 */
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Lê o VALOR de uma chave do dicionário, nunca o arquivo cru. Assertar sobre o arquivo inteiro
 * casaria comentários e chaves vizinhas — o mesmo defeito que o guard do #1586b teve de corrigir.
 */
function dictValue(src, key) {
  const re = new RegExp(`^\\s*'${escapeRe(key)}':\\s*'((?:[^'\\\\]|\\\\.)*)'`, 'm');
  return src.match(re)?.[1] ?? null;
}

// A afirmação de ausência de consequência, por idioma. É o núcleo do art. 18, VIII: não basta
// dizer "opcional", tem de dizer o que acontece com quem recusa.
const SEM_CONSEQUENCIA = {
  'pt-BR': /não tem efeito sobre o processo seletivo/i,
  'en-US': /no effect on the selection process/i,
  'es-LATAM': /efecto sobre el proceso de selección/i,
};

// Os dois provedores que de fato tratam sob este consentimento (medido em 07/08/2026):
// Google/Gemini produziu as 47 análises do ciclo aberto; Anthropic/Claude roda triagem, briefing
// e análise de vídeo. Nomear só um era informação incorreta sobre o destinatário dos dados.
const PROVEDORES = [/Google/, /Anthropic/];

describe('#1642 A — a tela de consentimento afirma a ausência de consequência, nos 3 idiomas', () => {
  for (const [lang, path] of Object.entries(DICTS)) {
    const src = read(path);

    it(`${lang}: consentBody diz o que acontece com quem NÃO consente`, () => {
      const v = dictValue(src, 'pmi.onboarding.consentBody');
      assert.ok(v, `${lang}: chave pmi.onboarding.consentBody não encontrada`);
      assert.match(
        v,
        SEM_CONSEQUENCIA[lang],
        `${lang}: o texto voltou a silenciar sobre a consequência da recusa (art. 18, VIII)`,
      );
    });

    it(`${lang}: consentBody nomeia os DOIS provedores que tratam sob este consentimento`, () => {
      const v = dictValue(src, 'pmi.onboarding.consentBody');
      for (const p of PROVEDORES) {
        assert.match(v, p, `${lang}: consentBody deixou de nomear ${p} (art. 9º, I)`);
      }
    });
  }
});

describe('#1642 A — a política pública separa as bases legais e lista os dois subprocessadores', () => {
  for (const [lang, path] of Object.entries(DICTS)) {
    const src = read(path);

    it(`${lang}: a linha da análise por IA não invoca mais base que DISPENSA consentimento`, () => {
      const v = dictValue(src, 'privacy.s4.googleAi');
      assert.ok(v, `${lang}: privacy.s4.googleAi não encontrada`);
      // Art. 7º, V (procedimento preliminar) é a base do PROCESSO SELETIVO e vive em
      // privacy.s3.row3.basis. Citá-la na mesma frase que o consentimento é a contradição que a
      // issue chama de "materialização textual do gate": não se dispensa e se exige ao mesmo tempo.
      assert.doesNotMatch(
        v,
        /Art\.?\s*7\s*[º°]?\s*,?\s*V\b/i,
        `${lang}: a dupla base legal voltou à linha da análise por IA`,
      );
      assert.match(
        v,
        /Art\.?\s*7\s*[º°]?\s*,?\s*I\b/i,
        `${lang}: a base do consentimento (art. 7º, I) sumiu da linha da análise por IA`,
      );
    });

    it(`${lang}: existe linha própria para a Anthropic`, () => {
      const v = dictValue(src, 'privacy.s4.anthropicAi');
      assert.ok(v, `${lang}: privacy.s4.anthropicAi não encontrada`);
      assert.match(v, /Anthropic/, `${lang}: a linha existe mas não nomeia o subprocessador`);
    });

    it(`${lang}: o art. 7º, V continua sendo a base do PROCESSO seletivo`, () => {
      // O ponto da correção não é apagar o art. 7º, V: é devolvê-lo ao lugar certo. Se esta
      // asserção cair junto com a de cima, a separação virou supressão.
      const v = dictValue(src, 'privacy.s3.row3.basis');
      assert.ok(v, `${lang}: privacy.s3.row3.basis não encontrada`);
      assert.match(v, /7,?\s*V/i, `${lang}: o processo seletivo perdeu a base legal autônoma`);
    });
  }

  it('a página de privacidade renderiza a linha nova (chave órfã não informa ninguém)', () => {
    const page = read(PRIVACY_PAGE);
    assert.ok(page, `${PRIVACY_PAGE} não encontrada`);
    assert.match(
      page,
      /privacy\.s4\.anthropicAi/,
      'a chave existe nos 3 dicionários mas não é exibida: o titular continua sem a informação',
    );
  });
});

describe('#1642 A — a migration do e-mail de nudge', () => {
  it('existe e troca a instrução, não só acrescenta texto', () => {
    const sql = read(MIGRATION_PATH);
    assert.ok(sql, `migration esperada em ${MIGRATION_PATH}`);
    // Sem comentários: o cabeçalho desta migration CITA a frase antiga para explicar o defeito.
    const code = sql.replace(/^\s*--.*$/gm, '');
    assert.doesNotMatch(
      code,
      /prefere não dar consentimento/i,
      'a instrução antiga sobreviveu no corpo da migration',
    );
    assert.match(code, /não tem efeito sobre o processo seletivo/i);
    assert.match(code, /no effect on the selection process/i);
    assert.match(code, /efecto sobre el proceso de selección/i);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada B — DB-aware
// ─────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SUPABASE_SRK);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = dbGated
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

describe('#1642 B — o template VIVO é o que sai no e-mail', () => {
  it('as 3 línguas afirmam a ausência de consequência, em HTML e em texto', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb
      .from('campaign_templates')
      .select('body_html, body_text')
      .eq('slug', 'pmi_consent_nudge')
      .single();
    assert.ifError(error);
    assert.ok(data, 'template pmi_consent_nudge não existe no banco');

    for (const [lang, re] of [
      ['pt', SEM_CONSEQUENCIA['pt-BR']],
      ['en', SEM_CONSEQUENCIA['en-US']],
      ['es', SEM_CONSEQUENCIA['es-LATAM']],
    ]) {
      // As duas variantes importam: cliente que bloqueia HTML lê a de texto.
      assert.match(data.body_html?.[lang] ?? '', re, `body_html.${lang} não afirma a ausência de consequência`);
      assert.match(data.body_text?.[lang] ?? '', re, `body_text.${lang} não afirma a ausência de consequência`);
    }
  });

  it('nenhuma língua manda ignorar o e-mail por não querer consentir', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb
      .from('campaign_templates')
      .select('body_html, body_text')
      .eq('slug', 'pmi_consent_nudge')
      .single();
    assert.ifError(error);

    // O onboarding tem outras etapas além do consentimento: mandar ignorar a mensagem por causa
    // dele custava as demais. "Já completou" continua sendo motivo legítimo para desconsiderar.
    const proibido = [
      /prefere não dar consentimento/i,
      /prefer not to grant AI consent/i,
      /prefiere no dar consentimiento/i,
    ];
    const tudo = JSON.stringify([data.body_html, data.body_text]);
    for (const re of proibido) {
      assert.doesNotMatch(tudo, re, `a instrução antiga voltou ao template vivo: ${re}`);
    }
  });
});

describe('#1642 B — e o mundo confirma o texto: nenhum gate cria a consequência negada', () => {
  it('NENHUMA função em produção recusa o convite por ausência de análise de IA', { skip: dbGated ? false : skipMsg }, async () => {
    // Mais amplo, de propósito, que o teste do #1640 (que afirma duas funções nominais): aqui a
    // varredura é sobre o banco inteiro, para pegar o gate REINTRODUZIDO em função nova. Enquanto
    // a tela e o e-mail prometem que a recusa não tem efeito, esta linha é a prova da promessa.
    const { data, error } = await sb.rpc('_audit_functions_matching', { p_pattern: 'GATE_NO_AI' });
    assert.ifError(error);
    assert.deepEqual(
      data ?? [],
      [],
      `o gate de IA voltou a existir em ${(data ?? []).length} função(ões): ` +
        `${(data ?? []).map((r) => r.proname).join(', ')}. ` +
        'A tela e o e-mail agora AFIRMAM ao candidato que a recusa não tem consequência — ' +
        'com este gate vivo, a plataforma passou a mentir na direção inversa.',
    );
  });
});
