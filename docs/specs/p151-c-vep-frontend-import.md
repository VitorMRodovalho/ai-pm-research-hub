# Spec p151 C — VEP Frontend Import (JSON consolidado via server-side proxy)

**Status**: READY FOR IMPLEMENTATION
**Sessão**: p151 (2026-05-12)
**Owner**: PM Vitor Maia Rodovalho
**Predecessores diretos**:
- p150 manual ingest via Claude MCP SQL (memory `project_p150_pmi_vep_ingest_applied.md`)
- p150 backlog spawned (memory `project_pmi_vep_frontend_import_backlog.md`)
- p150 logic canonical PM diretiva (memory `feedback_pmi_vep_ingest_logic_canonical.md`)
- B-full PAUSED (memory `handoff_p151_b_full_paused_pending_humans.md`)

---

## 0. Contexto e gap

**Estado atual:**

| Path | Onde | Problema |
|---|---|---|
| Worker `/ingest` | `cloudflare-workers/pmi-vep-sync/src/index.ts:160` (HTTP POST, secret-gated) | Requer `INGEST_SHARED_SECRET` no script extract_pmi_volunteer.js (browser). PM não tem o secret colado fácil. |
| Tab `/admin/selection?tab=import` | `selection.astro:245-...` | Hoje só tem "VEP Opportunities Config" + "Import CSV por email". Sem caminho para JSON consolidado. |
| Fallback p150 | Claude MCP SQL direto (35 UPDATEs + 41 history rows manual) | Bypassa worker logic (welcome dispatch, onboarding token, idempotency safeguards). Erro-prone. |

**PM diretiva p150** (texto direto):
> "nao precisa executar agora, pode colocar em backlog ou desenhar requisito para a demanda" + "logica de importacao do json do vep para poder ter via via de import frontend, com a logica de checar se o application id é existente para so fazer update das informacoes, e se nao for existente criar no ciclo em avaliacao mais novo o id da nova aplicacao com os dados do aplicante e fazer toda logica de conferir se o aplicante (pelo pmi id) já é membro ou foi do nucleo, se é re aplicante"

**Logic canonical** (sediment `feedback_pmi_vep_ingest_logic_canonical.md`):
- Ingest sempre por **compound key** `(vep_application_id, vep_opportunity_id)`
- Existe → **UPDATE** no ciclo atual da pessoa (refresh **OBRIGATÓRIO** de `resume_url` — SAS Azure 48h TTL)
- Não existe → **CREATE** no ciclo `open` mais novo
- Anti-pattern: diff filtrado por cycle único (worker pega cycle único atualmente — sediment p150 captou que múltiplos `open` cycles simultâneos quebram lookup)

---

## 1. Decisão arquitetural

**Reusa worker existente via server-side Astro proxy** (NÃO duplicar logic em EF nova).

**Justificativa:**
- Worker já tem toda logic canonical: `upsertSelectionApplication`, `mapScriptToNucleo`, `issueOnboardingToken`, `dispatchWelcome`, `getOpenSelectionCycle`, Phase B canonical UPSERT, service_history INSERT
- Sediment `feedback_worker_db_schema_drift_audit_pattern.md` (p131) documenta dor real de drift entre worker e DB — duplicar logic em EF nova multiplica risco
- Astro tem suporte nativo a server endpoints (`.ts` em `src/pages/api/`) com env binding via Cloudflare Worker context — secret fica server-side

**Fluxo:**

```
[Admin no browser]
    ↓ POST FormData/JSON
[Astro endpoint /api/admin/import-pmi-vep-json.ts]
    ↓ valida session JWT (Supabase) + canV4 manage_member gate
    ↓ pega INGEST_SHARED_SECRET do env (Wrangler binding)
    ↓ forward para worker /ingest com x-ingest-secret header
[Worker pmi-vep-sync /ingest]
    ↓ aplica logic canonical existente (idempotency + cycle resolution + UPSERT + Phase B)
    ↓ retorna IngestSummary JSON
[Astro endpoint]
    ↓ retorna IngestSummary ao browser
[Admin UI]
    ↓ renderiza preview (dry-run) ou stats (apply)
```

