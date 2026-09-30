# ADR-0133 - Competições (hackathons e awards): programa, edição, inscrição, equipe, submissão e resultado

**Status:** Proposta (30/09/2026). Nada vai ao banco antes da aprovação do GP.
**Pedido:** decisão do GP em 30/09/2026, repassada pela lane `nucleo-hackathon` e confirmada diretamente com ele: a plataforma recebe a inscrição do Hackathon de Impacto Social, pensada para a **série** (próximas edições e os awards), com o modelo de dados decidido antes do código.
**Relacionadas:** ADR-0005 (`initiatives` é o primitivo de domínio), ADR-0006 (`persons` + `engagements`), ADR-0009 (tipos novos são configuração), ADR-0012 (fonte única por conceito), ADR-0022 (catálogo de notificações), ADR-0105 (visibilidade), ADR-0131 (externo é atributo do vínculo), [#2529](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2529), #1050 (limite por IP).

---

## Contexto

### O calendário e as regras (edital da edição piloto)

- Formulário público no ar em **19/10**, pronto e testado por volta de 12/10. Inscrições fecham em 09/11.
- De 09 a 13/11: conferência, validação pelo PMI Student Club e sorteio, se houver. Resultado em 13/11.
- Dia do hackathon: sábado depois de 11/12, data em aberto. Submissão até 15h00 (repositório, SHA do commit, vídeo, carimbo de hora); a seleção começa às 15h05.
- Depois do dia: certificados em quatro níveis (participação, finalista, vencedora, atuação), com carga horária.
- Inscrição **individual**, informando o nome da equipe e o de quem a lidera. Equipes de 3 a 5 pessoas, com ao menos um perfil técnico. 18 anos ou mais e matrícula em ensino superior, **declaradas**; só as finalistas comprovam, depois do dia. Pode misturar instituições e capítulos. Gratuita. **Sem login.** Aviso LGPD, consentimento explícito e limite por IP.

### O que já existe, medido em 30/09/2026

| Peça | Estado |
|---|---|
| Equipe, submissão, julgamento, prêmio, competição | **Nenhuma tabela.** |
| Fluxo de seleção (`selection_applications`, `selection_cycles`, comitê, entrevistas) | Específico do ciclo de voluntários (VEP, comitê, entrevista); `selection_applications` tem 157 colunas. |
| Pessoa sem filiação (`persons`, login opcional) | Existe. E-mail único só para convidado de evento (índice parcial por `consent_version` `event-guest%`). |
| Vínculo com base legal, retenção e anonimização por tipo (`engagements` + `engagement_kinds`) | Existe; tipo novo é configuração (ADR-0009). |
| Tipo de iniciativa configurável (`initiative_kinds`) | 8 tipos; nenhum de competição. |
| Iniciativa "Hackathon de Impacto Social" | Existe, `workgroup`, ativa: é a equipe que organiza. |
| Certificado de não membro (`event_guest_certificates` + `issue_event_guest_certificate`) | Existe: pessoa + evento, código verificável (`verify_certificate`), pt-BR/en-US/es-LATAM, retenção com limpeza, PDF por gatilho. Aceita **um tipo** (`event_participation`, por CHECK), **sem carga horária**, **1** emitido até hoje, **nenhuma tela** de emissão. |
| Consentimento versionado (`consent_records`, `privacy_policy_versions`) | Existe (política, versão, canal, hash de IP e de user agent, revogação). |
| Formulário público sem login | Padrão existente: `capture_visitor_lead`, função `SECURITY DEFINER` executável por `anon`, com `rl_check_and_bump(ação, limite, janela)` no banco, que conta por IP (`cf-connecting-ip`) e deixa passar quando o IP não chega. |
| Revisor externo | Tipo de vínculo `external_reviewer` existe (base legal: consentimento). |

---

## Decisão

### 1. O programa é uma iniciativa; a edição é tabela própria

- **Programa** (a série: "Hackathon de Impacto Social", um award) = uma iniciativa de um **tipo novo, `competition`**, configurado em `initiative_kinds` (ADR-0009). Autoridade escopada (`can()` com recurso), board, presença e os vínculos de organização e revisão ficam nela, como em qualquer iniciativa (ADR-0005).
- **Edição** (uma ocorrência com datas) = tabela **`competition_editions`**: programa, `slug` público, título, modalidade (`hackathon` ou `award`), janela de inscrição (`registration_opens_at`, `registration_closes_at`), evento do dia (`event_id`), prazo de submissão (`submission_deadline_at`), fuso, tamanho de equipe (mínimo e máximo, ou sem equipe), elegibilidade declarada, **esquema do formulário** (campos, obrigatoriedade, textos por idioma), base legal, retenção em dias, versão da política de privacidade, níveis de certificado com carga horária, e o estado (`draft`, `open`, `closed`, `in_review`, `results`, `done`).
- Uma edição nova é linha nova, não código novo. Um award é a mesma estrutura com outra modalidade.
- **Decidido pelo GP em 30/09/2026:** o programa ganha uma **iniciativa própria**. O `workgroup` "Hackathon de Impacto Social" segue sendo a equipe que organiza; a série dura mais que a equipe de uma edição.

### 2. A pessoa é o cadastro único, e se inscrever não torna ninguém membro

- A inscrição **encontra ou cria** a pessoa em `persons` pelo e-mail normalizado dentro da organização, sem login e sem linha em `members`. É isso que liga a mesma pessoa entre edições, que é o objetivo da série.
- A pessoa não ganha filiação nem papel por se inscrever (ADR-0131: externo é atributo do vínculo). O vínculo só nasce na seleção (item 5).
- Cada inscrição carrega a própria base legal e o próprio prazo de retenção, tirados da edição. Quando todos os prazos de uma pessoa sem outro vínculo vencem, ela é anonimizada pelo caminho que `persons` já tem (`anonymized_at`).

### 3. Inscrição individual; a equipe se forma na conferência

- **`competition_registrations`**: edição, pessoa, estado (`submitted`, `validated`, `rejected`, `selected`, `not_selected`, `withdrawn`), respostas do formulário (validadas contra o esquema da edição), as declarações como colunas próprias (idade, condição de estudante, instituição, perfil técnico), o nome da equipe e o de quem lidera **como declarados**, o registro de consentimento, quem conferiu e quando, e `retention_until`. Uma inscrição por pessoa e edição; reenviar com a inscrição aberta atualiza a mesma linha.
- **`competition_registration_events`**: histórico de estado, com quem mudou e por quê.
- **`competition_teams`** (edição, nome, nome normalizado, estado, liderança) e **`competition_team_members`** (equipe, inscrição, papel `leader` ou `member`): formadas na conferência, **agrupando os nomes de equipe declarados**, com as checagens à vista: tamanho fora de 3 a 5, nenhum perfil técnico, liderança declarada que não se inscreveu, nomes quase iguais.
- Por que não formar a equipe na inscrição: o edital pede inscrição individual com o nome da equipe (2.3). Um código de equipe gerado na primeira inscrição evitaria erro de digitação e fica como opção do esquema para edições futuras.

### 4. A validação é um papel escopado, e a exportação é o mínimo que não depende de ninguém

- Ação **`review_competition_registrations`**, escopada à iniciativa do programa, concedida por um vínculo de revisor. O PMI Student Club entra por esse papel **se e quando** o acordo existir.
- Até lá, a conferência é feita por quem organiza, com **exportação em CSV agrupada por equipe**, por uma função `SECURITY DEFINER` que registra o acesso a dado pessoal. Nada no desenho depende de o Student Club aceitar.

### 5. A seleção vira vínculo, não filiação

- No resultado, cada inscrição selecionada gera um vínculo **`competition_participant`** na iniciativa do programa, com a edição e a equipe nos metadados. Base legal, retenção e anonimização vêm da configuração do tipo de vínculo, como qualquer outro.

### 6. Submissão por equipe, com prazo no servidor e sem conta

- **`competition_submissions`**: equipe, edição, URL do repositório, SHA do commit (40 caracteres hexadecimais), URL do vídeo, `submitted_at` pelo relógio do **servidor**, e versão. Vale a última enviada antes do prazo; as anteriores ficam no histórico.
- Sem conta: cada equipe selecionada recebe, por e-mail da liderança, um **link com token** (só o hash é guardado). A função confere o token e o prazo da edição no servidor e devolve um recibo com a hora registrada. O magic link segue não resolvido (ADR-0131).
- No prazo, a exportação alimenta a ferramenta da banca.

### 7. O julgamento fica fora; o contrato é entrada e saída

- O motor de julgamento é da lane da banca. Esta ADR define a interface: **saída** = equipes e submissões da edição; **entrada** = **`competition_results`** (edição, equipe, colocação: `finalist`, `winner` ou outra, posição, quando e por qual fonte).
- Nota, critério e rubrica não entram aqui. Se o motor da banca vier para a plataforma, ele se pendura nos mesmos identificadores de edição, equipe e submissão.

### 8. Certificados reaproveitam o de convidado, com níveis e carga horária

- `event_guest_certificates` passa a aceitar os tipos `competition_participation`, `competition_finalist`, `competition_winner` e `competition_staff` (atuação), ganha **`workload_hours`** e, opcionalmente, a edição e a equipe. O evento é o dia do hackathon.
- Os níveis e as horas vêm da edição; a emissão é em lote, a partir dos resultados e dos vínculos. Quem emite e quem contra-assina é a decisão (d).

### 9. Formulário público: sem login, consentimento versionado e limite por IP

- Página pública da edição (pt-BR, com as páginas `/en/` e `/es/` que as regras do projeto pedem), chamando uma função `anon` **`competition_register(edição, respostas)`** que: aplica `rl_check_and_bump`; confere a janela da edição; valida as respostas contra o esquema; exige as declarações (idade, estudante, regulamento) e o consentimento; grava o consentimento em `consent_records` com a versão da política da edição; é idempotente por edição e e-mail; e devolve um recibo opaco.
- Nenhuma tabela nova é legível por `anon`; RLS em todas; leitura e exportação só por função com autoridade.
- E-mail de confirmação: opcional, pela infraestrutura de e-mail existente, sem dado além do da própria pessoa.
- **Contato só por e-mail** (decisão do GP em 30/09/2026): o formulário não coleta telefone. Menos dado pessoal, e o canal oficial depois do resultado usa o e-mail informado.

### 10. Base legal, retenção e textos são configuração da edição

- Base legal, prazo de retenção, versão da política e os textos do formulário ficam na edição. A decisão (a) entra sem código novo, e **o go-live espera por ela**.

---

## Consequências

- Seis tabelas novas (`competition_editions`, `competition_registrations`, `competition_registration_events`, `competition_teams`, `competition_team_members`, `competition_submissions`) mais `competition_results`, todas com RLS e acesso só por funções com autoridade.
- `event_guest_certificates`: o CHECK de `type` cresce e entra `workload_hours`.
- Configuração: o tipo de iniciativa `competition`, a iniciativa do programa, e os tipos de vínculo `competition_participant` e `competition_reviewer`. Quem organiza continua no `workgroup` atual.
- Telas: a página pública de inscrição e uma tela de conferência com a exportação.
- O Sympla, ou outro formulário externo, continua possível só como plano B da inscrição do piloto; os dados voltariam por importação para as mesmas tabelas.

## Alternativas rejeitadas

- **Reaproveitar `selection_applications` e `selection_cycles`:** o fluxo é do voluntariado (VEP, comitê, entrevistas, 157 colunas). Misturar competição ali mistura regimes de autoridade e de LGPD.
- **Programa como tabela à parte das iniciativas:** duplicaria autoridade, board e vínculos; `initiatives` é o primitivo (ADR-0005).
- **Criar a pessoa só na seleção:** menos linhas em `persons` para quem não é selecionado, mas perde a identidade entre edições, que é o ponto da série. A retenção por inscrição cobre o custo.
- **Código de equipe na inscrição:** diverge do edital (2.3); fica como opção do esquema.
- **Guardar o julgamento agora:** é da lane da banca; aqui só a interface.

## Perguntas abertas (do GP)

- (a) Base legal e prazo de retenção do dado das inscrições.
- (b) "Participante" como vínculo sem filiação; se o adendo ao Manual é necessário.
- (c) Autoridade do PMI Student Club (até 09/11); até lá, a exportação.
- (d) Emissor e contra-assinatura dos certificados de não membro (até dezembro).

## Decididas (GP, 30/09/2026)

- (e) O programa tem iniciativa própria do tipo `competition`; o `workgroup` segue como a equipe que organiza.
- (f) Contato só por e-mail; o formulário não coleta telefone.
