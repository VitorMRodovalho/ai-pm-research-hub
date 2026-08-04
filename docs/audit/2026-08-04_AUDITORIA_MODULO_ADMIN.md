# Auditoria do módulo administrativo - 04/08/2026

**Pergunta da sessão:** o problema do Fernando é sistêmico ou pontual?
**Veredito:** **sistêmico**, e não é do lado da autoridade. É do lado da **tela**.
**Escopo:** diagnóstico + recomendação. Nenhuma cirurgia feita, nenhuma concessão proposta.

Todos os números abaixo vêm de tool call do turno de 04/08 (89 membros ativos, 1691 chamadas
`can_by_member`, `pg_proc` lido ao vivo). Onde o handoff anterior divergia, o número vivo prevalece e
a divergência está anotada.

---

## 1. O achado central: quatro vocabulários de autoridade, e o menu usa o mais fraco

O módulo admin decide "quem vê o quê" em quatro linguagens diferentes, que não conversam:

| # | vocabulário | onde vive | quem consome | é fronteira real? |
|---|---|---|---|---|
| 1 | `Permission` (`admin.access`, `admin.campaigns`, …) via `hasPermission()` | `src/lib/permissions.ts:118-322` (tabelas `TIER_PERMISSIONS` + `DESIGNATION_PERMISSIONS`) | **o menu lateral inteiro** (`AdminSidebar.tsx:222-227`) | **não** - só mostra/esconde link |
| 2 | `AccessTier` + allowlist por rota via `canAccessAdminRoute()` | `src/lib/admin/constants.ts:59-93` | ~9 scripts de página | não - client-side |
| 3 | ações V4 via `canFor()` / `canForAdminEntry()` | `src/lib/permissions.ts:507-583` | **2 componentes**, de 54 rotas | não - client-side |
| 4 | `can_by_member(action)` no corpo do RPC | `pg_proc` | os RPCs | **sim - a única** |

O vocabulário 1 é derivado de `operational_role` + `designations`, isto é, do **cache de exibição**.
O vocabulário 4 é derivado de `engagements`. São populações diferentes por construção.

Consequência medida sobre os 89 membros ativos:

```
entra pelo V4 (canForAdminEntry) E vê algum item de menu:   29
entra pelo V4 mas o menu está VAZIO:                         0
NÃO entra pelo V4 e mesmo assim vê itens de menu:           56   <- o desalinhamento
nem entrada nem menu:                                        4
```

**56 de 89 membros ativos veem itens de menu para os quais não têm a autoridade de entrada.** Não é
um caso; é a maioria da base.

---

## 2. A pergunta do PM, respondida: o time de comunicação alcança comunicação e webinar?

**Não. E o motivo desmonta a hipótese de "faltou liberar permissão".**

Time de comunicação ativo hoje: **3 pessoas** (1 `comms_leader`, 2 `comms_member`), todas com
`operational_role = researcher`.

Rastreando **Mayanna Duarte** (`comms_leader`) pelas quatro camadas, para o item "Comunicação"
(`/admin/comms-ops`) e "Mídia Social" (`/admin/comms`):

| camada | o que decide | resultado |
|---|---|---|
| 4. RPC `get_comms_dashboard_metrics` | `can_view_comms_analytics()`, que termina em `v_desig && ARRAY['comms_leader','comms_member']` | ✅ **AUTORIZA** |
| 2. página `/admin/comms` | `canAccessAdminRoute(m,'admin_comms')`; `ROUTE_ALLOWED_DESIGNATIONS.admin_comms = ['comms_leader','comms_member']` (`constants.ts:86`) | ✅ **AUTORIZA** |
| 2'. página `/admin/comms-ops` | nenhum gate - `CommsDashboard client:load` na linha 76, incondicional | ✅ passa |
| 1. **menu lateral** | `hasPermission(m,'admin.campaigns')`; a designation `comms_leader` concede `board.view_global` + `admin.gamification` + `champion.award*` e **não** `admin.campaigns` (`permissions.ts:270-274`) | ❌ **ESCONDE** |

**Três camadas autorizam o time de comunicação. A quarta - a única que é puramente cosmética - é a
que diz não.** O backend já foi construído para eles. Eles só não conseguem achar a porta.

