# p201 WhatsApp Action Intake Map

**Data:** 2026-05-19  
**Fonte:** `/home/vitormrodovalho/Downloads/A/NucleoIA_Acoes_Pendentes_19mai2026.csv`  
**Status:** Triagem inicial para transformar mensagens WhatsApp em backlog governado.

> Nota: o ZIP informado como `WhatsApp Chat with João Coelho Júnior (PMI CE  Nucleo IA).zip` não foi localizado em `/home/vitormrodovalho/Downloads` via glob inicial. A issue do evento foi aberta com base no CSV; anexos/chat bruto devem ser reanexados quando o caminho correto estiver disponível.

---

## 1. Objetivo

Transformar ações extraídas de WhatsApp em objetos governáveis da plataforma, evitando que demandas críticas fiquem apenas em chats, áudios ou memória pessoal.

Este documento mapeia o destino recomendado para cada tipo de item:

- GitHub Issue
- Board item / checklist
- Meeting action item
- Webinar/evento
- Initiative/engagement
- Partner/relationship
- Governance/legal record
- Personal follow-up

---

## 2. Taxonomia de Destino

| Tipo no CSV | Destino primário | Destino secundário | Observação |
|---|---|---|---|
| `BUG` / `BUG/ACESSO` | GitHub Issue | Board item técnico | Exige evidência, owner, DoD e rollback quando houver código/SQL |
| `EVENTO` | `events` / webinar proposal / board item | partner/entity se externo | Se virar ciclo recorrente ou grupo de trabalho, criar Initiative |
| `WEBINAR` | webinar proposal / campaign board | Sympla/comms checklist | Comunicação precisa de janela mínima de 30 dias |
| `ACESSO` | Issue ou board item de permissions | governance docs/Drive owner | Não resolver por chat sem auditoria |
| `PRAZO` | Board item com due date | checklist ou meeting action item | Ex.: SLA curadoria |
| `REINTEGRAÇÃO` / `ONBOARDING` | member lifecycle / engagement | issue se schema/role gap | Deve passar por authority model |
| `PI/CONTRATO` | governance/legal issue | document version / approval chain | Precisa de registro formal |
| `PARCERIA` / evento externo | partner entity + partner card | initiative/event | Ex.: Universidade de Vassouras / João |
| `ÁUDIO NÃO OUVIDO` | personal follow-up task | só vira issue após conteúdo confirmado | Não transformar inferência em backlog técnico |
| `ARQUIVO NÃO REVISADO` | board item / document review | curation flow | Depende do tipo do arquivo |

---

## 3. Buckets Prioritários do CSV

### 3.1 P0/P1 Técnico já tratado ou em issues

| ID | Item | Status recomendado |
|---|---|---|
| A03 / B01 | Roberto curador + ponto focal sem acesso curadoria | Parcialmente tratado p201; manter em issue de permissions V4 |
| A06 / B03 | Attendance não atualiza em tempo real | Manter como issue técnica específica se reproduzir com evidência |
| A07 / B04 | Falta incorreta Jefferson | Verificar dados/evento antes de issue técnica |
| A15 / B06 | Tribo 07 data 19 como traço | Tratado p201 com `get_tribe_attendance_grid` hotfix |
| B02 / A14 | Notas corrompidas via Claude/MCP | Criar issue MCP/notes específica |
| B08 / A02 | Ana Carla sem acesso doc governança | Criar task de acesso/governance docs |

### 3.2 Eventos/Webinars/Iniciativas

| ID | Item | Destino recomendado |
|---|---|---|
| A01 | Mesa Redonda IA & Competências — João Coelho / Universidade de Vassouras | Issue + board item + evento; avaliar se vira initiative |
| A04 | Dry run Tribo 06 20/05 | Board item / meeting action |
| A10 | PMI Global Summit Detroit | Issue/proposal track |
| A12/A13 | Agenda de webinares + Sympla/Comms | Webinar pipeline + comms board |
| A27 | PI/contrato webinar Débora | Governance/legal issue |

### 3.3 Pessoas/Engagements

| ID | Pessoa | Destino recomendado |
|---|---|---|
| A11 | Rogério Peixoto reintegração como observer T07 | Member lifecycle / engagement decision |
| A16 | Vinicyus acesso Drive T07 | Access task |
| A22 | 3 pedidos entrada Tribo 02 | Initiative invitations / request-to-join triage |
| A23 | Novo membro canadense Tribo 01 | Intake/onboarding verification |
| A24 | CPMAI QA/QC Herlon | CPMAI initiative board + authority issue #160 |
| A25 | Alexandre observer | Member lifecycle / engagement |

