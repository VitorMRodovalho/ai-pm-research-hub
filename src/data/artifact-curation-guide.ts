// Guia de artefatos, revisão e curadoria (#2447): o que é artefato, como classificar, o fluxo de
// publicação e as boas práticas de quem lidera, escreve e cura.
//
// Conteúdo em pt-BR por DESIGN (mesma regra de pre-onboarding-guide.ts e volunteer-guide.ts):
// apenas o chrome da página é localizado via i18n (keys `guiaArt.*`).
//
// Fonte das regras: as próprias RPCs (complete_peer_review, complete_leader_review,
// submit_for_curation, _curation_auto_assign, curation_reviewer_sla_sweep) e a decisão do GP de
// 24/09/2026 sobre quais tipos passam por curadoria (tags.requires_curation). Se uma regra mudar
// no banco, este texto muda junto.

export interface GuideStep {
  title: string;
  who: string;
  detail: string;
}

export interface GuideRow {
  type: string;
  examples: string;
  flow: string;
}

export interface GuideFaq {
  q: string;
  a: string;
}

/** O que é artefato, e o que não é. */
export const whatIsArtifact: string[] = [
  'Um <strong>artefato</strong> é algo que a iniciativa <strong>entrega</strong> e reporta ao portfólio do Núcleo: um artigo, um e-book, um framework, um webinar, uma ferramenta, uma prova de conceito.',
  'Uma <strong>tarefa</strong> é o trabalho do dia a dia para chegar lá: reunião, registro de ausência, respostas de um questionário, vídeo de apresentação da tribo, organização interna. Tarefa fica no quadro, mas <strong>não é artefato</strong>.',
  'Na dúvida, pergunte: "isso vai aparecer no relatório do ciclo como entrega da iniciativa?" Se a resposta for sim, é artefato.',
];

/** Os tipos e para onde cada um vai. */
export const artifactTypes: GuideRow[] = [
  { type: 'Publicação', examples: 'Artigo acadêmico, artigo no LinkedIn, e-book, estudo de caso, infográfico, report', flow: 'Peer review, revisão do líder e curadoria' },
  { type: 'Framework', examples: 'Modelo, arquitetura de referência, método', flow: 'Só portfólio' },
  { type: 'Webinar', examples: 'Evento aberto, série de webinars', flow: 'Só portfólio' },
  { type: 'Ferramenta / POC', examples: 'Protótipo, ferramenta, prova de conceito', flow: 'Só portfólio' },
  { type: 'Pesquisa / Workshop', examples: 'Pesquisa de campo, material de workshop', flow: 'Só portfólio' },
];

/** Como classificar no card. */
export const howToClassify: GuideStep[] = [
  {
    title: 'Marque "Entregável reportável (Portfólio)"',
    who: 'Líder da iniciativa ou GP',
    detail: 'No card, marque a caixa <strong>📊 Entregável reportável (Portfólio)</strong>. É ela que faz o card contar como entrega no portfólio.',
  },
  {
    title: 'Escolha o tipo de artefato',
    who: 'Líder da iniciativa ou GP',
    detail: 'Logo abaixo aparece <strong>Tipo de artefato</strong>. A plataforma sugere um tipo pelo título; confira e clique em <strong>usar</strong>, ou escolha outro. Para publicação, escolha também o <strong>formato</strong> (artigo, e-book, estudo de caso...).',
  },
  {
    title: 'Confira para onde o card vai',
    who: 'Todos',
    detail: 'Abaixo do tipo, a plataforma diz se ele passa por revisão e curadoria ou vai só para o portfólio. A seção <strong>Revisão Pré-Curadoria</strong> só aparece em publicação.',
  },
];