Menu efetivo de Mayanna hoje: **2 itens de 40** - "Gamificação" e "Ajuda". Dos 2 `comms_member`:
**1 item de 40** (só "Ajuda").

Webinars: `canAccessWebinarsWorkspace()` = `hasPermission('board.view_global')`, que a designation
`comms_leader` **concede**. Mas a entrada de menu "Webinars" exige `admin.access`, que ela não tem.
Mesmo padrão: a página abriria, o menu não a leva até lá.

---

## 3. Matriz papel × módulo admin (89 ativos, 40 entradas de menu)

Perfil = `operational_role` + `designations`. "Entra?" = `canForAdminEntry()` calculado sobre as
ações V4 vivas. "Menu" = itens visíveis computados com o módulo real `hasPermission()`.

| perfil | n | entra (V4) | menu visível | ações V4 org |
|---|---|---|---|---|
| `researcher` (puro) | 51 | NÃO | 1/40 | 0 |
| `tribe_leader` | 12 | SIM | 22/40 | 6 |
| `sponsor` + chapter_board+legal_signer+sponsor | 4 | SIM | 26/40 | 6 |
| `chapter_liaison` + chapter_liaison | 3 | SIM | 12/40 | 5 |
| `guest` | 3 | NÃO | 0/40 | 1 |
| `chapter_liaison` + chapter_board | 2 | SIM | 22/40 | 2 |
| `researcher` + comms_member | 2 | NÃO | 1/40 | 0 |
| `chapter_liaison` + chapter_board+**chapter_vice_president** | 1 | **NÃO** | 22/40 | **0** |
| `chapter_liaison` + chapter_board+filiacao_director | 1 | SIM | 23/40 | 5 |
| `chapter_liaison` + chapter_board+voluntariado_director | 1 | SIM | 22/40 | 2 |
| `chapter_liaison` + certificacao_director+chapter_board | 1 | SIM | 22/40 | 5 |
| `chapter_liaison` + ambassador+chapter_liaison+ip_committee | 1 | SIM | 12/40 | 6 |
| `chapter_liaison` + pmo_liaison | 1 | SIM | 12/40 | 5 |
| `researcher` + **comms_leader** | 1 | NÃO | **2/40** | 0 |
| `researcher` + ambassador+founder+ip_committee | 1 | NÃO | 3/40 | 2 |
| `sponsor` + …+founder | 1 | SIM | 26/40 | 6 |
| `guest` + external_reviewer | 1 | NÃO | 0/40 | 0 |
| `manager` [superadmin] | 2 | SIM | 40/40 | 16-17 |

### O caso `tribe_leader` (12 pessoas, inclui o Fernando) - o menu promete 22 e entrega uma fração

Ações V4 do `tribe_leader`: `write`, `manage_event`, `manage_initiative`, `manage_board_admin`,
`view_pii`, `award_champion`. Confrontando com o gate medido de cada RPC por trás do item de menu:

| item de menu visível | RPC | action exigida | entrega? |
|---|---|---|---|
| Dashboard (`/admin`) | `get_admin_dashboard` | `manage_platform` OU `view_chapter_dashboards` | ❌ **← o `400` do print** |
| Comparação de Tribos | `exec_cross_initiative_comparison` | `manage_platform` OU `view_chapter_dashboards` | ❌ ← o 2º `400` |
| Membros | `admin_list_members` | `view_internal_analytics` | ❌ |
| Reconciliação VEP | `get_vep_divergence_report` | `view_internal_analytics` | ❌ |
| Certificados & Termos | `get_volunteer_agreement_status` | `manage_member` | ❌ |
| Saúde da Coorte | `get_gp_cohort_health` | `manage_member` OU `view_internal_analytics` | ❌ |
| Analytics / Meu Capítulo / Rel. do Ciclo | `get_chapter_dashboard` | `view_internal_analytics` | ❌ |
| Governança | `get_governance_stats` | `manage_platform` | ❌ |
| Parcerias | `get_partner_pipeline` | `view_partner` | ❌ |
| Portfólio Executivo | `get_portfolio_planned_vs_actual` | qualquer membro logado | ✅ |
| Tags | `get_tags` | sem gate de action | ✅ |

