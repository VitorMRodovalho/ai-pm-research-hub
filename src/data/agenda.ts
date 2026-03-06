// ─── Kick-off agenda items ───

export interface AgendaItem {
  time: string;
  unit: string;
  title: string;
  description: string;
}

export const AGENDA: AgendaItem[] = [
  {
    time: '00–15',
    unit: 'min',
    title: 'Boas-vindas e Abertura Institucional',
    description: 'Celebração. Palavra dos 5 Capítulos. 44 colaboradores.',
  },
  {
    time: '15–30',
    unit: 'min',
    title: 'Mapa Estratégico e Objetivos',
    description: '4 Quadrantes. KPIs 2026. Estrutura do Núcleo.',
  },
  {
    time: '30–45',
    unit: 'min',
    title: 'Dinâmica das Tribos',
    description: '8 vídeos. Escolha sua tribo até Sáb 08/Mar 12h BRT.',
  },
  {
    time: '45–60',
    unit: 'min',
    title: 'Networking — Breakout Rooms',
    description: 'Salas de 4-5 pessoas. Pergunta quebra-gelo.',
  },
  {
    time: '60–75',
    unit: 'min',
    title: 'Regras do Jogo e Ferramentas',
    description: 'Dashboard. Drive, Miro, WhatsApp.',
  },
  {
    time: '75–90',
    unit: 'min',
    title: 'Q&A e Encerramento',
    description: 'Links, cursos PMI, foto oficial.',
  },
];
