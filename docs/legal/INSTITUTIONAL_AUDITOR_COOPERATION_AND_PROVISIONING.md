# Auditor Institucional — Cooperação Federada Externa, RoPA/LIA e Protocolo de Provisionamento (#952 FU-4)

> **Status:** RASCUNHO operacional — **pré-requisito de governança para provisionar o primeiro
> auditor institucional.** Enquanto este documento não estiver ratificado e o checklist de go-live
> (§7) satisfeito, o tier permanece **dormante** (nenhum engagement atribuído) e nenhum acesso é
> concedido. Linguagem jurídica final pendente de DPO / advogado licenciado.
>
> **Origem:** Onda 2 FU-4 (achado **F8** do plano `~/.claude/plans/onda-2-auditoria-keen-kahn.md`).
> Tier técnico = **ADR-0111** (`institutional_auditor` + `view_aggregate_analytics`,
> allowlist-by-construção). Split read/write sponsor = **ADR-0110** (FU-1). Migration
> `20260805000292_onda2_fu3_institutional_auditor.sql`.
>
> **Controladora:** PMI Goiás (CNPJ 06.065.645/0001-99), capítulo sede do Programa Núcleo IA.
> **Operadora:** plataforma `nucleoia.vitormr.dev`. **DPO:** Ivan Lourenço Costa (titular) ·
> Angeline Altair Silva Prado (substituta) — dpo@pmigo.org.br. **Nota de impedimento:** o DPO
> titular acumula o cargo de presidente do PMI-GO (papel `sponsor` sede, regulado no §5); a
> ratificação do RoPA/LIA (§3) deve ser feita pela **DPO substituta** ou por advogado licenciado
> independente, para preservar a independência do encarregado (Art. 41, §2º, II LGPD) — ver §8.
>
> **Não é aconselhamento jurídico.** Esqueleto para revisão, baseado no enquadramento já aprovado
> no #628 / SPEC-625 e no Anexo R3 (#641).

---

## 1. Finalidade e escopo

Este documento define o regime de governança e proteção de dados para conceder a um **órgão
institucional externo** da rede PMI (ex.: **PMI LATAM**, PMI Global, iniciativa **PMIxAI**) acesso
de **leitura agregada** ao Programa Núcleo IA — sem expor dado pessoal individual, sem escrita e sem
qualquer função de gestão (`manage_*`).

O caso de uso motivador é a apresentação do **LIM** (Leadership Institute Meeting): a sede PMI-GO,
por intermédio do seu presidente/sponsor, presta contas do Programa à rede institucional PMI. Para
isso, um observador institucional externo recebe um acesso **read-only agregado, com prazo**, em vez
de uma conta de "analista interno" (que carregaria PII e escrita).

### 1.1 Três eixos de visibilidade federada

