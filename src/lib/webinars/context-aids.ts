type WebinarEventLike = {
  id?: string | number | null;
  title?: string | null;
  date?: string | null;
};

type AttendanceRouteLike = {
  action?: string | null;
};

type CommsRouteLike = {
  q?: string | null;
  eventId?: string | null;
  stage?: string | null;
  title?: string | null;
  date?: string | null;
};

export function getAttendanceHandoffCopy(action?: string | null): string {
  if (action === 'meeting-link') {
    return 'Handoff contextual: completar o meeting link operacional deste webinar.';
  }
  if (action === 'youtube-url') {
    return 'Handoff contextual: registrar o replay deste webinar no evento correspondente.';
  }
  return 'Handoff contextual: abrir o fluxo de eventos no contexto do webinar selecionado.';
}

export function getAttendanceEditAssistantCopy(action?: string | null): string {
  if (action === 'meeting-link') {
    return 'Assistente contextual: adicione ou confirme o meeting link desta sessao, revise data/duracao e salve para liberar a divulgacao no fluxo de webinars.';
  }
  if (action === 'youtube-url') {
    return 'Assistente contextual: cole o replay em `youtube_url`, confirme a flag de gravacao e salve para que o proximo handoff de publicacao possa seguir.';
  }
  return '';
}

export function buildWebinarCommsHref(route: AttendanceRouteLike, ev: WebinarEventLike): string {
  const params = new URLSearchParams();
  params.set('focus', 'broadcasts');
  params.set('context', 'webinar');
  params.set('stage', route?.action === 'youtube-url' ? 'followup' : 'invite');
  if (ev.id != null) params.set('eventId', String(ev.id));
  if (ev.title) {
    params.set('q', String(ev.title));
    params.set('title', String(ev.title));
  }
  if (ev.date) params.set('date', String(ev.date));
  return `/admin/comms-ops?${params.toString()}`;
}

export function buildAttendanceFromCommsRoute(route: CommsRouteLike): string {
  const params = new URLSearchParams();
  params.set('tab', 'events');
  params.set('type', 'webinar');
  if (route?.q) params.set('q', route.q);
  if (route?.eventId) params.set('eventId', route.eventId);
  if (route?.stage === 'followup') {
    params.set('action', 'youtube-url');
    params.set('edit', '1');
  }
  return `/attendance?${params.toString()}`;
}

export function buildCommsPlaybookTemplates(
  route: CommsRouteLike,
  formatDate: (iso: string) => string
): Array<{ title: string; tone: string; subject: string; body: string }> {
  const title = route.title || 'Webinar';
  const date = formatDate(route.date || '') || 'data a confirmar';
  const invite = {
    title: 'Convite base',
    tone: 'bg-blue-50 border-blue-200',
    subject: `[Webinar] ${title} — ${date}`,
    body: `Olá, pessoal.\n\nTemos o webinar "${title}" programado para ${date}.\n\nSe possível, reforcem a participação do público-alvo e utilizem o link operacional já validado no Attendance.\n\nEm breve seguimos com novos lembretes.`,
  };
  const reminder = {
    title: 'Lembrete base',
    tone: 'bg-amber-50 border-amber-200',
    subject: `[Lembrete] ${title} acontece em ${date}`,
    body: `Olá, pessoal.\n\nPassando para lembrar do webinar "${title}", marcado para ${date}.\n\nConfiram o link da sessão, a audiência pretendida e a orientação de presença antes do início.\n\nNos vemos lá.`,
  };
  const followup = {
    title: 'Follow-up base',
    tone: 'bg-emerald-50 border-emerald-200',
    subject: `[Replay] ${title} — material disponível`,
    body: `Olá, pessoal.\n\nO webinar "${title}" já foi realizado e estamos fechando a publicação do replay e dos materiais relacionados.\n\nAssim que o conteúdo estiver confirmado nas superfícies finais, podemos divulgar o acesso e próximos passos ao público.`,
  };
  if (route.stage === 'followup') return [followup, invite];
  if (route.stage === 'reminder') return [reminder, invite];
  return [invite, reminder];
}
