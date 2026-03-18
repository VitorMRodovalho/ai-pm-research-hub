import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyBadge } from '../../supabase/functions/_shared/classify-badge.ts';

// ── Trail (20 XP) ──
test('classifyBadge: PMI trail — Generative AI Overview', () => {
  const r = classifyBadge('Generative AI Overview for Project Managers', 'generative-ai-overview');
  assert.equal(r.category, 'trail');
  assert.equal(r.points, 20);
});

test('classifyBadge: PMI trail — Data Landscape GenAI', () => {
  const r = classifyBadge('Data Landscape for GenAI for Project Managers', 'data-landscape-genai');
  assert.equal(r.category, 'trail');
  assert.equal(r.points, 20);
});

test('classifyBadge: PMI trail — Prompt Engineering', () => {
  const r = classifyBadge('Prompt Engineering for Project Managers', 'prompt-engineering-pm');
  assert.equal(r.category, 'trail');
  assert.equal(r.points, 20);
});

test('classifyBadge: PMI trail — Practical Application Gen AI', () => {
  const r = classifyBadge('Practical Application of Gen AI for Project Managers', 'practical-gen-ai');
  assert.equal(r.category, 'trail');
  assert.equal(r.points, 20);
});

test('classifyBadge: PMI trail — AI in Infrastructure Construction', () => {
  const r = classifyBadge('AI in Infrastructure and Construction', 'ai-infra-construction');
  assert.equal(r.category, 'trail');
  assert.equal(r.points, 20);
});

test('classifyBadge: PMI trail — AI in Agile Delivery', () => {
  const r = classifyBadge('AI in Agile Delivery', 'ai-agile-delivery');
  assert.equal(r.category, 'trail');
  assert.equal(r.points, 20);
});

// ── Course (15 XP) ──
test('classifyBadge: course — Citizen Developer CDBA', () => {
  const r = classifyBadge('Citizen Developer Business Analyst (CDBA) Introduction', 'cdba-intro');
  assert.equal(r.category, 'course');
  assert.equal(r.points, 15);
});

test('classifyBadge: course — Introduction to Cognitive CPMAI', () => {
  const r = classifyBadge('Introduction to Cognitive Project Management for AI (CPMAI)', 'intro-cpmai');
  assert.equal(r.category, 'course');
  assert.equal(r.points, 15);
});

// ── cert_cpmai (45 XP) ──
test('classifyBadge: cert_cpmai — CPMAI certification', () => {
  const r = classifyBadge('PMI-CPMAI Certified Professional', 'pmi-cpmai');
  assert.equal(r.category, 'cert_cpmai');
  assert.equal(r.points, 45);
});

test('classifyBadge: cert_cpmai — Cognitive Project Management', () => {
  const r = classifyBadge('Cognitive Project Management for AI', 'cognitive-pm');
  assert.equal(r.category, 'cert_cpmai');
  assert.equal(r.points, 45);
});

// ── cert_pmi_senior (50 XP) ──
test('classifyBadge: cert_pmi_senior — PMP', () => {
  const r = classifyBadge('Project Management Professional (PMP)', 'pmp');
  assert.equal(r.category, 'cert_pmi_senior');
  assert.equal(r.points, 50);
});

test('classifyBadge: cert_pmi_senior — PgMP', () => {
  const r = classifyBadge('Program Management Professional (PgMP)', 'pgmp');
  assert.equal(r.category, 'cert_pmi_senior');
  assert.equal(r.points, 50);
});

test('classifyBadge: cert_pmi_senior — PfMP', () => {
  const r = classifyBadge('Portfolio Management Professional (PfMP)', 'pfmp');
  assert.equal(r.category, 'cert_pmi_senior');
  assert.equal(r.points, 50);
});

test('classifyBadge: cert_pmi_senior — PMI-ACP', () => {
  const r = classifyBadge('PMI Agile Certified Practitioner (PMI-ACP)', 'pmi-acp');
  assert.equal(r.category, 'cert_pmi_senior');
  assert.equal(r.points, 50);
});

test('classifyBadge: cert_pmi_senior — PMI-RMP', () => {
  const r = classifyBadge('PMI Risk Management Professional (PMI-RMP)', 'pmi-rmp');
  assert.equal(r.category, 'cert_pmi_senior');
  assert.equal(r.points, 50);
});

test('classifyBadge: cert_pmi_senior — PMI-SP', () => {
  const r = classifyBadge('PMI Scheduling Professional (PMI-SP)', 'pmi-sp');
  assert.equal(r.category, 'cert_pmi_senior');
  assert.equal(r.points, 50);
});

// ── cert_pmi_mid (40 XP) ──
test('classifyBadge: cert_pmi_mid — PMI-PMOCP', () => {
  const r = classifyBadge('PMI PMO Certified Professional (PMI-PMOCP)', 'pmi-pmocp');
  assert.equal(r.category, 'cert_pmi_mid');
  assert.equal(r.points, 40);
});

