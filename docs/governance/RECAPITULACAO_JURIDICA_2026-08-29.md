# Recapitulação jurídica do acervo de documentos do Núcleo

**Medido em:** 2026-08-29 · **Guarda-chuva:** #632 · **Lane:** #2067 / `docs/recapitulacao-juridica`

Fontes cruzadas: banco da plataforma (`governance_documents`, `document_versions`,
`admin_audit_log`, `member_document_signatures`), `git log` deste repositório e do
`nucleo-wiki`, caixa institucional do Núcleo (revisão jurídica de maio a agosto de
2026) e dois grupos de WhatsApp exportados pelo PM.

> **Ler o #632 antes deste arquivo.** Ele é o guarda-chuva do workstream e carrega
> decisões já ratificadas pelo PM, que esta lane executa e **não re-litiga**:
> documento aprovado entra como **v0 real** (a numeração de trabalho v1.4 / v2.7 /
> R3 não migra), **logo do capítulo sede e nunca o masterbrand PMI**, e **domínio
> institucional** nos instrumentos.

> **Convenção de privacidade.** Repositório público. Pessoas aparecem por papel
> (advogada parecerista, advogado parecerista, presidência do capítulo, diretoria
> de voluntariado, contraparte do PMI Argentina), nunca por nome, e-mail ou
> telefone. O texto dos instrumentos vive fora do repositório (cadeia de governança
> em `.docx`, per SPEC-1153).

> **Sobre datas.** Todo carimbo aqui está em **BRT**. Vários campos do banco são
> `timestamptz` e renderizam em UTC por padrão, o que empurra eventos do fim da
> noite para o dia seguinte. Onde uma data importa, ela foi lida com
> `at time zone 'America/Sao_Paulo'`.

---

## 1. A noite de 10→11 de junho: nove versões em cinco horas

O pacote revisado dos instrumentos foi escrito na plataforma numa única noite. A
sequência abaixo está corroborada por três fontes independentes que batem à hora:
`admin_audit_log`, `document_versions` e o `git log` deste repositório.

| Horário (BRT) | Evento | Fonte |
|---|---|---|
| 10/06 19:52 | `governance.term_signature_hold` no Termo: `active` → `under_review`, com a razão "Termo em atualização jurídica (Parecer 01/2026), hold de ~1 semana" | audit log |
| 10/06 23:36 | commit `b51af645` `feat(632): diagramação logo sede + domínio institucional nos PDFs de instrumentos (#635)` | git |
| 10/06 23:59 → 11/06 00:18 | **seis** versões `draft-rev-juridica-2026-06-07` criadas: Anexo Técnico, Adendo de PI, **Termo**, Adendo Retificativo, Política, Acordo Bilateral | audit log |
| 11/06 02:26 | `governance.documents_created_bulk`: os **três instrumentos novos** criados como draft, com a razão citando o #632 e a decisão do PM de que "os 9 docs entram como drafts" | audit log |
| 11/06 03:23 | commit `305b8dac` `fix(632): doc_type p/ 3 instrumentos novos + RLS edit de draft unlocked (mig 146/147) (#644)` | git |
| 11/06 03:37 → 03:41 | **três** versões criadas: Simplificado, Declaração, DPA | audit log |
| 11/06 04:48 | `governance.draft_domain_swap` e `draft_chaptername_unify` aplicados aos drafts, byte-exact | audit log |
| 11/06 09:42 | e-mail ao time jurídico com os **nove `.docx`** (`doc01`…`doc09`) | caixa do Núcleo |