---

## 2. Modificações no worker (mínimas)

Worker `pmi-vep-sync/src/index.ts` precisa suportar **dry-run mode**:

```typescript
// Em handleIngest, após parsing body:
const dryRun = body.dry_run === true;

// Substituir todos os INSERTs/UPDATEs por wrappers:
if (dryRun) {
  // Simular operação, calcular diff, NÃO executar
  // Para UPSERT: SELECT existing row → mark WILL_UPDATE or WILL_INSERT
  // Para welcome/onboarding: mark would_dispatch
} else {
  // Executar (path existente)
}
```

**Alternativa mais simples** (recomendada): adicionar **early exit** com diff-only sem fazer UPSERT:

```typescript
// p151 C: dry-run preview support
if (body.dry_run === true) {
  const diff = {
    cycle_id: cycle.id, cycle_code: cycle.cycle_code,
    applications_received: body.applications.length,
    will_insert: [], will_update: [], will_skip: [], errors: []
  };

  for (const app of body.applications) {
    const oppId = String(app._opportunityId);
    const opp = oppLookup[oppId];
    if (!opp) { diff.will_skip.push({ ref: String(app.applicationId), reason: 'opportunity_not_active' }); continue; }
    if (!opp.essay_mapping || Object.keys(opp.essay_mapping).length === 0) { diff.will_skip.push({ ref: String(app.applicationId), reason: 'essay_mapping_missing' }); continue; }

    const mapped = mapScriptToNucleo(app, opp, allQRs, cycle.id, cycle.cycle_code, env.ORG_ID);
    if (!mapped.email || !mapped.applicant_name) { diff.will_skip.push({ ref: String(app.applicationId), reason: 'missing_required' }); continue; }

    // Lookup existing by compound key
    const existing = await db.from('selection_applications')
      .select('id, applicant_name, status, cycle_id, role_applied, chapter')
      .eq('vep_application_id', mapped.vep_application_id)
      .eq('vep_opportunity_id', mapped.vep_opportunity_id)
      .maybeSingle();

    if (existing.data) {
      diff.will_update.push({
        application_id: existing.data.id,
        applicant_name: mapped.applicant_name,
        existing_cycle_id: existing.data.cycle_id,
        existing_status: existing.data.status,
        existing_role: existing.data.role_applied
      });
    } else {
      diff.will_insert.push({
        applicant_name: mapped.applicant_name,
        email: mapped.email,
        opportunity_id: oppId,
        chapter: opp.chapter,
        role_applied: opp.default_role
      });
    }
  }

  return jsonResponse({ dry_run: true, summary: diff }, 200);
}
// ... existing logic
```

**Modificação total no worker**: ~50 linhas + 1 type. Sem mudança em DB.

---

## 3. Astro endpoint `/api/admin/import-pmi-vep-json.ts`

