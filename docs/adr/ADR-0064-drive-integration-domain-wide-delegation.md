# ADR-0064: Drive Integration write path — Domain-Wide Delegation

**Status:** Accepted (2026-04-28)
**Decision date:** p78 session (smoke-test discovery + autonomous resolution)
**Supersedes:** —
**Related:** Issue #110 (Mayanna Item 07), `docs/SETUP_GOOGLE_DRIVE_INTEGRATION.md`

---

## Context

Phase 3 do Drive Integration (p78) entrega 2 EFs novas (`drive-upload-to-folder`,
`drive-create-subfolder`) + 3 MCP tools (`register_card_drive_file`,
`upload_text_to_drive_folder`, `create_drive_subfolder`).

Smoke test surfaceu constraint estrutural do Google Drive API que não estava
documentada na Phase 1/2:

> **Service Accounts não têm storage quota própria.**
> Tentar `files.create` (multipart upload) em pasta de My Drive de outro
> usuário retorna 403 com `storageQuotaExceeded`:
> `"Service Accounts do not have storage quota. Leverage shared drives, or
> use OAuth delegation instead."`

Subfolder creation funciona (folders consomem 0 bytes de quota), mas qualquer
upload real falha. Phase 3 fica code-complete mas operacionalmente bloqueada.

### Alternativas avaliadas

| Path | Trade-off |
|------|-----------|
| **A. Domain-Wide Delegation (DwD)** — SA impersonates `nucleoia@pmigo.org.br`. File ownership cai no usuário institucional, usa quota dele. | Requer Workspace Admin enable DwD pro client_id da SA com scope `drive`. ~2min de PM-side setup. Não invasivo nas pastas existentes. |
| **B. Shared Drive (Team Drive)** — mover as 12 pastas para um Shared Drive, adicionar SA como Manager. | Resolve quota (Shared Drive tem quota da org). Mas exige migrar pastas existentes (PM já configurou estrutura My Drive, `nucleoia@pmigo.org.br` é dono). Possível regressão para usuários que sabem onde os arquivos estão. |
| **C. Frontend upload via OAuth Browser Flow** — usuário autentica com Google, faz upload direto do browser. Plataforma só registra metadata. | Não bloqueia em DwD. Mas: cada usuário precisa instalar/autorizar OAuth scope. Aumenta friction substancial. Quebra workflow "Claude gera ata e arquiva" via MCP. |

## Decision

**Adotar Path A (Domain-Wide Delegation) como caminho primário para writes.**

### Implementação

EFs `drive-upload-to-folder` e `drive-create-subfolder` injetam `sub:
"nucleoia@pmigo.org.br"` no JWT payload (override via env var
`GOOGLE_DRIVE_IMPERSONATE_USER` se preciso testar com outra conta).

PM action: enable DwD em Workspace Admin Console com:
- Client ID: `117466213352176222096`
- Scope: `https://www.googleapis.com/auth/drive`

Steps detalhadas em `docs/SETUP_GOOGLE_DRIVE_INTEGRATION.md` Passo 9.

### Validação

Após PM completar DwD:
- `drive-upload-to-folder` upload smoke test = 200 com `drive_file_id`
- `drive-create-subfolder` continua funcionando (já validado pré-DwD)
- Files ficam owned por `nucleoia@pmigo.org.br` (usa quota dela, ~15GB Workspace default)
- 12 initiatives já vinculadas continuam read-only enquanto DwD não é setup

### Read path: continua sem DwD

`drive-list-folder-files` (Phase 1/2) usa scope `drive.readonly` sem `sub`.
Read não consome quota — funciona com ou sem DwD. Nenhuma regressão na
listagem das 56 atas reais já mapeadas.

## Consequences

### Positive

- **Phase 3 desbloqueia com 1 PM action de ~2min** (vs migração de pastas para Shared Drive)
- **Não-invasivo**: pastas existentes (LATAM LIM 2026, T1-T8, Comitê Curadoria, etc.) ficam intactas
- **Auditoria mais clara**: arquivos criados via plataforma ficam owned por `nucleoia@pmigo.org.br` (rastreável institucionalmente)
- **Quota usage**: 15GB default da Workspace cobre folga grande (atas em markdown ~50KB/cada → 300k+ atas)

### Negative / risks

- **Workspace dependency**: se conta `nucleoia@pmigo.org.br` for suspensa/perdida, todos writes parados (mesmo backup `vitorodovalho@gmail.com` não cobre upload via SA). Já era o SPOF aceito na Phase 1.
- **DwD é amplo**: client_id `117466213352176222096` poderia (em tese) impersonar QUALQUER usuário do domínio se outras contas forem adicionadas como subjects. Mitigação: SA's PEM só está em Vault Supabase, não circula. Reset DwD = revogar entry no Console.
- **Scope `drive` é amplo**: SA tem theoretical full read+write em qualquer pasta de `nucleoia@pmigo.org.br`. Mitigação: PM já compartilhou seletivamente as 12 pastas; SA só age onde tem permission explícita.

### Reopening criteria (Path B Shared Drive)

Migrar para Shared Drive se:
1. Ops volume > 10GB / mês (saturação iminente da quota da conta institucional)
2. Auditoria/compliance pede separação clara entre dados pessoais do usuário institucional e dados Núcleo IA
3. Mais de uma conta institucional precisar acessar (ex: PMI Brasil entra na governança e quer Manager direto sem DwD)

Quando reopening: cria Shared Drive "Núcleo IA", move folders, atualiza
`board_drive_links.drive_folder_id` (folder IDs persistem em moves dentro do mesmo Workspace),
adiciona SA como Manager. Remove DwD entry. EFs voltam a usar JWT sem `sub`.

## Implementation references

- EFs: `supabase/functions/drive-upload-to-folder/index.ts`,
  `supabase/functions/drive-create-subfolder/index.ts`
- MCP tools: `supabase/functions/nucleo-mcp/index.ts` (v2.52.0, +3 tools = 234 total)
- Setup guide: `docs/SETUP_GOOGLE_DRIVE_INTEGRATION.md` Passo 9
- Vault key: `google_drive_service_account_json` (já seedada — JSON da SA)
- Smoke test (post-DwD): curl em `drive-upload-to-folder` com folder_id qualquer dos 12 linked

## Provenance

- Phase 3 build: p78 autonomous marathon (continuação p77)
- Smoke test discovery: 403 storageQuotaExceeded em primeira tentativa de upload
- Resolution time: ~10min de patch (sub claim) + redeploy
- PM action remaining: Passo 9 do setup guide (~2min)
