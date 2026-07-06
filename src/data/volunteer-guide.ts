// Guia do Voluntário - conteúdo didático de apoio ao Termo de Adesão
//
// Conteúdo em pt-BR por DESIGN: o glossário §13 acima nesta mesma página é
// extraído do content_html da Política (documento lacrado em pt-BR) e é servido
// em português mesmo nos locales /en e /es. Este guia segue a mesma regra para
// manter a página coerente. Apenas o chrome (títulos/rótulos de seção, botões)
// é localizado via i18n (keys `glossario.guide.*`). As referências de cláusula
// são independentes de idioma e ficam aqui.
//
// Não é fonte legal: em divergência, prevalece o Termo/Política (Cláusula 13.5).

export interface GuideItem {
  text: string;
  ref: string;
}

export interface FaqEntry {
  q: string;
  a: string;
  ref: string;
}

export interface FlowBranch {
  answer: 'SIM' | 'NÃO';
  path: string;
  when: string;
  intro: string;
  steps: string[];
  result: string;
}

// O que o voluntário MANTÉM
export const keepItems: GuideItem[] = [
  { text: 'Seus <strong>direitos morais</strong> (autoria, crédito, integridade). São inalienáveis e ninguém pode tirar.', ref: 'Cl. 2.1' },
  { text: 'O direito de <strong>publicar</strong> seu trabalho, com atribuição ao Núcleo.', ref: 'Cl. 2.3 e 2.4' },
  { text: 'A liberdade de <strong>sair a qualquer momento</strong>, sem ônus.', ref: 'Cl. 6' },
  { text: 'Suas <strong>obras anteriores e independentes</strong>, que você pode declarar como suas.', ref: 'Declaração de Exclusão' },
];

// O que o voluntário CONCEDE
export const grantItems: GuideItem[] = [
  { text: 'Uma <strong>licença não-exclusiva e gratuita</strong> ao Núcleo, para uso educacional e científico.', ref: 'Cl. 2.2' },
  { text: 'Isso <strong>não é cessão</strong>: você não transfere a propriedade, e não abrange obras futuras em bloco.', ref: 'art. 51' },
  { text: 'O compromisso de <strong>creditar o Núcleo</strong> quando publicar (fórmula de atribuição).', ref: 'Cl. 2.4' },
];

// Fluxograma Path A / Path B
export const flow = {
  start: 'Você quer submeter sua obra a um periódico, repositório, editora ou evento externo.',
  decision: 'O destino publica sua obra sob licença aberta <strong>CC-BY 4.0</strong> ou <strong>CC-BY-SA 4.0</strong>?',
  branches: [
    {
      answer: 'SIM',
      path: 'Path A',
      when: 'automático',
      intro: 'Você mesmo resolve, na plataforma.',
      steps: [
        'Preenche um checklist de 4 itens (sem conflito de interesse; sem embargo maior que 6 meses; sem cessão exclusiva pendente; periódico confirmado como CC-BY / CC-BY-SA, com link).',
        'Cumpridos os 4, o re-licenciamento é deferido na hora.',
        'Você e o Núcleo publicam em paralelo, sob licenças compatíveis.',
      ],
      result: 'Resultado: siga em frente, com atribuição.',
    },
    {
      answer: 'NÃO',
      path: 'Path B',
      when: 'Comitê de Curadoria',
      intro: 'Exige exclusividade, embargo maior que 6 meses, CC-BY-NC / ND, licença proprietária, ou há conflito.',
      steps: [
        'O Comitê decide em 15 dias úteis (prorrogáveis por mais 15; gate opcional de 45 dias para parecer externo).',
        'Pode aprovar: suspensão temporária (standby) da licença por até 24 meses (teto de 48); versão prévia como contribuição autônoma; ajuste da atribuição; ou negativa fundamentada.',
        'Durante o standby, você pode dar exclusividade ao periódico.',
      ],
      result: 'Resultado: decisão registrada em ata.',
    },
  ] as FlowBranch[],
};

