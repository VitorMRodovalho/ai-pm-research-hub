# Plano de ondas e lanes — como parar o backlog de crescer

**Medido em 23/08/2026.** Todos os números vieram de consulta na hora (`gh issue list`, leitura dos
workflows). Nenhum é recitado.

---

## 1. O diagnóstico, medido

### A lista cresce, e está acelerando

| data | issues abertas |
|---|---:|
| 01/05/2026 | 23 |
| 01/06/2026 | 106 |
| 01/07/2026 | 91 |
| 01/08/2026 | 137 |
| **23/08/2026** | **244** |

Fechadas no total: **666**. Ou seja, o time fecha muito — o problema não é falta de entrega.

Saldo por semana nas últimas 12 (abriu menos fechou): **9 das 12 foram positivas**, e as duas
últimas foram as piores da série: **+51** e **+42**.

### A causa não é desleixo, é assimetria de vazão

Das 116 issues abertas nos últimos 21 dias, a esmagadora maioria é **achado de auditoria medido**,
não pedido de feature. Os títulos denunciam: "o guard fica verde", "N de M pessoas", "a métrica diz
100% e a tela diz 61%", "o gatilho dispara numa transição mas a elegibilidade tem quatro campos".

**A capacidade de AUDITAR passou a capacidade de REMEDIAR.** Cada sessão profunda produz de 5 a 15
achados. Isso é a auditoria funcionando, e não dá para "consertar" desligando o que acha.

### O defeito real não é o tamanho, é a triagem

| medida | valor |
|---|---:|
| abertas | 244 |
| **sem label de prioridade** | **123 (50%)** |
| sem label de onda | 52 |
| paradas há mais de 30 dias | **0** |

⚠️ **Zero issues obsoletas.** Não existe a alavanca fácil de "fechar o que morreu" — a lista está
viva. O que existe é metade dela sem prioridade, e uma lista sem prioridade não é fila, é depósito.

---

## 2. A restrição real de paralelismo (e ela não é o número de temas)

Antes de propor N lanes, medi o que limita N. **Não é a quantidade de assuntos.**

### A faixa do banco serializa TODAS as PRs

`.github/actions/wait-for-db-lane` põe `validate` e `check-invariants` numa fila de runtime sobre o
**banco de produção compartilhado**. Não é por branch: é global, e inclui a `main`.

| parâmetro medido | valor |
|---|---|
| duração do `validate` | mediana **735-763s**, máximo observado **1552s** |
| teto de espera (`max-wait-seconds`) | **3600s** |
| critério de desistência (`stuck-seconds`) | 1800s sem a cabeça da fila mudar |

**Toda PR consome a faixa**, porque `validate` é required em todas, independentemente do que a PR
muda. Com mediana de ~12,5 min:

- 3 PRs à frente = ~37 min de espera. Confortável.
- 4 PRs à frente = ~50 min. Dentro do teto, mas apertado.
- **5 PRs à frente = ~62 min. Estoura os 3600s.**

### Duas restrições que não são de CI

