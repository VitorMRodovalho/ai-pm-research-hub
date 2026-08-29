# Recapitulação jurídica do acervo de documentos do Núcleo

**Medido em:** 2026-08-29 · **Guarda-chuva:** #632 · **Lane:** #2067 / `docs/recapitulacao-juridica`

Fontes cruzadas nesta medição: banco da plataforma (`governance_documents`,
`document_versions`, `member_document_signatures`), caixa institucional do Núcleo
(trilha de revisão jurídica de maio a agosto de 2026) e dois grupos de WhatsApp
exportados pelo PM (o grupo de documentos com o time jurídico e o grupo de
articulação com o PMI Argentina).

> **Ler o #632 antes deste arquivo.** Ele é o guarda-chuva do workstream e
> carrega decisões já ratificadas pelo PM, que esta lane executa e **não
> re-litiga**: documento aprovado entra como **v0 real** (a numeração de trabalho
> v1.4 / v2.7 / R3 não migra), **logo do capítulo sede e nunca o masterbrand
> PMI**, e **domínio institucional** (`nucleoia.pmigo.org.br`) nos instrumentos,
> com o redirect a ser corrigido antes de imprimir o endereço.

> **Convenção de privacidade.** Este repositório é público. Pessoas aparecem aqui
> por papel (advogada parecerista, advogado parecerista, presidência do capítulo,
> diretoria de voluntariado, contraparte do PMI Argentina), nunca por nome,
> e-mail ou telefone. O texto dos instrumentos vive fora do repositório (cadeia de
> governança em `.docx`, per SPEC-1153).

---

## 1. O objeto central não é o acervo, é o pacote revisado

O enunciado do PM foi: *"temos só o termo de voluntário atualmente dentro da
plataforma devidamente aprovado, dos 10 documentos, mas o time jurídico já havia
aprovado outros."* Está certo, e o #632 já dava a forma correta do problema:
existe um **pacote revisado** de nove instrumentos, e ele é a unidade de trabalho,
não as cadeias de versões da plataforma.

**O pacote está localizado.** Ele viaja como nove anexos `.docx` do e-mail de
**11/06/2026** ao time jurídico, nomeados de `doc01` a `doc09`:

| # | Anexo | Documento |
|---|---|---|
| 1 | `doc01-politica-governanca-pi.docx` | Política de Governança de Propriedade Intelectual |
| 2 | `doc02-termo-adesao-voluntario.docx` | Termo de Adesão ao Serviço Voluntário |
| 3 | `doc03-acordo-cooperacao-bilateral.docx` | Acordo de Cooperação Bilateral, Template Unificado |
| 4 | `doc04-anexo-tecnico-plataforma.docx` | Anexo Técnico, Plataforma Operacional |
| 5 | `doc05-adendo-retificativo-voluntario.docx` | Adendo Retificativo ao Termo de Adesão |
| 6 | `doc06-adendo-propriedade-intelectual.docx` | Adendo de PI aos Acordos de Cooperação |
| 7 | `doc07-declaracao-exclusao-pi.docx` | Declaração de Exclusão de PI e Autoria Independente |
| 8 | `doc08-termo-adesao-simplificado.docx` | Termo de Adesão Simplificado ao Acordo Bilateral |
| 9 | `doc09-acordo-operador-dpa.docx` | Acordo de Operador / Tratamento de Dados (art. 39 LGPD) |

## 2. Correção ao #632: o pacote subiu. O que não aconteceu foi a publicação

O #632 registra que "nenhum subiu". Na data em que foi escrito, 11/06, era
verdade. **Deixou de ser no mesmo dia.** A medição de hoje mostra que oito dos
nove documentos têm, dentro da plataforma, uma versão gravada em **11/06/2026**,
rotulada `draft-rev-juridica-2026-06-07`:

