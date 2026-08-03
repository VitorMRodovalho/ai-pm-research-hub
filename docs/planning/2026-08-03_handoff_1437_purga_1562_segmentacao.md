# Handoff 03/08/2026 — purga da #1437, correção da #1562, e um vermelho herdado (#1565)

> ⚠️ **Nenhum número aqui vale como medição.** Medidos em 03/08 de madrugada. Re-consulte a fonte.

Continuação de `2026-08-02_handoff_1437_sintetico_alcanca_campanha.md`, com duas decisões do Vitor.

## 1. #1437 — o que ela era, e o que sobrou

Aberta em 20/07 ao estranhar "96 membros ativos" na home. Tinha dois pendentes.

**Pendente 2 (redefinir "membros ativos" para operacional-only): já estava FEITO** por sessão
anterior — não por este trabalho. Medido: `v_operational_members` existe, `get_homepage_stats()`
devolve `members: 69`, `v_active_members` (88) segue para outros usos.

**Pendente 1 (purgar as sintéticas): executado nesta sessão.**

### Correção de um erro meu

Eu havia afirmado que as 10 linhas soft-retiradas estavam "inalcançáveis, sem risco". Isso valia
**só para campanha**. Medido depois: o log continuava crescendo sobre elas (última linha 03/08
01:40:03), com 13 registros em 7 dias, 11 varreduras de teardown do Drive em 14 dias, e
`member_offboarding_records` subindo de 9 para 10.

Pior: **parte disso foi causada pelo meu próprio soft-retire.** Ao setar `offboarded_at` eu coloquei
a 10ª na esteira de desligamento — ela ganhou registro de offboarding e varredura de teardown do
Drive **8 minutos depois** do UPDATE. O tratamento ratificado em 20/07 tira da campanha e empurra
para outra fila.

### A purga (migration `20260805000503`)

Decisão do Vitor: **apagar com registro**. Justificativa: `pii_access_log` existe para provar quem
acessou dado pessoal DE QUEM, e não há pessoa por trás dessas linhas — sem titular não há dado
pessoal nem direito a documentar.

Descobri no caminho que `target_member_id` **é nullable**, então orfanar em vez de apagar era
possível — uma quarta via que eu não havia oferecido. Descartada de propósito e registrado na
migration: 633 linhas dizendo "acessou campos de \<alvo desconhecido\>" seriam indistinguíveis de
anonimização de dado REAL, e um auditor futuro não teria como separar as duas coisas.

| | antes | depois |
|---|---|---|
| membros sintéticos | 10 | **0** |
| `members` | 131 | 121 |
| `pii_access_log` | 26.395 | 25.762 (**-633**) |
| `v_operational_members` / home | 69 | **69** |
| destinatários da campanha de 02/08 | 89 | **89** |
| invariantes violadas | 0 | **0** |

O registro do envio de 02/08 foi **preservado**: o destinatário sintético virou contato externo
(`member_id` NULL, e-mail no campo `external_email`), porque aquela campanha realmente teve 89
destinatários e reescrever isso seria falsear o histórico. A migration se **recusa a rodar** se o
alvo não for exatamente 10 linhas de domínio reservado — uma purga que erra o conjunto é pior que
uma que não acontece.

## 2. #1562 — `include_inactive` anulava a segmentação

`v_include_inactive` estava no MESMO `OR` dos filtros de segmento, então o checkbox tornava a
cláusula inteira verdadeira e descartava papel, designação e capítulo.

Semântica confirmada pelo Vitor: **filtro vazio sem `all` continua devolvendo 0**, e
`include_inactive` significa **união** (ativos + inativos) dentro do segmento.

Medido contra os dados reais (migration `20260805000504`):

| combinação | antes | depois |
|---|---|---|
| `all`, sem inativos | 88 | 88 |
| `all` + inativos | 121 | 121 |
| `chapter_liaison`, sem inativos | 10 | 10 |
| **`chapter_liaison` + inativos** | **121** | **11** |
| filtro vazio sem `all` | 0 | 0 |
| **filtro vazio + inativos** | **121** | **0** |

O pior caso era o filtro vazio: um clique acidental disparava para a base inteira.

### Um desvio de escopo, declarado

Ao escrever o guard descobri que ele cairia num `catch` e **passaria sempre**: a introspecção
existente (`_audit_list_public_function_bodies`) devolve md5 e tamanho, não o corpo, e sem o texto
não dá para afirmar "esta cláusula não existe". Criei `_audit_function_source(text)` (migration
`20260805000505`, SECDEF, EXECUTE só para `service_role`, revogado de anon/authenticated) para o
guard ler o corpo **vivo** em vez do arquivo de migration — afirmar o local da definição barraria
refatoração legítima. Sem isso eu teria entregue uma defesa decorativa.

O guard foi verificado por discriminação: aplicado ao corpo vivo, verde; aplicado ao corpo anterior
(que tem o defeito), vermelho. Não mutei a função em produção porque isso abriria uma janela real
de bypass numa função de envio.

## 3. #1565 — vermelho herdado, NÃO causado por este trabalho

`npm test` fecha com **1 falha**: `#676 live: drift report surfaces missing future occurrences`.

A tribo ROI & Portfólio tem **duas séries futuras**: 9 quartas (correto, criadas hoje 06:00 UTC) e
**8 terças espúrias** (criadas semanalmente entre 15/06 e 27/07). A regra diz quarta
(`day_of_week=3`, âncora numa quarta) e 16 das 17 ocorrências passadas foram quarta. O
materializador vinha gerando **um dia antes** e passou a gerar certo sem limpar o que criou errado —
assinatura da armadilha de coluna `date` parseada como UTC.

O vermelho nasceu **hoje às 06:00 UTC**, quando as quartas foram materializadas: antes disso o
invariante fechava. Não é flake nem regressão de código — é dado vivo mudando sob um teste que lê a
produção.

Os 8 eventos de terça estão vazios (0 presença, 0 ponto). **Decisão do Vitor: registrar e não
apagar por ora.** Consequência: o `validate` segue vermelho para qualquer PR até a limpeza.

⚠️ A primeira terça espúria é **04/08**, o dia do webinar da tribo.

## 4. Estado

- **#1437**: pendentes 1 e 2 ambos resolvidos → candidata a fechar.
- **#1562**: corrigida, com guard de duas camadas.
- **#1565**: aberta, sem trabalho.
- **#1561, #1556, #1205, #1557, #1558, #1560**: sem trabalho.
- Trilha B (base legal dos 941 externos): desbloqueada, não iniciada.

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