- **DDL em banco compartilhado:** quem aplica migration antes do merge deixa as outras branches
  vermelhas (#1910, medido). Só **uma** lane pode aplicar DDL por vez.
- **Árvore de trabalho compartilhada:** medido em 22-23/08, uma lane trocou a branch do diretório
  por baixo de outra sessão. **`git worktree` por lane é obrigatório**, não recomendação.

### A resposta ao "quantas branches em paralelo"

**Três lanes de trabalho + a sessão main que mergeia.** Quatro PRs em voo é o limite que a faixa do
banco sustenta com folga. Propor 8 lanes temáticas seria planejar uma vazão que não existe: as PRs
ficariam esperando em fila e a espera apareceria como CI lenta, não como plano errado.

---

## 3. O desenho das lanes: por SUPERFÍCIE DE COLISÃO, não por tema

Agrupar lane por assunto é o instinto errado aqui, porque duas lanes de temas diferentes colidem se
as duas mexem em schema. O que separa de verdade é **o que a lane pode escrever**.

| lane | pode | não pode | fila |
|---|---|---|---|
| **L1 · SCHEMA** | `apply_migration`, DDL, corpo de RPC | — | é a única com DDL; serializa por natureza |
| **L2 · ESTRUTURAL** | guards, CI, docs, frontend, i18n | qualquer DDL, qualquer escrita de dado | nunca colide em dado |
| **L3 · DADOS/OPS** | escrita via RPC canônica, backfill, medição, superfície MCP | DDL | colide com L1 se L1 mexer na mesma tabela |
| **main** | mergear | segurar lane | nunca abre PR própria |

**Regra de ouro:** se uma onda precisa de DDL **e** de frontend, ela vira duas PRs em lanes
diferentes, com a de schema primeiro. Não uma PR grande.

---

## 4. Os 244 agrupados por tema

Agrupamento derivado do título e das labels. Um item cai no primeiro tema que casa, então a
contagem é de atribuição única.

| tema | issues | sem prioridade |
|---|---:|---:|
| seleção · VEP · filiação | 39 | 20 |
| presença · XP · onboarding | 37 | 22 |
| CI · suíte · infra | 31 | 19 |
| MCP | 28 | 14 |
| agenda · eventos | 28 | 19 |
| governança · docs · termo | 27 | 5 |
| board · card · portfólio | 13 | 8 |
| outros | 11 | 4 |
| comms · curadoria · vídeo | 10 | 2 |
| admin UI · frontend | 10 | 6 |
| segurança · LGPD · PII | 6 | 1 |
| dados · KPI · métricas | 4 | 3 |


## presenca-xp-onboarding (37)
  #1886 #1885 #1884 #1881 #1880 #1877 #1875 #1870 #1826 #1776 #1729 #1728 #1726 #1714 #1713 #1710 #1656 #1654 #1652 #1634 #1602 #1531 #1528 #1277 #1218 #1209 #1171 #1069 #1044 #1014 #983 #873 #809 #718 #617 #591 #300

## selecao-vep-filiacao (39)
  #1895 #1888 #1867 #1866 #1863 #1857 #1854 #1852 #1850 #1838 #1777 #1762 #1694 #1691 #1668 #1664 #1662 #1614 #1588 #1581 #1580 #1579 #1576 #1575 #1574 #1573 #1358 #1310 #1134 #1102 #1095 #1045 #1031 #935 #888 #704 #485 #348 #132

## ci-suite-infra (31)
  #1940 #1939 #1932 #1929 #1925 #1896 #1848 #1844 #1830 #1744 #1742 #1696 #1695 #1693 #1582 #1567 #1565 #1533 #1520 #1403 #1394 #1381 #1340 #1221 #1185 #1106 #1078 #934 #612 #601 #235

## mcp (28)
  #1915 #1829 #1780 #1749 #1681 #1672 #1670 #1620 #1610 #1601 #1600 #1578 #1571 #1558 #1556 #1428 #1356 #1292 #1183 #912 #885 #707 #280 #208 #207 #206 #93 #92

## agenda-eventos (28)
  #1911 #1910 #1906 #1876 #1699 #1676 #1675 #1661 #1658 #1655 #1607 #1604 #1603 #1561 #1560 #1557 #1537 #1494 #1416 #1415 #1398 #1032 #1009 #1008 #811 #633 #172 #108

## board-card-portfolio (13)
  #1903 #1901 #1858 #1671 #1628 #1592 #1570 #1354 #1055 #1019 #981 #909 #588

## seguranca-lgpd-pii (6)
  #1748 #1631 #1617 #1025 #1018 #939

## governanca-docs-termo (27)
  #1882 #1814 #1213 #1169 #1165 #1164 #1152 #1059 #1056 #989 #970 #945 #727 #661 #641 #632 #574 #573 #455 #335 #334 #311 #210 #204 #200 #173 #165

## comms-curadoria-video (10)
  #1917 #1697 #1414 #1374 #1094 #942 #911 #883 #96 #95

## dados-kpi-metricas (4)
  #1700 #1669 #1355 #233

## admin-ui-frontend (10)
  #1869 #1685 #1590 #1219 #1205 #1184 #1135 #1046 #737 #109

## outros (11)
  #1916 #1855 #1842 #1751 #1577 #1061 #1006 #736 #638 #634 #587

---

## 5. A ordem das ondas, e por quê

Uma onda = um tema, atribuído à lane cuja superfície ele exige. Ondas rodam em sequência; as
**lanes** é que rodam em paralelo dentro de cada onda.

### Onda 0 — TRIAGEM (bloqueia as outras, e é curta)

**Antes de qualquer onda temática.** 123 issues sem prioridade tornam impossível escolher o que
entra numa onda. Sem isto, toda onda começa com uma discussão de escopo.

- Rotular prioridade e onda nas 123. Não precisa de análise: prioridade grosseira serve.
- Criar `origin:audit` vs `origin:request` — hoje não dá para separar "achado de guard" de "pedido
  de gente", e são filas com economia diferente.
- Lane: **L2**. Sem código, sem DB.

### Onda 1 — PRESENÇA · XP · ONBOARDING (37)

Vai primeiro entre as temáticas porque **tem prazo vivo**: o selo grava 24/08 08h40, e a decisão
sobre o piso está em aberto. Além disso #1877 já é épica de jornada e #1652 é épica de presença,
então o escopo já está parcialmente desenhado.

- L3 (dados/ops): correções de registro, medição, decisão do piso.
- L1 (schema): #1656 (3 semânticas de presença sem SSOT), #1652.
- L2: #1654 (coluna fixa), #1655 (a grade escrita 4 vezes).

### Onda 2 — CI · SUÍTE · INFRA (31)

Vem logo depois porque é **multiplicadora de vazão**: enquanto o `validate` custa 12,5 min de faixa
serializada, toda onda seguinte paga esse pedágio. Itens que atacam isso diretamente: #1911 (nada
re-mede a main quando muda o banco), #1925 (decisão do PM, pendente), #1932 (lote de autoridade),
#1844/#1869 (validate estoura o teto), #1939/#1940 (higiene de repo).

