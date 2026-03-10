/**
 * Onboarding WhatsApp Chat Analysis
 * Parses the WhatsApp group export for OnboardingIntegração to extract:
 * - FAQ/pain points via keyword + question detection
 * - Activity timeline (messages per day/week)
 * - Sender participation distribution
 * - Suggested onboarding improvements
 *
 * Usage: npx tsx scripts/onboarding_whatsapp_analysis.ts
 */
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const WA_DIR = '/home/vitormrodovalho/Downloads/data/raw-drive-exports/Sensitive/Whatsapp groups';
const OUTPUT_DIR = join(__dirname, '..', 'data', 'ingestion-logs');
const OUTPUT_FILE = join(OUTPUT_DIR, 'onboarding_insights.json');

const MSG_REGEX = /^(\d{1,2}\/\d{1,2}\/\d{2,4}),?\s+(\d{1,2}:\d{2}(?:\s*[AP]M)?)\s*-\s*(.+?):\s+(.+)$/;
const SYSTEM_PATTERNS = [
  /joined using/i, /created group/i, /added/i, /changed/i, /left$/i,
  /Messages and calls are end-to-end encrypted/i, /was added to the community/i,
  /\.vcf \(file attached\)/i,
];
const QUESTION_KEYWORDS_PT = [
  'como', 'quando', 'onde', 'qual', 'quais', 'porque', 'por que',
  'duvida', 'dúvida', 'ajuda', 'problema', 'erro', 'consigo',
  'nao sei', 'não sei', 'preciso', 'posso', 'devo', 'alguem', 'alguém',
];
const THEME_KEYWORDS: Record<string, string[]> = {
  'Acesso à plataforma': ['login', 'acesso', 'senha', 'plataforma', 'hub', 'entrar', 'cadastro', 'registr'],
  'Seleção de tribo': ['tribo', 'tribe', 'quadrante', 'alocação', 'alocar', 'escolher tribo'],
  'Credly / Certificação': ['credly', 'badge', 'certificado', 'certificação', 'pmi', 'credencial'],
  'Reuniões / Agenda': ['reunião', 'reuniao', 'meeting', 'agenda', 'calendar', 'horário', 'horario', 'calendário'],
  'Conteúdo / Artefatos': ['artigo', 'artefato', 'documento', 'pdf', 'apresentação', 'material', 'pesquisa'],
  'WhatsApp / Comunicação': ['whatsapp', 'grupo', 'mensagem', 'telegram', 'comunicação'],
  'Processo de onboarding': ['onboarding', 'integração', 'integracao', 'bem-vindo', 'bemvindo', 'voluntário', 'voluntario'],
  'Ferramentas': ['notion', 'trello', 'drive', 'google', 'github', 'supabase'],
};

interface ParsedMessage {
  date: string;
  time: string;
  sender: string;
  content: string;
  isQuestion: boolean;
  themes: string[];
}

function findOnboardingFile(): string {
  const files = readdirSync(WA_DIR);
  const match = files.find(f => /onboarding|integracao|integração|novos.*voluntários/i.test(f));
  if (!match) throw new Error('No onboarding WhatsApp chat file found in ' + WA_DIR);
  return join(WA_DIR, match);
}

function parseMessages(text: string): ParsedMessage[] {
  const lines = text.split('\n');
  const messages: ParsedMessage[] = [];

  for (const line of lines) {
    const match = line.match(MSG_REGEX);
    if (!match) continue;
    const [, date, time, sender, content] = match;

    if (SYSTEM_PATTERNS.some(p => p.test(content)) || content === '<Media omitted>') continue;
    if (content.trim().length < 3) continue;

    const lower = content.toLowerCase();
    const isQuestion = content.includes('?') || QUESTION_KEYWORDS_PT.some(kw => lower.includes(kw));

    const themes: string[] = [];
    for (const [theme, keywords] of Object.entries(THEME_KEYWORDS)) {
      if (keywords.some(kw => lower.includes(kw))) themes.push(theme);
    }

    messages.push({ date, time, sender: sender.trim(), content: content.trim(), isQuestion, themes });
  }
  return messages;
}

function analyzeTimeline(messages: ParsedMessage[]) {
  const byDay: Record<string, number> = {};
  const byWeek: Record<string, number> = {};

  messages.forEach(m => {
    byDay[m.date] = (byDay[m.date] || 0) + 1;
    const parts = m.date.split('/');
    const weekKey = parts[0] + '/' + parts[2];
    byWeek[weekKey] = (byWeek[weekKey] || 0) + 1;
  });

  return {
    messagesPerDay: Object.entries(byDay).map(([date, count]) => ({ date, count })).sort((a, b) => a.date.localeCompare(b.date)),
    totalDays: Object.keys(byDay).length,
    avgPerDay: messages.length / Math.max(Object.keys(byDay).length, 1),
  };
}