| Documento | Estado | Caracteres (markdown) | Publicada |
|---|---|---:|---|
| Acordo de Operador / DPA (doc 9) | `draft` | 47.747 | não |
| Política de Governança de PI (doc 1) | `under_review` | 43.753 | não |
| Acordo de Cooperação Bilateral (doc 3) | `under_review` | 35.190 | não |
| Adendo Retificativo (doc 5) | `under_review` | 20.437 | não |
| Adendo de PI (doc 6) | `under_review` | 15.643 | não |
| Anexo Técnico (doc 4) | `under_review` | 12.147 | não |
| Termo de Adesão Simplificado (doc 8) | `draft` | 12.121 | não |
| Declaração de Exclusão de PI (doc 7) | `draft` | 11.344 | não |
| **Total parado** | | **198.382** | |

O nono, o Termo de Adesão ao Serviço Voluntário (doc 2), é o único que completou
a volta: está `active`, com a versão `R3-C3-IP v9` ratificada em **07/07/2026**.

**O diagnóstico correto, portanto, não é "não importaram".** É que a importação
aconteceu e parou no passo seguinte: nenhuma das oito foi publicada ou travada, e
como o campo `version` de cada documento continua apontando para a versão
anterior (v1.4, v2.6, v2.7 conforme o caso), **a plataforma exibe o texto
pré-revisão e o texto revisado fica invisível**. Também explica por que os três
documentos que o #632 dava como ausentes (Declaração, Simplificado e DPA) hoje
existem: entraram nesse mesmo lote, cada um com uma única versão, não publicada.

Isso muda o custo da correção. Não é reimportar de fora: é publicar o que já está
dentro, sob o esquema v0 do #632.

## 3. O rótulo mente sobre o conteúdo

