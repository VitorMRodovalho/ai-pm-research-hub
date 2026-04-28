# Google Drive Integration — Setup Guide (PM action required)

**Issue:** #110 (Mayanna report Item 07)
**Phase 1 status:** ✅ Schema + RPCs + EF skeleton shipped (autonomous, p77 marathon)
**Phase 2 status:** ✅ Vault seeded, 12 initiatives linked, list EF live (p78)
**Phase 3 status:** 🟡 Upload + create-subfolder EFs deployed; **upload BLOCKED on PM Step 9 (DwD)**

---

## Pré-requisitos

- [x] Conta institucional `nucleoia@pmigo.org.br` (Google Workspace, confirmado pelo PM)
- [x] Conta backup admin `vitorodovalho@gmail.com` com acesso admin completo (confirmado pelo PM)
- [ ] Google Cloud Console project (criar se não existe)

---

## Passo a passo

### Passo 1 — Google Cloud Console: criar/selecionar project

1. Acessar https://console.cloud.google.com/
2. Login com `nucleoia@pmigo.org.br`
3. Project picker (top bar): "**Núcleo IA**" se já existe; senão:
   - "New Project"
   - Name: "Núcleo IA - Drive Integration"
   - Organization: PMI Goiás (se Workspace organização)
   - Create

### Passo 2 — Enable Drive API

1. Project selecionado → menu hambúrguer → APIs & Services → Library
2. Search "Google Drive API"
3. Click "Enable"

Tempo: ~5min.

### Passo 3 — Criar Service Account

1. APIs & Services → Credentials → "Create Credentials" → "Service account"
2. Service account name: `nucleo-ia-drive-integration`
3. Service account ID: `nucleo-ia-drive` (gera email `nucleo-ia-drive@<project-id>.iam.gserviceaccount.com`)
4. Description: "Service account para integração Drive da plataforma Núcleo IA"
5. Click "Create and Continue"
6. Grant role: skip (não precisa Project IAM role para shared folders)
7. Click "Done"

### Passo 4 — Gerar JSON key

1. Credentials → na lista, click no service account criado
2. Tab "Keys"
3. "Add Key" → "Create new key"
4. Type: JSON
5. Click "Create" → arquivo JSON baixa automático
6. **CRITICAL**: o JSON contém `private_key` — tratar como secret. NÃO commitar no git.

### Passo 5 — Workspace admin: compartilhar pasta com SA

Para CADA pasta Drive que será vinculada a um board:

1. No Google Drive (logado como `nucleoia@pmigo.org.br`)
2. Right-click na pasta → "Share"
3. Add: `nucleo-ia-drive@<project-id>.iam.gserviceaccount.com` (email da SA)
4. Role: "Editor" (permite list + upload + delete)
5. Notify: NÃO (SA não tem inbox)
6. Send

**Inicial:** compartilhar pasta master `/Núcleo IA` ou pastas específicas como `/Hub Comunicação`, `/Tribo X Output`, etc.

### Passo 6 — Seed Vault key no Supabase

1. Acessar Supabase Dashboard: https://supabase.com/dashboard/project/ldrfrvwhxsmgaabwmaik
2. Project Settings → Vault → "New Secret"
3. Name: `google_drive_service_account_json`
4. Description: "Service account JSON para Drive API V3 — issue #110 Mayanna Item 07"
5. Secret: cole o **CONTEÚDO COMPLETO** do JSON baixado no Passo 4
6. Save

Validar via SQL admin:
```sql
SELECT name, length(decrypted_secret) AS chars
FROM vault.decrypted_secrets
WHERE name = 'google_drive_service_account_json';
```
Deve retornar ~2300 chars (private_key é grande).

### Passo 7 — Deploy + smoke test EF

```bash
supabase functions deploy drive-list-folder-files --no-verify-jwt
```

Smoke test:
```bash
curl -sS -X POST "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/drive-list-folder-files" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <user_jwt>" \
  -d '{"folder_id":"<drive_folder_id>"}'
```

Esperado: `{"success": true, "files": [...]}`. Se 503 com `drive_integration_not_configured` → vault não foi seedada. Se 502 → SA não tem permission na pasta (revisar Passo 5).

### Passo 8 — Vincular boards a pastas

Via MCP (tools shipped p77) ou SQL admin:

```typescript
link_board_to_drive({
  board_id: "<hub_comunicacao_board_id>",
  drive_folder_id: "1AbCdEfGhIjKlMnOpQrStUvWxYz",
  drive_folder_url: "https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQrStUvWxYz",
  drive_folder_name: "Hub Comunicação - Templates"
})
```

---

## Como pegar drive_folder_id

URL pasta Drive típica:
```
https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQrStUvWxYz?usp=drive_link
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^
                                         este é o folder_id
```

---

## Troubleshooting

### "drive_integration_not_configured" (503)
Vault key `google_drive_service_account_json` não foi seedada (Passo 6).