```typescript
// src/pages/api/admin/import-pmi-vep-json.ts
import type { APIRoute } from 'astro';
import { createServerClient } from '../../../lib/supabase-server';

export const POST: APIRoute = async ({ request, locals }) => {
  // 1. Auth: validate session JWT
  const supabase = createServerClient(request, locals);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  // 2. canV4 gate: manage_member (or import_applications if dedicated action)
  const { data: gate } = await supabase.rpc('can', { p_action: 'manage_member' });
  if (!gate) {
    return new Response(JSON.stringify({ error: 'Forbidden: requires manage_member' }), { status: 403 });
  }

  // 3. Parse payload
  let body: any;
  try {
    body = await request.json();
  } catch (e: any) {
    return new Response(JSON.stringify({ error: 'invalid_json' }), { status: 400 });
  }
  if (!body.payload) {
    return new Response(JSON.stringify({ error: 'missing payload field' }), { status: 400 });
  }

  // 4. Forward to worker
  const workerUrl = import.meta.env.PMI_VEP_SYNC_URL ?? 'https://pmi-vep-sync.vitormr.dev';
  const secret = import.meta.env.INGEST_SHARED_SECRET; // wrangler binding
  if (!secret) {
    return new Response(JSON.stringify({ error: 'server_misconfig: INGEST_SHARED_SECRET missing' }), { status: 500 });
  }

  const workerPayload = {
    ...body.payload,
    dry_run: body.dry_run === true
  };

  const workerResp = await fetch(`${workerUrl}/ingest`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-ingest-secret': secret
    },
    body: JSON.stringify(workerPayload)
  });

  const workerData = await workerResp.json();

  // 5. Log invocation via admin_audit_log (Astro endpoint, not worker)
  await supabase.rpc('log_admin_action', {
    p_action: body.dry_run ? 'import_pmi_vep_json_dry_run' : 'import_pmi_vep_json_apply',
    p_target_type: 'selection_applications_batch',
    p_metadata: {
      applications_received: body.payload?.applications?.length ?? 0,
      worker_status: workerResp.status,
      dry_run: body.dry_run === true
    }
  });

  return new Response(JSON.stringify(workerData), {
    status: workerResp.status,
    headers: { 'content-type': 'application/json' }
  });
};
```

**Env bindings** (wrangler.toml/astro.config):
- `INGEST_SHARED_SECRET` — já existe no worker, replicar no Astro env (Cloudflare Worker binding)
- `PMI_VEP_SYNC_URL` — default `https://pmi-vep-sync.vitormr.dev`

---

## 4. Frontend — novo card em tab Import

**Localização**: `src/pages/admin/selection.astro` na tab `import` (linha 245+), após o card "Import CSV" existente.

### HTML novo card

```html
<!-- p151 C: Import JSON consolidado -->
<div class="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-6 space-y-4">
  <div class="flex items-center justify-between">
    <h2 class="text-lg font-bold text-navy">{t('admin.selection.importJsonTitle', lang)}</h2>
    <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-100 text-purple-700">NEW</span>
  </div>
  <p class="text-sm text-[var(--text-secondary)]">{t('admin.selection.importJsonDesc', lang)}</p>
  <p class="text-[11px] text-[var(--text-muted)]">
    {t('admin.selection.importJsonHint', lang)}
    <code class="text-[10px] bg-[var(--surface-base)] px-1.5 py-0.5 rounded">cloudflare-workers/pmi-vep-sync/scripts/extract_pmi_volunteer.js</code>
  </p>

  <!-- File picker -->
  <div id="json-dropzone" class="border-2 border-dashed border-[var(--border-default)] rounded-xl p-8 text-center cursor-pointer hover:border-navy hover:bg-[var(--surface-hover)] transition-all">
    <div class="text-3xl mb-2">📦</div>
    <p class="text-sm font-semibold text-[var(--text-secondary)]" id="json-dropzone-label">
      {t('admin.selection.importJsonDropZone', lang)}
    </p>
    <p class="text-[11px] text-[var(--text-muted)] mt-1">{t('admin.selection.importJsonDropZoneHint', lang)}</p>
    <input type="file" id="json-file-input" accept=".json,application/json" class="hidden" />
  </div>

  <!-- Schema validation result -->
  <div id="json-schema-result" class="hidden text-[11px]"></div>

  <!-- Action buttons (dry-run preview + apply) -->
  <div class="flex gap-2">
    <button id="json-dry-run-btn" class="px-4 py-2 bg-purple-600 text-white rounded-lg text-[12px] font-bold cursor-pointer border-0 hover:opacity-90 disabled:opacity-40" disabled>
      📋 {t('admin.selection.importJsonDryRunBtn', lang)}
    </button>
    <button id="json-apply-btn" class="px-4 py-2 bg-navy text-white rounded-lg text-[12px] font-bold cursor-pointer border-0 hover:opacity-90 disabled:opacity-40" disabled>
      ✓ {t('admin.selection.importJsonApplyBtn', lang)}
    </button>
  </div>

  <!-- Preview (dry-run result) -->
  <div id="json-preview" class="hidden space-y-3">
    <div id="json-preview-summary" class="grid grid-cols-3 gap-2"></div>
    <details class="border border-[var(--border-default)] rounded-lg p-3">
      <summary class="text-[12px] font-semibold cursor-pointer">{t('admin.selection.importJsonShowDetails', lang)}</summary>
      <div id="json-preview-details" class="mt-2 max-h-[300px] overflow-y-auto text-[11px]"></div>
    </details>
  </div>

  <!-- Apply result -->
  <div id="json-apply-result" class="hidden bg-emerald-50 border border-emerald-200 rounded-lg p-3 text-[12px]"></div>
</div>
```

