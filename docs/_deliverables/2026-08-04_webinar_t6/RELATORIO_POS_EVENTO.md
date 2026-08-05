# Relatório pós-evento — 1º Webinar da Tribo 6 (ROI & Portfólio)

**Evento:** Aplicações Práticas de IA (IA na priorização, na análise de cenário e na segurança da informação)
**Quando:** terça, 04/08/2026, 19h00 às 20h18 (Brasília). Conteúdo de 19h05 a 20h18, 73 min.
**Onde:** Airmeet · aberto ao público · gravado
**Registro na plataforma:** webinar `4ff3a888-8959-4262-82e6-a6f54ffc3964` · evento `17497fca-c035-4d9a-8c37-9b721447c9fe`

> Fonte de todos os números: exports do Airmeet baixados em 05/08 às 00h04 (master, qna, chat, resource,
> in_session_cta, survey) e consultas à plataforma feitas em 05/08. Os CSVs com PII ficam fora do
> repositório. Nenhum e-mail ou nome de participante externo aparece aqui.

## 1. O funil

| medida | valor |
| --- | --- |
| inscritos | 127 |
| presentes | 61 |
| **taxa de comparecimento** | **48,0%** |
| entraram na sessão ao vivo | 60 |
| assistiram só pelo replay do Airmeet | 2 |
| entraram no lounge / networking | 0 |

Quebra por histórico, que é o dado mais acionável do lote:

| | inscritos | presentes | comparecimento |
| --- | --- | --- | --- |
| novos (1º evento do Núcleo) | 62 | 23 | **37,1%** |
| recorrentes | 65 | 38 | **58,5%** |

Quem já veio antes comparece a uma taxa 1,6× maior. A divulgação trouxe metade da base como gente nova,
e essa metade é a que evapora entre a inscrição e a sala.

## 2. Retenção

Tempo assistido, entre os 61 presentes: mediana **53 min**, média 51,5 min, sobre uma sessão de 73 min.
Mediana equivale a **73% da sessão**.

| corte | presentes |
| --- | --- |
| ≥ 5 min | 57 |
| ≥ 20 min | 45 |
| ≥ 45 min | 34 |
| ≥ 60 min | 26 |

Não houve queda concentrada: a curva é suave. Três pessoas ficaram menos de 5 min.

## 3. Interação

| medida | valor |
| --- | --- |
| mensagens no feed | 39, de 23 pessoas |
| linhas no Q&A | 12, de 7 pessoas |
| **perguntas de conteúdo** | **4, de 2 pessoas** |
| reações (emojis) | 90 |
| mãos levantadas | 0 |
| respostas ao survey | 0 |
| recursos publicados / baixados | 0 |
| CTAs em sessão | 0 |

⚠️ **As 12 do Q&A não são 12 perguntas.** Oito são saudação, emoji, agradecimento ou recado de áudio.
As quatro de conteúdo foram duas sobre a arquitetura de agentes apresentada (critério de alocação de
cada agente a um LLM diferente, e técnicas de refinamento do aprendizado, com o paralelo ao Model
Context Protocol) e duas sobre governança (o WhatsApp como canal corporativo de facto sem versão
Business, e o argumento de que a IA amplifica um problema cuja causa-raiz é a governança da empresa).
Qualquer leitura de "12 perguntas" superestima o engajamento por 3×.

⚠️ **As próprias abas do Airmeet divergem entre si.** A aba de resumo do chat diz 23 pessoas no feed e
a aba de atividade diz 25; o Q&A diz 7 e a atividade diz 8. Usar sempre a mesma aba ao comparar
edições.

⚠️ **Survey com zero respostas.** Não houve pesquisa de satisfação neste webinar, então não há NPS nem
nota. Se a avaliação importa para o relatório de portfólio, ela precisa ser configurada no Airmeet
antes do evento, não depois.

## 4. Quem esteve lá, do ponto de vista da plataforma

Cruzamento dos 61 presentes contra `members` + `member_emails`, por hash de e-mail:

| | valor |
| --- | --- |
| presentes que são membros | **28** |
| presentes que não são membros | **33** |
| membros com presença já registrada antes desta apuração | 5 |
| membros com presença registrada nesta apuração | 23 |

Os 28 membros vêm de 10 capítulos (GO, CE, RS, MG, DF, RJ, PE, PR, AM, MA).

**Os 33 externos não têm registro em lugar nenhum da plataforma.** Não são membros, não entraram como
`visitor_leads` (a captura de lead é do formulário do site, não do Airmeet) e não há rota para gravar
presença de não-membro. Ou seja: a plataforma enxerga 28 de 61. Aberto em **#1602**.

## 5. Efeito nos indicadores

- **Presença do evento:** de 5 para 28 (`attendance_record action='register'`, via MCP).
- **Duração real:** o evento estava com `duration_actual = 60`; passou para **73**. Horas de impacto do
  webinar: 28 × 73 min ≈ **34 h** (era ≈ 28 h com o valor errado).
- **Meta "6+ Webinares ou Talks":** continua em **0 de 6** e **não sobe** com este webinar. A janela de
  medição de `get_annual_kpis` está congelada em 30/06/2026 e os três webinares realizados são de
  julho e agosto. O mesmo defeito segura "Eventos realizados" em 147 quando o número até hoje é 220.
  Aberto em **#1603**.

## 6. Pendências abertas por este evento

| # | item |
| --- | --- |
| #1600 | `webinar_manage` não fecha o webinar (status e youtube_url fora da rota MCP) |
| #1601 | `event_write` não alcança os campos de realização (gravação, `duration_actual`, `initiative_id`) |
| #1602 | presença de público externo e resolução de e-mail em lote não têm rota |
| #1603 | janela congelada em `get_annual_kpis` (meta de webinares e eventos realizados) |

Fora do MCP, um achado de higiene: `comms_report scope='pending_webinars'` ainda lista **três webinares
de abril** das tribos 2, 4 e 5 (`91759ba1`, `2ab12ccf`, `cd596843`) parados em `confirmed` com
"preparar follow-up pós-evento". Ou aconteceram e nunca foram fechados, ou não aconteceram e deveriam
estar cancelados.
