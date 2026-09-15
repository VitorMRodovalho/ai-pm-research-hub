// tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs
// Baldes (#1908 + #1109): "test:structural" E "test:contracts". HERMETICO — so exercita funcoes
// puras de classify-badge.ts, sem rede e sem banco. NAO entra em "test:behavioural".
/**
 * #2296 — os 86 badges do fallback ganham taxonomia, sem inventar categoria.
 *
 * A FRASE DE FALHA QUE ESTE PORTAO PRODUZ:
 *
 *   Se alguem mover uma credencial para o balde de participacao (ou o contrario), ou repuxar a
 *   ORDEM das checagens de forma a dar dois precos a dois badges da mesma natureza, este arquivo
 *   fica vermelho nomeando o badge.
 *
 * MEDIDO EM 15/09, e e o que separa o trabalho em duas metades muito diferentes:
 *
 *   | medida | valor |
 *   |---|---:|
 *   | lancamentos no fallback | 118 |
 *   | badges distintos | 86 |
 *   | **ja reclassificaveis pelo codigo de ANTES desta mudanca** | **13** |
 *   | lacuna real de taxonomia | 73 |
 *
 * ⚠️ Os 13 nao eram lacuna: eram DADO PARADO. O #1209 (08/07) ja tinha acrescentado
 * 'cloud essentials', 'green project manager', 'design thinking', 'big data', 'well-architected',
 * 'pmi essentials' e 'm.o.r.e', e ninguem re-sincronizou as linhas existentes. Quem escrevesse
 * palavra-chave para os 86 criaria regra redundante para 13 e chamaria de taxonomia o que e
 * backfill. **Rode o classificador ATUAL sobre a lista ANTES de escrever a primeira palavra nova.**
 *
 * Depois da mudanca: 57 reclassificados, 29 permanecem em `badge` POR DECISAO (participacao,
 * associacao, reconhecimento e fidelidade valem 10, e isso e a regra, nao um esquecimento).
 *
 * Dano colateral medido em 0: com a ordem final, so `knowledge_ai_pm` corre risco (todo o resto e
 * decidido antes), e nenhum dos 41 nomes vivos dessa categoria casa palavra nova. Controle positivo
 * da mesma consulta: as palavras acham 15 badges do fallback, entao ela nao estava vazia.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyBadge, CATEGORY_POINTS } from '../../supabase/functions/_shared/classify-badge.ts';

const cat = (nome) => classifyBadge(nome, '').category;
const pts = (nome) => classifyBadge(nome, '').points;

// ═══════════════════════════════════════════════════════════════════════════
test('A · a credencial vence o treinamento quando o nome carrega as DUAS naturezas', () => {
  // A MORDIDA, achada ao escrever isto. Com a lista de treinamento ANTES de `specialization`,
  // este badge casava 'sap s/4hana cloud' e virava `course` (15), enquanto o irmao abaixo casava
  // 'sap certified' e virava `specialization` (25). Dois "SAP Certified" com precos diferentes
  // por acidente de ORDEM, nao por decisao.
  assert.equal(cat('SAP Certified - Managing SAP S/4HANA Cloud Public Edition Projects'), 'specialization',
    'a credencial tem de vencer: este nome carrega "SAP Certified" E "S/4HANA Cloud"');
  assert.equal(cat('SAP Certified - Project Manager - SAP Activate'), 'specialization');

  // E o treinamento puro, sem "certified", continua sendo treinamento.
  assert.equal(cat('SAP S/4HANA Cloud – Functional and Business Areas (ERP) in Portuguese'), 'course');
  assert.equal(cat('Transition from SAP Solution Manager to SAP Cloud ALM - Record of Achievement'), 'course');
});

test('B · participacao e associacao PERMANECEM em 10, e isso e a decisao', () => {
  for (const nome of [
    'Lifelong Learning', 'Lifelong Learning 2026',
    'Chapter Leader 2023',
    'ACMP Member Badge', 'APM Student',
    'CertiProf Online Summit Attendee (Version 2)',
    'Construction Management Association of America Member',
    'Worldwide Communities - Community Champion 2019',
    'Survey Contributor of The Agile Adoption Report 2021',
    'FY26 LevelUp Super Luminary',
    'Instructor Recognition - First Class Delivered',
    'Mentor Silver',
  ]) {
    assert.equal(cat(nome), 'badge', `${nome} saiu do balde de participacao`);
    assert.equal(pts(nome), 10, `${nome} deixou de valer 10`);
  }
});

test('C · certificacao de TERCEIRO vai para specialization, nao para a escada do PMI', () => {
  // `cert_pmi_*` e a escada de credencial do PMI (PMP, PgMP, DASM/DASSM, PMO-CP). Jogar credencial
  // de terceiro la dentro apagaria o significado da escada — e `specialization` ja e onde AWS,
  // Azure, ITIL, TOGAF, PRINCE2, ISC2 e Scrum Alliance moram desde sempre.
  for (const nome of [
    'Certified Public-Private Partnerships (PPP) Foundation',
    'Fundamentos Na Lei Geral De Proteção De Dados - LGPDF™',
    'OKR Master Professional Certification - OKRMPC® !',
    'Professional Agile Leadership™ - Evidence-Based Management™ (PAL-EBM)',
    'Professional Scrum™ with Kanban I (PSK I)',
    'Exam 346: Managing Office 365 Identities and Requirements',
  ]) {
    assert.equal(cat(nome), 'specialization', `${nome} nao caiu em specialization`);
    assert.ok(!cat(nome).startsWith('cert_pmi'), `${nome} invadiu a escada do PMI`);
  }
});

test('D · formacao de terceiro vai para course (15)', () => {
  for (const nome of [
    'Construction Project Communications',
    'Digital Construction Practitioner',
    'Foundations of Organizational Transformation',
    'Google People Management Essentials',
    'Red Hat Training: Open Practices for your DevOps Journey (TL250) - Ver. 1.0',
    'McKinsey.org Forward Program',
    'Notion Essentials Badge',
  ]) {
    assert.equal(cat(nome), 'course', `${nome} nao caiu em course`);
    assert.equal(pts(nome), 15);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
test('E · zero dano colateral: os ja classificados NAO mudam de categoria', () => {
  // Nomes REAIS lidos de gamification_points em 15/09. Um deles por categoria em risco, mais os
  // que quase colidiram com as palavras novas. Se uma palavra nova for alargada, isto fica vermelho
  // ANTES de alguem reprecificar gente por acidente.
  const esperado = [
    ['Professional Scrum Master™ I (PSM I)', 'specialization'],   // 'professional scrum' e nova
    ['MCSA: Office 365 - Certified 2017', 'specialization'],       // 'office 365' e nova
    ['Red Hat AI Foundations Executive Certificate', 'knowledge_ai_pm'], // NAO e 'red hat training'
    ['Google Business Intelligence Professional Certificate(v.2)', 'knowledge_ai_pm'],
    // Lido do banco em 15/09: `knowledge_ai_pm`, e o classificador concorda. O `®` cola em
    // "PMI" e impede o casamento de 'pmi essentials' (o proprio codigo documenta isso), entao
    // ele cai em knowledge_ai_pm por 'ai '. A primeira versao desta fixture dizia `course` e
    // esta camada REPROVOU — o erro era meu, de transcricao, e foi ela que o achou.
    ['PMI® Essentials: Seven AI Project Patterns', 'knowledge_ai_pm'],
    ['Project Management Professional (PMP)®', 'cert_pmi_senior'],
    ['PMI PMO Certified Professional (PMI-PMOCP)™', 'cert_pmi_mid'],
    ['PMI Certified Professional in Managing AI (PMI-CPMAI)™', 'cert_cpmai'],
    ['Generative AI Overview for Project Managers', 'trail'],
    ['Value Stream Management', 'knowledge_ai_pm'],
  ];
  for (const [nome, categoria] of esperado) {
    assert.equal(cat(nome), categoria, `COLATERAL: ${nome} mudou de ${categoria} para ${cat(nome)}`);
  }
});

test('G · o limite do #1209 continua de pe: certificacao FORA do dominio fica em 10', () => {
  // ⚠️ ESTA CAMADA NASCE DE UM ERRO MEU, e por isso ela existe.
  //
  // Levei ao dono, em 15/09, "DEPC, OneTrust e Oracle sao certificacao real, subam de faixa", e ele
  // aprovou. So que o #1209 (GP, 08/07) JA tinha decidido o contrario, com razao declarada em
  // tests/edge-functions/classify-badge.test.mjs: "KEEP at badge/10 — participation/recognition +
  // out-of-domain certs (nucleo = AI + PM)". Eu tinha varrido `tests/contracts/` atras de guard,
  // como manda a regra do repo, e o guard do classificador mora em `tests/edge-functions/`.
  //
  // ⇒ A varredura por guard tem de ser pela COISA que se vai mudar (classify-badge), nao pelo
  //   diretorio que a regra cita. O diretorio e onde o ULTIMO incidente morava.
  //
  // A decisao de 15/09 foi tomada sem a regra do #1209 na tela, entao ela NAO a revoga. Ate haver
  // decisao nova e informada, o limite do #1209 vale, e estas tres continuam em 10.
  for (const nome of [
    'DevOps Essentials Professional Certificate - DEPC® !',
    'OneTrust Certified Privacy Professional',
    'Oracle Certified Professional, Java SE 5 Programmer',
    'Essentials for Projects',
    'Product and Project Collaboration',
  ]) {
    assert.equal(cat(nome), 'badge',
      `${nome} subiu de faixa contra um guard rail explicito do #1209. Se a mudanca e intencional, ` +
      'mude LA tambem, com a data e o motivo da decisao nova — nunca so aqui');
    assert.equal(pts(nome), 10);
  }
});

test('F · nenhuma categoria NOVA foi inventada (o guard #1149 precifica de UMA tabela)', () => {
  assert.equal(Object.keys(CATEGORY_POINTS).length, 10,
    'a decisao foi MAPEAR para as categorias que existem. Uma categoria nova aqui exige linha ' +
    'nova em gamification_rules, senao o #1149 reprova por drift de preco');
  assert.equal(CATEGORY_POINTS.badge, 10);
  assert.equal(CATEGORY_POINTS.course, 15);
  assert.equal(CATEGORY_POINTS.specialization, 25);
});