### "Drive API list failed: 403" (502)
SA não tem permission na pasta. Revisar Passo 5 — adicionar SA email como Editor.

### "Token exchange failed: 401"
JSON da SA inválido OU SA foi deletada. Regenerar key (Passo 4) + reseedar Vault (Passo 6).

### "Drive API list failed: 429"
Quota exceeded (default 10k requests/100s/project). Pode pedir aumento no Google Cloud Console se virar problema operacional.

---

## Backup & continuidade

**Single Point of Failure aceito (PM-confirmed):**

- Conta institucional: `nucleoia@pmigo.org.br`
- Backup admin: `vitorodovalho@gmail.com` (acesso completo às pastas)

**Recovery em caso de incident:**
- Conta institucional suspensa: PM logs em `vitorodovalho@gmail.com` + recria SA + reseedar Vault
- Pasta Drive movida/deletada: `link_board_to_drive` registra novo folder_id
- API quota exceeded: aumentar quota no Console + cache layer futuro

---

## Passo 9 — Domain-Wide Delegation (REQUIRED para upload + write)

**Discovery (p78 smoke test):** Service Accounts não têm storage quota própria.
Tentar `files.create` com upload em pasta de My Drive retorna 403:
> "Service Accounts do not have storage quota. Leverage shared drives,
> or use OAuth delegation instead."

A solução adotada: **Domain-Wide Delegation** — SA impersonates `nucleoia@pmigo.org.br`
para que o arquivo seja **owned** por essa conta (e use a quota dela).

### Setup steps:

1. Login como **Workspace Admin** em `nucleoia@pmigo.org.br` em https://admin.google.com/
2. Menu: **Security → Access and data control → API controls**
3. Click **Manage Domain Wide Delegation**
4. Click **Add new**
5. Preencher:
   - **Client ID:** `117466213352176222096`
     *(esse é o `client_id` numérico do SA. Source: Vault `google_drive_service_account_json` campo `client_id`)*
   - **OAuth scopes (comma-delimited):** `https://www.googleapis.com/auth/drive`
6. Click **Authorize**

### Validação:

Após autorizar, smoke test:
```bash
curl -sS -X POST "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/drive-upload-to-folder" \
  -H "Content-Type: application/json" -H "Authorization: Bearer test" \
  -d '{"folder_id":"<any_linked_folder>","filename":"smoke.md","mime_type":"text/markdown","content_text":"smoke"}'
```
Esperado: HTTP 200 + `{"success":true, drive_file_id, drive_file_url}`.

Se retornar `{"error":"unauthorized_client"}` — DwD ainda não foi propagado (espera ~30s) ou client_id/scope incorretos.

### Rollback:
Reverter DwD = Workspace Admin → API controls → Domain-Wide Delegation → encontrar entry
do client_id `117466213352176222096` → Delete. Após delete, todas as ops write via SA
falharão com 401.

### Alternativa não-adotada: Shared Drive
Mover as 12 pastas para um Shared Drive (Team Drive) e adicionar SA como Manager
elimina a necessidade de DwD. Não adotamos pois exige migração das pastas existentes
(mantemos My Drive structure que PM já configurou). Pode virar Phase 5 se DwD virar
operacionalmente difícil.

---

## EFs Phase 3 (deployed p78)

1. ✅ **`drive-upload-to-folder`**: text/base64 upload → Drive multipart API. 7MB cap.
   - Inputs: `folder_id, filename, mime_type, content_text|content_base64`
   - Output: `{drive_file_id, drive_file_url, size_bytes, mime_type, filename}`
2. ✅ **`drive-create-subfolder`**: cria subpasta dentro de pasta linkada
   - Inputs: `parent_folder_id, name`
   - Output: `{drive_folder_id, drive_folder_url, name, parent_folder_id}`

## MCP tools (deployed p78, v2.52.0)

1. `register_card_drive_file` — wraps RPC para registrar arquivo Drive existente como card attachment
2. `upload_text_to_drive_folder` — Claude-friendly: gera ata.md, sobe + auto-registra em card opcional
3. `create_drive_subfolder` — cria subpasta + opcionalmente auto-link a iniciativa

## Phase 4 (issue #111, future)

- Cron auto-discovery de atas: scan folders com purpose='minutes', detecta novos arquivos, cria/sync events com minutes_url

---

## Provenance

- Mayanna usability report (Abril 2026) — Item 07
- p77 Decision: Opção A (institutional service account) com SPOF controlado
- Phase 1 ship: p77 ULTRA-marathon
- Phase 2 ship: p77/p78 (Vault seeded + 12 initiatives linked + list EF live)
- Phase 3 ship: p78 (upload + create-subfolder EFs + 3 MCP tools — blocked on Step 9 DwD)
- Phase 4 (future): cron auto-discovery atas (#111)
- ADR-0064 documenta DwD discovery + decisão

Assisted-By: Claude (Anthropic)