### JS handlers

```typescript
// Em <script> de selection.astro, após handlers de CSV import:
let pendingJsonPayload: any = null;
let pendingDryRunSummary: any = null;

const jsonDropzone = document.getElementById('json-dropzone');
const jsonFileInput = document.getElementById('json-file-input') as HTMLInputElement;
const jsonSchemaResult = document.getElementById('json-schema-result');
const jsonDryRunBtn = document.getElementById('json-dry-run-btn') as HTMLButtonElement;
const jsonApplyBtn = document.getElementById('json-apply-btn') as HTMLButtonElement;
const jsonPreview = document.getElementById('json-preview');
const jsonApplyResult = document.getElementById('json-apply-result');

jsonDropzone?.addEventListener('click', () => jsonFileInput?.click());

jsonFileInput?.addEventListener('change', async () => {
  const file = jsonFileInput.files?.[0];
  if (!file) return;
  try {
    const text = await file.text();
    const parsed = JSON.parse(text);
    // Schema validation
    const validation = validateConsolidatedJsonShape(parsed);
    if (!validation.ok) {
      jsonSchemaResult.classList.remove('hidden');
      jsonSchemaResult.innerHTML = `<div class="bg-red-50 border border-red-200 rounded-lg p-2 text-red-800">❌ ${esc(validation.error)}</div>`;
      jsonDryRunBtn.disabled = true;
      return;
    }
    pendingJsonPayload = parsed;
    jsonSchemaResult.classList.remove('hidden');
    jsonSchemaResult.innerHTML = `<div class="bg-emerald-50 border border-emerald-200 rounded-lg p-2 text-emerald-800">
      ✓ Arquivo válido: ${parsed.applications?.length ?? 0} applications, ${parsed.opportunities?.length ?? 0} opportunities, ${parsed.questionResponses?.length ?? 0} QRs, ${parsed.serviceHistory?.length ?? 0} history rows
    </div>`;
    jsonDryRunBtn.disabled = false;
    jsonApplyBtn.disabled = true;
    pendingDryRunSummary = null;
  } catch (e: any) {
    jsonSchemaResult.classList.remove('hidden');
    jsonSchemaResult.innerHTML = `<div class="bg-red-50 border border-red-200 rounded-lg p-2 text-red-800">❌ JSON inválido: ${esc(e.message)}</div>`;
    jsonDryRunBtn.disabled = true;
    pendingJsonPayload = null;
  }
});

function validateConsolidatedJsonShape(obj: any): { ok: boolean; error?: string } {
  if (!obj || typeof obj !== 'object') return { ok: false, error: 'root deve ser object' };
  if (!Array.isArray(obj.applications)) return { ok: false, error: 'falta applications array' };
  if (obj.applications.length === 0) return { ok: false, error: 'applications array vazio' };
  // Opcionais mas comuns:
  if (obj.opportunities && !Array.isArray(obj.opportunities)) return { ok: false, error: 'opportunities deve ser array se presente' };
  if (obj.questionResponses && !Array.isArray(obj.questionResponses)) return { ok: false, error: 'questionResponses deve ser array se presente' };
  if (obj.serviceHistory && !Array.isArray(obj.serviceHistory)) return { ok: false, error: 'serviceHistory deve ser array se presente' };
  // Sample application shape
  const a = obj.applications[0];
  if (!a.applicationId) return { ok: false, error: 'applications[0].applicationId ausente' };
  if (!a._opportunityId) return { ok: false, error: 'applications[0]._opportunityId ausente (campo synthetic do script)' };
  return { ok: true };
}

jsonDryRunBtn?.addEventListener('click', async () => {
  if (!pendingJsonPayload) return;
  jsonDryRunBtn.disabled = true;
  jsonDryRunBtn.textContent = '⏳ Calculando preview...';
  try {
    const resp = await fetch('/api/admin/import-pmi-vep-json', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ payload: pendingJsonPayload, dry_run: true })
    });
    const data = await resp.json();
    if (!resp.ok) throw new Error(data.error || data.message || 'erro inesperado');
    pendingDryRunSummary = data.summary;
    renderDryRunPreview(data.summary);
    jsonApplyBtn.disabled = false;
  } catch (e: any) {
    toast(`Erro no preview: ${e.message}`, 'error');
  } finally {
    jsonDryRunBtn.disabled = false;
    jsonDryRunBtn.textContent = '📋 Preview (dry-run)';
  }
});

jsonApplyBtn?.addEventListener('click', async () => {
  if (!pendingJsonPayload || !pendingDryRunSummary) return;
  if (!confirm(`Aplicar import: ${pendingDryRunSummary.will_insert?.length ?? 0} NEW + ${pendingDryRunSummary.will_update?.length ?? 0} UPDATE + ${pendingDryRunSummary.will_skip?.length ?? 0} SKIP. Confirma?`)) return;
  jsonApplyBtn.disabled = true;
  jsonApplyBtn.textContent = '⏳ Aplicando...';
  try {
    const resp = await fetch('/api/admin/import-pmi-vep-json', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ payload: pendingJsonPayload, dry_run: false })
    });
    const data = await resp.json();
    if (!resp.ok) throw new Error(data.error || data.message || 'erro inesperado');
    renderApplyResult(data);
    pendingJsonPayload = null;
    pendingDryRunSummary = null;
    jsonFileInput.value = '';
    jsonSchemaResult.classList.add('hidden');
    jsonPreview.classList.add('hidden');
    jsonDryRunBtn.disabled = true;
  } catch (e: any) {
    toast(`Erro no apply: ${e.message}`, 'error');
  } finally {
    jsonApplyBtn.disabled = false;
    jsonApplyBtn.textContent = '✓ Aplicar';
  }
});

function renderDryRunPreview(summary: any) { /* render 3-card stats + details table */ }
function renderApplyResult(data: any) { /* render success banner with summary stats */ }
```

