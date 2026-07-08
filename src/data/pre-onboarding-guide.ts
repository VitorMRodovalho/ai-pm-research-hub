// Guia do Pré-Onboarding: jornada passo a passo + FAQ para novos voluntários
// (candidatos aprovados que ainda não assinaram o Termo de Voluntariado).
//
// Conteúdo em pt-BR por DESIGN (mesma regra de volunteer-guide.ts): o público
// são candidatos de capítulos brasileiros do PMI e o material espelha a
// comunicação oficial feita em português. Apenas o chrome (títulos de seção,
// banner, rótulos) é localizado via i18n (keys `guiaPre.*`).
//
// Origem: dúvidas reais do grupo de pré-onboarding do Ciclo 4 (2026/2).
// Cada entrada do FAQ corresponde a uma pergunta recorrente dos candidatos.

export interface JourneyStep {
  title: string;
  where: string;
  detail: string;
  link?: { href: string; label: string };
}

export interface PreFaqEntry {
  q: string;
  a: string;
}

// A jornada canônica: aprovado → membro ativo
export const journey: JourneyStep[] = [
  {
    title: 'Aceite sua vaga no VEP',
    where: 'volunteer.pmi.org',
    detail:
      'Após a aprovação, o PMI envia um e-mail do remetente <strong>noreply@pmi.org</strong> com o link de aceite. Se não encontrar o e-mail, acesse o VEP e clique em <strong>[My Info &amp; Activity / Minhas Informações e Atividades]</strong> → <strong>[Accept Position / Aceitar Posição]</strong>. Sem o aceite, a jornada não começa.',
    link: { href: 'https://volunteer.pmi.org/', label: 'Abrir o VEP' },
  },
  {
    title: 'Entre na plataforma do Núcleo',
    where: 'nucleoia.pmigo.org.br',
    detail:
      'Use o <strong>mesmo e-mail cadastrado no PMI</strong>: é ele que vincula sua conta à vaga aceita. Você entrará como <em>Visitante</em>, e isso é esperado nesta fase (veja o FAQ).',
    link: { href: 'https://nucleoia.pmigo.org.br/', label: 'Entrar na plataforma' },
  },
  {
    title: 'Complete seu perfil',
    where: 'Meu Perfil (/profile)',
    detail:
      'Revise o <strong>consentimento de privacidade</strong>, confira o <strong>nome completo</strong> (formatado, sem caixa alta), carregue a <strong>foto</strong> e preencha <strong>telefone, endereço, cidade, estado, CEP e data de aniversário</strong>. Esses dados são exigidos pela Lei nº 9.608/1998 e pela LGPD, e usados apenas no Termo de Voluntariado e na comunicação institucional. Aproveite para adicionar <strong>LinkedIn</strong>, e-mails alternativos e o <strong>Credly público</strong> (passo a passo no FAQ).',
    link: { href: 'https://nucleoia.pmigo.org.br/profile', label: 'Abrir Meu Perfil' },
  },
  {
    title: 'Garanta sua filiação PMI ativa',
    where: 'pmi.org + community.pmi.org',
    detail:
      'O programa é um benefício de <strong>filiados a capítulos brasileiros do PMI</strong>: mantenha a membrezia PMI ativa e a filiação a um capítulo do Brasil. Crie também seu perfil na <strong>community.pmi.org</strong> e deixe-o <strong>público</strong>, pois é por ele que a plataforma valida sua filiação e traz seu capítulo automaticamente.',
    link: { href: 'https://community.pmi.org/profile/', label: 'Perfil na PMI Community' },
  },
  {
    title: 'Assine o Termo de Voluntariado',
    where: 'Plataforma → Termo de Voluntariado',
    detail:
      'Com o perfil completo e a filiação ativa, a assinatura digital fica disponível. É o passo que muda seu papel de <em>Visitante</em> para <strong>Pesquisador ou Líder</strong> (conforme a vaga aprovada) e destrava o restante da plataforma. Dúvidas sobre o conteúdo do termo? Consulte o guia do voluntário no glossário.',
    link: { href: 'https://nucleoia.pmigo.org.br/governance/glossario', label: 'Guia do voluntário + glossário' },
  },
  {
    title: 'Participe do kickoff e escolha sua tribo',
    where: 'Evento de abertura do ciclo',
    detail:
      'No kickoff os temas de pesquisa do ciclo são apresentados: cada tribo com vídeo do líder, descrição da temática, proposta de valor, marcos de entrega e LinkedIn da liderança. A <strong>escolha da tribo é liberada a partir do kickoff</strong> (com o termo assinado). Ao final do evento há salas com os líderes para tirar dúvidas antes de decidir.',
    link: { href: 'https://nucleoia.pmigo.org.br/reunioes-gerais', label: 'Agenda de reuniões' },
  },
];