| Eixo | Quem | O que vê | Instrumento |
|---|---|---|---|
| **Sede (controladora)** | PMI-GO + GP (`manage_platform`) | Visão consolidada (tudo, incl. PII operacional) | Política de governança vigente |
| **Capítulo parceiro** | PMI-CE / DF / MG / RS | Agregado do **próprio** capítulo; sem lista nominal de outros (v1) | Acordos bilaterais + Anexo R3 (#641) |
| **🆕 Auditor institucional externo** | Órgão da rede PMI (LATAM/Global/PMIxAI) | Agregado **program-wide**, sem PII individual, sem recorte nominal | **Este documento** + ADR-0111 |

O auditor institucional **não é um capítulo parceiro**: não possui membros no Programa e não é
controlador de nenhum dado tratado aqui. É um **observador institucional da rede** que recebe
indicadores agregados para fins de accountability. Por isso seu regime é distinto do Anexo R3 (que
governa o eixo sede↔parceiro) e está documentado à parte, com referência cruzada (#641 §5.3).

---

## 2. O que o auditor vê — e o que nunca vê

### 2.1 Superfície concedida (allowlist por construção — ADR-0111)

A action `view_aggregate_analytics` é seedada **apenas** ao par `institutional_auditor × auditor` e é
honrada por **exatamente 12 RPCs**, todas verificadas ao vivo como **zero-PII / zero-escrita** (8 do
FU-3 original + 4 da emenda ADR-0111 de 2026-06-29, mig `20260805000294`):

| RPC | Conteúdo (agregado) |
|---|---|
| `get_cycle_report` | Relatório do ciclo (counts, taxas) |
| `get_annual_kpis` | KPIs anuais consolidados |
| `get_selection_pipeline_metrics` | Métricas de funil da seleção (counts por etapa) |
| `get_diversity_dashboard` | Agregados de diversidade por gênero/região (counts, **não** indivíduos) |
| `get_portfolio_items` | Itens de portfólio (mantém gate de confidencial #785) |
| `get_in_dashboard` | Pipeline institucional de MOU/capítulos (dado institucional) |
| `get_comms_to_adoption_funnel` | Alcance e funil de comunicação→adoção |
| `exec_role_transitions` | Matriz role→role (transições, sem nomes) |
| `exec_chapter_dashboard` | Saúde por capítulo (counts de membros/produção/engajamento/cert) — **supressão de célula pequena** p/ o auditor (capítulo com `<5` ativos → marcador suprimido) |
| `exec_chapter_comparison` | Comparação cross-chapter (só counts) — **supressão de célula pequena** p/ o auditor (capítulos `<5` ativos colapsam em "Outros (<5 ativos)") |
| `get_chapter_selection_summary` | Resumo de seleção do capítulo (`open_apps`=count + metadados de ciclo; sem quebra de membro) |
| `comms_metrics_latest_by_channel` | Métricas por canal social (reach/engagement/leads); `payload` jsonb **NULL no caminho do auditor** (forward-defense) |

> **Allowlist, não denylist.** Estender a superfície agregada do auditor exige **curadoria
> explícita** (verificar a RPC candidata como zero-PII/zero-escrita ao vivo) **+ atualização deste
> documento + da lista `SAFE_RPCS`** em `tests/contracts/institutional-auditor-aggregate-scope.test.mjs`.
> Esse teste impõe um **bound verdadeiro**: nenhuma RPC fora da allowlist pode honrar
> `view_aggregate_analytics` (uma 13ª RPC com a action em qualquer migration falha o teste). Nunca alargar
> a action para reusar uma action ampla (`view_pii`, `view_internal_analytics`) — foi exatamente a
> premissa falsa que o ADR-0111 derrubou.

### 2.2 O que é estruturalmente vedado

- **Diretório de membros / PII individual** (nome, e-mail, telefone, foto, `auth_id`, `pmi_id`,
  `credly`). Garantido pelo **carve-out RLS**: `rls_is_authoritative_member()` exclui
  `institutional_auditor`, então o auditor não recebe o diretório baseline mesmo por PostgREST direto.
- **Dados de seleção nominais** (candidatos, scores individuais).
- **Escrita de qualquer espécie** e qualquer `manage_*` — o auditor não possui nenhuma action de
  escrita; o gate server-side dos write-tools (`canV4`) falha-fechado.

### 2.3 Risco residual de re-identificação (célula pequena)

Agregados de **célula pequena** podem, em tese, ser re-identificáveis (ex.: `get_diversity_dashboard`
com um único indivíduo num cruzamento gênero×região; `get_cycle_report` de um capítulo muito pequeno).

**Salvaguardas atuais:** o escopo do auditor é **program-wide** (não recorta capítulo nominalmente),
o que dilui counts; o provisionamento exige acordo de finalidade restrita (§4).

**Supressão de célula pequena — IMPLEMENTADA EM CÓDIGO (k=5)** para as RPCs de quebra de membro por
capítulo, que foram o vetor de re-identificação concreto identificado na revisão adversarial por-RPC
(2026-06-29; ao vivo, **3 capítulos têm 1 único membro ativo** e `members.chapter` não tem CHECK/enum):

- `exec_chapter_dashboard`: para o **auditor externo** (holds `view_aggregate_analytics` AND NOT
  `view_internal_analytics`), capítulo com `<5` membros ativos retorna um marcador suprimido
  (`{suppressed:true, reason:'small_cell_below_threshold', threshold:5}`) em vez do detalhe.
- `exec_chapter_comparison`: para o auditor externo, capítulos com `<5` ativos colapsam num único
  bucket `"Outros (<5 ativos)"` (counts somados), nunca um registro de capítulo n=1.
- Controladores internos (`view_internal_analytics`/`manage_platform`) recebem o detalhe completo
  **inalterado** — a supressão é exclusiva do caminho do auditor externo (behavior-neutral; ao vivo,
  0 membros atuais alcançam o branch de supressão pois o tier está dormante).

**Hardening recomendado (FU futuro, ver §8):** estender a mesma supressão de célula pequena às demais
RPCs agregadas que cruzem subgrupos sensíveis identificáveis (ex.: `get_diversity_dashboard`
gênero×região), de forma transversal — fora do escopo desta emenda, que cobriu as RPCs de quebra por
capítulo (o vetor concreto).

---

## 3. RoPA + LIA da partilha agregada (Art. 37 + Art. 7º IX LGPD)

### 3.1 Registro das operações de tratamento (Art. 37)

São **duas** operações distintas, com titulares e bases legais diferentes — documentadas em separado para precisão de inspeção.

#### Operação 1 — Disponibilização de indicadores agregados ao auditor

| Campo | Conteúdo |
|---|---|
| **Operação** | Disponibilização de indicadores **agregados** do Programa Núcleo IA a um órgão institucional externo da rede PMI, para prestação de contas (accountability) institucional. |
| **Agente que trata** | PMI-GO (controladora), por intermédio da plataforma (operadora). O auditor externo é **destinatário** de agregados — **não** agente de tratamento de dados individuais, **não** controlador, **não** operador. |
| **Categorias de dado** | Agregados (counts, médias, taxas, funis). **Sem dado pessoal individual** por construção (§2 — allowlist de 12 RPCs zero-PII). |
| **Titulares** | Membros e pré-onboarding do Programa, **apenas refletidos em agregados**. |
| **Finalidade** | Accountability/transparência institucional do Programa perante a rede PMI federada. |
| **Base legal** | **Base operativa ATUAL = legítimo interesse do PMI-GO (Art. 7º, IX — LIA §3.2)**, enquanto a supressão de célula pequena (§2.3 / §8) não estiver implementada. Contagens/taxas/funis program-wide que **não identificam** qualquer pessoa natural não se enquadram, por construção, no conceito de dado pessoal (**Art. 5º, I**); a supressão de célula pequena (k-anonimato) tornará o Art. 5º, I / Art. 12 aplicável como proteção adicional às células suprimidas. (`engagement_kind.legal_basis = legitimate_interest`.) **Não** se invoca o Art. 12 como base primária enquanto houver risco residual de re-identificação reconhecido em §2.3. |
| **Retenção** | Os agregados **não são persistidos** junto ao auditor pela plataforma (leitura sob demanda); o acesso cessa com a revogação do engagement (§4.3). |
| **Destinatários** | O órgão externo nomeado no acordo de cooperação (§4 P1). Sem repasse a terceiros sem novo fundamento. |
| **Medidas de segurança (Art. 46)** | RLS carve-out (auditor não pega o diretório) + 12 RPCs SECDEF allowlisted (2 com supressão de célula pequena k=5), com **bound verdadeiro** no teste de contrato `institutional-auditor-aggregate-scope` (nenhuma RPC fora da allowlist pode honrar a action) + `end_date` CHECK no banco + provisionamento GP-only. |
| **Transparência (Art. 9º / Art. 10, §2º)** | Esta entrada + GC-149 + ciência formal dos capítulos parceiros (§6). **Quanto aos titulares-membros:** a inclusão de cláusula no Termo de Voluntariado / notificação de onboarding informando o reporte de participação **agregada** à rede institucional PMI é **pré-condição de provisionamento** (§4.1 P5, §7). **Este rascunho NÃO afirma** que o Termo vigente já cobre este fluxo — a transparência ex-post (este doc + GC-149) não substitui a informação ao titular do Art. 9º. |

#### Operação 2 — Registro do engagement do auditor (a pessoa indicada)

| Campo | Conteúdo |
|---|---|
| **Operação** | Registro e gestão do engagement do auditor na plataforma (provisionamento, prazo, revogação). |
| **Categorias de dado** | Identificação mínima: nome + vínculo institucional + prazo (`start_date`/`end_date`). Sem dado sensível. |
| **Titular** | A pessoa indicada pelo órgão externo como auditor. |
| **Base legal** | **Art. 7º, V** (execução do acordo de cooperação — P1 — do qual o auditor é a parte indicada), suplementada por **Art. 7º, II** (procedimento preliminar). Não é LIA: existe base contratual clara. |
| **Retenção** | Registro do engagement retido **730 dias** após o `end_date` (`retention_days_after_end`) — **base: Art. 16, I LGPD** (trilha de provisionamento/revogação de acesso de parte externa; prazo a confirmar com o DPO à luz do prazo prescricional aplicável — §8). |
| **Medidas de segurança (Art. 46)** | Provisionamento GP-only; `end_date` obrigatório (CHECK `engagements_institutional_auditor_end_date_check`); **trilha de provisionamento/revogação** = registro no GOVERNANCE_CHANGELOG + timestamps do engagement. **Não** há, hoje, log por-request das leituras agregadas (ver §8 — FU de granularidade de acesso). |

### 3.2 LIA — teste de legítimo interesse (Art. 7º IX c/c Art. 10)

1. **Finalidade legítima, específica e informada.** Prestar contas do impacto do Programa à rede
   institucional PMI (LATAM/Global). Finalidade institucional, não comercial; informada nesta entrada,
   no GC-149 e na ciência dos parceiros (§6).
2. **Necessidade (minimização).** É o mínimo: **somente agregado**, allowlist de **8** RPCs, **zero
   PII individual**, **zero escrita**. Não há base menos invasiva para prestar contas — e a escolhida
   já é a mais minimizadora possível (nada nominal sai da plataforma).
3. **Balanceamento (expectativa legítima × direitos do titular).** Membros aderem a um programa de
   voluntariado de um capítulo PMI com expectativa legítima de que sua participação **agregada** seja
   reportada à rede institucional. Nenhum dado pessoal individual é exposto ao auditor. Salvaguardas
   que pendem a balança para o titular: allowlist por construção, carve-out RLS, `end_date` obrigatório
   + provisionamento GP-only, ausência total de escrita, e o hardening de célula pequena (§2.3). Risco
   residual baixo, concentrado em re-identificação de célula pequena, mitigado pela natureza
   program-wide. Sem decisão automatizada; sem dado sensível individual.

**Conclusão:** legítimo interesse (Art. 7º, IX) é **base operativa adequada** para a transmissão de
agregados ao auditor enquanto a supressão de célula pequena não estiver implementada, sujeito às
salvaguardas acima; implementada a supressão, o Art. 5º, I / Art. 12 passa a proteger adicionalmente as
células suprimidas (§3.1 Operação 1). **Ratificação pendente** — pela DPO substituta ou advogado
independente (impedimento do titular, §8).

---

## 4. Protocolo de provisionamento (GP-only)

> **Quem pode provisionar:** apenas `manager` / `deputy_manager` (`created_by_role` do kind) —
> equivalentes a `manage_platform`. Superadmin curto-circuita. **Member lifecycle = GP-only**
> (LGPD Art. 18). O auditor **nunca** é auto-provisionado nem provisionável por papel parceiro.

### 4.1 Pré-condições — TODAS obrigatórias antes do 1º `INSERT`

- **P1 — Acordo/memo de cooperação formal** assinado com o órgão externo (MOU ou aditivo ao
  instrumento da rede), contendo: finalidade restrita (accountability), vedação de uso alheio ao
  Programa, prazo, e a pessoa indicada como auditor. Referenciar o instrumento no GC e no engagement.
- **P2 — Ciência formal dos capítulos parceiros** (PMI-CE/DF/MG/RS) de que um auditor institucional
  externo verá **agregados program-wide** que incluem dados dos seus capítulos — por ata ou e-mail
  (template em §6). **Critério de conclusão (falsificável):** envio registrado (com timestamp) + uma
  destas condições por capítulo — (a) **ciência escrita explícita**, ou (b) **ausência de objeção em
  10 dias úteis** do envio (silêncio = ciência, conforme o template). **Modo de falha:** se um capítulo
  apresentar **objeção formal**, o GP **suspende o provisionamento** e escalona ao DPO + presidência
  PMI-GO antes de prosseguir. Arquivar o e-mail enviado + timestamp + resposta (ou não-resposta após o
  prazo) como artefato de auditoria.
- **P3 — Ratificação do RoPA/LIA** (§3) pela **DPO substituta** (Angeline Altair Silva Prado) ou por
  advogado licenciado independente — dada a sobreposição de cargo do DPO titular (presidente/sponsor),
  ver §8 e nota de impedimento no cabeçalho.
- **P4 — `end_date` definido** (≤ 365 dias, alinhado ao prazo do acordo) e a **pessoa nomeada** do
  órgão externo.
- **P5 — Transparência ao titular-membro** (Art. 9º): cláusula no Termo de Voluntariado / notificação
  de onboarding informando o reporte de participação **agregada** à rede institucional PMI **incluída
  e vigente** — ou confirmação documentada do DPO de que o instrumento vigente já a cobre (com citação
  de versão/cláusula). A transparência ex-post não basta (Operação 1, §3.1).

### 4.2 Passos de provisionamento

1. Criar o engagement: `kind='institutional_auditor'`, `role='auditor'`, `person=<pessoa do órgão>`,
   `start_date`, **`end_date` (obrigatório — o CHECK do banco recusa NULL)**, `status='active'`,
   via o fluxo GP de gestão de engagement.
2. **Verificação ao vivo de 2 lados:** confirmar badge "Auditor Institucional" 🔎; confirmar que as
   **12 RPCs** agregadas retornam e que **qualquer RPC de PII/diretório nega** (ex.: `admin_list_members`,
   `get_member_detail`, `get_selection_dashboard`).
3. **Registrar no `GOVERNANCE_CHANGELOG`**: quem provisionou, qual órgão, prazo, instrumento (P1).

### 4.3 Revogação e expiração — controle obrigatório

> ⚠️ **`auto_expire_behavior = 'notify_only'`.** Ao vencer o `end_date`, o acesso **NÃO é
> auto-revogado** — o sistema apenas notifica. Para uma **parte externa**, isso deixa uma janela de
> acesso pós-vencimento até a ação manual. Como a base legal (Art. 7º, V/IX) está **vinculada ao prazo
> do acordo (P1)**, acesso após o `end_date` é tratamento sem fundamento (**Art. 15 LGPD — término do
> tratamento**) **e** quebra contratual do acordo de cooperação. O controle abaixo é, portanto,
> **não-opcional** (entra no gate de go-live §7).

- **Verificar o mecanismo de notificação ANTES do go-live (§7):** quem recebe o `notify_only`
  (cargo GP? DPO?), por qual canal (e-mail? notificação in-platform? só linha em log?) e com qual
  antecedência. Se a notificação **não alcança um humano nomeado** com lead time suficiente, então **(A)**
  implementar `auto_expire_behavior='revoke'` para o kind antes do 1º provisionamento (preferencial,
  fecha o risco estruturalmente), **ou (B)** o acordo (P1) prevê auto-certificação de término de uso
  pela parte externa no `end_date` (desloca o risco residual contratualmente).
- **Dono nomeado (function-anchored, espelha §5):** no provisionamento, criar uma **issue recorrente
  de revisão trimestral atribuída ao cargo GP** (não ao indivíduo). A entrada de provisionamento no
  GOVERNANCE_CHANGELOG lista os engagements institucionais ativos como **item de handoff obrigatório na
  transição de GP** — revogar ou reassignar antes da saída. Sem isso, a revisão trimestral fica órfã na
  exata lacuna que o §5 corrige para o `sponsor`.
- **SLA mínimo (se a opção B/notify_only for mantida):** revogação manual **no ou antes do `end_date`**,
  com lembrete **T-7** configurado; janela máxima de tolerância **D+1**. Revisão trimestral de todos os
  engagements institucionais ativos.
- **Hardening preferencial (opção A — §8):** alterar `auto_expire_behavior` deste kind para `revoke`.

---

## 5. SLA de reassignment de engagements institucionais (function-anchored)

> **Princípio (invariante V4):** autoridade é atada ao **cargo/função**, nunca ao indivíduo nomeado.
> Na troca de titular, o acesso **segue o cargo** — revoga-se do anterior e reassigna-se ao novo.

| Engagement institucional | Atado a | Na troca de titular |
|---|---|---|
| `sponsor` sede (presidência PMI-GO) | Cargo de presidente do capítulo sede | Revogar do presidente anterior + reassignar ao novo titular em **≤ 15 dias úteis da posse** (a confirmar com o DPO/governança). |
| `sponsor` parceiro (presidência CE/DF/MG/RS) | Cargo de presidente do capítulo parceiro | Idem — revogar+reassignar ≤ 15 dias úteis. |
| `institutional_auditor` | Pessoa indicada pelo órgão externo no acordo (P1) | Se a pessoa mudar: revogar o engagement antigo + novo `INSERT` para o novo indicado. O `end_date` força revisão periódica de qualquer modo. |

**`end_date` em engagements institucionais:** todo engagement institucional deve ter `end_date`
alinhado ao mandato/acordo. Para `institutional_auditor` é **CHECK no banco** (obrigatório). Para
`sponsor` é **disciplina operacional** (recomenda-se `end_date` = fim do mandato da presidência).

---

## 6. Template de ciência/concordância dos capítulos parceiros (P2)

> Texto-modelo que o GP envia aos capítulos parceiros (PMI-CE/DF/MG/RS) antes de provisionar o primeiro
> auditor institucional. **Instrumento distinto** da cláusula-modelo bilateral do Anexo R3 (#641 §7):
> o §7 governa a relação contratual sede↔capítulo; **este é uma notificação prévia de governança** sobre
> o eixo distinto sede→auditor externo (não carrega o mesmo peso contratual). Satisfaz o gate P2 (§4.1).

> **Assunto:** Ciência — acesso de leitura agregada da rede institucional ao Programa Núcleo IA
>
> Prezada liderança do PMI-[CE/DF/MG/RS],
>
> No contexto da prestação de contas do Programa Núcleo IA à rede institucional do PMI
> (ex.: PMI LATAM/Global), o PMI-GO, na qualidade de capítulo sede, **concederá a [ÓRGÃO EXTERNO]**
> um acesso de **leitura estritamente agregada** à plataforma do Programa, por **prazo determinado**
> (até [DATA]).
>
> Esse acesso:
> - expõe **apenas indicadores agregados** (counts, taxas, funis), **sem qualquer lista nominal e sem
>   dado pessoal individual** dos filiados de qualquer capítulo (allowlist de 8 relatórios agregados);
> - **não** permite escrita, gestão, nem acesso a dados de seleção ou ao diretório de membros;
> - tem finalidade **restrita** a accountability institucional, vedado uso alheio ao Programa;
> - é **revogado pelo GP** no término do prazo ou da necessidade (o sistema emite notificação ao GP no
>   vencimento; **a revogação é manual** e ocorre no prazo ou antes).
>
> Os dados dos filiados do seu capítulo entram **somente** nesses agregados, sem identificação individual.
> Solicitamos a **ciência** sobre o regime de acesso descrito neste e-mail. **Não é necessária aprovação
> formal** — apenas confirmação de recebimento e ciência. A **ausência de objeção em 10 dias úteis** será
> registrada como ciência; havendo objeção, suspenderemos o provisionamento e a trataremos antes de
> prosseguir.
>
> Atenciosamente, GP — Programa Núcleo IA / PMI-GO.

---

## 7. Checklist de go-live (gate antes do 1º auditor)

- [ ] **P1** — Acordo/memo de cooperação formal assinado com o órgão externo, com finalidade, prazo e pessoa indicada.
- [ ] **P2** — Ciência dos 4 capítulos parceiros satisfeita pelo critério falsificável (§4.1): envio com timestamp + ciência escrita **ou** ausência de objeção em 10 dias úteis; sem objeção pendente. Artefatos arquivados.
- [ ] **P3** — RoPA/LIA (§3) ratificado pela **DPO substituta** ou advogado independente (impedimento do titular — cabeçalho/§8).
- [ ] **P4** — `end_date` (≤ 365d) e pessoa do órgão definidos.
- [ ] **P5** — Transparência ao titular-membro (Art. 9º): cláusula no Termo/onboarding incluída e vigente, **ou** confirmação documentada do DPO com citação de versão/cláusula (§4.1 P5).
- [ ] **Mecanismo de revogação verificado (não-opcional, §4.3):** ou `auto_expire_behavior='revoke'` implementado (opção A), ou notificação `notify_only` confirmada como alcançando um humano nomeado com lead time + auto-certificação de término no acordo (opção B). **Não** provisionar com caminho de notificação não verificado.
- [ ] Verificação ao vivo de 2 lados (§4.2 passo 2): 12 RPCs retornam (com supressão de célula pequena ativa p/ as 2 de quebra por capítulo), RPCs de PII negam.
- [ ] Entrada no `GOVERNANCE_CHANGELOG` registrando o provisionamento.
- [ ] Dono nomeado da revogação (§4.3): issue recorrente trimestral atribuída ao **cargo GP** + engagements institucionais ativos marcados como item de handoff na transição de GP; lembrete T-7 e tolerância máxima D+1 do `end_date`.

> **Enquanto qualquer item acima estiver aberto, o tier permanece dormante** (0 engagements). O
> tier técnico já está vivo e behavior-neutral (ADR-0111); o que falta é **este gate de governança**.

---

## 8. Pendências para o DPO / advogado licenciado

1. **Ratificar** o RoPA/LIA (§3) — **pela DPO substituta** (Angeline Altair Silva Prado) ou advogado
   licenciado independente, dado o impedimento do DPO titular (acumula presidência/sponsor, Art. 41,
   §2º, II LGPD). Registrar o impedimento na trilha de governança.
2. **Definir** o prazo do SLA de reassignment de `sponsor` (sugestão: 15 dias úteis da posse).
3. **Confirmar o enquadramento** da base da Operação 1 conforme §3.1: LIA (Art. 7º, IX) como base
   **operativa atual** + Art. 5º, I / Art. 12 como proteção adicional **condicionada** à supressão de
   célula pequena. (Posição deste rascunho — validar.)
4. **Hardening `auto_expire_behavior` → `revoke`** para o kind do auditor:
   - **4a.** O DPO ratifica o risco residual de `notify_only` e **autoriza** o diferimento para FU, ou
     **requer** o hardening antes do go-live (decisão de risco).
   - **4b.** Autorizado o hardening, o **GP implementa** `auto_expire_behavior='revoke'` para o kind via
     migration (decisão técnica — não bloqueada no DPO).
5. **Definir o limiar** de supressão de célula pequena (k-anonimato) para as RPCs do auditor, se algum
   agregado expuser counts identificáveis por subgrupo sensível.
6. **Incluir/confirmar a transparência ao titular-membro** (P5/§3.1 Operação 1): cláusula no Termo de
   Voluntariado / notificação de onboarding sobre o reporte agregado à rede institucional PMI.
7. **Confirmar a base e o prazo da retenção** de 730 dias do registro do engagement pós-`end_date`
   (Operação 2 — Art. 16, I vs. demais incisos; prazo prescricional aplicável + política de retenção
   de auditoria do PMI-GO).

---

## 9. Referências

- **ADR-0111** — `institutional_auditor` + `view_aggregate_analytics` (tier técnico): `docs/adr/ADR-0111-institutional-auditor-aggregate-analytics.md`.
- **ADR-0110** — Sponsor read-only split (FU-1): `docs/adr/ADR-0110-sponsor-read-only-split.md`.
- **Anexo R3 #641** — Proteção de dados em cooperação federada (eixo sede↔parceiro): `docs/legal/641_MANUAL_R3_DATA_PROTECTION_ANNEX_DRAFT.md` §5.3.
- **RoPA/LIA #625** — modelo de RoPA + LIA: `docs/legal/RoPA_625_AFFILIATION_VERIFICATION_LIA.md`.
- **GOVERNANCE_CHANGELOG** — GC-149 (registro institucional da Onda 2 + provisionamento do auditor).
- **Plano Onda 2** — achado F8: `~/.claude/plans/onda-2-auditoria-keen-kahn.md`.
- **V4 Authority Model** — `docs/reference/V4_AUTHORITY_MODEL.md`.
- Migration `20260805000292_onda2_fu3_institutional_auditor.sql`.