### i18n trilingue keys (~10)

- `admin.selection.importJsonTitle`
- `admin.selection.importJsonDesc`
- `admin.selection.importJsonHint`
- `admin.selection.importJsonDropZone`
- `admin.selection.importJsonDropZoneHint`
- `admin.selection.importJsonDryRunBtn`
- `admin.selection.importJsonApplyBtn`
- `admin.selection.importJsonShowDetails`
- `admin.selection.importJsonWillInsert`
- `admin.selection.importJsonWillUpdate`
- `admin.selection.importJsonWillSkip`

---

## 5. Auth + observabilidade

### canV4 gate

`manage_member` action — mesmo gate do CSV import (consistent).

### Audit log

Cada invocação (dry-run e apply) gera row em `admin_audit_log` via RPC `log_admin_action`:
- `action`: `import_pmi_vep_json_dry_run` ou `import_pmi_vep_json_apply`
- `target_type`: `selection_applications_batch`
- `metadata`: `{ applications_received, worker_status, dry_run, summary? }`

### Worker logging

Worker já tem `logRunStart`/`logRunComplete` em `cron_run_log` table (mantém).

### MCP tool (opcional, futuro)

Não no escopo desta sessão. Spec separada se PM quiser chamada via Claude direto.

---

## 6. Decisões abertas