**O `400` do Fernando não é regressão nem é dele.** É a experiência-padrão de 12 pessoas, e a
superfície nunca foi desse papel. O defeito é o menu ter oferecido a porta.

---

## 4. Vocabulário órfão: o código não conhece designations que o banco usa

`DESIGNATION_PERMISSIONS` não tem entrada para 6 designations que existem em membros ativos.
`hasPermission` faz `DESIGNATION_PERMISSIONS[d] || []` - logo elas concedem **zero** no menu, em
silêncio, sem erro de build:

| designation | ativos | efeito no menu |
|---|---|---|
| `legal_signer` | 5 | nada |
| `ip_committee` | 3 | nada |
| `co_gp` | 1 | nada (embora seja admin-tier no V4 e no `getAccessTier`) |
| `pmo_liaison` | 1 | nada |
| `chapter_vice_president` | 1 | nada |
| `external_reviewer` | 1 | nada |

Mesmo padrão em `TIER_PERMISSIONS`: `guest` (4 ativos) não é um `OperationalTier` declarado → menu
zerado. Aqui o resultado está correto por acidente, não por desenho.

Caso mais visível: **Emanuele Melo** (`chapter_liaison` + `chapter_board` + `chapter_vice_president`)
vê 22 itens de menu e tem **0 ações V4**. Vice-presidente de capítulo com o mapa inteiro aberto e
nenhuma porta.

---

## 5. As três issues, reancoradas

### #1590 - confirmada, e maior do que estava escrito

O princípio do PM (menu inteiro visível + componente gateado + estado que nomeia a permissão que
falta) está correto e resolve o sintoma. Mas a causa não é "falta o gate por componente": é que o
menu e o gate **falam línguas diferentes**. Aplicar o princípio sem unificar o vocabulário produz um
menu completo cujos estados de sem-acesso nomeiam permissões (`admin.campaigns`) que não são as que o
servidor de fato exige (`manage_comms`) - o usuário pediria a permissão errada.

### #1591 - **a premissa está errada; corrigir a issue antes de trabalhar nela**

- `evaluate_applications` **não existe**: 0 linhas em `engagement_kind_permissions` (o catálogo tem 22
  actions), 0 funções no banco mencionam a string, 0 ocorrências em `src/` e `supabase/`.
  `can_by_member(..., 'evaluate_applications')` retorna `false` para qualquer pessoa porque a action é
  inventada - não porque falta concessão.
- O gate real de `submit_evaluation` é: estar em `selection_committee` do ciclo da candidatura **OU**
  ter `manage_platform`, e depois `role IN ('evaluator','lead')`.
- Fernando **está** no comitê do ciclo vivo (`08c1e301`, `status='open'`) como `evaluator`,
  `can_interview=true`. **Ele passa no gate de escrita.**
- O que o bloqueia é a **leitura**: `get_selection_dashboard` exige `view_internal_analytics`, que ele
  não tem. Ele pode avaliar e não consegue ver o que avaliar.

Comitê do ciclo vivo, 7 pessoas: 2 `manager` (171 e 265 avaliações), 4 `observer` (0 - corretamente
barrados pelo `role IN ('evaluator','lead')`), e **Fernando, o único `evaluator` não-manager, com 0**.
Somado à #1568 (superfície do avaliador no ar **sem entrada de menu**), o avaliador não tem caminho
nenhum. As duas se resolvem juntas.

> Nota de método: a issue nasceu de medir uma action inexistente. O tell é `can_by_member` retornando
> `false` para **todo mundo**, inclusive superadmin - action inexistente e action negada a todos são
> indistinguíveis pela resposta. Verificar a existência no catálogo antes de tratar `false` como gap.

### #1592 - reancorada, e o recorte útil é outro

| medição | valor vivo 04/08 |
|---|---|
| SECDEF em `public` | 1077 |
| executáveis por `anon` | **474** (o handoff dizia 446) |
| `anon` **e** sem nenhum sinal de gate no corpo | **156** |