A migration 147, citada nas notas das próprias versões ("pós fix RLS
`document_versions`"), é o commit das 03:23. As três criações seguintes acontecem
catorze minutos depois dela. A cadeia fecha sozinha.

**As versões são de junho, sem ambiguidade.** `authored_at` e `created_at` são
idênticos em todas, entre 10/06 23:59 e 11/06 03:41 BRT, e o audit log carimba os
mesmos instantes.

## 2. Nove foram escritas, oito sobrevivem: a do Termo foi apagada

Esta é a correção que o inventário anterior não tinha. A contagem de hoje encontra
**oito** versões `draft-rev-juridica-2026-06-07` na tabela. O audit log registra
**nove** criações naquela noite. A que falta é a do Termo de Adesão ao Serviço
Voluntário, criada em **11/06 00:06:25** e ausente de `document_versions`.

A cicatriz está na numeração. O Termo tem `version_number` **1,2,3,4,5,6,7,9**: o
**8 não existe**. Todos os outros oito documentos têm sequência contínua.

Não é conjectura de rótulo: é a linha do audit log de um lado e a ausência da linha
do outro, com o buraco na numeração no meio. O apagamento não tem registro próprio
no audit log, então **quando e por que a v8 saiu ainda é pergunta em aberto**.

Hipótese mais provável, a confirmar: o Termo estava sob `term_signature_hold` desde
as 19:52 daquela mesma noite (#625), e voltou a `active` em julho por um caminho
distinto do das outras oito. A v8 pode ter sido removida ao fechar esse hold. O
commit `3efce8b8` de 07/07 23:15, `fix(governance): #1187 term version label
read-through + zombie chain close on activation`, é o lugar por onde começar a
procurar.

## 3. O que está parado hoje

As oito versões sobreviventes seguem não publicadas e não travadas. Como o campo
`version` de cada documento continua apontando para a versão anterior, **a
plataforma exibe o texto pré-revisão e o revisado fica invisível**.

| Documento | Estado | Caracteres (markdown) |
|---|---|---:|
| Acordo de Operador / DPA (doc 9) | `draft` | 47.747 |
| Política de Governança de PI (doc 1) | `under_review` | 43.753 |
| Acordo de Cooperação Bilateral (doc 3) | `under_review` | 35.190 |
| Adendo Retificativo (doc 5) | `under_review` | 20.437 |
| Adendo de PI (doc 6) | `under_review` | 15.643 |
| Anexo Técnico (doc 4) | `under_review` | 12.147 |
| Termo de Adesão Simplificado (doc 8) | `draft` | 12.121 |
| Declaração de Exclusão de PI (doc 7) | `draft` | 11.344 |
| **Total parado** | | **198.382** |

**Correção ao item 1 do #632.** Ele registra que do pacote revisado "nenhum subiu",
o que era verdade quando foi escrito e deixou de ser na mesma noite. O diagnóstico
correto não é "não importaram": é que a importação aconteceu e parou no passo
seguinte, a publicação. O custo do conserto muda de reimportar de fora para
publicar o que já está dentro, como v0.

**Correção ao item 3 do #632 (domínio).** A troca de domínio nos instrumentos **já
foi executada** no conteúdo dos drafts em 11/06 04:48, byte-exact, com
`vitormr_left: 0` em doc01, doc04 e doc05 (o DPA guarda uma ocorrência deliberada,
na linha de CDN do Anexo I.5). O que resta do item 3 é a infraestrutura do
redirect, não o texto.

## 4. O rótulo mente sobre o conteúdo

As versões chamam-se `draft-rev-juridica-2026-06-07`. O nome sugere a revisão
jurídica. **Não é ela.** As notas descrevem uma varredura **editorial do próprio
PM**: "lifecycle" para "ciclo de vida", pontuação normalizada, "GP autor" para
"Autor da Plataforma", exemplos nominais removidos.

A data no rótulo (07/06) é anterior à autoria real (10-11/06). Nesta base
`version_label` é texto livre e não descreve o conteúdo. Não é motivo para
renomear: pela diretriz v0 do #632, essa numeração de trabalho não migra, e a
higiene vem de graça na publicação.

Há ainda **dois esquemas de numeração** para o mesmo pacote, e eles não coincidem.
Os anexos do e-mail vão de `doc01` a `doc09`; o audit log da criação em massa usa
`doc07/doc10/doc11` para os três instrumentos novos. Ao cruzar registros, ancore
pelo `document_id`, nunca pelo número do documento.

## 5. O ciclo jurídico, e o que ele cobre

| Data (BRT) | Evento |
|---|---|
| 14/05 | PM envia a rodada de seis documentos para revisão jurídica voluntária |
| 05/06 | Chega a análise, redigida pelo advogado parecerista (Parecer nº 01/2026) |
| 11/06 09:42 | PM devolve a rodada revisada dos **nove** documentos, com checagem cláusula a cláusula das doze recomendações: **oito acolhidas** (a, b, d, f, g, h, k, l), **duas com divergência consciente** (e, j), **duas pendentes de validação** (c, i) |
| 22/06 e 29/06 | PM cobra no grupo a validação dos documentos 1, 2 e 7, explicando que o Termo trava o início do Ciclo 4 |
| 06/07 12:34 | `ip_ratification_signoff` (gate `leader_awareness`) no Termo e na Política |
| 06/07 13:36 | Parecerista envia **quatro recomendações novas** sobre os documentos 1, 6 e 7 |
| 06/07 15:04 → 16:27 | PM consolida em `.docx` com as alterações em vermelho; ambos dão o de acordo nos documentos **1, 2, 6 e 7** |
| 06/07 22:23 | Termo v9 criada; **22:24** publicada e travada |
| 07/07 08:17 | PM anuncia no grupo que a presidência aprovou o Termo e o fluxo de assinatura começou |
| 07/07 16:13 | Carimbo `current_ratified_at` do Termo |
| 09/07 | Kickoff do Ciclo 4 |
| 21/08 | PM propõe ao jurídico as duas frentes seguintes: os **seis documentos restantes** e o webinar de PI e privacidade. Sem resposta registrada até 29/08 |

**Atenção a três instantes distintos** que a leitura apressada funde: a versão foi
**publicada** em 06/07 22:24, a aprovação foi **anunciada** em 07/07 08:17, e o
**carimbo** de ratificação é de 07/07 16:13. Só o terceiro é o que a plataforma
mostra como data de ratificação.

**Cobertura jurídica, documento a documento:**

| Aprovado em 06/07 | Ainda sem revisão jurídica |
|---|---|
| 1 Política de Governança de PI | 3 Acordo de Cooperação Bilateral |
| 2 Termo de Adesão ao Serviço Voluntário | 4 Anexo Técnico |
| 6 Adendo de PI aos Acordos | 5 Adendo Retificativo |
| 7 Declaração de Exclusão de PI | 8 Termo de Adesão Simplificado |
| | 9 Acordo de Operador / DPA |

O Termo é o único dos quatro aprovados que completou a volta. **Também é o único
com versão de julho:** em todo o `document_versions`, existe exatamente **uma**
linha criada em julho, a v9 do Termo. Todo o resto do pacote é de junho.

## 6. O pacote de 06/07 é o que falta localizar

Há uma segunda versão do pacote, posterior à que está na plataforma. Na tarde de
06/07 o PM consolidou as recomendações em `.docx`, marcando em vermelho as partes
alteradas, e o de acordo do jurídico veio sobre **esses** arquivos.

Esse pacote **não está no e-mail e não está na plataforma**: foi compartilhado pelo
WhatsApp, e a exportação do grupo traz apenas a marca de mídia omitida.

- para os documentos **1, 6 e 7**, o texto aprovado é o de 06/07, e a versão que a
  plataforma guarda é a de 11/06, anterior a ele;
- o único caso recuperável hoje é o documento **2**: seu texto aprovado entrou como
  v9 e serve de referência do que a consolidação de 06/07 mudou.

**Primeiro passo desta lane:** recuperar os `.docx` de 06/07 na origem. Sem eles,
publicar 1, 6 e 7 como v0 publicaria texto que o jurídico não viu.

### As quatro recomendações de 06/07, para conferir contra esses arquivos

- **(a)** coordenação internacional de depósitos de patentes no Adendo de PI,
  observando a prioridade unionista (art. 4º da Convenção da União de Paris e art.
  16 da Lei nº 9.279/1996);
- **(b)** termos de cessão de direitos patrimoniais assinados pelos autores e
  inventores no protocolo junto ao INPI, porque a aprovação tácita por silêncio da
  governança interna não tem eficácia perante a autarquia;
- **(c)** auditoria de dados pessoais no fluxo de transferência internacional,
  habilitando o Encarregado a verificar a conformidade dos capítulos parceiros com
  as SCCs e a ANPD;
- **(d)** na Cláusula Primeira da Declaração de Exclusão de PI, exigir Anexo I com
  descrição exaustiva do ativo e prova de anterioridade.

### As quatro perguntas de 11/06 ainda sem resposta registrada

- **imagem e voz**: se o processamento pela plataforma atrai o regime de dado
  pessoal sensível (art. 11 da LGPD);
- **premissas fiscais**: royalties remetidos a um Instrumento de Destinação e
  Rateio próprio;
- **teto de standby**: se a extensão por ata até 48 meses vale após o fim do
  embargo; e a **correção de citação**, o teto está ancorado no art. 49, **IV** da
  Lei 9.610 em cinco instrumentos, mas o dispositivo de prazo é o art. 49, **III**;
- **recurso de classificação de obra**: efeito suspensivo, prazos no segundo passo,
  e "mediação" contra "conciliação".

## 7. A tradução para o espanhol argentino: compromisso vencido

Em **26/08**, ao fim da primeira reunião com o PMI Argentina, o PM escreveu no
grupo: *"Mañana voy a generar la versión en español y se la envío por acá, por el
grupo, para un análisis preliminar; una vez validada, seguimos por los canales
formales."* "Mañana" era **27/08**. Hoje é **29/08**: **dois dias vencido**, e o
destinatário é o grupo de WhatsApp, não a plataforma.

O documento vinha nomeado na própria mensagem, *"nuestra plantilla de acuerdo de
cooperación entre capítulos"*: o **Acordo de Cooperação Bilateral** (doc 3).

**Qual texto traduzir.** O doc 3 é um dos cinco sem revisão jurídica, então não
existe versão aprovada dele. A base é o **texto revisado de 11/06**, na plataforma
como versão não publicada, com 35.190 caracteres, e **não** a v1.4 exibida hoje.
Conferir contra `doc03-acordo-cooperacao-bilateral.docx` antes de traduzir.

Três condicionantes já ditas pelo PM à contraparte:

1. o texto segue o **PMI Chapter Partnerships Framework** e o **PMI:Next, Guidance
   for Chapter Operations**;
2. *"cada capítulo deberá validar el texto con su propia asesoría legal local"*;
3. o envio é para **análise preliminar**.

Como o doc 3 não tem endosso jurídico, o aviso de rascunho precisa estar **dentro
do próprio documento**, em espanhol. E **es-AR não é o es-LATAM** dos três
dicionários da plataforma: voseo e terminologia jurídica local divergem, e a
variante argentina não deve realimentar o es-LATAM.

## 8. Dois achados de acervo, à margem do pacote

- **Ledger de assinaturas vazio.** `member_document_signatures` tem **0 linhas**
  para todos os 19 documentos. As assinaturas do Termo vivem em `certificates`, sob
  o tipo `volunteer_agreement`. Casa com a dívida do #1165.
- **Cadastro sem conteúdo.** O Manual de Governança e Operações R3 está em `draft`
  com **zero versões**.

---

## Ordem de trabalho

0. **Vencido (es-AR).** Gerar o Acordo Bilateral em espanhol argentino a partir do
   texto de 11/06, com o aviso de rascunho sem revisão jurídica dentro do próprio
   documento, e enviar ao grupo do PMI Argentina.
1. **Recuperar os `.docx` de 06/07.** Destrava a publicação de 1, 6 e 7.
2. **Investigar a v8 apagada do Termo.** Audit log registra a criação, a linha não
   existe, a numeração pula o 8. Começar pelo `#1187` (`3efce8b8`).
3. **Barato e contaminante.** Confirmar o inciso do art. 49 da Lei 9.610 e corrigir
   a citação nos cinco instrumentos.
4. **Decisão de produto do #632**: o que a `/library` exibe, e a diagramação com
   logo do capítulo sede.
5. **Redirect institucional.** O texto já está trocado nos drafts; falta a
   infraestrutura do redirect antes de imprimir o endereço.
6. **Publicar como v0** pelo chain workflow, nunca por UPDATE direto: os aprovados
   (1, 6, 7) depois do passo 1; os demais quando o ciclo dos seis restantes fechar.
7. **Pendente com terceiros.** Os seis documentos sem revisão e o webinar de PI e
   privacidade, propostos em 21/08 e sem resposta até 29/08.