// ── cert_pmi_practitioner (35 XP) ──
test('classifyBadge: cert_pmi_practitioner — DASSM', () => {
  const r = classifyBadge('Disciplined Agile Senior Scrum Master (DASSM)', 'dassm');
  assert.equal(r.category, 'cert_pmi_practitioner');
  assert.equal(r.points, 35);
});

test('classifyBadge: cert_pmi_practitioner — PMO-CP', () => {
  const r = classifyBadge('PMO Certified Practitioner (PMO-CP)', 'pmo-cp');
  assert.equal(r.category, 'cert_pmi_practitioner');
  assert.equal(r.points, 35);
});

// ── cert_pmi_entry (30 XP) ──
test('classifyBadge: cert_pmi_entry — DASM', () => {
  const r = classifyBadge('Disciplined Agile Scrum Master (DASM)', 'dasm');
  assert.equal(r.category, 'cert_pmi_entry');
  assert.equal(r.points, 30);
});

// ── specialization (25 XP) ──
test('classifyBadge: specialization — CAPM', () => {
  const r = classifyBadge('Certified Associate in Project Management (CAPM)', 'capm');
  assert.equal(r.category, 'specialization');
  assert.equal(r.points, 25);
});

test('classifyBadge: specialization — AWS', () => {
  const r = classifyBadge('AWS Solutions Architect Associate', 'aws-sa');
  assert.equal(r.category, 'specialization');
  assert.equal(r.points, 25);
});

test('classifyBadge: specialization — ITIL', () => {
  const r = classifyBadge('ITIL Foundation', 'itil');
  assert.equal(r.category, 'specialization');
  assert.equal(r.points, 25);
});

test('classifyBadge: specialization — SAFe', () => {
  const r = classifyBadge('SAFe Agilist', 'safe-agilist');
  assert.equal(r.category, 'specialization');
  assert.equal(r.points, 25);
});

test('classifyBadge: specialization — Power BI', () => {
  const r = classifyBadge('Microsoft Power BI Data Analyst', 'power-bi');
  assert.equal(r.category, 'specialization');
  assert.equal(r.points, 25);
});

test('classifyBadge: specialization — Lean Six Sigma', () => {
  const r = classifyBadge('Lean Six Sigma Green Belt', 'lean-six-sigma');
  assert.equal(r.category, 'specialization');
  assert.equal(r.points, 25);
});

// ── knowledge_ai_pm (20 XP) ──
test('classifyBadge: knowledge_ai_pm — Artificial Intelligence', () => {
  const r = classifyBadge('Introduction to Artificial Intelligence', 'intro-ai');
  assert.equal(r.category, 'knowledge_ai_pm');
  assert.equal(r.points, 20);
});

test('classifyBadge: knowledge_ai_pm — Machine Learning', () => {
  const r = classifyBadge('Machine Learning Fundamentals', 'ml-fundamentals');
  assert.equal(r.category, 'knowledge_ai_pm');
  assert.equal(r.points, 20);
});

test('classifyBadge: knowledge_ai_pm — Enterprise Design Thinking', () => {
  const r = classifyBadge('Enterprise Design Thinking Practitioner', 'edt');
  assert.equal(r.category, 'knowledge_ai_pm');
  assert.equal(r.points, 20);
});

test('classifyBadge: knowledge_ai_pm — Agile Coach', () => {
  const r = classifyBadge('Agile Coach Professional', 'agile-coach');
  assert.equal(r.category, 'knowledge_ai_pm');
  assert.equal(r.points, 20);
});

// ── badge fallback (10 XP) ──
test('classifyBadge: badge — unknown/generic badge', () => {
  const r = classifyBadge('Some Random Badge from Acme Corp', 'random-badge');
  assert.equal(r.category, 'badge');
  assert.equal(r.points, 10);
});

test('classifyBadge: badge — empty strings', () => {
  const r = classifyBadge('', '');
  assert.equal(r.category, 'badge');
  assert.equal(r.points, 10);
});

// ── Order-of-precedence edge cases ──
test('classifyBadge: CPMAI checked before PMI-senior (overlap on pmp-like keywords)', () => {
  // 'cpmai' matches both CERT_CPMAI and could match knowledge_ai_pm
  const r = classifyBadge('CPMAI Certification', 'cpmai-cert');
  assert.equal(r.category, 'cert_cpmai');
  assert.equal(r.points, 45);
});

test('classifyBadge: DASSM checked before DASM (substring overlap)', () => {
  // DASSM contains 'dasm' — must match practitioner (35), not entry (30)
  const r = classifyBadge('Disciplined Agile Senior Scrum Master (DASSM)', 'dassm');
  assert.equal(r.category, 'cert_pmi_practitioner');
  assert.equal(r.points, 35);
});

test('classifyBadge: trail checked before knowledge_ai_pm (both match generative ai)', () => {
  const r = classifyBadge('Generative AI Overview for Project Managers', 'genai-overview');
  assert.equal(r.category, 'trail');
  assert.equal(r.points, 20);
});
