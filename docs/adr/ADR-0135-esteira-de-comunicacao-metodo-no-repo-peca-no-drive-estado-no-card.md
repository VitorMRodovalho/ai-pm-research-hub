# ADR-0135 - Esteira de comunicação entregue ao time voluntário: método num repositório privado, peça no Drive, estado no card do Hub

**Status:** Proposta (20/11/2026). Os pesos dos critérios e as decisões da seção "Decidido" foram escolhidos pelo GP em 20/11/2026, em caixas de decisão. A ADR vira Aceita com o "aprovado" do GP sobre este texto.
**Relacionadas:** ADR-0002 do portfólio (visibilidade de repositório), ADR-0010 (wiki narrativa, dado operacional em SQL), ADR-0026 (`manage_comms`), ADR-0007 (`can()`), ADR-0008 (palestrante externo), ADR-0107/0108/0124 (acesso a Drive pelo vínculo), ADR-0133, ADR-0134.

---

## Contexto (medido em 20/11/2026 por outras sessões; cada item marca a fonte)

- **Hoje a esteira mora numa sessão de Claude Code.** Ela produz peças (post, capa, vídeo) com QA determinística (lint de copy, recorte por canal) e entrega um pacote com md5. O time voluntário de comunicação não tem Claude Code nem terminal, e o GP quer que o time revise e publique.
- **O time existe na plataforma** (medido pela orquestradora): a iniciativa "Hub de Comunicação", com um board e 6 vínculos ativos. `manage_comms` vem dos pares voluntário x {manager, deputy_manager, co_gp, comms_leader}; `comms_member` não tem (ADR-0026), então não agenda post.
- **Dores relatadas no grupo do time** (conversa interna de 20/11/2026 entre membros do time e uma colaboradora assíncrona, descrição agregada): engajamento baixo das tribos com as pautas do hub, com retorno muito baixo das iniciativas já tentadas; conteúdo concentrado nos líderes de tribo, com pesquisadores receosos de se expor; colaboradores com tempo só assíncrono; e dúvida sobre o foco (comunicação interna ou externa) diante da capacidade do time. As propostas da conversa vão na direção da regra de protagonismo do Núcleo: conteúdo centrado no pesquisador e cadência semanal, com uma edição de newsletter desdobrada em vários posts.
- **O card já tem o que uma fila precisa** (código lido): revisor, prazo, checklist, comentário, e arquivo do Drive ligado ao card sem upload (`drive_links register_file`).
- **A fila de agendamento não tem estado de aprovação** (código lido): quem tem `manage_comms` agenda direto. O portão hoje só pode ser o card.
- **`/admin/comms-ops` abre o board errado** (medido): pega o board ativo mais novo com `domain_key='communication'`, que não é o do Hub. A correção está numa lane, sem PR. O menu do workspace já abre o board do Hub pelo id.
- **Peça carrega nome e foto de membro.** A base é a cláusula 11 do termo de voluntariado, e `comms_clearance` fica falso quando há revogação registrada (migration 20260805000314, #729). Uso de imagem nunca é condição de participação (ADR-0133).
- **O Drive de trabalho do Hub já está ligado à iniciativa, mas tem dois limites** (medidos em 20/11/2026 pela lane de comunicação, só leitura, e corrigidos no mesmo dia):
  - a pasta pertence à conta pessoal de um voluntário, não a uma conta da organização;
  - a revogação automática (ADRs 0107/0108/0124) cobre o desligamento do Núcleo, não a saída de uma iniciativa: quem sai do Hub e continua ativo no Núcleo mantém o acesso, por herança das pastas acima ou por concessão direta na pasta do Hub.
  - Por isso, "o acesso sai com o vínculo" vale para quem deixa o Núcleo, e mesmo assim é hipótese até a revogação ser exercitada.
- **A correção de `/admin/comms-ops` está em PR** (#3133), com o "pode publicar" do GP.
- **"Liderança de comunicação" aponta dois campos diferentes no cadastro:** o papel `leader` no vínculo com o Hub e a designação `comms_leader`, que é a que dá `manage_comms`. Hoje estão com pessoas diferentes.
- **O mesmo desenho deve servir depois a um capítulo do PMI** (diretoria de inovação e tecnologia). O Policy Manual do PMI (jul/2025, §10.1.2) exige que todo material de marketing com a marca do capítulo seja revisado e aceito pelo papel de marketing e comunicação da diretoria antes de publicar (lido no PDF local).

## Opções comparadas

1. **Repositório de comunicação no GitHub do Núcleo**, com Actions para as checagens determinísticas.
2. **Hub de comunicação do portal**, com a peça trocada por tabelas SQL e um responsável por peça.
3. **Pastas do Drive mais Canva** (ou a ferramenta que o time já usa), com checklist.

## Portão eliminatório (passa ou não passa)

| | G1 contas da organização, MFA, saída documentada | G2 LGPD: peça com pessoa nunca em lugar público, acesso sai com a pessoa | G3 cadeia de PI conferida nos termos |
|---|---|---|---|
| 1 repo, **como casa da peça** | passa com condição: membros numa organização com 2FA obrigatório | **não passa**: foto em histórico de git não se apaga de verdade, e sair da organização no GitHub não acompanha o fim do vínculo | passa |
| 1 repo, **só como casa do código** | passa com a mesma condição | passa: não leva peça nem dado de pessoa | passa |
| 2 hub | passa: login da plataforma, autoridade por `can()` | passa: RLS e vínculo | passa |
| 3 Drive + Canva | **passa só com condição**: hoje a pasta do Hub é de conta pessoal; passa quando a pasta de trabalho da esteira nascer numa conta do Núcleo (decisão do GP, 20/11/2026: pasta nova, com cópia do conteúdo atual, sem transferir a pasta pessoal). Canva em conta da organização (decisão do GP, 20/11/2026) | **passa só com condição**: acesso por concessão da plataforma, revogação exercitada uma vez com controle positivo, e concessão direta de quem sai do Hub revista à mão enquanto o detector não cobrir a saída de iniciativa; o Canva só edita, e o arquivo final e a foto de membro moram no Drive | passa |

Consequência: o repositório sai do páreo como casa da peça e continua como casa do código. O Canva entra como ferramenta de edição na conta da organização, e o arquivo final volta ao Drive. A decisão sobre a conta não mudou nenhum grau da pontuação: o grau de C5 da opção 3 vem do compartilhamento manual, não da conta.

## Pontuação (pesos da opção A; escala 0 a 3; nota = soma de peso x grau / 3)

| critério | peso | 1 repo | 2 hub | 3 Drive + Canva | combinação |
|---|---|---|---|---|---|
| C1 autonomia do voluntário sem Claude Code nem terminal | 25 | 1: PR e upload de imagem pela web são atrito para quem não usa git | 2: card pela web; `comms_member` não agenda | 3: ferramentas do próprio time | 3: o voluntário só usa Drive, Canva e card |
| C2 rastreabilidade (revisou, aprovou, publicou) | 20 | 3: revisão de PR e histórico | 2: comentários e revisor no card; aprovação não é estado | 1: histórico de versão, sem registro de aprovação | 2: trilha no card, método versionado no repo |
| C3 estabilidade (versão fixa e dono) | 15 | 3: tag e dono | 1: tabela não versiona texto | 1: checklist em doc deriva | 3: checagens fixadas por tag no repo |
| C4 custo e manutenção para o Núcleo | 15 | 1: workflows a manter; minutos de Actions em repo privado (não medido) | 2: já existe; falta a correção da página | 2: barato, mas a cobrança fica manual | 2: três lugares, cada um no seu papel |
| C5 governança além do portão (menor privilégio, ativo pessoal) | 10 | 2: times do GitHub fora da autoridade da plataforma | 3: `can()` por papel | 1: compartilhamento manual | 2: estado e autoridade pela plataforma, mas no Drive a saída de uma iniciativa não revoga acesso, e a pasta herda acesso das pastas acima (medido 20/11) |
| C6 reuso pelo capítulo | 15 | 3: um código, um perfil por organização | 0: o portal é do Núcleo e o controlador LGPD do capítulo é outro | 2: o capítulo tem Workspace próprio; o método vira cópia de checklist | 2: o repo de método se reusa; Drive e estado são de cada organização |
| **nota** | 100 | **70,0** | **55,0** | **60,0** | **80,0** |

A combinação foi pontuada com os mesmos graus e as mesmas justificativas das opções puras. A nota do repo puro conta só para comparar: como casa da peça ele já tinha saído no portão.

## Decisão

**Combinação, cada camada num lugar só:**

| o quê | onde | por quê |
|---|---|---|
| a peça (arquivo de trabalho e final) | pasta nova da esteira numa conta do Núcleo, ligada à iniciativa na plataforma, uma subpasta por peça | o time já usa; cumpre G1 e G2 só depois das duas condições do portão |
| estado, responsável, revisor, prazo, aceite e link publicado | card no board do Hub, com o arquivo do Drive ligado (`register_file`) | dado que muda toda semana vai para o banco (ADR-0010); o card já tem os campos |
| método: checagens determinísticas, checklists, perfil de marca e voz da organização | repositório **privado** novo na organização do Núcleo no GitHub, com o perfil separado do código | repositório novo nasce privado (ADR-0002 do portfólio); versiona texto e código |
| guia do processo | wiki | conhecimento narrativo (ADR-0010) |

**Regras que vêm junto:**
- A esteira serve ao protagonismo do pesquisador: o conteúdo vem de quem pesquisa, e o time de comunicação dá forma à peça. A sessão de Claude Code é uma das produtoras possíveis, não a única.
- Tudo é assíncrono (card, prazo, comentário). Nenhuma etapa depende de alguém estar numa reunião.
- Nenhuma peça, foto ou gravação entra no repositório. Gravação bruta segue o fluxo de publicação do YouTube, no Drive.
- Cada checagem é um script com teste e com um controle positivo que prova que ela consegue reprovar.
- Cada skill ou checklist copiado de outra fonte fica fixado numa versão, com a origem registrada e um dono nomeado por papel. Só se atualiza por decisão de quem mantém.
- Se algum método reusado for ativo pessoal de alguém, o programa usa sob licença escrita, e o conflito de interesse é declarado.
- O Canva é usado só na conta da organização. Quem sai do time é retirado dela no mesmo dia em que o vínculo termina, e quem tem a designação `comms_leader` confere isso.
- A esteira usa uma pasta nova numa conta do Núcleo, que recebe uma cópia do conteúdo atual; a pasta pessoal não é transferida. A pasta nova é ligada à iniciativa na plataforma, para que o acesso venha só do vínculo, e peça nova nasce nela. A pasta herda o acesso das pastas acima, que é mais largo que o time; isso é aceito porque quem herda é membro ativo sob o mesmo termo, e o acesso cai quando a pessoa deixa o Núcleo. Quem sai do Hub e continua no Núcleo tem a concessão direta revista à mão pela liderança de comunicação, até o detector cobrir a saída de iniciativa. As concessões de quem saiu são medidas e revogadas (decisão do GP, 20/11/2026).
- Neste texto, "liderança de comunicação" quer dizer quem tem a designação `comms_leader` (decisão do GP, 20/11/2026), que é também a que dá `manage_comms` para publicar. O papel `leader` no vínculo com o Hub não decide revisão nem publicação.
- O piloto só começa com a correção de `/admin/comms-ops` em produção, para que o time tenha uma porta só para o board do Hub (decisão do GP, 20/11/2026).
- O voluntário não precisa de terminal: as checagens rodam do lado de quem produz, e o relatório entra no card como item do checklist. Rodar a checagem pela web (Action sobre o arquivo, ou tela no portal) é passo posterior, decidido com o que o piloto medir.

## RACI (por papel)

R = executa, A = responde, C = consultado, I = informado.

| atividade | pesquisador | produtor da peça | liderança de comunicação | membro de comunicação | GP / deputy GP | papel de marketing do capítulo | mantenedor do método | orquestradora |
|---|---|---|---|---|---|---|---|---|
| fornecer o conteúdo (aprendizado, achado, entrevista) e aprovar como aparece | R | C | I | C | I | | | |
| preparar a peça e abrir o card | C | R | I | R (quando é o produtor) | A | | | |
| rodar as checagens e anexar o relatório | | R | | | A | | C | |
| revisar | | | R | C | A (revisa quando a liderança é a autora) | | | |
| aprovar ("pode publicar") | | | C | | R/A | | | |
| aceite do capítulo (só peça com a marca dele) | | | I | | C | R/A | | |
| publicar e pôr o link no card | I | | R | | R/A | | | |
| manter checagens, checklists e perfil | | | C | | A | | R | |
| manter board, card e página do hub | | | I | | A | | | R |

"Produtor da peça" é um papel, não uma pessoa: pode ser um membro de comunicação ou a sessão de Claude Code. O pesquisador que dá o conteúdo vê a peça antes da revisão, porque o nome e o mérito são dele. O mantenedor do método é o GP até haver papel designado.

## Definição de pronto (por peça)

1. Arquivo final no Drive do Hub, ligado ao card.
2. Lint de copy aprovado, relatório no card.
3. Guia de marca conferido e recorte por canal aprovado.
4. `comms_clearance` verdadeiro para cada pessoa que aparece; quem não assinou ou revogou fica fora. Convidado externo tem consentimento próprio (ADR-0008).
5. Peça com a marca do capítulo: aceite do papel de marketing e comunicação do capítulo, registrado no card.
6. Revisão registrada no card pelo revisor atribuído, dentro do prazo.
7. "pode publicar" do GP como comentário no card.
8. Publicado, link do post no card, card em done.

## Caminho de volta (peça reprovada)

1. O revisor comenta no card o motivo, com uma categoria fixa: copy, marca, consentimento, fato, recorte, outro.
2. O card volta para in_progress com o mesmo autor.
3. O autor corrige, roda as checagens de novo e devolve para review.
4. Na segunda volta da mesma peça, o card sobe ao GP, que decide entre corrigir, refazer ou arquivar.
5. Falha de consentimento não volta: a pessoa sai da peça ou a peça é arquivada.

## Piloto

- **Peça:** post de LinkedIn do Núcleo (texto e imagem), só peças do Núcleo, sem a marca do capítulo.
- **Conteúdo:** um post semanal de aprendizado escrito a partir do conteúdo de um pesquisador, e uma edição de newsletter desdobrada em posts.
- **Duração e volume:** 3 semanas a partir da apresentação ao time, que só acontece depois da correção da página do hub e da pasta nova no Drive; 6 posts propostos.
- **Medidas, decididas antes de começar,** lidas de comentários com etiqueta fixa no card, sem código novo:
  - M1, tempo da peça pronta à publicação, em dias úteis;
  - M2, parcela de peças devolvidas, por categoria de motivo;
  - M3, onde o voluntário trava, por categoria;
  - M4, parcela de posts com conteúdo de pesquisador.
- **Para na hora** se um post sair sem o consentimento de quem aparece nele ou sem o "pode publicar".

## O que fica reutilizável para o capítulo

- **Reusa:** o repositório de método (checagens, testes, checklists), com um perfil do capítulo (marca, voz, aprovador, canais); este RACI e esta definição de pronto como modelo; as medidas do piloto.
- **Não reusa:** o Drive, as contas de rede social (titular e admins próprios), o board e o portal, o aprovador, e a base LGPD (outro controlador). O logo vem só do portal de marketing do PMI, e o site do capítulo não é destino automático.
- É proposta para a diretoria de 2027, depois que ela tomar posse, não implantação.

## Consequências

- O time revisa e publica sem Claude Code, e o GP sai do caminho crítico de tudo menos do "pode publicar".
- Enquanto a fila de agendamento não tiver estado de aprovação, o portão é o card. Pôr a aprovação na fila é migration, decidida depois do piloto.
- A esteira resolve o fluxo da peça, não o engajamento das tribos. Ela tira atrito de quem quer contribuir; trazer o pesquisador para contribuir continua sendo trabalho do time e das lideranças, e o piloto mede se isso aconteceu (M4).
- Três lugares pedem disciplina: cada um guarda só a sua camada, e o card aponta para os outros dois.

## Decidido pelo GP em 20/11/2026

- Pesos dos critérios: opção A, com o portão G1 a G3.
- O piloto espera a correção da página do hub.
- A conta do Canva é da organização.
- Pasta da esteira: pasta nova numa conta do Núcleo, com cópia do conteúdo atual, sem pedir transferência da pasta pessoal.
- As concessões manuais de quem saiu são medidas e revogadas, uma escrita por vez com o OK do GP.
- Revisor e prazo, como a lane propôs: a liderança de comunicação revisa; o GP ou o deputy GP cobrem quando ela é a autora; prazo de revisão de 2 dias úteis para post de LinkedIn.
- Quem revisa, no campo do cadastro: a designação `comms_leader`.