function analyzeSenders(messages: ParsedMessage[]) {
  const counts: Record<string, number> = {};
  messages.forEach(m => { counts[m.sender] = (counts[m.sender] || 0) + 1; });
  return Object.entries(counts)
    .map(([sender, count]) => ({ sender, count, pct: Math.round((count / messages.length) * 100) }))
    .sort((a, b) => b.count - a.count);
}

function analyzeThemes(messages: ParsedMessage[]) {
  const themeCounts: Record<string, number> = {};
  messages.forEach(m => m.themes.forEach(t => { themeCounts[t] = (themeCounts[t] || 0) + 1; }));
  return Object.entries(themeCounts)
    .map(([theme, count]) => ({ theme, count }))
    .sort((a, b) => b.count - a.count);
}

function extractTopQuestions(messages: ParsedMessage[], limit = 10): string[] {
  return messages
    .filter(m => m.isQuestion && m.content.includes('?'))
    .map(m => m.content)
    .slice(0, limit);
}

function suggestImprovements(themes: { theme: string; count: number }[], questions: string[]): string[] {
  const suggestions: string[] = [];

  const topTheme = themes[0]?.theme;
  if (topTheme === 'Acesso à plataforma') {
    suggestions.push('Adicionar guia visual passo-a-passo de primeiro login ao onboarding');
  }
  if (topTheme === 'Seleção de tribo') {
    suggestions.push('Criar quiz interativo para ajudar novos membros a escolher sua tribo');
  }
  if (themes.some(t => t.theme === 'Credly / Certificação')) {
    suggestions.push('Incluir tutorial de configuração Credly como step dedicado no onboarding');
  }
  if (themes.some(t => t.theme === 'Reuniões / Agenda')) {
    suggestions.push('Mostrar próximas reuniões da tribo diretamente na página de onboarding');
  }
  if (themes.some(t => t.theme === 'Ferramentas')) {
    suggestions.push('Criar seção "Ferramentas Essenciais" com links diretos no onboarding');
  }
  if (questions.length > 5) {
    suggestions.push('Criar FAQ dinâmico baseado nas perguntas mais frequentes do grupo de integração');
  }
  suggestions.push('Implementar progress tracker para membros acompanharem seu avanço no onboarding');
  return suggestions;
}

function main() {
  console.log('🔍 Locating onboarding WhatsApp chat file...');
  const chatFile = findOnboardingFile();
  console.log(`📄 Found: ${chatFile}`);

  const raw = readFileSync(chatFile, 'utf-8');
  const messages = parseMessages(raw);
  console.log(`✅ Parsed ${messages.length} messages (excluding system/media)`);

  const questions = messages.filter(m => m.isQuestion);
  console.log(`❓ Questions/pain points: ${questions.length}`);

  const timeline = analyzeTimeline(messages);
  const senders = analyzeSenders(messages);
  const themes = analyzeThemes(messages);
  const topQuestions = extractTopQuestions(messages);
  const improvements = suggestImprovements(themes, topQuestions);

  console.log(`\n📊 Theme Analysis:`);
  themes.forEach(t => console.log(`   ${t.theme}: ${t.count} mentions`));

  console.log(`\n🏆 Top Participants:`);
  senders.slice(0, 5).forEach(s => console.log(`   ${s.sender}: ${s.count} messages (${s.pct}%)`));

  console.log(`\n💡 Suggested Improvements:`);
  improvements.forEach(s => console.log(`   - ${s}`));

  mkdirSync(OUTPUT_DIR, { recursive: true });
  const output = {
    generatedAt: new Date().toISOString(),
    sourceFile: chatFile,
    totalMessages: messages.length,
    totalQuestions: questions.length,
    questionRate: Math.round((questions.length / messages.length) * 100) + '%',
    timeline: {
      totalDays: timeline.totalDays,
      avgMessagesPerDay: Math.round(timeline.avgPerDay * 10) / 10,
      dailyBreakdown: timeline.messagesPerDay,
    },
    themes: themes,
    topQuestions: topQuestions,
    senderParticipation: senders,
    suggestedImprovements: improvements,
    onboardingPhases: [
      { phase: 'Pre-Onboarding', description: 'Apresentações pessoais e boas-vindas', keyThemes: ['Processo de onboarding', 'WhatsApp / Comunicação'] },
      { phase: 'Setup', description: 'Acesso à plataforma e perfil', keyThemes: ['Acesso à plataforma', 'Ferramentas'] },
      { phase: 'Integração', description: 'Seleção de tribo e primeiras reuniões', keyThemes: ['Seleção de tribo', 'Reuniões / Agenda'] },
      { phase: 'Produção', description: 'Primeiros artefatos e certificações', keyThemes: ['Conteúdo / Artefatos', 'Credly / Certificação'] },
    ],
  };

  writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2));
  console.log(`\n💾 Full report saved to: ${OUTPUT_FILE}`);
}

main();
