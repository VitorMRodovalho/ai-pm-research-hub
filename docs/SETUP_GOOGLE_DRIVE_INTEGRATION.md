# Google Drive Integration — Setup Guide (PM action required)

**Issue:** #110 (Mayanna report Item 07)
**Phase 1 status:** ✅ Schema + RPCs + EF skeleton shipped (autonomous, p77 marathon)
**Phase 2 status:** 🟡 Aguardando PM completar este setup para ativar

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

## Próximas EFs (Phase 2 follow-up)

Após smoke test do `drive-list-folder-files`:

1. **`drive-upload-to-folder`**: proxy upload — file flows client → EF → Drive multipart API → register_card_drive_file RPC
2. **`drive-create-subfolder`**: cria subpastas automaticamente (board novo → pasta nova)
3. **MCP tools**: get_board_drive_files (chama EF list), upload_card_attachment (chama EF upload)

---

## Provenance

- Mayanna usability report (Abril 2026) — Item 07
- p77 Decision: Opção A (institutional service account) com SPOF controlado
- Phase 1 ship: p77 ULTRA-marathon
- Phase 2 trigger: PM completar Passos 1-6 deste doc

Assisted-By: Claude (Anthropic)
