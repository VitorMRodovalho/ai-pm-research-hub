# Relatório pós-evento do 1º Webinar da Tribo 6 (ROI & Portfólio)

**Evento:** Aplicações Práticas de IA (IA na priorização, na análise de cenário e na segurança da informação)
**Quando:** terça, 04/08/2026, 19h00 às 20h18 (Brasília). Conteúdo de 19h05 a 20h18, 73 min.
**Onde:** Airmeet · aberto ao público · gravado
**Registro na plataforma:** webinar `4ff3a888-8959-4262-82e6-a6f54ffc3964` · evento `17497fca-c035-4d9a-8c37-9b721447c9fe`
**Gravação:** https://youtu.be/__cXwlfgtwM (pública, playlist Webinars, 72min30s, com capítulos)

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

🟡 **O material do Fernando existe e está no ar, mas só como QR na tela.** Ele oferece um kit com os
cinco agentes e os prompts que usa (planejador, crítico técnico, crítico de negócio, advogado do
diabo e consolidador, cada um em um modelo diferente). O endereço aparece no slide de encerramento
dele, aos 32min42s do vídeo publicado: **https://m2br.academy/materiais/pmi**, "Kit de Análise de
cenário e gestão de portfólio com IA". Conferido em 05/08: responde **HTTP 200**, título "Kit PMI —
Análise de cenário com IA | M2BR Academy".

O que faltou foi registro em texto. O export de recursos do Airmeet veio **vazio** (nenhum recurso
publicado, nenhum download) e o chat tem só os três links de LinkedIn dos palestrantes. Quem assiste
ao replay precisa pausar e ler o slide, ou apontar a câmera para a tela. **A descrição do YouTube
resolve isso**, e é onde o link foi colocado.

Para os próximos: todo link mostrado por QR deveria ir também para a aba de recursos do Airmeet e
para o chat, que são os dois lugares que viram registro.

## 4. Quem esteve lá, do ponto de vista da plataforma

Cruzamento dos 61 presentes contra `members` + `member_emails`, por hash de e-mail:

| | valor |
| --- | --- |
| presentes que são membros | **28** |
| presentes que não são membros | **33** |
| membros com presença já registrada antes desta apuração | 5 |
| membros com presença registrada nesta apuração | 23 |

Os 28 membros vêm de **9 capítulos**: CE (7), GO (6), RS (4), MG (3), PE (2), RJ (2), DF (2), PR (1)
e AM (1). Um webinar de tribo puxando presença de nove capítulos é o argumento multi-capítulo do KPI
acontecendo na prática.

**Os 33 externos não têm registro em lugar nenhum da plataforma.** Não são membros, não entraram como
`visitor_leads` (a captura de lead é do formulário do site, não do Airmeet) e não há rota para gravar
presença de não-membro. Ou seja: a plataforma enxerga 28 de 61. Aberto em **#1602**.

## 5. O que foi gravado na plataforma

| o quê | antes | depois |
| --- | --- | --- |
| presença no evento | 5 | **28** |
| `duration_actual` | 60 | **73** |
| `events.initiative_id` | `null` | Tribo 6 |
| `events.is_recorded` | `false` | `true` (+ `recording_url`, `recording_type='youtube'`) |
| `webinars.status` | `confirmed` | **`completed`** |
| `webinars.youtube_url` | `null` | https://youtu.be/__cXwlfgtwM |
| ata do evento | inexistente | publicada, com 4 ações e 2 decisões estruturadas |
| card no board | `in_progress` | `done` |
| pipeline de comms | "preparar follow-up pós-evento" | **"divulgar replay e materiais"** |

