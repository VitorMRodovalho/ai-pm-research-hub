# SPEC 996 — Jornada de Verificação de Filiação (enriquecida)

- **Issue:** #996 (melhoria) · depende de **#995** (bug do parser `pmi_memberships`)
- **Status:** planejamento (não implementar nesta branch)
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

### 4.4 Radar de renovação (F-D)
- "Em dia" no nível de **membresia** = `vep_status_raw='Active'` (ou `service_latest_end_date >= hoje`).
- **Data de vencimento** por capítulo = entrada **manual** no modal de verificação
  (`member_affiliation_verifications.membership_expires_on`), alimentando o farol `farol()` já existente.
- **Não** exibir farol de expiração automático por capítulo (seria falso). Ver §6.

## 5. Modelo & contratos

- **Sem novas tabelas.** A SSOT continua sendo `member_affiliation_verifications` (append-only).
- Se §4.1 estender `get_affiliation_verification_queue`: **DROP + CREATE** (muda shape de retorno), `NOTIFY pgrst`,
  registrar migration + `migration repair` (GC-097). Manter o gate e o `log_pii_access_batch` atuais.
- Frontend: `brChapters()` tolerante a string|objeto (resolvido por #995); novos filtros são estado de client
  sobre a coorte; nenhum novo endpoint de escrita.

## 6. Decisão em aberto para o PM

**Radar de expiração por capítulo.** A fonte automática não traz a data. Opções:
- **(a) Só membresia (recomendado):** farol automático = ativo/inativo (VEP); expiração só quando a diretoria
  digita a data. Simples e honesto.
- **(b) Enriquecer o worker:** investigar se `community.pmi.org` expõe data de renovação por capítulo num campo
  ainda não raspado (não há evidência hoje; `script-mapper.ts:78` só recebe nomes). Seria issue separada de
  pipeline, alto custo, incerto.
- **(c) Manual-first com lembrete:** entrada manual + cron de "radar de renovação" reusando `membership_expires_on`.

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
- [ ] Expiração manual alimenta o farol; nenhum farol de expiração automático falso por capítulo.
- [ ] Testes: parser (#995), shape do RPC estendido, gate de autoridade inalterado.