O número que importa é 156, não 474: `EXECUTE` para `anon` só vira exposição quando o corpo também
não checa nada. Duas funções que meu primeiro recorte marcou como sem gate **têm** gate, por helper
(`can_view_comms_analytics()`, `auth.uid()`) - regex sobre `can_by_member` subconta. Os 156 precisam
ser abertos um a um antes de virar afirmação de risco.

---

## 6. Recomendação de padrão (para decisão do PM, antes da cirurgia)

**Princípio de desenho:** o menu deve perguntar à mesma fonte que o servidor. Enquanto o menu falar
`Permission` e o RPC falar `action`, todo ajuste é remendo.

### R1 - o menu passa a declarar a **action V4**, não a `Permission`

Cada entrada de `SECTIONS` declara a action que o RPC de trás exige (`manage_comms`,
`view_internal_analytics`, …). A visibilidade vem de `canForAdminEntry()`; o estado de cada item vem
de `canFor(action)`. Isso já é o SSOT - `canFor` lê o mesmo catálogo que `can_by_member`.

### R2 - três estados por item, nunca dois

`disponível` · `sem permissão` · `indisponível`. O estado de sem-permissão é a entrega do princípio
do PM.

**Correção do `ux-leader`:** a versão inicial desta recomendação mandava o estado **exibir** a action
(`manage_comms`). Isso é jargão de banco, e um voluntário do PMI não sabe pedir isso. O estado tem de
carregar **dois campos**, não um:

- **exibição** - rótulo humano + quem libera: *"Comunicação - acesso restrito. Liberado por quem
  coordena Comunicação no seu capítulo/GP."* com botão **Pedir acesso**.
- **payload** - a action viaja no corpo da solicitação, não na tela:
  *"Solicito acesso a Comunicação (ref: `manage_comms`) - perfil atual: tribe_leader."*

Isso preserva a propriedade que o PM quer (a pessoa pede a coisa certa a quem libera) sem despejar o
vocabulário do banco na interface. Exige um mapa `action → rótulo humano` (22 entradas hoje, uma por
action do catálogo) - que **R5 deve proteger também**, não só a existência da action.

### R3 - Path-2 (designation inline) precisa ser declarável no menu

O caso comunicação prova que nem toda autoridade é engagement-derived: `can_view_comms_analytics()`
autoriza por designation. O menu tem de conseguir declarar "esta entrada abre por `manage_comms`
**ou** pela designation `comms_leader`/`comms_member`" - senão R1 sozinho continuaria escondendo o
time de comunicação. Isso não é concessão nova: é espelhar no cliente um gate que **já existe** no
servidor.

**Ressalva do `ux-leader` sobre R3:** quando o item abre por `manage_comms` **ou** pela designation,
o texto tem de dizer **qual dos dois braços** falhou. Se disser genericamente "peça `manage_comms`", a
Mayanna - que já tem a designation - pediria a permissão errada. O OR precisa de mecanismo *e* de
texto por braço.

### R4 - zero chamada de rede sem permissão

Item em estado de sem-permissão não monta a ilha. Hoje 52 de 54 rotas montam `client:load`
incondicional, o que é a origem do `400` no console.

**Ressalva do `ux-leader`:** R2 e R4 juntos abrem um loop que ninguém fecha - pedir → esperar →
nunca saber que foi atendido. Recém-liberado, o item só muda de cadeado para ativo no próximo reload,
sem sinal nenhum. Fechar com um badge leve ("Novo acesso") no primeiro carregamento pós-concessão.

### R5 - barreira contra vocabulário órfão

Um teste de contrato que falhe quando existir `designations`/`operational_role` no banco sem entrada
no mapa do código, e quando uma entrada de menu declarar action fora do catálogo de
`engagement_kind_permissions`. Sem isso, os 6 órfãos de hoje viram 9 na próxima designation criada.
Esta é a barreira que faltou no #1551 e permitiu o #1592 reaparecer.

### R6 - "menu inteiro" vale por **seção**, não por item, abaixo de um limiar

Levantada pelo `ux-leader`, e é uma qualificação real do princípio do PM. Para o `researcher` puro
(51 de 89 ativos, hoje 1 item), abrir 40 itens com 39 cadeados não produz auto-evidência: produz
fadiga de permissão, e ensina o usuário a ignorar cadeado. Auto-evidência só funciona quando o
bloqueio é **plausível** para aquele perfil.