### 3.4 Follow-ups pessoais / baixa estrutura

Não abrir issue técnica sem confirmar conteúdo:

- áudios não ouvidos;
- fotos sem contexto;
- mensagens com “algum feedback?” sem identificação;
- follow-ups pessoais com Mario/Fernando/Ligia.

Esses devem virar uma lista pessoal/PM action ou board privado, não backlog público.

---

## 4. João Coelho — Webinar / Iniciativa

### Contexto confirmado do CSV

- Evento: **Inteligência Artificial e o Futuro das Competências**
- Data: **02/06/2026**
- Horário: **19:10–21:30**
- Local/formato: **Online + Universidade de Vassouras, polo Saquarema**
- Público: **Engenharia de Software**
- Organizador externo/parceiro: **João Coelho Júnior / PMI-CE**
- Formato operacional: mesa redonda com Google Meet/Teams + YouTube ao vivo.
- Possíveis palestrantes: Vitor, Ana, Débora/Fernando/Hayala/Letícia/Sara conforme disponibilidade e fit com público de engenharia de software.
- Observação: Fabricio não poderá participar na data.
- Possível envolvimento: PMI-RJ, Sympla, canal do Núcleo e canal do evento.
- Canal informado por João para transmissão: `https://www.youtube.com/@sestec.software`.
- João mobilizou alunos para marketing/divulgação; há coordenação local, time de comunicação dos alunos, coffee-break e patrocínios/prêmios em discussão.
- Grupo WhatsApp de planejamento já foi criado/separado; o link deve ser tratado como dado operacional privado e armazenado no portal/metadados da iniciativa, não em documento público.

**Nota de privacidade:** não registrar em docs/issues públicas empresas atuais/passadas de Sarah. Caso Sarah participe, usar apenas descrição pública/segura do perfil: engenharia de sistemas, infraestrutura/data centers e perspectiva profissional complementar.

### Decisão de modelagem

Este item deve ser tratado como **evento externo/parceria + possível iniciativa**, não apenas webinar simples.

Destino recomendado:

1. **GitHub Issue** para planejar.
2. **Partner entity** para Universidade de Vassouras / João, se ainda não existir.
3. **Event row** para a data quando confirmado.
4. **Initiative** para planejamento e execução, com João como owner/coordinator operacional, sem alterar sua tribo de pesquisador.
5. **Board item/checklist** para tarefas:
   - confirmar público;
   - validar palestrantes;
   - confirmar Fabricio indisponível;
   - mapear substitutos;
   - alinhar com líderes;
   - decidir Sympla;
   - alinhar canal do Núcleo + canal local de YouTube;
   - envolver time de alunos/comunicação/coordenacao local no planejamento;
   - criar briefing;
   - abrir iniciativa no portal se confirmado;
   - registrar WhatsApp privado da iniciativa no metadado adequado;
   - criar/vincular pasta Drive quando necessária;
   - carregar pessoas/engagements;
   - preparar comunicação.

### Perguntas de decisão

- É evento único, webinar, ou início de uma iniciativa com alunos?
- Será público do Núcleo, PMI-CE, PMI-RJ, Universidade, ou misto?
- Haverá captação de leads/voluntários?
- Os alunos entrarão como `visitor_leads`, `candidate`, `observer`, `study_group_participant` ou outro kind?
- João será owner/coordinator operacional da iniciativa? Se sim, qual `engagement kind/role` melhor modela isso sem conflito com sua tribo atual?
- Qual é o papel do João: partner contact, speaker, organizer, liaison?
- O grupo de alunos/comunicação local deve entrar como contatos externos, visitor leads ou participantes da iniciativa?
- O evento será transmitido também no canal do Núcleo?
- Sympla será usado agora ou ficará para edição futura?

---

## 5. Issues Recomendadas

Criar issues:

1. **Pipeline WhatsApp → backlog governado** — GitHub #168
2. **Evento/Iniciativa João Coelho — IA & Competências 02/06** — GitHub #169
3. **MCP/notes corruption via Claude** — GitHub #170
4. **Acesso Ana Carla a docs de governança** — GitHub #171
5. **Agenda webinares + Sympla + comunicação 30 dias** — GitHub #172
6. **Reintegração Rogério / observer T07** — GitHub #173

Itens técnicos já cobertos por p201 ou issues existentes não devem duplicar.

---

## 6. Regra de Governança

Itens vindos de WhatsApp só entram na plataforma quando tiverem:

- fonte;
- pessoa responsável;
- categoria;
- evidência mínima;
- destino correto;
- nível de privacidade;
- próxima ação clara.

Áudios não ouvidos e inferências devem ficar como **pendentes de verificação**, não como fatos.