// FAQ
export const faq: FaqEntry[] = [
  { q: 'Assinar este termo cria vínculo de emprego?',
    a: 'Não. É serviço voluntário (Lei 9.608/1998), sem vínculo trabalhista, previdenciário, fiscal ou financeiro com o PMI-GO.',
    ref: 'Cláusula 1' },
  { q: 'Eu perco os direitos das minhas obras?',
    a: 'Não. Você mantém os direitos morais (autoria, crédito, integridade), que são inalienáveis. Ao Núcleo você concede apenas uma licença não-exclusiva e gratuita para uso educacional e científico, e não uma cessão de propriedade.',
    ref: 'Cláusulas 2.1 e 2.2' },
  { q: 'Posso publicar meu trabalho num periódico ou livro?',
    a: 'Sim, sempre com a atribuição ao Núcleo. Se o periódico exigir exclusividade, embargo ou licença restritiva, siga o fluxo Path A / Path B explicado acima. Licenças abertas permitem inclusive uso comercial pela editora; a única exigência é o crédito.',
    ref: 'Cláusulas 2.3, 2.4 e 2.6' },
  { q: 'Antes de submeter: o que eu preciso avisar ao GP?',
    a: 'Com pelo menos 15 dias de antecedência, você informa ao Gerente de Projeto: a obra, o destino (periódico, repositório ou evento), a política editorial, o prazo de embargo e a licença exigida. Com isso o Núcleo classifica em Path A (automático) ou Path B (comitê). Para Track A, o GP pode pedir revisão, mas não veta.',
    ref: 'Cláusulas 2.4 e 2.6.1' },
  { q: 'Como funciona a suspensão (standby) da licença no Path B?',
    a: 'Quando o Comitê aprova um standby, a licença sobre aquela obra específica fica suspensa por até 24 meses (padrão), com teto de 48. Durante esse período: o Núcleo não publica, distribui nem cria derivados daquela obra (suas outras obras seguem normais); você pode conceder exclusividade ao periódico; e a licença do Núcleo não se extingue, apenas deixa de ser exercida. Quando o embargo termina, ou se houver rejeição ou desistência antecipada, a licença é restabelecida automaticamente na data da comunicação, e você avisa o GP. Você também inclui uma nota de agradecimento ao Núcleo na publicação, ou no seu perfil de autor caso o periódico não permita.',
    ref: 'Cláusulas 2.6.3 a 2.6.9' },
  { q: 'O que registra a decisão do Path B?',
    a: 'Toda decisão de Path B vira uma ata na plataforma, com voto nominal, fundamentação, eventual voto divergente e declaração de conflito de interesse de cada votante. Você, como autor, tem voz consultiva sobre a sua própria obra, sem voto. Isso garante rastreabilidade e imparcialidade.',
    ref: 'Cláusula 2.6.10' },
  { q: 'O que é a "atribuição obrigatória"?',
    a: 'Uma frase-padrão que identifica você como autor e o Núcleo (PMI-GO) como origem, junto com a licença. Ela deve constar de forma legível em toda publicação externa. O texto exato está no seu Termo.',
    ref: 'Cláusula 2.4' },
  { q: 'Trouxe uma tese, artigo ou metodologia de antes. O Núcleo fica com isso?',
    a: 'Não, desde que você registre esses ativos na Declaração de Exclusão de Propriedade Intelectual, listando cada um de forma detalhada com prova de anterioridade. Obra 100% sua e anterior fica fora do regime de obra coletiva.',
    ref: 'Declaração de Exclusão (instrumento próprio)' },
  { q: 'E se a minha criação virar patente ou marca?',
    a: 'Só se ela for selecionada para registro, após análise de viabilidade. Nesse caso, você assina um Termo de Cessão específico daquele ativo, no ato do depósito no INPI, e continua reconhecido como inventor ou autor. Não é uma cessão de tudo em bloco: vale ativo por ativo.',
    ref: 'Termo de Cessão de Direitos Patrimoniais' },
  { q: 'Vocês vão usar minha imagem e voz?',
    a: 'Apenas com o seu consentimento, para divulgação institucional e promocional do trabalho voluntário, sem uso comercial. Você pode revogar esse consentimento a qualquer momento, sem efeito retroativo.',
    ref: 'Cláusula 11' },
  { q: 'Moro na União Europeia ou no Reino Unido. Muda algo?',
    a: 'Sim. A Cláusula 14 trata da transferência internacional dos seus dados ao Brasil, com salvaguardas específicas (cláusulas-padrão contratuais) e o seu consentimento, também revogável. Para quem mora no Brasil, essa cláusula não se aplica.',
    ref: 'Cláusula 14' },
  { q: 'Como eu me desligo do Núcleo?',
    a: 'A qualquer momento, sem ônus. Ao sair, ficam preservados os seus direitos morais, os créditos e as licenças que você já concedeu sobre obras concluídas, além do reconhecimento do trabalho feito.',
    ref: 'Cláusulas 6 e 15.4.5' },
  { q: 'O termo pode mudar depois que eu assinar?',
    a: 'Mudança simples (redacional) é apenas informada. Mudança importante exige o seu novo aceite: você pode concordar, apresentar objeção fundamentada, ou se desligar sem prejuízo. Obras que você já constituiu seguem a versão vigente na data em que foram criadas.',
    ref: 'Cláusula 15' },
  { q: 'E os meus dados pessoais (LGPD)?',
    a: 'Você tem direito de acesso, correção, eliminação e portabilidade, exercidos junto ao Encarregado. O PMI-GO é o controlador dos dados; eles não são vendidos nem repassados a bancos de dados de terceiros.',
    ref: 'Cláusula 9' },
  { q: 'Quem é o Encarregado de dados e como falo com ele?',
    a: 'O Encarregado (DPO) é o ponto focal de privacidade entre você, a plataforma e a ANPD: Ivan Lourenço Costa (titular) e Angeline Prado (substituta). O contato é feito pela plataforma do Núcleo.',
    ref: 'Cláusula 9 e Seção 2 da Política' },
  { q: 'Onde tiro outras dúvidas?',
    a: 'Com o Gerente de Projeto (GP) para questões gerais do Núcleo, e com o Encarregado para dados pessoais. Tudo pela plataforma.',
    ref: 'nucleoia.pmigo.org.br' },
];
