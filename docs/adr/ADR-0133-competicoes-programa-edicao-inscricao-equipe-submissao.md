# ADR-0133 - Competições (hackathons e awards): programa, edição, inscrição, equipe, submissão e resultado

**Status:** Proposta (30/09/2026). O conflito com a decisão de 25/09 foi resolvido pelo GP (supersessão, seção abaixo). Nada vai ao banco antes da aprovação do GP.
**Pedido:** decisão do GP em 30/09/2026, repassada pela lane `nucleo-hackathon` e confirmada diretamente com ele: a plataforma recebe a inscrição do Hackathon de Impacto Social, pensada para a **série** (próximas edições e os awards), com o modelo de dados decidido antes do código.
**Insumo:** pacote de inscrição da edição piloto da lane `nucleo-hackathon` (campos, declarações, aviso de privacidade, parâmetros e as regras do edital que o modelo sustenta), rascunho de 30/09/2026 ainda não aprovado pelo GP.
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

## Supersessão da decisão de 25/09/2026 (decidida pelo GP em 30/09/2026)

Esta ADR foi escrita sem ler a arquitetura da banca, e contradizia uma decisão já tomada. Em `banca/docs/ARQUITETURA.md`, seção 8 (na `main` da banca, commit `7f989c5`), está a **decisão do GP de 25/09/2026**, repassada pela lane `ai-pm-research-hub-3a`: a inscrição seria um **serviço próprio**, com dado pessoal e arquivos em D1 e R2 próprios na Cloudflare; **"Nenhum dado de inscrito passa pelo Supabase do hub"**; a ponte com a banca seria um service binding, no formato **entry-contract v1**.

Depois dela, um fato mudou: o edital (5.1-A) passou a pedir tudo por link, sem arquivo. O R2 e a URL assinada perderam o objeto; a separação do dado pessoal, não.

**Decisão do GP em 30/09/2026, perguntada diretamente nesta sessão com as duas saídas à vista: "Supera a de 25/09".** A razão, nas palavras dele: "banco de dados consegue ter as camadas devidamente separadas, não tem por que não aproveitar a conta do Supabase que já temos em plano pago para otimizar a arquitetura". A inscrição mora no Supabase do hub, **numa camada própria** (item 0 abaixo). Consequências:

- A seção 8 da banca precisa registrar a mesma supersessão, **pelo fluxo daquele repositório**; esta ADR não o edita.
- A ponte com a banca deixa de ser service binding entre Workers: a banca recebe as entradas **exportadas pelo hub**, no formato do entry-contract (a v2, do formato de um dia), por arquivo ou por endpoint autenticado, a combinar com a lane da banca. A banca continua sem receber o contato das pessoas além do que o conflito de interesse exige.
- O que a separação protegia passa a ser protegido dentro do hub, por construção: tabelas próprias, RLS em todas, **nenhuma leitura por `anon`**, acesso só por funções com autoridade escopada ao programa, registro de todo acesso a dado pessoal nas exportações, e retenção e anonimização por edição (item 10).

## Decisão

### 0. Camada própria: o schema `competition`, fora da API

- As tabelas de competição ficam no schema **`competition`**, e não em `public`. Medido em 30/09/2026: a API de dados do Supabase expõe só `public` e `graphql_public`, então **nenhuma tabela desse schema é consultável pela API**, por ninguém, com ou sem login.
- O único caminho de entrada e de saída são funções `SECURITY DEFINER` em `public`, cada uma com a sua autoridade: a inscrição pública (`anon`, com limite por IP), a conferência e a exportação (autoridade escopada ao programa), a submissão (token da equipe), a importação do resultado e a emissão de certificado.
- RLS fica ligada nas tabelas mesmo assim (defesa em profundidade), e toda leitura de dado pessoal por essas funções é registrada.
- Nos itens abaixo, `competition_editions` quer dizer `competition.editions`, e assim por diante: o prefixo some dentro do schema.

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

