# SPEC 996 — Jornada de Verificação de Filiação (enriquecida)

- **Issue:** #996 (melhoria) · depende de **#995** (bug do parser `pmi_memberships`)
- **Status:** planejamento (não implementar nesta branch) · **§6 decidido pelo PM = opção (a′): radar automático a partir de `service_latest_end_date` (revisado 2026-07-01, ver §6)**
- **Data:** 2026-07-01
- **Rota afetada:** `/admin/filiacao` · componente `src/components/admin/AffiliationQueueIsland.tsx`
- **Autoridade de escrita (inalterada):** RPC SECURITY DEFINER + gate `filiacao_director` / `manage_member` + atestação F1b (`trg_affiliation_attestation`)

> Grounding (queries read-only ao vivo, 2026-07-01): coorte da fila = **82** membros ativos não-verificados;
> pré-onboarding = **34**; com enriquecimento PMI via `selection_applications` = **45**; com string
> `"…, Brazil Chapter"` = **45/45**; tipo do elemento `pmi_memberships[0]` = **45× string / 0× object**.
> Todos os números aqui devem ser re-aterrados no momento da implementação (não recitar deste doc).

---

## 1. Problema

A fila de filiação faz a diretoria **re-verificar manualmente** o que a plataforma já sabe. O enriquecimento
PMI (Phase B, via worker `pmi-vep-sync`) popula `selection_applications` com identidade completa, exibida na aba
**PMI** do Processo Seletivo (`get_application_pmi_profile`), mas a **fila de filiação não a expõe**. Somado a
isso, o parser atual (#995) esconde até o capítulo BR que já está no payload.

Consequência: 45/82 membros com capítulo BR ativo já provado aparecem como "verificar manualmente",
anulando o ganho do auto-enriquecimento.

## 2. Objetivo

Migrar a jornada de **"verificar tudo na unha"** → **"revisar o auto-derivado e confirmar exceções"**, sem
afrouxar o boundary de autoridade nem prometer automação que a fonte não sustenta.

## 3. Fonte de dados (o que já existe)

| Necessidade | Fonte | Observação |
|---|---|---|
| Existência de capítulo BR | `selection_applications.pmi_memberships` (array de **strings**) | via `get_affiliation_verification_queue`. #995 corrige o parser. |
| Ativo/inativo (geral) | `selection_applications.vep_status_raw` (`Active`/…) | proxy de "em dia" no nível de membresia, não por capítulo. |
| Membro desde/até | `service_first_start_date` / `service_latest_end_date` | deriva `member_status` (active/past). |
| Identidade rica (PMI ID, certs, nº voluntariados, última sync) | `get_application_pmi_profile(application_id)` | já usada pela seleção; reaproveitar. |
| Trilha de verificação (SSOT) | `member_affiliation_verifications` (append-only) | `chapter_verified`, `membership_active`, `membership_expires_on`, `method`. |
| Confirmação em lote via VEP | `verify_member_affiliations_bulk(p_member_ids, p_method:'vep_sync')` | já existe (mig 148). |

**Limite honesto:** a forma string de `pmi_memberships` **não carrega data de expiração por capítulo** (a fonte
"PMI Community member history strings" não expõe). Portanto o radar por-capítulo de "vence em breve / vencida"
**não é automatizável**; ver §6.

## 4. Escopo funcional

### 4.1 Linha enriquecida (F-A)
Cada linha da fila ganha contexto PMI sem sair da tela:
- Badge **ativo/inativo** derivado de `vep_status_raw`.
- Capítulo(s) BR (pós-#995) com o `chapter` declarado ao lado, sinalizando divergência declarado-vs-VEP.
- **PMI ID**, **membro desde/até**, **última sync** e **nº de voluntariados** num expand/painel por linha.
- Decisão: reusar a fonte `get_application_pmi_profile` **ou** estender o próprio
  `get_affiliation_verification_queue` a devolver esses campos já agregados (evitar N+1 no client).
  **Recomendado:** estender o RPC da fila (uma chamada, já é SECURITY DEFINER e já loga PII em lote).

### 4.2 Confirmação em lote (F-B)
- Regra de auto-sugestão: `vep_status_raw='Active'` **E** existe capítulo BR ⇒ candidato a "verificável via VEP".
- Ação em lote sobre a seleção usando `verify_member_affiliations_bulk(..., p_method:'vep_sync')` — infra pronta,
  já grava `membership_active` derivado de `vep_status_raw='Active'`.
- Manual (`sede_manual`) permanece para exceções (perfil privado / sem VEP / divergência declarada).
- Preservar atestação F1b e o bloqueio de auto-verificação (não verificar a si mesmo).

### 4.3 Filtros & controles (F-C)
Substituir as 2 abas fixas por controles combináveis:
- **Status** (farol): não verificada / verificada / vence em breve / vencida / inativa.
- **Capítulo** (lista PMI-XX) e **VEP status** (`Active`/`Submitted`/`OfferExtended`/`—`).
- **Busca** por nome/email (client-side sobre a coorte já carregada).
- **Ordenação** por nome, status, última sync.
- **Default "precisa atenção":** pré-onboarding + não verificados/vencidos primeiro (mantém a intenção da aba atual).

### 4.4 Radar de renovação (F-D) — automático a partir do enriquecido
- **Vigência ("em dia")** = `vep_status_raw='Active'` (sinal autoritativo do VEP).
- **Data de vencimento** = `selection_applications.service_latest_end_date` (a mesma "Até" já exibida na aba PMI
  da seleção). É a data enriquecida confiável — **não** deixar como manual-only.
- **Correção obrigatória de bug:** o caminho `vep_sync` de `verify_member_affiliations_bulk`
  (`supabase/migrations/20260805000148_625_...:246`) hoje grava `membership_expires_on = NULL` com o comentário
  **falso** "vep_sync não tem expiração". Deve passar a **ler `service_latest_end_date`** (via o mesmo LATERAL
  por email que já usa para `vep_status_raw`) e gravá-la em `membership_expires_on`. Assim o farol `farol()`
  (vence-em-breve/vencida) passa a funcionar **automaticamente** para toda a coorte enriquecida.
- **Manual** (`sede_manual`) permanece só como **override/fallback** para quem não tem data enriquecida (~4/75).
- **Guarda de consistência:** a vigência ativa/inativa é dirigida pelo **VEP** (autoritativo), não pela data
  sozinha — evita marcar "vencida" alguém que o VEP ainda reporta `Active`. Grounding: 41/41 VEP-Active têm
  `service_latest_end_date` no futuro (0 passadas, 0 nulas), i.e. a data é consistente com o VEP.

## 5. Modelo & contratos

- **Sem novas tabelas.** A SSOT continua sendo `member_affiliation_verifications` (append-only).
- **`verify_member_affiliations_bulk` (RPC change):** no ramo `vep_sync`, incluir `a.service_latest_end_date` no
  SELECT LATERAL (mig 148:226-231) e gravá-la em `membership_expires_on` no INSERT (mig 148:246, hoje `NULL`).
  Assinatura inalterada ⇒ pode ser `CREATE OR REPLACE`; `NOTIFY pgrst` opcional (shape de retorno não muda).
- Se §4.1 estender `get_affiliation_verification_queue`: **DROP + CREATE** (muda shape de retorno), `NOTIFY pgrst`,
  registrar migration + `migration repair` (GC-097). Manter o gate e o `log_pii_access_batch` atuais.
- Frontend: `brChapters()` tolerante a string|objeto (resolvido por #995); novos filtros são estado de client
  sobre a coorte; nenhum novo endpoint de escrita.

## 6. Decisão do PM — radar de expiração

> **DECIDIDO (PM, 2026-07-01, REVISADO): opção (a′) — radar automático a partir do dado enriquecido.**
> A data de vencimento **vem do enriquecido** (`selection_applications.service_latest_end_date`, a "Até" já
> exibida na seleção) e deve alimentar `member_affiliation_verifications.membership_expires_on` automaticamente
> — corrigindo o bug que hoje grava `NULL` no caminho `vep_sync` (ver §4.4). Vigência ativa/inativa dirigida
> pelo **VEP Active** (autoritativo); a data dirige "vence em breve/vencida". Entrada manual só como override
> para os poucos sem data enriquecida.

**Histórico da decisão.** A primeira leitura (2026-07-01, revertida no mesmo dia) concluiu "manual only" a
partir de `pmi_memberships` ser um array de **strings** sem expiry. Isso estava **errado**: o re-aterramento
mostrou que a data existe em coluna dedicada e é confiável.

Grounding (queries read-only ao vivo, 2026-07-01):
- `service_latest_end_date` populada em **71/75** apps enriquecidas; **62** no futuro, min `2024-12-31` /
  max `2028-01-31` (padrão de renovação anual, não term-end aleatório).
- **41/41** membros VEP-Active têm a data no **futuro** — 0 passadas, 0 nulas ⇒ consistente com a vigência VEP.
- O bug: `verify_member_affiliations_bulk` (mig 148:246) grava `membership_expires_on = NULL` e o SELECT
  (mig 148:226-231) nem lê `service_latest_end_date`.

Opções avaliadas:
- **(a′) Automático do enriquecido ✅ ESCOLHIDA:** ler `service_latest_end_date` no `vep_sync` → gravar em
  `membership_expires_on`; farol de renovação passa a funcionar sem digitação. Manual = override/fallback (~4/75).
- **(a) Só membresia (descartada):** era baseada na premissa falsa de que não havia data.
- **(b) Enriquecer o worker (não necessário agora):** a data já chega; só o RPC a descartava. Fica como caminho
  futuro apenas se PMI passar a expor uma renovação **por capítulo** distinta (hoje `service_latest_end_date` é o
  máximo agregado — ver caveat abaixo).

**Caveat semântico (manter honesto).** `service_latest_end_date` é o *fim de serviço/membresia mais recente*
(máximo agregado dos registros do PMI Community), não um campo de "dues renewal" por capítulo; a coluna
`membership_status` está **100% NULL** (morta, não usar). Para o gate "filiado a capítulo BR em dia" isso é um
proxy adequado (rotular na UI como "membro até", não "capítulo vence em"), e a vigência real vem do VEP.

## 7. Invariantes a preservar (não re-litigar)
- Escrita **só** via RPC SECURITY DEFINER + gate `filiacao_director`/`manage_member` + atestação F1b.
- LGPD Art. 37: leitura nominal logada (`log_pii_access_batch`).
- Trilha append-only como SSOT; cache `members.pmi_id_verified` derivado, nunca fonte.
- Confidencialidade de iniciativas (ADR-0105) não é afetada (filiação é sobre membro, não iniciativa).

## 8. Fora de escopo
- Mudar o pipeline de enriquecimento VEP (worker) — salvo decisão §6(b).
- Alterar a aba PMI do Processo Seletivo.
- Qualquer afrouxamento do boundary de autoridade.

## 9. Aceite (da melhoria)
- [ ] Linha da fila mostra capítulo BR + badge ativo/inativo + PMI ID/última sync (painel).
- [ ] Confirmação em lote via VEP funcional para a coorte `Active` + capítulo BR, com atestação F1b preservada.
- [ ] Filtros de status/capítulo/VEP + busca + ordenação; default "precisa atenção".
- [ ] `verify_member_affiliations_bulk` (`vep_sync`) grava `service_latest_end_date` em `membership_expires_on`
      (não mais `NULL`); farol de renovação funciona automaticamente para a coorte enriquecida; manual = override.
- [ ] Testes: parser (#995), shape do RPC estendido, gate de autoridade inalterado.