Regra proposta: se o perfil não tem **nenhuma** action da seção inteira (não 1-2 itens - a seção
toda), colapsar a seção num único item bloqueado ("Governança - bloqueado", com o mesmo *pedir
acesso*) em vez de expandir os 4-6 itens. Seções onde o perfil já tem pelo menos uma action seguem
expandidas item a item, que é onde a granularidade importa. Nada fica oculto; o princípio do PM é
preservado, sem forçar 39 decisões de "isso é pra mim?" por sessão.

**RATIFICADA PELO PM em 04/08:** vale a regra por seção. Seção sem nenhuma action do perfil colapsa
num item bloqueado único; seção com ao menos uma action fica expandida item a item. O `researcher`
puro passa a ver ~5 cadeados de seção em vez de 39 de item; o `comms_leader` vê a seção "Conteúdo"
aberta, com "Comunicação" e "Mídia Social" em estado de pedir-acesso - que é exatamente o caso que
esta auditoria mediu como escondido hoje.

### R7 - `tribe_leader` entra no módulo; o travamento é por item e por seção

**DECIDIDA PELO PM em 04/08:** o `tribe_leader` **pode alcançar o `/admin`**, com acesso travado nos
itens e seções que não lhe cabem.

Consequências, e o que a decisão **não** é:

- **Não há concessão a fazer.** Os 12 `tribe_leader` já passam em `canForAdminEntry()` (têm `write`,
  `manage_event`, `manage_initiative`, `manage_board_admin`, `view_pii`, `award_champion`). A entrada
  no módulo já é legítima hoje; o que falta é o travamento, não a permissão. Com isso, **o arco
  inteiro fecha sem um único `INSERT INTO engagement_kind_permissions`.**
- **O `/admin` em si passa a ser uma tela de widgets travados para eles.** `get_admin_dashboard` e
  `exec_cross_initiative_comparison` exigem `manage_platform` ou `view_chapter_dashboards`, que o papel
  não tem e, por esta decisão, não vai ganhar. Então a landing do módulo, para 12 de 89 pessoas, fica
  sendo cadeado + pedir-acesso. Isso é coerente com o princípio (a permissão faltante vira
  auto-evidente) mas é uma primeira impressão fraca do módulo.
- **Decisão de implementação que decorre daí, e é de produto:** o que a landing `/admin` mostra para
  quem entra sem `manage_platform`/`view_chapter_dashboards`. As saídas plausíveis são (a) os widgets
  travados como qualquer outro item, ou (b) a landing redirecionar para o primeiro item ao qual a
  pessoa tem acesso de fato. Fica registrada aqui para ser resolvida no desenho da cirurgia, não
  agora.

### O que **não** fazer

- Nenhum `INSERT INTO engagement_kind_permissions`. Nada nesta auditoria é gap de concessão, e a
  decisão R7 confirma isso para o último caso em aberto. O vocabulário 4 está coerente; quem está
  errado é o 1.
- Não recriar gate de rota no servidor - ADR-0106 aposentou isso por desenho.
- Não "consertar" #1591 concedendo `evaluate_applications`: a action não existe.

### Decisões do PM

**Decididas em 04/08:**

- ✅ **R6 - colapso por seção zerada.** Ver R6 acima.
- ✅ **R7 - `tribe_leader` alcança o `/admin`, com travamento por item e por seção.** Ver R7 acima.
  Sem concessão: o papel já passa em `canForAdminEntry()`.
- ✅ **Ordem de execução: a Opção A do #1584 vem primeiro.** Este arco do admin fica em fila atrás
  dela; o gap assessment da jornada do candidato segue em aberto quanto a posição.

- ✅ **R8 - Fernando avalia neste ciclo; a saída é entrada de menu para `/minhas-avaliacoes`**, não
  concessão de `view_internal_analytics`. Ver R8 abaixo.

**Consequência de R6+R7 juntas:** a cirurgia do **#1590** é **inteiramente de cliente**. Não toca
`engagement_kind_permissions`, não toca RPC, não toca RLS. Isso a torna reversível e testável sem
migração, e mantém a fronteira real (vocabulário 4) intacta. **R8 é a exceção, e está fora do #1590.**