- **`competition_registrations`**: edição, pessoa, estado (`submitted`, `valid`, `excluded`, `selected`, `waitlisted`, `not_selected`, `withdrawn`), respostas do formulário (validadas contra o esquema da edição), e como colunas próprias o que o processo decide: nome social (usado no certificado e na comunicação quando preenchido), instituição e curso, perfil técnico e área, **se lidera** e o **e-mail de quem lidera**, o nome da equipe declarado, GitHub, origem e canal (opcionais), a comprovação de matrícula (item 3-C), quem conferiu e quando, e `retention_until`. Os parâmetros de campanha (UTM) ficam à parte, porque não são dado pessoal.
- **Uma pessoa, uma equipe por edição** (proposta do pacote da edição piloto, pendente do GP): uma inscrição por pessoa e edição; o mesmo e-mail na mesma edição não abre outra, e a pessoa corrige a sua pelo link do e-mail (item 9).
- **`competition_registration_events`**: histórico de estado, com quem mudou e por quê.
- **`competition_teams`** (edição, nome, **código público** de equipe, estado, liderança) e **`competition_team_members`** (equipe, inscrição, papel `leader` ou `member`): formadas na conferência **pela chave exata do e-mail de quem lidera**, que todo integrante informa e que é o e-mail da própria inscrição de quem lidera. O nome da equipe continua pedido e a conferência acusa divergência entre nome e chave, além de: tamanho fora de 3 a 5, nenhum perfil técnico, liderança que não se inscreveu, pessoa que lidera informando outra liderança.
- Por que não formar a equipe na inscrição com código: o padrão das plataformas de hackathon (quem lidera cria a equipe e recebe um código) exige conta ou confirmação por e-mail antes do agrupamento. O e-mail de quem lidera dá a mesma exatidão sem isso. O código continua opção do esquema para edições futuras, a avaliar com o benchmark.

### 3-A. Declarações: caixas separadas, texto versionado, e o que é opcional é consentimento

- A edição declara as suas declarações no esquema: chave, texto versionado, obrigatória ou não. Cada uma é uma caixa separada e desmarcada; o envio só passa com as obrigatórias marcadas.
- **`competition_registration_declarations`** guarda, por inscrição, a chave, a **versão do texto** aceita e a hora. Na edição piloto: 18 anos ou mais, matrícula em ensino superior, a penalidade coletiva da 2.8 (exigida na tela antes do envio), o aceite do edital e a leitura do aviso de privacidade.
- O que é opcional e revogável (aviso de próximas edições; uso de imagem, quando existir) vai para **`consent_records`**, que já tem revogação. **Uso de imagem nunca é condição para se inscrever.**

### 3-B. Validação conjunta, com impedimento

- A validação é ato conjunto das partes que a edição declara (na piloto, o PMI Student Club e o Núcleo; edital 3.3). **`competition_registration_reviews`** guarda cada decisão: inscrição, **parte**, quem decidiu, decisão (`valid` ou `exclude`), motivo, declaração de ausência de vínculo com a equipe, e a hora.
- **Excluir exige acordo de todas as partes; na divergência a inscrição segue válida** (3.3-A). O estado da inscrição é derivado das decisões, não escrito à mão.
- **Quem tem vínculo com a equipe não decide sobre ela** (3.3-B): a função recusa a decisão de quem é integrante da equipe e exige a declaração de ausência de vínculo.

### 3-C. Comprovação de matrícula das finalistas: o fato, não o documento

- Depois do dia (2.7), a conferência registra **que** a matrícula foi comprovada, **por quem** e **quando**. O documento não é guardado.

### 4. A validação é um papel escopado, e a exportação é o mínimo que não depende de ninguém

- Ação **`review_competition_registrations`**, escopada à iniciativa do programa, concedida por um vínculo de revisor que diz **qual parte** a pessoa representa. O PMI Student Club entra por esse papel **se e quando** o acordo existir.
- Até lá, a conferência é feita por quem organiza, com **exportação em CSV agrupada por equipe**, por uma função `SECURITY DEFINER` que registra o acesso a dado pessoal. Nada no desenho depende de o Student Club aceitar: sem a segunda parte na plataforma, a decisão dela entra registrada por quem organiza, com a indicação de que foi transcrita.

### 4-A. Sorteio público e reproduzível por terceiro