// FAQ: perguntas reais do grupo de pré-onboarding
export const preFaq: PreFaqEntry[] = [
  {
    q: 'Por que ainda apareço como "Visitante"?',
    a: 'Todo mundo aparece como Visitante até assinar o Termo de Voluntariado. Depois da assinatura, seu papel muda automaticamente para <strong>Pesquisador</strong> ou <strong>Líder</strong>, conforme a vaga em que você foi aprovado, e as áreas da plataforma são destravadas. Não é erro: é a fase da jornada.',
  },
  {
    q: 'Já aceitei a vaga no VEP. Por que preciso assinar outro termo?',
    a: 'O aceite no volunteer.pmi.org é o passo global do PMI. No Brasil, a <strong>Lei do Voluntariado (nº 9.608/1998)</strong> e a <strong>LGPD</strong> exigem um passo a mais: o Termo de Adesão ao Serviço Voluntário, assinado digitalmente na plataforma. São dois atos diferentes e ambos são necessários.',
  },
  {
    q: 'O botão de assinar o termo não aparece (ou aparece "em atualização"). O que faço?',
    a: 'Duas causas comuns: (1) faltam pré-requisitos, como perfil completo (nome, telefone, endereço completo, data de aniversário) e filiação PMI ativa a um capítulo brasileiro; a tela "Minhas pendências" lista o que falta; (2) o termo está temporariamente pausado para atualização jurídica; nesse caso não é nada do seu lado: você será avisado por e-mail e pelo grupo quando a assinatura reabrir.',
  },
  {
    q: 'O sistema não reconhece meu CEP. E agora?',
    a: 'A base de CEPs foi atualizada e passou a aceitar também CEPs complementares (de logradouro). Se o seu CEP ainda não for reconhecido, envie-o no grupo de onboarding (pode ser em mensagem privada) para incluirmos na base.',
  },
  {
    q: 'Como pego meu link público do Credly?',
    a: '1) Acesse <strong>credly.com</strong> e faça login (a mesma conta onde estão suas badges PMI). 2) Em <strong>Settings → Privacy</strong>, deixe seu perfil como <strong>Público</strong>; sem isso a plataforma não consegue ler suas certificações. 3) Abra seu perfil, copie a URL no formato <strong>credly.com/users/seu-usuario</strong> e cole no campo do Meu Perfil. Leva menos de 2 minutos e libera XP automático pelas suas badges.',
  },
  {
    q: 'Por que o Núcleo usa o Credly?',
    a: 'O Credly agrega certificações de fontes confiáveis (PMI, Microsoft, IBM e outras certificadoras) e tem API pública. A plataforma lê seu perfil público e pontua automaticamente o que é correlato a IA, machine learning, ciência de dados, gestão de projetos e liderança, alimentando a gamificação da sua jornada junto com presença em eventos, entregáveis e protagonismo.',
  },
  {
    q: 'O Credly é pago? Preciso criar conta nova?',
    a: 'É gratuito. Dá para entrar com SSO (Google, LinkedIn ou Outlook). Dica: cadastre no Credly <strong>todos os e-mails que você usa ou já usou</strong> (inclusive corporativos antigos), pois certificações emitidas para outros e-mails aparecem no seu perfil quando o e-mail está vinculado.',
  },
  {
    q: 'Minha filiação/capítulo não aparece na plataforma. Por quê?',
    a: 'Em geral é porque o seu perfil na <strong>community.pmi.org</strong> ainda não existe ou está com a opção de não exibir o capítulo. Crie o perfil (ele já nasce público por padrão) e confira a visibilidade: é por essa integração que a plataforma valida membrezia e filiação.',
  },
  {
    q: 'Preciso ser membro do PMI e filiado a um capítulo?',
    a: 'Sim, o programa é um benefício de filiados a capítulos brasileiros do PMI. Se a sua membrezia está vencida ou você ainda não é filiado, dá para resolver pelo site do PMI (há opção estudantil com desconto expressivo e o parcelamento para o Brasil, piloto do PMI Global). Se precisar, colocamos você em contato com o diretor de filiação do seu capítulo.',
  },
  {
    q: 'Quando escolho minha tribo? Onde vejo os detalhes de cada uma?',
    a: 'A escolha é liberada <strong>a partir do kickoff do ciclo</strong>, e exige o termo assinado. No kickoff, cada tema de pesquisa é apresentado com vídeo do líder, descrição, proposta de valor, marcos de entrega e LinkedIn da liderança, e há salas com os líderes ao final para tirar dúvidas. Não se preocupe em decidir antes disso.',
  },
  {
    q: 'O que significa a barra "Completude do Perfil"?',
    a: 'Ela mede os itens do seu cadastro que a jornada usa (foto, PMI ID, LinkedIn, telefone, Credly, e-mail alternativo e, para papéis operacionais, vínculo ao ciclo e ≥1 curso da Trilha PMI AI). Logo abaixo da barra aparece exatamente o que falta. Alguns itens, como a escolha de tribo, só destravam em fases seguintes; a barra não precisa estar em 100% para assinar o termo.',
  },
  {
    q: 'O que é a Trilha PMI AI e por que ela aparece como pendência?',
    a: 'É a esteira de mini-certificações de IA do PMI Global: cursos gratuitos, do básico ao intermediário, dos quais <strong>6 emitem badge no Credly</strong>. Fazer a trilha gera XP na gamificação, PDUs, e é meta do Núcleo em 2026 (70% dos voluntários ativos com 6/6). Vale começar já no pré-onboarding: o primeiro curso concluído já conta no seu perfil.',
  },
  {
    q: 'Como funcionam as reuniões do Núcleo?',
    a: 'Dois ritmos: a <strong>tribo</strong> se reúne semanalmente em torno do tema de pesquisa, com metas e entregáveis; e a <strong>reunião geral</strong> (quinzenal, às quintas 19h BRT) é um espaço de protagonismo, com a pauta montada pelos próprios pesquisadores, que reservam blocos de 5 a 30 minutos para apresentar temas, ideias e resultados. Não é reunião de status. A agenda fica sempre com dois eventos à frente em /reunioes-gerais, e as gerais são gravadas e publicadas no YouTube.',
  },
  {
    q: 'Onde encontro as gravações e os canais oficiais?',
    a: 'YouTube: <strong>youtube.com/@nucleo_ia</strong> (gravações das reuniões gerais e webinars) · LinkedIn: <strong>linkedin.com/company/nucleo-ia</strong> · Instagram: <strong>@nucleo.ia.gp</strong>. Seguir, curtir e comentar ajuda a rede a crescer, e dá projeção a você, que agora faz parte dela.',
  },
  {
    q: 'Encontrei um erro ou algo não salva. O que faço?',
    a: 'Reporte no grupo de onboarding (print ajuda muito) ou pela Central de Ajuda da plataforma. Vocês são o primeiro ciclo a passar pela jornada 100% digital: o projeto é de Pesquisa &amp; Desenvolvimento e cada erro reportado, crítica ou sugestão melhora a experiência dos próximos ciclos. Bugs de cadastro (CEP, campos que não salvam) têm sido corrigidos no mesmo dia.',
  },
];