| ID | Decisão | Default proposto |
|---|---|---|
| C-AUTH | canV4 action | `manage_member` (consistent com CSV import) |
| C-DRY-RUN | Sempre exigir dry-run antes de apply? | Sim (UI requer dry-run done para enable apply button) |
| C-MULTI-CYCLE | Quando múltiplos cycles `open`, qual pegar? | Mais novo por `open_date DESC` (atual do worker — sediment p150 #5) |
| C-PRIOR-CYCLE | Update aplica em qualquer cycle ou só `open` mais novo? | Update aplica no cycle EXISTENTE da pessoa (preserve history); skip_prior_cycle se cycle não é mais open |
| C-PAYLOAD-SIZE | Limite tamanho payload? | 5MB default (Astro/Cloudflare worker limit). Documentar |
| C-PARTIAL-APPLY | Comportamento em erro mid-batch? | Continuar processando (atual do worker) + retornar errors[] |

---

## 7. Migrações esperadas

**Zero migrações de schema.** Reusa estrutura existente (`selection_applications`, `vep_opportunities`, `pmi_chapter_memberships`, etc.) e RPCs do worker.

**Mudanças:**
- Worker `pmi-vep-sync/src/index.ts`: ~50L (dry-run support)
- Astro endpoint novo: `src/pages/api/admin/import-pmi-vep-json.ts` (~70L)
- Frontend selection.astro: ~80L (novo card + JS handlers + schema validator)
- i18n 3 dicts: ~10 keys × 3 langs = 30 entries
- `astro.config.mjs` ou `wrangler.toml` da plataforma: env binding `INGEST_SHARED_SECRET` + `PMI_VEP_SYNC_URL`

**Deploy:**
- `cd cloudflare-workers/pmi-vep-sync && npx wrangler deploy` (worker)
- `npx wrangler deploy` (platform Astro)

---

## 8. Smoke plan (p151b-c após implementação)

1. **Dry-run com JSON real**: pegar JSON consolidado `/home/vitormrodovalho/Downloads/A/pmi_volunteer_full_enriched_2026-05-12.json` (171 rows). Upload via UI → dry-run preview.
2. **Expected diff**: 0 will_insert (todos 3 "novos" já existem), ~35 will_update, ~62 will_skip_prior_cycle (cycle3-2026 anterior).
3. **Apply**: clica apply → smoke `selection_applications.updated_at >= now() - 5min` para 35 rows.
4. **Audit log check**: 2 rows em `admin_audit_log` (dry-run + apply).
5. **Idempotency**: re-rodar apply imediatamente → 0 changes (todos status='applied' já).
6. **Cycle 4 actual scenario**: novo candidato fictício no JSON → will_insert detectado + welcome dispatched.

---

## 9. Cronograma (3 sessões)

| Sessão | Output | Trabalho |
|---|---|---|
| **p151b-c** (esta ou próxima) | Spec aprovada + worker dry-run patch + Astro endpoint | Worker mod (~50L) + endpoint (~70L) + i18n (10 keys × 3) |
| **p152-c** | Frontend new card + i18n + smoke | selection.astro mod (~80L) + smoke real JSON |
| **p153-c** | QA + cycle 4 scenario dry-run completo | Smoke production + audit log verify |

Total: ~3-4h código + ~1h smoke/QA.

---

## 10. Cross-refs

- Spec predecessor (B-full): `docs/specs/p150-b-full-subjective-scoring-spec.md` — PAUSED em humanos
- Worker source: `cloudflare-workers/pmi-vep-sync/src/index.ts`
- Logic canonical: `feedback_pmi_vep_ingest_logic_canonical.md` (p150 PM diretiva)
- Worker schema drift sediment: `feedback_worker_db_schema_drift_audit_pattern.md` (p131)
- Audit pattern: `feedback_admin_audit_log_columns.md` (p92)
- Sediment "INSERT silencioso": `feedback_supabase_insert_silent_400.md` (p138) — relevante para endpoint robustez
- p150 ingest histórico: `project_p150_pmi_vep_ingest_applied.md`
- Backlog origin: `project_pmi_vep_frontend_import_backlog.md` (p150)