/** O caminho de uma publicação até sair. */
export const publicationFlow: GuideStep[] = [
  {
    title: 'Peer review (colegiado da tribo)',
    who: 'Autores do card ou líder',
    detail: 'A tribo lê a peça e registra um resumo do feedback. Se o artigo já foi escrito a várias mãos, use <strong>Dispensar peer review</strong> e diga o motivo (por exemplo, "artigo colaborativo").',
  },
  {
    title: 'Revisão do líder',
    who: 'Líder da iniciativa',
    detail: 'O líder escolhe: <strong>Aprovar</strong> (segue para a curadoria), <strong>Dispensar</strong> (peça já colaborativa, também segue) ou <strong>Devolver</strong> (volta para a tribo, com uma nota obrigatória explicando o que ajustar).',
  },
  {
    title: 'Curadoria',
    who: 'Comitê de Curadoria',
    detail: 'Ao entrar na curadoria, a plataforma <strong>designa 2 pareceristas</strong> por rodízio (nunca um autor do card). Cada um avalia com a rubrica de 5 critérios em até <strong>7 dias</strong>. Há lembrete 2 dias antes do prazo; se vencer, outro curador é designado quando houver, e a gestão é avisada.',
  },
  {
    title: 'Resultado',
    who: 'Comitê de Curadoria',
    detail: 'Com as aprovações exigidas, a peça é publicada. Se o comitê pedir revisão, o card volta para a tribo com o feedback registrado na descrição, e o ciclo recomeça.',
  },
];

/** Boas práticas. */
export const goodPractices: string[] = [
  '<strong>Um card por artefato.</strong> Não duplique cards ("cópia"): o portfólio conta cada card como uma entrega.',
  '<strong>Classifique ao criar</strong>, não no fim do ciclo: o portfólio e os relatórios leem a classificação o tempo todo.',
  '<strong>Tarefa não entra no fluxo de publicação.</strong> Se uma tarefa entrou por engano, o líder usa <strong>Devolver</strong> com uma nota.',
  '<strong>Atribua os autores no card.</strong> São eles que recebem os avisos de cada etapa, e é por eles que a curadoria evita designar o próprio autor.',
  '<strong>Anexe o artefato no card</strong> (arquivo ou link) antes do peer review. Sem ele, ninguém tem o que avaliar.',
  '<strong>Nunca coloque senha ou credencial em comentário.</strong> Os comentários são lidos por quem acessa o quadro. Use um cofre de senhas ou um documento com acesso restrito.',
  '<strong>Use as datas do card</strong> (baseline e forecast): é por elas que o portfólio mostra o planejado contra o realizado.',
];

/** Quem é avisado de quê. */
export const whoIsNotified: GuideRow[] = [
  { type: 'Card entra na curadoria', examples: 'Os 2 pareceristas designados (na hora) e o comitê', flow: 'Aviso na plataforma e e-mail' },
  { type: 'Prazo do parecer em 2 dias', examples: 'O parecerista designado', flow: 'Lembrete na plataforma e e-mail' },
  { type: 'Parecer vencido', examples: 'A gestão do Núcleo', flow: 'Aviso na plataforma e e-mail' },
  { type: 'Mudança de etapa do card', examples: 'Os autores atribuídos ao card', flow: 'Aviso na plataforma' },
];

export const faq: GuideFaq[] = [
  {
    q: 'Não vejo a seção "Revisão Pré-Curadoria" no meu card. Por quê?',
    a: 'Ela só aparece em card marcado como <strong>Entregável reportável</strong> com um tipo de <strong>publicação</strong>. Framework, webinar, ferramenta, POC, pesquisa e workshop vão para o portfólio sem curadoria. Se o card é uma publicação e a seção não aparece, peça ao líder para conferir a classificação.',
  },
  {
    q: 'Quem pode classificar o tipo de artefato?',
    a: 'O líder da iniciativa e a gestão do Núcleo, as mesmas pessoas que marcam o card como entregável de portfólio. Os autores podem sugerir o tipo ao líder.',
  },
  {
    q: 'O card entrou no fluxo de revisão, mas não é artefato. E agora?',
    a: 'O líder abre o card e usa <strong>Devolver</strong>, com uma nota curta ("não é artefato"). O card volta a ser tarefa comum e sai do fluxo.',
  },
  {
    q: 'Quando posso dispensar o peer review?',
    a: 'Quando a peça já foi construída em conjunto pela tribo (artigo colaborativo). A dispensa exige um motivo, que fica registrado no histórico do card.',
  },
  {
    q: 'Quem escolhe os pareceristas da curadoria?',
    a: 'A plataforma, por rodízio: quem tem menos pareceres em aberto é designado primeiro, e nunca um autor do card. Cada peça recebe 2 pareceristas.',
  },
  {
    q: 'O artefato precisa estar no Drive?',
    a: 'Anexe o arquivo ou o link no card antes do peer review. Os pareceristas avaliam o que estiver anexado.',
  },
];