- Antes do sorteio, publica-se a lista das equipes válidas pelo **código público** de equipe, sem nome de pessoa (3.5).
- **`competition_draws`** guarda: a lista publicada e quando, a **fonte da semente** (o concurso da Loteria Federal, o primeiro depois do encerramento) e o valor, a **versão do algoritmo**, a capacidade apurada (teto D2), a **ordem completa** e quem executou. Cada equipe recebe a posição; a lista de espera segue essa ordem.
- O algoritmo é determinístico e publicado (por exemplo, ordenar por um hash do código de equipe com a semente), para qualquer pessoa refazer a conta com os mesmos dados públicos.

### 4-B. Resultado por escrito a toda equipe

- Toda equipe recebe o resultado por escrito, selecionada ou não, com a posição na lista de espera (3.6); o mesmo vale para a seleção de finalistas (5-A.14). O envio fica registrado por equipe, com a hora, para provar que ninguém ficou sem resposta.

### 5. A seleção vira vínculo, não filiação

- No resultado, cada inscrição selecionada gera um vínculo **`competition_participant`** na iniciativa do programa, com a edição e a equipe nos metadados. Base legal, retenção e anonimização vêm da configuração do tipo de vínculo, como qualquer outro.

### 6. Submissão por equipe, com prazo no servidor e sem conta

- **`competition_submissions`**: equipe, edição, URL do repositório, SHA do commit (40 caracteres hexadecimais), URL do vídeo, `submitted_at` pelo relógio do **servidor**, e versão. Vale a última enviada antes do prazo; as anteriores ficam no histórico.
- Sem conta: cada equipe selecionada recebe, por e-mail da liderança, um **link com token** (só o hash é guardado). A função confere o token e o prazo da edição no servidor e devolve um recibo com a hora registrada. O magic link segue não resolvido (ADR-0131).
- **O prazo é a hora da submissão registrada pelo servidor, não a data do commit** (5-A.3). Na importação para a banca, a organização confere se o commit informado está no repositório público e **registra a hora da conferência e o resultado** (`commit_checked_at`, `commit_found`); commit não encontrado não é avaliado (5-A.3-A).
- No prazo, a exportação alimenta a ferramenta da banca.

### 7. O julgamento fica fora; o contrato é entrada e saída

- O motor de julgamento é da lane da banca. Esta ADR define a interface: **saída** = equipes e submissões da edição; **entrada** = **`competition_results`** (edição, equipe, colocação: `finalist`, `winner` ou outra, posição, quando e por qual fonte).
- Nota, critério e rubrica não entram aqui. Se o motor da banca vier para a plataforma, ele se pendura nos mesmos identificadores de edição, equipe e submissão.

### 8. Certificados reaproveitam o de convidado, com níveis e carga horária

- `event_guest_certificates` passa a aceitar os tipos `competition_participation`, `competition_finalist`, `competition_winner` e `competition_staff` (atuação), ganha **`workload_hours`** e, opcionalmente, a edição e a equipe. O evento é o dia do hackathon.
- Os níveis e as horas vêm da edição; a emissão é em lote, a partir dos resultados e dos vínculos. Quem emite e quem contra-assina é a decisão (d).
- ⚠️ **Conflito com o edital (7.2-C, certificado verificável por código):** medido em 30/09/2026, `issue_event_guest_certificate` grava `retention_until = data do evento + 1 ano`, e `delete_expired_event_guest_certificates` apaga o certificado vencido **e a pessoa só-convidada**. Hoje nenhum cron chama essa limpeza, mas o desenho prevê a remoção, e depois dela `verify_certificate` não acha o código. É mudança de ROPA, portanto decisão do GP. A proposta do pacote da piloto: guardar **só o nome e o código** pelo tempo em que o certificado precisar ser verificável.

### 9. Formulário público: sem login, consentimento versionado e limite por IP