- Lane: **L2** quase inteira. É a onda mais paralelizável.

### Onda 3 — SELEÇÃO · VEP · FILIAÇÃO (39)

Maior aglomerado, e dirigido pelo calendário do ciclo. Tem sub-blocos claros: filiação PMI
(#1852-#1867), avaliação do comitê (#1838, #1895), formulário/VEP (#1573-#1581).

### Onda 4 — MCP (28) **em paralelo com** AGENDA · EVENTOS (28)

Os dois cabem juntos porque **quase não colidem**: MCP é superfície de tool (L3), agenda é schema +
frontend (L1+L2).

### Onda 5 — GOVERNANÇA · DOCS · TERMO (27)

Tem só 5 sem prioridade, ou seja, é o aglomerado mais bem triado da lista. Deixa para depois
justamente por isso: ele não perde qualidade esperando.

### Depois: board/card (13), comms (10), admin UI (10), segurança (6), KPI (4), outros (11)

---

## 6. Como parar a lista de crescer

O erro seria mirar em "fechar mais". A medição diz outra coisa: **o time já fecha 666**, e mesmo
assim o saldo é positivo em 9 de 12 semanas. Três mecanismos, nesta ordem:

### (a) Cota de fechamento por onda

Uma onda só fecha quando fecha **mais do que abriu**. Hoje uma onda de auditoria abre 15 e fecha 3,
e o saldo entra na lista sem ninguém decidir. A cota transforma isso em decisão explícita: ou se
remedeia mais, ou se declara que o achado vira dívida aceita — **com rótulo**, não por omissão.

### (b) Separar o que a auditoria acha do que as pessoas pedem

`origin:audit` e `origin:request`. Sem isso, a lista mistura duas economias: achado de guard tem
custo de remediação conhecido e prioridade derivável do risco; pedido de gente tem prazo e dono.
Misturados, os dois se atrapalham e nenhum é priorizado direito.

### (c) Teto de abertura por sessão

Uma sessão que acha 15 defeitos deve abrir as 15 — não se esconde achado. Mas deve **fechar a
sessão com uma proposta de agrupamento**, não com 15 issues soltas. Épicas já vêm sendo usadas
(#1877, #1780, #1652, #1700, #1699); a regra é torná-las obrigatórias acima de 5 achados no mesmo
subsistema.

---

## 7. Coleta de LL, legado e modernização durante as ondas

Hoje a coleta existe (issue `[LL]` permanente + `pmo-sync.sh harvest`), mas depende de lembrar.
Proposta de torná-la parte do fechamento de onda:

**No fechamento de cada onda, três saídas obrigatórias:**

1. **LL para o framework** — o que mudou no jeito de trabalhar, não no código. Vai na issue `[LL]`
   e é colhido pelo PMO. Critério: se a lição vale para outro projeto, é LL de framework; se vale só
   aqui, é memória do projeto.
2. **Legado encontrado** — código/dado que a onda tocou e que está vivo por inércia. Rótulo
   `type:legacy`. Não vira trabalho na hora; vira **inventário datado**, para a decisão de aposentar
   ser tomada com o custo à vista.
3. **Modernização** — dependência, versão, padrão. Rótulo `type:modernization`. Separado do defeito
   de propósito: hoje #1617 (Astro com 3 advisories de XSS) e #1620 (spec MCP deprecando o
   transporte) estão na mesma fila que bugs de dado, e competem mal.

⚠️ **Por que rótulo separado e não issue separada:** a lista já tem 244. Criar uma segunda lista
para modernização só move o problema. O rótulo permite consultar como fila própria sem duplicar
gestão.

---

## 8. O que isso muda na prática, em uma frase por item

| decisão | hoje | proposto |
|---|---|---|
| nº de lanes paralelas | improvisado | **3 + main**, pela faixa do banco |
| critério da lane | tema | **superfície de colisão** (DDL / estrutural / dados) |
| worktree | opcional | **obrigatório** por lane |
| DDL | qualquer lane | **só L1**, uma por vez |
| triagem | 50% sem prioridade | onda 0 fecha a lacuna antes de começar |
| saldo da onda | emergente | **cota explícita**: fecha mais do que abre, ou rotula a dívida |
| LL / legado / modernização | quando alguém lembra | **saída obrigatória** do fechamento de onda |

---

## 9. Riscos deste plano, ditos na frente

- **A cota de fechamento pode incentivar a NÃO abrir issue.** É o efeito perverso óbvio. Mitigação:
  a cota é da onda, não da sessão, e "rotular como dívida aceita" conta como desfecho.
- **Três lanes exigem três contextos vivos.** Se não houver gente/sessão para três, o plano vira
  uma lane e duas paradas — que é pior do que duas lanes bem alimentadas. **Dimensione pelo que há.**
- **A ordem das ondas é minha recomendação, não medição.** O que é medido é o agrupamento, o
  gargalo e o saldo. A sequência é julgamento e é sua para trocar.
- **O agrupamento por regex tem imprecisão.** Um item cai no primeiro tema que casa; alguns
  poderiam pertencer a dois. Serve para dimensionar onda, não para fechar escopo.