As oito versões chamam-se `draft-rev-juridica-2026-06-07`. O nome sugere a revisão
jurídica. **Não é ela.** As notas das oito descrevem a mesma coisa, e é outra: uma
varredura **editorial do próprio PM**, feita em 11/06 (#632), que trocou
"lifecycle" por "ciclo de vida", normalizou pontuação, renomeou "GP autor" para
"Autor da Plataforma" e removeu exemplos nominais.

A data no rótulo (07/06) é anterior à autoria real (11/06). Nesta base,
`version_label` é texto livre e não descreve o conteúdo: quem se guiar pelo
rótulo conclui que há revisão jurídica presa ali, e não há.

Não é motivo para renomear nada. Pela diretriz v0 do #632, essa numeração de
trabalho não migra, e a higiene vem de graça na publicação como v0.

## 4. A revisão jurídica de verdade: o que foi aprovado, e o que ficou fora

O ciclo com os dois pareceristas voluntários correu assim:

- **14/05** o PM envia a rodada de seis documentos para revisão jurídica voluntária;
- **05/06** chega a análise, redigida pelo advogado parecerista (Parecer nº 01/2026);
- **11/06** o PM devolve a rodada revisada dos **nove** documentos, com uma
  checagem cláusula a cláusula das doze recomendações do Parecer: **oito acolhidas
  integralmente** (a, b, d, f, g, h, k, l), **duas com divergência consciente de
  desenho** (e, j) e **duas pendentes de validação fina** (c, i);
- **06/07** o parecerista envia **quatro recomendações novas** e, no mesmo dia,
  ambos dão o de acordo nos documentos **1, 2, 6 e 7**;
- **07/07** a presidência do capítulo aprova o Termo na plataforma e o fluxo de
  assinatura da nova coorte começa;
- **21/08** o PM propõe ao jurídico as duas frentes seguintes: fechar os **seis
  documentos restantes** e estruturar o webinar de PI e privacidade. Sem resposta
  registrada até 29/08.

**Cobertura jurídica, documento a documento:**

| Aprovado em 06/07 | Ainda sem revisão jurídica |
|---|---|
| 1 Política de Governança de PI | 3 Acordo de Cooperação Bilateral |
| 2 Termo de Adesão ao Serviço Voluntário | 4 Anexo Técnico |
| 6 Adendo de PI aos Acordos | 5 Adendo Retificativo |
| 7 Declaração de Exclusão de PI | 8 Termo de Adesão Simplificado |
| | 9 Acordo de Operador / DPA |

## 5. O pacote de 06/07 é o que falta localizar

Há uma segunda versão do pacote, posterior ao que está na plataforma. Na tarde de
**06/07** o PM consolidou as recomendações em `.docx`, marcando em vermelho as
partes alteradas, e compartilhou os arquivos. O de acordo do jurídico veio sobre
**esses** arquivos, no mesmo dia.

Esse pacote **não está no e-mail e não está na plataforma**: foi compartilhado
pelo WhatsApp, e a exportação do grupo traz apenas `<Media omitted>` nessa
mensagem. Consequência prática:

- para os documentos **1, 6 e 7**, o texto que o jurídico aprovou é o de 06/07, e
  a versão que a plataforma guarda é a de 11/06, anterior a ele;
- o único caso recuperável hoje é o documento **2**: seu texto aprovado entrou na
  plataforma como `R3-C3-IP v9` em 07/07, e serve de referência do que a
  consolidação de 06/07 mudou.

**Primeiro passo desta lane:** recuperar os `.docx` de 06/07 na origem (mídia do
WhatsApp do PM ou o Drive onde foram gerados). Sem eles, publicar 1, 6 e 7 como v0
publicaria texto que o jurídico não viu.

### As quatro recomendações de 06/07, para conferir contra esses arquivos

- **(a)** cláusula de coordenação internacional de depósitos de patentes no Adendo
  de PI, observando a prioridade unionista (art. 4º da Convenção da União de Paris
  e art. 16 da Lei nº 9.279/1996), para evitar perda de novidade;
- **(b)** termos de cessão de direitos patrimoniais assinados pelos autores e
  inventores no ato do protocolo junto ao INPI, porque a aprovação tácita por
  silêncio prevista na governança interna não tem eficácia perante a autarquia,
  que exige documento formal escrito;
- **(c)** auditoria de dados pessoais no fluxo de transferência internacional,
  habilitando o Encarregado a verificar periodicamente a conformidade dos
  capítulos parceiros com as SCCs e a ANPD;
- **(d)** na Cláusula Primeira da Declaração de Exclusão de PI, exigir Anexo I com
  descrição exaustiva do ativo e prova de anterioridade, sob pena de ineficácia da
  declaração quanto ao ativo omitido ou genérico.

### As quatro perguntas de 11/06 ainda sem resposta registrada

- **imagem e voz** (divergência consciente): se o processamento de imagem e voz
  pela plataforma atrai o regime de dado pessoal sensível (art. 11 da LGPD);
- **premissas fiscais** (divergência consciente): tributação de royalties remetida
  a um Instrumento de Destinação e Rateio próprio, antes do primeiro royalty;
- **teto de standby**: se a extensão por ata até 48 meses é aceitável após o fim
  do embargo editorial; e a **correção de citação**, o teto está ancorado no
  art. 49, **IV** da Lei 9.610 em cinco instrumentos, mas o dispositivo de prazo é
  o art. 49, **III** (o IV é territorial);
- **recurso de classificação de obra**: efeito suspensivo expresso, prazos no
  segundo passo, e se o termo é "mediação" ou "conciliação".

O item do art. 49 é o mais barato e o mais contaminante: uma citação errada
replicada em cinco instrumentos.

## 6. A tradução para o espanhol argentino: compromisso com data, e vencido

Não é tarefa a planejar. É promessa feita, com destinatário e prazo.

Em **26/08/2026**, ao fim da primeira reunião com o PMI Argentina, o PM escreveu
no grupo: *"Mañana voy a generar la versión en español y se la envío por acá, por
el grupo, para un análisis preliminar; una vez validada, seguimos por los canales
formales."* "Mañana" era **27/08**. Hoje é **29/08**: o compromisso está **dois
dias vencido**, e o destinatário é o grupo de WhatsApp com a contraparte, não a
plataforma.

O documento também já estava determinado pela própria mensagem, *"nuestra
plantilla de acuerdo de cooperación entre capítulos"*, ou seja o **Acordo de
Cooperação Bilateral, Template Unificado** (doc 3). Não era suposição: é
compromisso registrado, e a escolha do PM em 29/08 confirma o mesmo documento.

**Qual texto traduzir.** O doc 3 é um dos cinco que o jurídico ainda não revisou,
então não existe versão aprovada dele. A base correta é o **texto revisado de
11/06**, que está na plataforma como versão não publicada, com 35.190 caracteres
de markdown, e **não** a v1.4 que a plataforma exibe hoje. Conferir contra
`doc03-acordo-cooperacao-bilateral.docx` do e-mail de 11/06 antes de traduzir: as
duas devem ser o mesmo texto, e é barato provar.

Três condicionantes já ditas pelo PM à contraparte, que a tradução precisa honrar:

1. o texto segue o **PMI Chapter Partnerships Framework** e o **PMI:Next, Guidance
   for Chapter Operations**, ambos já enviados ao grupo;
2. *"cada capítulo deberá validar el texto con su propia asesoría legal local, ya
   que somos entidades jurídicas independientes"*;
3. o envio é para **análise preliminar**; só depois de validado seguem os canais
   formais.

**O que a medição acrescenta:** como o doc 3 não tem endosso jurídico, o aviso de
que é rascunho para conversa, e não peça a ratificar, não é formalidade de
tradução. Precisa estar dito **dentro do próprio documento**, em espanhol, não só
na mensagem que o acompanha.

E a variante importa: **es-AR não é o es-LATAM** que a plataforma usa nos três
dicionários. Voseo e terminologia jurídica local divergem. Sendo rascunho para
conversa e não instrumento a assinar, a variante argentina é a escolha certa para
o destinatário, e não deve realimentar o es-LATAM da plataforma.

## 7. Dois achados de acervo, à margem do pacote

- **O ledger de assinaturas está vazio.** `member_document_signatures` tem **0
  linhas** para todos os 19 documentos. As assinaturas do Termo vivem em
  `certificates`, sob o tipo `volunteer_agreement`. O ledger existe, está modelado
  e não é usado, o que casa com a dívida registrada em #1165.
- **Cadastro sem conteúdo.** O Manual de Governança e Operações R3 está em `draft`
  com **zero versões**.

---

## Ordem de trabalho

A ordem do #632 continua valendo. O que a medição de hoje altera é o passo 1, que
deixa de ser "inventariar e localizar" e passa a ser "recuperar o pacote de 06/07",
e acrescenta um item vencido na frente de tudo.

0. **Vencido (es-AR).** Gerar o Acordo Bilateral em espanhol argentino a partir do
   texto revisado de 11/06, com o aviso de rascunho sem revisão jurídica dentro do
   próprio documento, e enviar ao grupo do PMI Argentina.
1. **Recuperar os `.docx` de 06/07** (mídia do WhatsApp ou Drive de origem). É o
   que destrava a publicação de 1, 6 e 7.
2. **Barato e contaminante.** Confirmar com o jurídico o inciso do art. 49 da Lei
   9.610 e corrigir a citação nos cinco instrumentos.
3. **Decisão de produto do #632**: o que a `/library` exibe, e o modelo de
   diagramação com logo do capítulo sede.
4. **Corrigir o redirect** de `nucleoia.pmigo.org.br` antes de imprimir o endereço
   nos instrumentos.
5. **Publicar como v0** pelo chain workflow de governança, nunca por UPDATE
   direto: os aprovados (1, 6, 7) depois do passo 1; os demais quando o ciclo
   jurídico dos seis restantes fechar.
6. **Pendente com terceiros.** Os seis documentos ainda sem revisão e o webinar de
   PI e privacidade, ambos propostos ao jurídico em 21/08 e sem resposta até 29/08.
