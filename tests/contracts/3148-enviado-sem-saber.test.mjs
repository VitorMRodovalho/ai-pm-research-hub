/**
 * #3148: "enviado" e "você será avisado" sem saber se aconteceu.
 *
 * Competição, portal do aprovado, painel do Termo, broadcast da tribo e filiação no perfil afirmavam
 * um envio ou um aviso futuro que o código não garante. O guard lê o bloco que decide e o texto que a
 * pessoa vê, nos 3 idiomas. Comentários JS saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments as mask } from '../helpers/guard-pin-staleness.mjs';

const read = (p) => readFileSync(resolve(process.cwd(), p), 'utf8');
const PANEL = mask(read('src/components/admin/VolunteerAgreementPanel.tsx'));
const PORTAL = mask(read('src/components/pmi-onboarding/PMIOnboardingPortal.tsx'));
const EF = mask(read('supabase/functions/send-tribe-broadcast/index.ts'));
const TRIBE = mask(read('src/pages/tribe/[id].astro'));
const DICT = Object.fromEntries(['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, read(`src/i18n/${l}.ts`)]));

function val(dict, key) {
  const m = dict.match(new RegExp(`\\n\\s*'${key.replaceAll('.', '\\.')}': '((?:[^'\\\\]|\\\\.)*)',\\n`));
  assert.ok(m, `achou ${key}`);
  return m[1];
}

test('#3148 E5: o painel do Termo diz quantos avisos saíram e quantos a janela de 7 dias pulou', () => {
  assert.match(PANEL,
    /const targets = Number\(data\?\.targets \?\? 0\);\s+const skipped = String\(Number\(data\?\.skipped_recent \?\? 0\)\);\s+const msg = targets > 0\s+\? t\.notifySent\.replace\('\{targets\}', String\(targets\)\)\.replace\('\{skipped\}', skipped\)\s+: t\.notifyNoneNew\.replace\('\{skipped\}', skipped\);\s+\(window as any\)\.toast\?\.\(msg, targets > 0 \? 'success' : 'info'\);/,
    'painel: a mensagem sai dos números do RPC, com o caso zero à parte');
  const sent = [...PANEL.matchAll(/notifySent: '([^']*)',/g)].map((m) => m[1]);
  const none = [...PANEL.matchAll(/notifyNoneNew: '([^']*)',/g)].map((m) => m[1]);
  assert.equal(sent.length, 3, 'painel: notifySent nos 3 idiomas');
  assert.equal(none.length, 3, 'painel: notifyNoneNew nos 3 idiomas');
  for (const s of sent) assert.ok(s.includes('{targets}') && s.includes('{skipped}'), `painel: "${s}" leva as duas contagens`);
  for (const s of none) assert.ok(s.includes('{skipped}'), `painel: "${s}" leva a contagem da janela`);
});

test('#3148 E2: o portal não presume que o link saiu', () => {
  assert.match(PORTAL, /setAccessState\(\(data as any\)\?\.state \?\? 'error'\);/, 'portal: sem estado é erro');
  assert.doesNotMatch(PORTAL, /\?\? 'sent'/, 'portal: nenhum padrão "sent"');
  for (const [l, d] of Object.entries(DICT)) {
    assert.doesNotMatch(val(d, 'pmi.onboarding.access.emailLinkSent'), /^(Link enviado|Link sent|Enlace enviado)/, `${l}: o texto não afirma o envio`);
  }
});

test('#3148 E6: o broadcast conta quem foi endereçado e a tela avisa o modo de teste', () => {
  assert.match(EF, /const finalBcc = sandbox \? \[\] : allBcc[\s\S]*?const addressed = finalBcc\.length/, 'EF: a contagem vem do que foi de fato endereçado');
  assert.doesNotMatch(EF, /recipient_count: allBcc\.length/, 'EF: nenhum registro ou resposta com o total de membros');
  assert.equal((EF.match(/recipient_count: addressed, status: '(failed|sent)'/g) || []).length, 2, 'EF: os dois registros usam a contagem endereçada');
  assert.match(EF, /return json\(\{ success: true, sandbox, recipient_count: addressed,/, 'EF: a resposta diz se foi modo de teste');
  assert.match(TRIBE,
    /if \(data\.sandbox === true\) \{\s+\(window as any\)\.toast\?\.\(BC\.sandbox, 'info'\);\s+\} else \{\s+const msg = \(BC\.sent[^;]*;\s+\(window as any\)\.toast\?\.\(msg, 'success'\);\s+\}/,
    'tribo: no modo de teste, não diz que os membros receberam');
  assert.match(TRIBE, /sandbox: t\('tribe\.broadcast\.sandbox', lang\),/, 'tribo: o texto vai ao script');
  for (const d of Object.values(DICT)) val(d, 'tribe.broadcast.sandbox');
});

test('#3148 E1 e E7: competição e filiação não afirmam envio nem aviso que o código não garante', () => {
  const cond = { 'pt-BR': /^Se \{email\}/, 'en-US': /^If \{email\}/, 'es-LATAM': /^Si \{email\}/ };
  for (const [l, d] of Object.entries(DICT)) {
    assert.match(val(d, 'competition.doneSentTo'), cond[l], `${l}: o envio é condicional`);
    assert.doesNotMatch(val(d, 'competition.doneTitle'), /Falta confirmar|Now confirm|Falta confirmar tu/, `${l}: o título não presume inscrição pendente`);
    assert.doesNotMatch(val(d, 'profile.affiliation.unverifiedDesc'), /avisad|notified/i, `${l}: sem promessa de aviso`);
  }
});