- Página pública da edição (pt-BR, com as páginas `/en/` e `/es/` que as regras do projeto pedem), chamando uma função `anon` **`competition_register(edição, respostas)`** que: aplica `rl_check_and_bump`; confere a janela da edição no fuso dela; valida as respostas contra o esquema (e-mail digitado duas vezes, liderança coerente); exige as declarações obrigatórias; grava declarações e consentimentos com a versão do texto; e devolve um recibo opaco. **Não há teto de inscrições no formulário**: toda inscrição válida vai ao sorteio, e o teto se aplica na conferência.
- **Correção pela própria pessoa, até o encerramento, pelo link do e-mail de confirmação**: cada inscrição tem um token próprio (só o hash é guardado). Sem o link, o mesmo e-mail na mesma edição não altera nem duplica a inscrição, e a resposta pública não revela se o e-mail já estava inscrito.
- Nenhuma tabela nova é legível por `anon`; RLS em todas; leitura e exportação só por função com autoridade.
- **E-mail de confirmação** (recomendado pelo pacote da piloto, decisão do GP): os dados enviados, o nome da equipe e o e-mail de quem lidera, o link de correção, os links do edital e do aviso de privacidade, as datas, e o lembrete da 2.8. Vai pela infraestrutura de e-mail existente (Resend).
- **Onde o dado fica** (medido em 30/09/2026): o banco está em `sa-east-1` (São Paulo). A documentação de backups do Supabase não declara a região dos backups; o e-mail sai pelo Resend, que oferece envio a partir de `sa-east-1` entre outras regiões, e a região do domínio de envio não foi medida. O aviso de privacidade precisa dessas duas respostas antes do go-live.
- **Contato só por e-mail** (decisão do GP em 30/09/2026): o formulário não coleta telefone. Menos dado pessoal, e o canal oficial depois do resultado usa o e-mail informado.

### 10. Base legal, retenção e textos são configuração da edição

- Base legal, prazo de retenção, versão da política e os textos do formulário ficam na edição. A decisão (a) entra sem código novo, e **o go-live espera por ela**.

### 11. O que o benchmark acrescenta

Benchmark da lane `nucleo-hackathon` (17 plataformas de hackathon e awards, 10 dimensões, fontes lidas em 30/09/2026; leitura parcial de algumas). Entra no modelo, onde quer que ele more:

- **Versão do formulário imutável depois da primeira resposta**, com cada resposta ligada à versão; cada campo com identificador estável, alvo (pessoa, inscrição, equipe ou entrega), marca de dado pessoal, visibilidade e retenção. Plataformas que reescrevem respostas antigas quando o formulário ao vivo muda são o contraexemplo.
- **Decidir em silêncio e publicar tudo de uma vez**: estado pendente até a publicação do resultado, o que casa com o 13/11.
- **Data de trava da equipe**, depois da qual a composição não muda.
- **Estados que não se confundem**: válida, selecionada, finalista e vencedora são estados distintos.
- **O limite por IP é freio, não barreira**: `rl_check_and_bump` deixa passar quando o IP não chega. Avaliar captcha no formulário público.
- **Etapas da série numa tabela própria**, quando houver mais de uma edição (colunas bastam para a piloto).
- **Contrato com a banca**: o entry-contract v1 ainda usa as rodadas do formato anterior e categoria obrigatória; pela regra do próprio contrato, o formato de um dia pede uma v2. Instituição em texto livre atrapalha o motor de conflito, que lê o domínio.
- **Botão "Adicionar ao LinkedIn"**: é URL estática, não preenche sozinho e exige uma Página da organização.

---

## Consequências

- Schema novo `competition`, fora da API. Tabelas novas nele, todas com RLS e acesso só por funções com autoridade: `competition_editions`, `competition_registrations`, `competition_registration_events`, `competition_registration_declarations`, `competition_registration_reviews`, `competition_teams`, `competition_team_members`, `competition_draws`, `competition_submissions` e `competition_results`, mais o registro do envio do resultado por equipe.
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
- Do pacote da edição piloto (lane `nucleo-hackathon`, rascunho ainda não aprovado): controlador do dado e encarregado; uma pessoa, uma equipe por edição; low-code conta como perfil técnico; idiomas da página (recomendação: só pt-BR na piloto); e-mail de confirmação (recomendação: sim); hora de abertura (sugestão 09h00 de 19/10); teto de equipes (D2); uso de imagem (seção 9 do edital).
- Região dos backups do Supabase e do domínio de envio do Resend, para o aviso de privacidade declarar ou não transferência internacional.

## Decididas (GP, 30/09/2026)

- (e) O programa tem iniciativa própria do tipo `competition`; o `workgroup` segue como a equipe que organiza.
- (f) Contato só por e-mail; o formulário não coleta telefone.
