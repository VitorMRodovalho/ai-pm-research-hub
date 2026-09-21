# ADR-0131 - Convidado externo e VINCULO, nao atributo da pessoa

**Status:** Accepted (2026-09-20)
**Ratificado por:** decisao do dono, apos a pergunta literal: *"Na tabela de usuarios ter uma coluna
alem de voluntario ativo e organizacao ligada e se externo ou nao? E o externo so ativo quando a
iniciativa que ele tiver ainda estiver ativa?"*
**Contexto de origem:** piloto do Hackathon de Impacto Social, que recebe participantes de tres
entidades externas ao Nucleo. #2393 (vaga por tema) e #2395 sao vizinhas.

## Contexto

Um piloto com entidades parceiras precisou incluir pessoas que **nao sao voluntarias do Nucleo**. A
proposta inicial foi uma coluna booleana em `members` dizendo se a pessoa e externa, e uma regra de
que o externo so fica ativo enquanto a iniciativa dele estiver ativa.

Antes de decidir, o modelo foi medido em 2026-09-20.

## O que ja existe, medido

**"Externo" ja e dito por tres caminhos, todos em uso:**

| onde | valores | linhas em uso |
|---|---|---:|
| `members.operational_role` | `guest` | 12 |
| `members.chapter` | `Externo`, `Outro` | 6 |
| `engagements.kind` | `ambassador` 17 · `speaker` 14 · `sponsor` 5 · `external_reviewer` 3 · `guest` 2 | 41 |

**Prazo no vinculo ja e a norma:** 225 dos 318 engajamentos (71%) tem `end_date`. Ha tres bases
legais em uso (`consent`, `contract`, `legitimate_interest`), e `legitimate_interest` e a que o
`create_external_signer_invite` ja aplica a externo.

**A cascata que a proposta queria criar ja se comporta como esperado:** 2 iniciativas arquivadas, 8
engajamentos nelas, e **zero** ativos sem prazo. Controle positivo: 147 ativos em iniciativas
ativas, logo a consulta enxerga.

**Organizacao:** `organization_id` existe em `members`, `persons` e `engagements`, com guard proprio
(`multi-org-isolation`), e ha **1** organizacao. Estrutura multi-org existe, dado e mono-org.

## Decisao

### 1. NAO criar coluna booleana de "externo" em `members`

Seria a **quarta** fonte para um conceito que tres ja expressam, e a ADR-0012 existe por causa
disso: o caso que a originou foi tres colunas para o mesmo status.

A razao de fundo e mais forte que a contagem: **"externo" nao e atributo da pessoa, e do vinculo.**
A mesma pessoa pode ser palestrante convidada num evento e, meses depois, voluntaria aprovada num
ciclo. Um booleano em `members` a obriga a ser uma coisa so, e transfere para um humano a obrigacao
de virar a chave na hora certa. O `kind` do engajamento nao tem esse problema porque nasce por
vinculo e morre com ele.

### 2. NAO derivar "externo ativo" para uma coluna

A regra "externo so ativo enquanto a iniciativa estiver ativa" e **correta e ja observada**. Gravar
o resultado dela numa coluna criaria estado que pode divergir do fato, e obrigaria a manter
sincronia - exatamente o que a ADR-0012 manda evitar. O estado vive em
`engagements.status` + `end_date` cruzado com `initiatives.status`.

### 3. O que FAZER, em vez da coluna

- **Um `kind` de engajamento para convidado de iniciativa.** Hoje falta o valor certo: `guest` e
  recusado por iniciativa de kind `workgroup` (`Engagement kind "guest" not allowed for initiative
  kind "workgroup"`), e `workgroup_member` afirma pertencimento que o externo nao tem. Segue o
  espirito do `external_signer`, que ja existe para outro proposito.
- **O magic-link de autopreenchimento.** `create_external_signer_invite` cria pessoa e member e
  devolve `'note': 'Magic-link URL generation pending Phase IP-3 Edge Function.'`. A metade que o
  dono pediu ("deixa eles mesmos preencherem") e a que **nao esta construida**.
- **Uma invariante**, nao uma coluna: engajamento ativo nao sobrevive a iniciativa arquivada.

## Consequencias

- **Positiva:** nada a manter em sincronia, e a pergunta "esta pessoa e externa?" continua tendo uma
  resposta por vinculo, que e a unica que nao envelhece.
- **Positiva:** o `chapter_code` deixa de ser bloqueio. A invariante
  `U_active_person_has_primary_chapter_affiliation` so alcanca quem tem capitulo dentro do
  `chapter_registry`; `EXTERNAL` nao esta la, entao externo sai do denominador por desenho.
- **Custo aceito:** quem quiser contar externos precisa consultar por `kind`, nao por flag. E uma
  consulta a mais e um estado a menos.
- **Nao resolvido aqui:** o magic-link. Sem ele, criar externo continua sendo ato de administrador,
  e o autopreenchimento nao existe.

## O que esta declarado como NAO medido

A cascata de arquivamento tem **amostra pequena**: 2 iniciativas arquivadas e 8 engajamentos. Zero
violacoes e consistente com "a cascata funciona" **e** com "ela nunca foi exercida de verdade". A
invariante do item 3 nasceria verde, e guard que nasce verde sobre dado limpo e barato - mas antes
de afirmar que a cascata funciona, arquive uma iniciativa de teste e meca.

Cross-ref: ADR-0012 (fonte unica por conceito), #2393 (vaga por tema), #2395 (board null).