**Aberta e nova, gerada por R7:** o que a landing `/admin` mostra para quem entra sem
`manage_platform`/`view_chapter_dashboards` (12 pessoas). Widgets travados ou redirect para o
primeiro item acessível. Resolver no desenho da cirurgia.

---

## 7. R8 - a entrada de menu do avaliador (decisão do PM, 04/08)

**Decisão:** Fernando avalia neste ciclo, e a saída é dar entrada de menu para `/minhas-avaliacoes`
(#1568). Nenhuma concessão de `view_internal_analytics` - o anti-pattern que o próprio #1568 já
rejeitou por escalar privilégio muito além do caso de uso.

### ⚠️ Isto NÃO é mudança só de cliente

Uma leitura anterior desta sessão sugeriu que a entrada de menu provavelmente se resolveria sem
servidor. **Está errada, e a #1568 já documentava o porquê.** Confirmado ao vivo em 04/08:

| verificação | resultado |
|---|---|
| `get_member_by_auth` carrega participação em `selection_committee`? | **não** |
| esse payload é o que alimenta o nav? | sim (`navigation.config.ts:104-106`) |
| a rota é `lgpdSensitive`? | sim - expõe PII de candidato |
| existe guard bloqueando `tribe_leader` em rota `lgpdSensitive` sem designation? | sim, `tests/contracts/route-acl.test.mjs` |

Portanto o trabalho é: expor o sinal de comitê no payload do nav → **mudança de assinatura de RPC** →
**`db:types` no mesmo PR**, senão o gate `gen-types-drift` reprova
(`reference-rpc-signature-change-requires-gen-types-in-same-pr`). E o `route-acl.test.mjs` tem de
passar a ser satisfeito pelo **sinal de comitê**, nunca por afrouxamento do papel - o guard está
certo e não deve ser relaxado.

### ⚠️ O predicado não pode ser "está no comitê"

`get_my_pending_evaluations` gateia por **participação no comitê apenas**; medido: **não** checa
`role IN ('evaluator','lead')`. Quem checa o papel é o `submit_evaluation`, no fim da jornada.

Consequência de uma entrada chaveada em "está no comitê": os **4 `observer`** do ciclo vivo veriam o
item, abririam a fila, leriam as candidaturas e só seriam recusados **no envio**. Isso é reintroduzir,
dentro do próprio conserto, exatamente a doença que esta auditoria diagnosticou - uma porta oferecida
que não abre.

**Predicado correto:** participação em `selection_committee` do ciclo em `phase='evaluating'`
**E** `role IN ('evaluator','lead')`. Hoje isso habilita **3 pessoas** (os 2 `manager` + Fernando),
não 7.

### Caso exemplar de R3

Esta entrada é a prova de que R3 não é detalhe: a autoridade do avaliador **não é uma action V4** -
é participação numa tabela. Um menu que só saiba declarar `canFor(action)` não consegue expressá-la,
do mesmo modo que não consegue expressar a designation do time de comunicação. R3 tem de cobrir os
dois casos, e o texto de sem-acesso tem de dizer qual braço do OR falhou.

### Ordem sugerida

R8 é independente do #1590 e não precisa esperar por ele. Mas depende de mexer em RPC, então **não
cabe na cirurgia de cliente** - é PR próprio, com `db:types`, e deve andar junto do #1568/#1591.

---

## Anexos / rastro

- Inventário completo das 54 rotas (rota → ilha → gate de montagem → gate do componente → RPCs) e as
  40 entradas de menu com a `Permission` de cada uma: levantado nesta sessão, `AdminSidebar.tsx:49-120`.
- **Achado lateral:** `src/components/nav/AdminNav.astro` define um menu concorrente, com lógica de
  `minTier`/`allowedDesignations` própria, e **não é importado por nenhum arquivo**. É um quinto
  vocabulário, morto. Candidato a remoção - ver
  `reference-fix-landed-on-the-dead-twin-implementation`.
- Script da matriz e `members.json` (89 ativos × 19 actions) ficaram no scratchpad da sessão; a matriz
  é reprodutível com `esbuild src/lib/permissions.ts` + `can_by_member` via PostgREST.