A presença entrou por `attendance_record action='register'` e a ata por `meeting_minutes`, ambos pelo
MCP. Os campos de `webinars` e de gravação do evento foram por UPDATE direto, porque não há rota MCP
(#1600, #1601) e porque a rota da tela apagaria o `board_item_id` (#1604).

## 6. Efeito nos indicadores

**O contador da meta não se mexeu, e isso não é erro de execução.** Medido depois de fechar tudo:

| medida | valor |
| --- | --- |
| webinares com `status='completed'` no banco | 2 → **3** |
| `get_webinars_count` na janela do KPI (até 30/06) | **0** |
| `get_webinars_count` de 01/01 até hoje | **3** |
| Horas de Impacto, janela default do painel | **842** |
| Horas de Impacto, de 01/01 até hoje | **1387** |

A meta "6+ Webinares ou Talks" continua exibindo **0 de 6** com três webinares realizados, porque a
janela de medição parou em 30/06/2026 e os três são de julho e agosto. O mesmo defeito segura
"Eventos realizados" em 147 quando o número até hoje é 220, e o painel do workspace em 842 horas de
impacto quando são 1387. As 28 presenças registradas hoje caem inteiras fora de todas as janelas
default, porque o evento é de agosto. Aberto em **#1603**.

Duração real: `duration_actual` foi de 60 para **73**, o que muda a conta de horas de impacto deste
webinar de ≈28 h para ≈34 h. Esse ganho só aparece em superfície com janela corrigida.

## 7. Pendências abertas por este evento

| # | item |
| --- | --- |
| #1600 | `webinar_manage` não fecha o webinar (status e youtube_url fora da rota MCP) |
| #1601 | `event_write` não alcança os campos de realização (gravação, `duration_actual`, `initiative_id`) |
| #1602 | presença de público externo e resolução de e-mail em lote não têm rota |
| #1603 | janela congelada em `get_annual_kpis` (meta de webinares e eventos realizados) |
| #1604 | editar um webinar pelo modal do admin apaga o `board_item_id` |

⚠️ **A #1604 saiu de uma tentativa de fazer a coisa certa.** Antes de fechar o webinar por SQL fui
conferir se dava para fechar pelo admin, e dava: `upsert_webinar` aceita `p_status` e `p_youtube_url`,
e o gate dela permite ao **próprio organizador** (o Denis, neste caso) fechar o webinar dele. Só que a
função grava `board_item_id = p_board_item_id` sem `COALESCE` e o modal nunca envia esse parâmetro.
Fechar este webinar pela tela teria apagado, em silêncio, o vínculo com o card
`f5a77542-4007-4229-916b-ead5852b20e6`. Por isso o fechamento foi por UPDATE direto.

Isso também corrigiu a #1600, que eu havia escrito afirmando que o líder de tribo dependia do owner
para fechar um webinar. Não depende: a capacidade existe na web. O que não existe é a rota no MCP.

## 8. Achados de higiene, sem issue aberta

**Três webinares de abril presos no pipeline.** `comms_report scope='pending_webinars'` ainda lista
`91759ba1`, `2ab12ccf` e `cd596843` (tribos 2, 4 e 5) em `confirmed` com "preparar follow-up
pós-evento". Ou aconteceram e nunca foram fechados, ou não aconteceram e deveriam estar cancelados. É
o mesmo sintoma que a #1600 descreve: sem rota de fechamento, webinar não fecha.

**Cópia velha de liderança em `initiatives.metadata`.** O `metadata.leader_member_id` da Tribo 6
aponta para o líder anterior. O SSOT (`engagements`, papel `leader` desde 23/06) e a coluna que a
tela realmente lê (`tribes.leader_member_id`) trazem o líder atual, então **não há efeito visível
hoje**. Fica registrado porque é uma terceira representação do mesmo fato, e a única das três que
está errada. Detectado ouvindo o próprio webinar, onde a transição de liderança é anunciada.

**Kickoff de comms nunca registrado.** `comms_kickoff_at` do webinar é `null` e
`comms_kickoff_logged` é `false`, embora a divulgação tenha saído em 27/07 e 02/08. Marcar agora
gravaria a data de hoje, que seria pior que o `null`: o campo aceita apenas "agora"
(`mark_kickoff`), não uma data retroativa.
