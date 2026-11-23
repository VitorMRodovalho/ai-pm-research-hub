# ADR-0124 — Drive membership auto-grant + provisioning (grant mirror of ADR-0107, membership side)

**Status:** Accepted
**Date:** 2026-07-15
**Source:** Issue [#1376](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/1376) (auto-grant asymmetry), origin [#1375](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/1375) (active members losing access)
**Related:** ADR-0107 (#209 Drive revocation cascade — the revoke primitive this mirrors), ADR-0108 (#301 curation FILE grant — the file-level cousin), ADR-0094 (Initiative Collaboration Hub — G4.1 service-account role), ADR-0007 (V4 authority), GC-162 (LGPD).
**Reuses:** the #209/#301 Drive-permission infra — SA auth via `_shared/drive-sa.ts`, `isServiceRoleToken` gate, ledger + partial-unique idempotency + deny-all RLS, the `listPermissions` folder helper, the drain/reconcile-cron discipline.

---

## Context

The platform had **auto-REVOKE** (ADR-0107/#209: offboarded members are detected and their Drive
permissions removed) and a **curation FILE grant** (ADR-0108/#301: curators get temporary `commenter`
access to a submitted artifact). It had **no auto-GRANT of the WORKSPACE folder to active tribe/initiative
members**. Access to a tribe folder depended on a human sharing it by hand, which broke silently on every
reorg, folder move, or new member — with no repair and no observability. The member only discovered the
break when they tried to open the folder (the #1375 incident: "todos os participantes perderam acesso").

Grounded at build time (live, `ldrfrvwhxsmgaabwmaik`, 2026-07-15):
- `drive_auto_revoke_enabled = false` and only 13 historical revocations (all offboarding). The platform
  **did not** revoke active members — confirming the loss is a Drive-side event the platform cannot repair.
- 6 of 12 active research tribes had **no** workspace link — the 6 created in July (C4), all unlinked;
  the 6 from April were linked by a one-off manual batch (2026-04-28). Tribe creation provisions nothing.
- 70 active engaged persons: 48 in initiatives WITH a workspace link (access depends on a manual share),
  32 in initiatives WITHOUT any folder.

Two symptoms, one root: **there is no provisioning automation** — every folder and every grant is manual.

## Decision

Close the auto-revoke ↔ auto-grant asymmetry with a **folder-anchored reconcile** (mirror of the
offboarding scan, grant side) plus a **GP-triggered provisioner** for the folder itself.

1. **Ledger** `drive_membership_grants` — GRANT mirror of `drive_offboarding_audit`. Keyed by
   `(initiative_id, drive_folder_id, grantee)`; role=`writer` (Editor — the tribe collaboration model,
   vs #301's least-privilege `commenter`); partial-unique on `(drive_folder_id, permission_email)` while
   live; deny-all RLS; `permission_email` is PII (SECDEF read only).

2. **Reconcile EF** `reconcile-initiative-drive-access` (service-role, SA `drive` scope). For each active
   workspace link: `listPermissions(folder)` (the SA CAN read the folder ACL — the "no ACL tool" caveat is
   about the assistant, not the EF) × active roster (`get_initiative_drive_roster`, PII-logged) → grant the
   missing emails (`POST /permissions`, role=writer, out-of-domain `sendNotificationEmail` wrinkle reused
   from #301) → `upsert_membership_drive_grants` (idempotent). Single-pass scan+grant (no human-approval
   gate — grants are low-risk, unlike revokes). Self-healing: re-run after any reorg re-grants.

3. **Daily cron** `membership-drive-reconcile-daily` (04:00 UTC) — full sweep, self-heal.

4. **Folder provisioning is GP-triggered, not cron-autonomous** (owner decision, #1376). `drive-create-subfolder`
   is OAuth user-delegated so folder OWNERSHIP falls to a human (governance/backup); a cron has no user.
   MCP tool `provision_initiative_drive` (GP, `manage_platform`) creates the subfolder (owner=human) +
   links it (workspace) + triggers the reconcile. The **weekly cron** `drive-workspace-missing-alert-weekly`
   only ALERTS the GP of tribes/workgroups still missing a folder (`notify_missing_drive_workspaces`).

5. **Observability** — `list_membership_drive_grants` + `get_membership_drive_grant_health` (GP), the
   latter surfacing the missing-folder queue that feeds `provision_initiative_drive`.

## Consequences

- **Prerequisite (unchanged from #209/ADR-0094 G4.1):** the SA needs organizer/fileOrganizer on the parent
  folder or every `POST` returns 403. Failures land as `failed` ledger rows (never crash), surfaced by
  the health RPC. Resolution is validated by **owner test** (folder opens), not ACL read — the SA creds are
  in the Vault and no tool reads an arbitrary folder ACL.
- Revocation stays the offboarding lane (#209). This ledger only records the grant side; when a member is
  offboarded, the offboarding scan detects+revokes the writer permission this created.
- The missing-folder alert is deliberately scoped to `research_tribe` + `workgroup` (avoids noise on
  community verticals, which have no folders by design). The GRANT reconcile is kind-agnostic — it works
  wherever a workspace link exists.

## Apply order

Same gate as #209: schedule the reconcile cron ONLY after the EF is deployed and the SA-role prerequisite
is confirmed (a `dry_run` reconcile returns a plan without granting). The weekly alert cron is pure SQL and
safe to schedule immediately.

---

## Emenda 1: o acesso termina com o vínculo com a iniciativa (#3147, 22/11/2026)

**Decisões do GP (21 e 22/11/2026):** revogar ao fim do vínculo com a iniciativa, com aviso e controle pela tela;
7 dias entre o aviso e a revogação, e em iniciativa confidencial o acesso sai no primeiro ciclo; quem tem
`manage_platform` não entra na fila (vê a confidencial pela ADR-0105); a primeira lista passa pelo GP antes de a
revogação automática ligar.

1. **A concessão ganha o estado `revoked`** (#3135), com `revoked_at`, `revoked_by` e `revoked_via`
   (`membership_queue` ou `offboarding_audit`). O índice de concessão viva não muda: uma linha revogada sai dele, e o
   reconcile pode conceder de novo quando a pessoa volta.
2. **A fila é uma tabela própria**, `drive_membership_revocations`, e não linhas em `drive_offboarding_audit`. Ali a
   invariante AL afirma que nenhuma linha aberta aponta para membro ativo, e esta fila é justamente de membro ativo.
3. **Quem fica com acesso é o predicado do roster** (`get_initiative_drive_roster`), num helper só
   (`_drive_grant_keeps_access`), usado para entrar na fila, para aprovar e para cancelar.
4. **O executor é o da ADR-0107**, sem mudança na EF: `get_drive_revocation_row` e `mark_drive_revocation_done` acham
   também o item novo pelo id, e o cron `revoke-drive-drain-hourly` drena as duas filas. A leitura do executor é a
   última conferência antes do Drive: o item de fim de vínculo cuja pessoa voltou ao roster, ou ganhou
   `manage_platform`, entre a aprovação e o dreno devolve `stale_keeps_access`, a EF não age, e o ciclo cancela.
5. **O ciclo** (`enqueue_membership_drive_revocations`, de hora em hora) também alinha o ledger com a trilha de
   desligamento. O id da permissão do Drive se repete quando o acesso volta, então a revogação só fecha a concessão se
   veio depois do último envio dela.
6. **A chave** `site_config.drive_membership_revoke_enabled` nasce desligada. Com ela desligada, o ciclo ainda alinha
   o ledger, cancela o que deixou de valer e forma a fila, mas não avisa nem aprova ninguém. Revogam com a chave
   desligada só as ações da gestão na tela: "revogar já" e a revogação avulsa.
7. **A tela** fica em `/admin/members/drive-teardown`, abaixo da fila de desligamento, e mostra também o que está
   aberto nela. A gestão segura, solta, desfaz (mantém o acesso daquela concessão), aprova já, e pede revogação
   avulsa de qualquer concessão viva. "Aprovar já" e avulsa recusam o titular com `manage_platform`; "aprovar já"
   recusa também quem voltou ao roster.
8. **O aviso** (decisões do GP de 22/11/2026, depois da revisão de segurança): vai por sino e e-mail, um por pessoa e
   iniciativa, mesmo quando a pessoa tem duas concessões na mesma pasta (e-mail alternativo). "Aprovar já" avisa na
   hora quem ainda não foi avisado, com o texto de acesso encerrado. A avulsa não avisa nem tem prazo. A
   confidencialidade que decide o prazo é a da iniciativa no momento do aviso, não a da entrada na fila.
   "Um por pessoa e iniciativa" vale dentro de um episódio (segunda fatia, 23/11/2026): só cala o aviso outro item
   do mesmo par ainda aberto e detectado a até 7 dias deste, e o aviso de acesso encerrado só é calado por outro
   aviso de acesso encerrado. Se a iniciativa fica confidencial depois de um aviso de 7 dias, o acesso sai no ciclo
   seguinte, e a pessoa recebe nesse ciclo o aviso de acesso encerrado (decisão do GP, 23/11/2026).
9. **A pausa fica no manual, como na ADR-0107 Emenda 1, item 2.** O ciclo só avisa e aprova quem é `active` ou
   `alumni`. O item de quem está `inactive` (reversível sem portão) fica na tela, com o motivo, até a gestão aprovar;
   o aviso dessa aprovação não afirma que o vínculo terminou.
10. **Um bloqueio não é para sempre.** Um item falho, ou um "manter" da gestão, impede a concessão de voltar à fila.
    Quando a pessoa volta ao roster, esse item fecha como `engagement_restored`, e se o vínculo terminar de novo a
    concessão entra limpa. Cada item liberado grava no `admin_audit_log` (`drive_membership_revocation_released`) o
    estado de antes, porque o próprio item passa a dizer `engagement_restored`.
11. **Fora desta emenda:** pasta de trabalho de mais de uma iniciativa (#3178; 0 casos em 22/11/2026, com guard que
    avisa se aparecer) e acesso fora do ledger, como compartilhamento manual depois da revogação (#3179).

## Emenda 2: a pasta decide quem fica, e o acesso fora do ledger vai à revisão (#3178 e #3179, 23/11/2026)

1. **Quem fica olha a pasta (#3178).** `_drive_grant_keeps_access(pessoa, iniciativa, pasta)`: fica quem está no roster
   da iniciativa da concessão ou de qualquer iniciativa ativa com vínculo de trabalho vivo na mesma pasta (o mesmo "usa a
   pasta" de `get_membership_drive_targets`). O ciclo, o executor e o "aprovar já" passam a pasta da concessão, e a
   versão de dois argumentos sai. Quem sai de uma iniciativa e segue em outra que usa a pasta não entra na fila. O item
   aberto pela iniciativa de onde a pessoa saiu por último continua com o nome da iniciativa da concessão.
2. **O acesso fora do ledger vai à revisão (#3179).** O reconcile diário lê a ACL de cada pasta de trabalho, inclusive a
   de roster vazio, e manda para `record_drive_folder_acl`, que classifica num lugar só. Vira item de
   `drive_folder_access_findings` a permissão de usuário sem concessão viva de quem não fica pelo roster da pasta. Ficam
   fora o dono da pasta, grupo, domínio e link, a conta de serviço e quem tem `manage_platform` (a exceção nomeada do
   item da Emenda 1). O item fecha sozinho quando a permissão some, ganha concessão viva, ou a pessoa entra no roster.
3. **Nada sai sozinho.** A gestão mantém (com motivo), reabre, ou pede a revogação (com motivo), em
   `/admin/members/drive-teardown`. A revogação vai pelo executor da ADR-0107, que reconfere antes do Drive, e não avisa
   a pessoa, como a avulsa. A permissão herdada da pasta-mãe não é revogada na pasta de trabalho: só sai na pasta-mãe.
   A chave `drive_membership_revoke_enabled` não manda nesta revisão.
4. **Fora desta emenda:** grupo, domínio e link aberto ("qualquer pessoa com o link") na pasta de trabalho, e a leitura
   da ACL de pasta que não é de trabalho.
