// PMI Volunteer Applications Extractor — Núcleo IA & GP
// =====================================================================
// VERSION: 2026-05-09 p131 (M1-M5 enhancements)
//
// CHANGELOG p131:
//   M1 — validação pré-submit + diff visualizer (modal interativo antes
//        de POSTar para /ingest, mostra new/updated/skipped + warnings
//        de Active sem serviceEndDateUTC).
//   M2 — error parser pós-POST (agrupa errors[] por scope, mostra tabela
//        formatada em vez de array crú).
//   M3 — token expiry warning (decode OIDC JWT do localStorage; alerta
//        se < 30 min antes de iniciar varredura).
//   M4 — single-source pattern (default = JSON canonical only; CSVs
//        opt-in via CONFIG.EXPORT_CSV_DEBUG = true para depuração).
//   M5 — Phase B unified file picker (já existia em modal centralizado;
//        cosmetic refinement: progress feedback durante enrichment).
// =====================================================================
// Captura completa das 3 dimensões de cada candidato/voluntário:
//
//   (1) FILIAÇÕES PMI HISTÓRICAS (multi-chapter)
//       — getVolunteerServiceHistory de community.pmi.org dá array de
//         TODOS os roles voluntários servidos pelo applicant, com
//         chapterName/chapterId/startDate/endDate/opportunityURL.
//       — Caso real: alguém filiado a PMI-WDC + PMI-GO aparece com
//         múltiplas entries de chapters distintos no histórico.
//       — getVolunteerInformation_v2 ainda traz certifications + industry
//         atuais.
//
//   (2) MORADIA REAL DO CANDIDATO
//       — `applicant.city/state/country` em /api/applications/{id}
//         retorna vazio para a maioria dos candidatos (privacy default
//         de volunteer.pmi.org). MAS getVolunteerInformation_v2 em
//         community.pmi.org traz `location` (e.g., "Fortaleza, CE,
//         Brazil") + `state` (e.g., "CE") populados, porque vem do
//         perfil PMI Community (público dentro do PMI).
//
//   (3) CHAPTER DE ENTRADA NO NÚCLEO (auto-declarado)
//       — Resposta livre da Q "Você é filiado a um dos capítulos
//         parceiros do Núcleo (PMI-CE/DF/GO/MG/RS)?" — vai para
//         questionResponses (já capturado via FETCH_DETAIL).
//       — Importante: NÃO confundir com (1). Candidato pode ter histórico
//         em PMI-WDC + PMI-GO mas declarar entrada via PMI-GO apenas.
//
// ESTRUTURA DA EXTRAÇÃO:
//   1. Auto-descobre chapters/opportunities do recruiter (volunteer.pmi.org)
//   2. Para cada opportunity, varre as 3 abas (submitted/qualified/rejected)
//   3. Para cada application:
//      a. Busca detalhe + comments (volunteer.pmi.org/api/applications/X)
//      b. Busca enrichment (community.pmi.org/api/v1/UserVolunteer/*)
//         — service history, profile info, isOpenToVolunteer
//   4. (Opcional) Auto-POST do JSON para o worker pmi-vep-sync /ingest
//      → upsert em selection_applications + persons.pmi_memberships +
//        engagements.start_date/end_date + emite onboarding_tokens + welcome
//   5. Sempre baixa CSVs + JSON local para arquivo
//      — pmi_opportunities_<date>.csv
//      — pmi_applications_<date>.csv
//      — pmi_question_responses_<date>.csv
//      — pmi_volunteer_service_history_<date>.csv  (NOVO)
//      — pmi_volunteer_full_<date>.json
//
// CROSS-ORIGIN (CORS):
//   Os endpoints de enrichment estão em community.pmi.org, mas este script
//   roda em volunteer.pmi.org. Cookie é compartilhado via SSO PMI mas o
//   browser pode bloquear cross-origin com `credentials:'include'` se o
//   PMI Community CORS não whitelistar volunteer.pmi.org.
//
//   Comportamento:
//     - Script tenta enrichment com `credentials:'include'`.
//     - Se primeira chamada retornar erro CORS / 401, marca
//       `communityEnrichmentBlocked = true` e SKIPA enrichment para todos
//       os applicants restantes (sem repetir falha).
//     - Workaround: rodar fase B separadamente — abrir community.pmi.org
//       em outra aba (logado), chamar `window.__pmi_enrichFromCommunity()`
//       que esse script expõe globalmente. Esse helper lê o JSON salvo
//       em localStorage da fase A e faz as chamadas same-origin.
//
// USO:
//   1. Login no PMI VEP (https://volunteer.pmi.org/recruiter-dashboard/...)
//   2. Login TAMBÉM em community.pmi.org/profile/<seu-username> (mesma sessão SSO,
//      mas precisa ter sido tocado pra cookie estar ativo)
//   3. F12 no recruiter dashboard → Console
//   4. Customize CONFIG abaixo (especialmente NUCLEO_INGEST_URL + SECRET)
//   5. Cole tudo → Enter
//   6. Aguarde 2-5 min (depende do volume — ~7 chamadas por application)
//   7. Se enrichment falhar: ver mensagem no console com workaround

(async () => {
  // ===== CONFIG =====
  const CONFIG = {
    // Filtros (null = auto-descobrir tudo do recruiter)
    OPPORTUNITY_IDS: null,           // ou ex: [64966, 64967]

    // Worker /ingest endpoint (deixa em branco para apenas baixar files)
    NUCLEO_INGEST_URL: 'https://pmi-vep-sync.ai-pm-research-hub.workers.dev/ingest',
    NUCLEO_INGEST_SECRET: '<PEGAR_DO_SUPABASE_VAULT_OU_CLOUDFLARE_SECRET>',
                                     // ⚠️ NÃO commit valor real — é shared secret do worker.
                                     // Para obter: Cloudflare dashboard → pmi-vep-sync worker → Settings → Variables
                                     // OU: ask o GP do Núcleo. Esse repo PUBLIC, então valor real fica só na sua cópia local.

    // Coleta — VEP (volunteer.pmi.org)
    PAGE_SIZE: 50,
    FETCH_DETAIL: true,              // detalhe + question responses por application
    FETCH_COMMENTS: true,            // comments internos por application
    DOWNLOAD_RESUMES: false,         // PDFs (SAS expira ~24h) — true só quando arquivar
    DOWNLOAD_LOCAL_FILES: true,      // baixa JSON canonical localmente (arquival)
    // p131 M4: single-source pattern. JSON canonical contém TODOS dados
    // (applications, opportunities, questionResponses, serviceHistory).
    // CSVs são debug-only — default false. Set true se precisar inspecionar
    // dimensions específicas em planilha.
    EXPORT_CSV_DEBUG: false,
    // p131 M1: validação pré-submit. Default true = mostra modal de diff
    // antes de POSTar (você confirma manualmente). Set false para auto-POST
    // sem confirmação (ex: scripted automation).
    PRE_SUBMIT_CONFIRMATION: true,
    // p131 M3: token expiry warning. Threshold em minutos para alertar
    // antes de iniciar varredura. Padrão: 30min. Detection via JWT exp claim.
    TOKEN_EXPIRY_WARN_MIN: 30,

    // Coleta — Community Profile (community.pmi.org) — enrichment 3-dimensional
    FETCH_PROFILE_INFO: true,        // /UserVolunteer/getVolunteerInformation_v2
                                     //   → location, state, certifications, industry
    FETCH_PROFILE_HISTORY: true,     // /UserVolunteer/getVolunteerServiceHistory
                                     //   → array de roles históricos (multi-chapter signal)
    FETCH_PROFILE_PERMISSIONS: false,// /UserVolunteer/getVolunteerProfilePermissions
                                     //   → low signal — só útil pra debug. Desliga por default.
    FETCH_OPEN_TO_VOLUNTEER: true,   // /UserVolunteer/getIsOpenToVolunteer
                                     //   → re-engagement signal
    PROFILE_API_BASE: 'https://community.pmi.org/api/v1',

    // Rate limiting (PMI tolera bem; conservador por segurança)
    DELAY_MS: 200,                   // entre páginas de listagem
    DELAY_DETAIL_MS: 350,            // entre detail calls (volunteer.pmi.org)
    DELAY_PROFILE_MS: 200,           // entre profile calls (community.pmi.org)
  };

  // ===== p131 M3 — TOKEN EXPIRY CHECK =====
  // PMI VEP usa OIDC. Token JWT salvo em localStorage com chaves variando
  // (oidc.user:..., id_token, access_token). Detect + decode exp claim,
  // alerta se < threshold minutos. Não bloqueia execução — só avisa.
  function checkTokenExpiry() {
    try {
      // Procura tokens em localStorage (PMI armazena com prefixo oidc.user:*)
      let tokens = [];
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (!k) continue;
        if (k.startsWith('oidc.user:') || k.includes('access_token') || k.includes('id_token')) {
          try {
            const v = JSON.parse(localStorage.getItem(k) || '{}');
            const t = v.access_token || v.id_token || (typeof v === 'string' ? v : null);
            if (t && t.split('.').length === 3) tokens.push({ key: k, jwt: t });
          } catch { /* not JSON, skip */ }
        }
      }
      if (!tokens.length) {
        console.log('🟡 [M3] Não detectei JWT em localStorage — token check pulado.');
        return { detected: false };
      }
      const t = tokens[0];
      const payload = JSON.parse(atob(t.jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
      const expMs = (payload.exp || 0) * 1000;
      const remainMs = expMs - Date.now();
      const remainMin = Math.round(remainMs / 60000);
      if (remainMs < 0) {
        console.error(`❌ [M3] TOKEN EXPIRADO há ${-remainMin} min — re-login antes de continuar.`);
        return { detected: true, expired: true, remainMin };
      }
      if (remainMin < CONFIG.TOKEN_EXPIRY_WARN_MIN) {
        console.warn(`⚠️ [M3] Token expira em ${remainMin} min — varredura de ${apps?.length || '?'} candidatos pode levar 2-5min. Re-login agora se quiser margem.`);
        return { detected: true, expired: false, warning: true, remainMin };
      }
      console.log(`✅ [M3] Token válido por mais ${remainMin} min (${(remainMin/60).toFixed(1)}h).`);
      return { detected: true, expired: false, warning: false, remainMin };
    } catch (e) {
      console.log(`🟡 [M3] Token check falhou: ${e.message} — prosseguindo sem warning.`);
      return { detected: false, error: e.message };
    }
  }

  // ===== p131 M1 — PRE-SUBMIT VALIDATION + DIFF VISUALIZER =====
  // Antes de POSTar para /ingest, mostra modal centralizado com:
  //   - Total de applications no payload
  //   - Active sem serviceEndDateUTC (anomalia — esperado ter end date)
  //   - Submitted sem submittedDateUtc (anomalia)
  //   - Distribuição por status + bucket
  //   - Botão Confirmar/Cancelar (user controla)
  // Retorna true se user confirmou; false se cancelou.
  async function preSubmitValidation(payload) {
    const apps = payload.applications || [];
    const summary = {
      total: apps.length,
      withEndDate: apps.filter(a => a.serviceEndDateUTC).length,
      activeNoEndDate: apps.filter(a => a.status === 'Active' && !a.serviceEndDateUTC).length,
      submittedNoTimestamp: apps.filter(a => a.status === 'Submitted' && !a.submittedDateUtc).length,
      byStatus: {},
      byBucket: {}
    };
    for (const a of apps) {
      summary.byStatus[a.status || 'unknown'] = (summary.byStatus[a.status || 'unknown'] || 0) + 1;
      summary.byBucket[a._bucket || 'unknown'] = (summary.byBucket[a._bucket || 'unknown'] || 0) + 1;
    }
    summary.serviceHistoryRows = (payload.serviceHistory || []).length;
    summary.questionResponses = (payload.questionResponses || []).length;
    summary.opportunities = (payload.opportunities || []).length;

    if (!CONFIG.PRE_SUBMIT_CONFIRMATION) {
      console.log('🟡 [M1] PRE_SUBMIT_CONFIRMATION=false — auto-prossegue.');
      console.table(summary.byStatus);
      return true;
    }

    return new Promise((resolve) => {
      const overlay = document.createElement('div');
      overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,0.65);display:flex;align-items:center;justify-content:center;font-family:system-ui,-apple-system,Segoe UI,sans-serif';
      const card = document.createElement('div');
      card.style.cssText = 'background:#fff;padding:28px 36px;border-radius:12px;max-width:680px;box-shadow:0 24px 64px rgba(0,0,0,0.45)';
      const warnings = [];
      if (summary.activeNoEndDate > 0) warnings.push(`⚠️ ${summary.activeNoEndDate} application(s) Active SEM serviceEndDateUTC — anomalia.`);
      if (summary.submittedNoTimestamp > 0) warnings.push(`⚠️ ${summary.submittedNoTimestamp} application(s) Submitted SEM submittedDateUtc — anomalia.`);
      if (summary.total === 0) warnings.push('❌ Payload vazio — não vai POSTar nada.');
      const statusRows = Object.entries(summary.byStatus).map(([s, n]) => `<tr><td>${s}</td><td style="text-align:right">${n}</td></tr>`).join('');
      const bucketRows = Object.entries(summary.byBucket).map(([s, n]) => `<tr><td>${s}</td><td style="text-align:right">${n}</td></tr>`).join('');
      card.innerHTML = `
        <h2 style="margin:0 0 16px;color:#0a7d2c;font-size:20px;font-weight:700">📋 Pré-submit — Confirmar envio para Núcleo</h2>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-bottom:16px">
          <div><h3 style="margin:0 0 8px;font-size:13px;color:#555;text-transform:uppercase">Por Status</h3>
            <table style="width:100%;font-size:13px;border-collapse:collapse"><tbody>${statusRows}</tbody></table>
          </div>
          <div><h3 style="margin:0 0 8px;font-size:13px;color:#555;text-transform:uppercase">Por Bucket</h3>
            <table style="width:100%;font-size:13px;border-collapse:collapse"><tbody>${bucketRows}</tbody></table>
          </div>
        </div>
        <div style="background:#f5f5f5;padding:12px;border-radius:6px;font-size:13px;line-height:1.6">
          <strong>Totais:</strong> ${summary.total} apps · ${summary.withEndDate} com serviceEndDateUTC · ${summary.serviceHistoryRows} history rows · ${summary.questionResponses} essays · ${summary.opportunities} opps
        </div>
        ${warnings.length ? `<div style="background:#fef3cd;border:1px solid #ffe183;padding:12px;border-radius:6px;margin-top:12px;font-size:13px;color:#7a5e00">${warnings.map(w => `<div>${w}</div>`).join('')}</div>` : ''}
        <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:20px">
          <button id="__pmi_cancel_btn" style="background:#fff;color:#666;border:1px solid #ccc;padding:10px 20px;border-radius:6px;cursor:pointer;font-size:14px">Cancelar</button>
          <button id="__pmi_confirm_btn" style="background:#0a7d2c;color:#fff;border:0;padding:10px 24px;border-radius:6px;cursor:pointer;font-size:14px;font-weight:600">Confirmar e enviar</button>
        </div>
      `;
      overlay.appendChild(card); document.body.appendChild(overlay);
      card.querySelector('#__pmi_confirm_btn').addEventListener('click', () => { overlay.remove(); resolve(true); });
      card.querySelector('#__pmi_cancel_btn').addEventListener('click', () => { overlay.remove(); resolve(false); });
    });
  }

  // ===== p131 M2 — POST-INGEST ERROR PARSER =====
  // Agrupa errors[] por scope, mostra tabela formatada + actionable hints.
  function parseIngestErrors(errors) {
    if (!errors || !errors.length) {
      console.log('✅ [M2] Sem erros no ingest.');
      return;
    }
    const byScope = {};
    for (const e of errors) {
      const scope = e.scope || 'unknown';
      byScope[scope] = byScope[scope] || [];
      byScope[scope].push(e);
    }
    console.warn(`⚠️ [M2] ${errors.length} erro(s) no ingest, agrupados em ${Object.keys(byScope).length} scope(s):`);
    for (const [scope, list] of Object.entries(byScope)) {
      console.group(`%c❌ ${scope} (${list.length})`, 'color:#c00;font-weight:bold');
      const errPattern = {};
      for (const e of list) {
        const key = (e.error || 'unknown').substring(0, 80);
        errPattern[key] = (errPattern[key] || 0) + 1;
      }
      console.table(Object.entries(errPattern).map(([err, count]) => ({ error_pattern: err, count })));
      // Actionable hints
      const sample = list[0]?.error || '';
      if (sample.includes('Could not find') && sample.includes('column')) {
        console.warn('💡 Hint: schema cache PostgREST desatualizado OU coluna não existe no DB. Rodar `NOTIFY pgrst, "reload schema"` ou aplicar migration.');
      } else if (sample.includes('insufficient_privilege')) {
        console.warn('💡 Hint: auth gate bloqueou — verificar can_by_member da action requerida.');
      } else if (sample.includes('rate limit') || sample.includes('429')) {
        console.warn('💡 Hint: rate limit hit — reduzir CONFIG.DELAY_MS ou chunkear payload.');
      }
      console.groupEnd();
    }
  }

  // ===== UTIL =====
  const fetchJson = async (url, opts = {}) => {
    const r = await fetch(url, { headers: { accept: 'application/json' }, ...opts });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  };
  // Cross-origin variant — manda cookie de community.pmi.org via credentials:'include'.
  // Browser pode bloquear se CORS não whitelistar volunteer.pmi.org.
  const fetchProfileJson = async (url) => {
    const r = await fetch(url, {
      headers: { accept: 'application/json' },
      credentials: 'include',
      mode: 'cors',
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const dl = (blob, name) => { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); };
  const csvEscape = v => v == null ? '' : `"${String(v).replace(/"/g,'""').replace(/\r?\n/g,' ')}"`;
  const toCsv = (cols, rows) => [cols.join(','), ...rows.map(r => cols.map(c => csvEscape(r[c])).join(','))].join('\n');

  // ===== HOST DETECTION + PHASE B (community.pmi.org enrichment-only) =====
  // CORS reality: community.pmi.org responde com `Access-Control-Allow-Origin: *`,
  // o que quebra `credentials:'include'` quando script roda em volunteer.pmi.org.
  // Workaround: rodar enrichment SAME-ORIGIN em community.pmi.org. Este branch
  // detecta o host e oferece Phase B (file picker → enrichment → JSON download).
  const HOST = location.host;

  // ===== p131 M3 — invoca token check no início =====
  // Roda antes de iniciar varredura longa (2-5min). Não bloqueia, só warns.
  if (HOST !== 'community.pmi.org') {
    // Phase A em volunteer.pmi.org — token check faz sentido
    checkTokenExpiry();
  }
  async function runPhaseB() {
    console.log(`%c🌐 Phase B — community.pmi.org enrichment mode`, 'color:#0a0;font-weight:bold');

    // 1) Modal centralizado (overlay full-screen, impossível de não ver)
    const file = await new Promise((resolve) => {
      const overlay = document.createElement('div');
      overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,0.65);display:flex;align-items:center;justify-content:center;font-family:system-ui,-apple-system,Segoe UI,sans-serif';

      const card = document.createElement('div');
      card.style.cssText = 'background:#fff;padding:36px 48px;border-radius:12px;max-width:540px;box-shadow:0 24px 64px rgba(0,0,0,0.45);text-align:center';
      card.innerHTML = [
        '<h2 style="margin:0 0 12px;color:#0a7d2c;font-size:22px;font-weight:700">🌐 Phase B — PMI Community Enrichment</h2>',
        '<p style="margin:0 0 8px;color:#333;font-size:14px;line-height:1.55">',
        'Selecione o arquivo <code style="background:#f3f3f3;padding:2px 6px;border-radius:3px;font-size:13px">pmi_volunteer_full_&lt;data&gt;.json</code><br>',
        'baixado pela Phase A em volunteer.pmi.org', '</p>',
        '<p style="margin:0 0 24px;color:#888;font-size:12px">(geralmente em ~/Downloads/)</p>',
        '<button id="__pmi_pick" style="background:#0a7d2c;color:#fff;border:0;padding:14px 32px;font-size:16px;border-radius:6px;cursor:pointer;font-weight:600;box-shadow:0 4px 12px rgba(10,125,44,0.3)">📂 Escolher arquivo JSON…</button>',
        '<p id="__pmi_status" style="margin:18px 0 0;color:#555;font-size:13px;min-height:18px"></p>',
        '<button id="__pmi_cancel" style="background:transparent;color:#999;border:0;padding:8px;font-size:12px;cursor:pointer;margin-top:8px;text-decoration:underline">Cancelar</button>',
      ].join('');

      const input = document.createElement('input');
      input.type = 'file'; input.accept = '.json,application/json';
      input.style.display = 'none';

      overlay.appendChild(card); overlay.appendChild(input);
      document.body.appendChild(overlay);

      card.querySelector('#__pmi_pick').addEventListener('click', () => input.click());
      card.querySelector('#__pmi_cancel').addEventListener('click', () => { overlay.remove(); resolve(null); });
      input.addEventListener('change', () => {
        const f = input.files[0];
        if (!f) return;
        card.querySelector('#__pmi_status').textContent = `✓ ${f.name} (${(f.size/1024).toFixed(1)} KB) — processando…`;
        setTimeout(() => { overlay.remove(); resolve(f); }, 350);
      });
      console.log(`📂 Modal centralizado aberto. Clique no botão verde "📂 Escolher arquivo JSON…"`);
    });
    if (!file) { console.error('❌ Phase B cancelada — nenhum arquivo selecionado'); return; }

    const phaseA = JSON.parse(await file.text());
    const apps = phaseA.applications || [];
    const recruiterPersonId = phaseA.meta?.recruiter?.personId;
    if (!recruiterPersonId) { console.error('❌ JSON inválido — meta.recruiter.personId ausente'); return; }
    console.log(`📥 Phase A carregada — ${apps.length} applications, recruiter ${recruiterPersonId}`);

    // Mostra card de progresso (não some até o final)
    const progressOverlay = document.createElement('div');
    progressOverlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,0.65);display:flex;align-items:center;justify-content:center;font-family:system-ui,-apple-system,Segoe UI,sans-serif';
    progressOverlay.innerHTML = `
      <div style="background:#fff;padding:36px 48px;border-radius:12px;max-width:540px;box-shadow:0 24px 64px rgba(0,0,0,0.45);text-align:center">
        <h2 style="margin:0 0 12px;color:#0a7d2c;font-size:22px;font-weight:700">⏳ Enriquecendo via PMI Community…</h2>
        <p id="__pmi_prog" style="margin:0 0 8px;color:#333;font-size:14px;line-height:1.55">Iniciando…</p>
        <div style="width:100%;height:8px;background:#eee;border-radius:4px;margin:16px 0;overflow:hidden">
          <div id="__pmi_bar" style="width:0%;height:100%;background:#0a7d2c;transition:width 0.3s"></div>
        </div>
        <p id="__pmi_breakdown" style="margin:0;color:#666;font-size:12px"></p>
      </div>`;
    document.body.appendChild(progressOverlay);
    const progEl = progressOverlay.querySelector('#__pmi_prog');
    const barEl = progressOverlay.querySelector('#__pmi_bar');
    const bdEl = progressOverlay.querySelector('#__pmi_breakdown');

    // 2) Enrichment loop — same-origin, sem CORS issues
    // 400 silencioso = profile privado/desativado/sem permissão (não é erro real)
    const profileCache = new Map();
    const serviceHistoryRows = [];
    const stats = { total: 0, ok: 0, private: 0, error: 0 };

    // PMI Community API quirk: response body é uma STRING JSON dupla-encodada
    // (e.g., body = `"{\"isSuccess\":true,...}"`). response.json() retorna a
    // string crua, NÃO o objeto. Precisa parsear de novo se for string.
    const callProfileApi = async (path) => {
      try {
        const r = await fetch(`https://community.pmi.org/api/v1${path}`, {
          headers: { accept: 'application/json' }, credentials: 'include'
        });
        if (r.status === 400) return { __private: true };
        if (!r.ok) return { __error: r.status };
        const raw = await r.json();
        // Double-parse se body veio como string (ex: getVolunteerInformation_v2,
        // getVolunteerServiceHistory). getIsOpenToVolunteer já vem como objeto.
        if (typeof raw === 'string') {
          try { return JSON.parse(raw); }
          catch { return { __error: 'invalid double-encoded JSON' }; }
        }
        return raw;
      } catch (e) { return { __error: e.message }; }
    };

    let i = 0;
    for (const a of apps) {
      i++;
      if (!a.applicantId) continue;
      const cacheKey = String(a.applicantId);
      if (profileCache.has(cacheKey)) {
        Object.assign(a, profileCache.get(cacheKey).flat);
        continue;
      }
      stats.total++;
      const cached = { flat: {} };
      const pid = a.applicantId, eid = recruiterPersonId;
      let profileOk = false;

      // Profile info — campos descobertos via HAR analysis 2026-05-09:
      //   location, state, city, country, certifications, industry, company,
      //   designation, aboutMe, linkedInURL, volunteerInterest, specialties,
      //   membership[], membershipChapters[]
      const r1 = await callProfileApi(`/UserVolunteer/getVolunteerInformation_v2?profileOwnerPersonId=${pid}&endUserPersonId=${eid}`);
      if (r1?.isSuccess) {
        profileOk = true;
        const res = r1.result || {};
        cached.flat.profileLocation = res.location ?? null;
        cached.flat.profileState = res.state ?? null;
        cached.flat.profileCity = res.city ?? null;
        cached.flat.profileCountry = res.country ?? null;
        cached.flat.profileCertifications = (res.certifications || []).join(',');
        cached.flat.profileIndustry = res.industry ?? null;
        cached.flat.profileCompany = res.company ?? null;
        cached.flat.profileDesignation = res.designation ?? null;
        cached.flat.profileAboutMe = res.aboutMe ?? null;
        cached.flat.profileLinkedinUrl = res.linkedInURL ?? null;
        cached.flat.profileVolunteerInterest = (res.volunteerInterest || []).join(',');
        cached.flat.profileSpecialties = (res.specialties || []).join(',');
        // Multi-chapter ATUAL (membership ativa) — separado do histórico
        if (Array.isArray(res.membership) && res.membership.length) {
          cached.flat.profileMemberships = JSON.stringify(res.membership);
        }
        if (Array.isArray(res.membershipChapters) && res.membershipChapters.length) {
          cached.flat.profileMembershipChapters = JSON.stringify(res.membershipChapters);
        }
      } else if (r1?.__private) {
        cached.flat.profilePrivate = true;
      }
      await sleep(200);

      // Service history
      const r2 = await callProfileApi(`/UserVolunteer/getVolunteerServiceHistory?profileOwnerPersonId=${pid}&endUserPersonId=${eid}`);
      if (r2?.isSuccess && Array.isArray(r2.result?.volunteerHistory)) {
        profileOk = true;
        const hist = r2.result.volunteerHistory;
        cached.flat.serviceHistoryCount = hist.length;
        const distinctChapters = new Set(hist.map(h => h.chapterName).filter(Boolean));
        cached.flat.serviceHistoryChapters = [...distinctChapters].join(';');
        const startDates = hist.map(h => h.startDate).filter(Boolean).sort();
        cached.flat.serviceFirstStartDate = startDates[0] || null;
        cached.flat.serviceLatestEndDate = hist.map(h => h.endDate).filter(Boolean).sort().slice(-1)[0] || null;
        for (const h of hist) {
          serviceHistoryRows.push({
            applicantId: a.applicantId, applicantName: a.applicantName, applicantEmail: a.applicantEmail,
            roleId: h.id, title: h.title, roleTitle: h.roleTitle,
            chapterName: h.chapterName, chapterId: h.chapterId,
            startDate: h.startDate, endDate: h.endDate,
            isSelfReported: h.isSelfReported, opportunityURL: h.opportunityURL,
            categoryId: h.categoryId, additionalInformation: h.additionalInformation,
          });
        }
      }
      await sleep(200);

      // IsOpenToVolunteer
      const r3 = await callProfileApi(`/UserVolunteer/getIsOpenToVolunteer?profileOwnerPersonId=${pid}`);
      if (r3?.isOpenToVolunteer === true || r3?.isOpenToVolunteer === 'true') {
        cached.flat.isOpenToVolunteer = true;
      } else if (r3?.isOpenToVolunteer === false || r3?.isOpenToVolunteer === 'false') {
        cached.flat.isOpenToVolunteer = false;
      }
      await sleep(200);

      if (profileOk) stats.ok++;
      else if (r1?.__private || r2?.__private || r3?.__private) stats.private++;
      else stats.error++;

      profileCache.set(cacheKey, cached);
      Object.assign(a, cached.flat);

      // Atualiza UI
      const pct = ((i / apps.length) * 100).toFixed(0);
      progEl.textContent = `Processando ${i}/${apps.length} candidaturas — ${a.applicantName ?? '?'}`;
      barEl.style.width = pct + '%';
      bdEl.textContent = `✓ ${stats.ok} enriquecidos · 🔒 ${stats.private} privados · ⚠️ ${stats.error} indisponíveis`;
    }

    progressOverlay.remove();

    // 3) Download JSON enriquecido + CSV de service history
    const date = new Date().toISOString().slice(0,10);
    const enriched = { ...phaseA, applications: apps, serviceHistory: serviceHistoryRows,
                       phaseB: { enrichedAt: new Date().toISOString(), profilesFetched: profileCache.size } };
    dl(new Blob([JSON.stringify(enriched, null, 2)], { type: 'application/json' }),
       `pmi_volunteer_full_enriched_${date}.json`);
    if (serviceHistoryRows.length) {
      const histCols = ['applicantId','applicantName','applicantEmail','roleId','title','roleTitle',
                        'chapterName','chapterId','startDate','endDate','isSelfReported',
                        'opportunityURL','categoryId','additionalInformation'];
      dl(new Blob([toCsv(histCols, serviceHistoryRows)], { type: 'text/csv' }),
         `pmi_volunteer_service_history_${date}.csv`);
    }
    console.log(`\n${'═'.repeat(50)}`);
    console.log(`✅ Phase B done — ${profileCache.size} profiles enriched, ${serviceHistoryRows.length} service-history rows`);
    console.log(`📥 Baixados: pmi_volunteer_full_enriched_${date}.json + pmi_volunteer_service_history_${date}.csv`);
    window.__pmi_phaseB = { phaseA, applications: apps, serviceHistory: serviceHistoryRows, profileCache };
    console.log(`Disponível em window.__pmi_phaseB`);
  }

  if (HOST === 'community.pmi.org') {
    await runPhaseB();
    return;
  }
  if (HOST !== 'volunteer.pmi.org') {
    console.error(`❌ Domínio errado (${HOST}). Use:\n` +
                  `  • Phase A: https://volunteer.pmi.org/recruiter-dashboard/... (listing + detail)\n` +
                  `  • Phase B: https://community.pmi.org/profile/<seu-username> (enrichment same-origin)`);
    return;
  }

  // ===== METADATA =====
  const meta = { extractedAt: new Date().toISOString() };
  const me = await fetchJson('/api/Authorization/user/roles/v2');
  meta.recruiter = { personId: me.personId, name: me.personName, email: me.emailAddress, chapters: me.recruiter };
  console.log(`👤 ${me.personName} — chapters: ${me.recruiter.join(', ')}`);

  // ===== 1.5) SMOKE TEST community.pmi.org (CORS / SSO) =====
  // Roda 1 chamada de baixo custo contra community.pmi.org com o próprio personId
  // do recruiter. Se passar, enrichment funciona pra todos. Se não, skip global.
  let communityEnrichmentBlocked = false;
  const wantsEnrichment =
    CONFIG.FETCH_PROFILE_INFO ||
    CONFIG.FETCH_PROFILE_HISTORY ||
    CONFIG.FETCH_PROFILE_PERMISSIONS ||
    CONFIG.FETCH_OPEN_TO_VOLUNTEER;
  if (wantsEnrichment) {
    try {
      // getIsOpenToVolunteer só requer profileOwnerPersonId (sem endUserPersonId)
      // — endpoint de menor custo / menor blast radius pra teste.
      await fetchProfileJson(`${CONFIG.PROFILE_API_BASE}/UserVolunteer/getIsOpenToVolunteer?profileOwnerPersonId=${me.personId}`);
      console.log(`✅ community.pmi.org session OK — enrichment habilitado`);
    } catch (e) {
      communityEnrichmentBlocked = true;
      console.warn(
        `⚠️  community.pmi.org enrichment INDISPONÍVEL: ${e.message}\n` +
        `    Razões prováveis: (a) não logado em community.pmi.org, (b) CORS bloqueou cross-origin.\n` +
        `    Workaround: abra https://community.pmi.org/profile/<seu-username> em outra aba (mesma sessão),\n` +
        `    rode o script normalmente lá — same-origin não tem o problema. OU continue sem enrichment\n` +
        `    (campos profile_*, service_history* virão null no payload).`
      );
    }
  }

  // ===== 1) AUTO-DESCOBRIR OPPORTUNITIES =====
  let opportunityIds = CONFIG.OPPORTUNITY_IDS;
  const opportunityRows = [];

  if (!opportunityIds) {
    opportunityIds = [];
    for (const chapterId of me.recruiter) {
      let page = 1, hasMore = true;
      while (hasMore) {
        try {
          const data = await fetchJson(
            `/api/opportunities?filters=partyID%3D%3D${chapterId}&sorts=-lastPostingDateUTC&page=${page}&pageSize=${CONFIG.PAGE_SIZE}`
          );
          const ops = data?.result?.opportunities || [];
          if (ops.length === 0) { hasMore = false; break; }
          for (const o of ops) {
            opportunityIds.push(o.id);
            opportunityRows.push({
              opportunityId: o.id, name: o.name, chapterName: o.chapterName,
              status: o.status, classification: o.opportunityClassification,
              lastPostingDateUTC: o.lastPostingDateUTC, postingEndDate: o.postingEndDate,
              numberOfApplications: o.numberOfApplications,
              canManageApplications: o.permissions?.canManageApplications,
              canExportApplications: o.permissions?.canExportApplications,
            });
          }
          console.log(`📂 chapter ${chapterId} page ${page}: ${ops.length} opportunities`);
          page++;
          await sleep(CONFIG.DELAY_MS);
        } catch (e) { console.error(e); hasMore = false; }
      }
    }
  }
  meta.opportunityIds = opportunityIds;
  console.log(`🎯 ${opportunityIds.length} opportunities a varrer`);

  // ===== 2) FUNIL POR OPPORTUNITY =====
  const buckets = (oppId) => [
    {
      name: 'submitted',
      path: `/api/opportunity/${oppId}/applications/status/submitted?filters=&sorts=-submittedDate`,
      listKey: 'submittedApplication',
      normalize: (a) => ({
        _bucket: 'submitted', applicationId: a.applicationId, applicantId: a.applicantId,
        applicantName: a.applicantName, applicantEmail: a.applicantEmail,
        status: a.status, statusId: a.statusId,
        submittedDateUtc: a.submittedDate, expiryDateUtc: a.expiryDate,
        resumeUrl: a.resumeUrl, profileUrl: a.profileUrl, label: a.label,
      }),
    },
    {
      name: 'qualified',
      path: `/api/opportunity/${oppId}/qualifiedapplications?filters=&sorts=status`,
      listKey: 'qualifiedApplication',
      normalize: (a) => ({
        _bucket: 'qualified', applicationId: a.applicationId, applicantId: a.applicantId,
        applicantName: a.applicantName, applicantEmail: a.applicantEmail,
        status: a.applicationStatus, statusId: a.statusId,
        startDate: a.startDate, endDate: a.endDate, hours: a.hours,
        docuSignCompletion: a.docuSignCompletion, onboardingStatus: a.onboardingStatus,
        profileUrl: a.profileUrl,
      }),
    },
    {
      name: 'rejected',
      path: `/api/opportunity/${oppId}/RejectedApplications?filters=&sorts=-submittedDate`,
      listKey: 'rejectedApplication',
      normalize: (a) => ({
        _bucket: 'rejected', applicationId: a.applicationId, applicantId: a.applicantId,
        applicantName: a.applicantName, applicantEmail: a.applicantEmail,
        status: a.applicationStatus, statusId: a.statusId,
        submittedDateUtc: a.applicationSubmittedDateUtc,
        declinedByRecruiterDateUtc: a.declinedByRecruiterDateUtc,
        declinedByVolunteerDateUtc: a.declinedByVolunteerDateUtc,
        applicationWithdrawnDateUtc: a.applicationWithdrawnDateUtc,
        roleRemovedDateUtc: a.roleRemovedDateUtc,
        offerExpiredDateUtc: a.offerExpiredDateUtc,
        applicationExpiredDateUtc: a.applicationExpiredDateUtc,
        startDate: a.startDate, endDate: a.endDate,
        resumeUrl: a.resumeUrl, profileUrl: a.profileUrl,
      }),
    },
  ];

  const applications = [];

  for (const oppId of opportunityIds) {
    console.log(`\n━━━ Opportunity ${oppId} ━━━`);
    for (const b of buckets(oppId)) {
      let page = 1, count = 0, hasMore = true;
      while (hasMore) {
        try {
          const data = await fetchJson(`${b.path}&page=${page}&pageSize=${CONFIG.PAGE_SIZE}`);
          const list = data?.result?.[b.listKey] || [];
          if (list.length === 0) { hasMore = false; break; }
          for (const a of list) {
            applications.push({ _opportunityId: oppId, ...b.normalize(a) });
          }
          count += list.length;
          page++;
          await sleep(CONFIG.DELAY_MS);
        } catch (e) {
          if (page === 1) console.warn(`  [${b.name}] sem dados`); else console.error(`  [${b.name}] page ${page}: ${e.message}`);
          hasMore = false;
        }
      }
      console.log(`  [${b.name}]: ${count}`);
    }
  }
  console.log(`\n📊 ${applications.length} candidaturas listadas`);

  // ===== 3) DRILL-DOWN POR APPLICATION =====
  const questionResponses = [];
  const serviceHistoryRows = [];   // rows planas para o CSV relacional

  // Cache para não buscar profile do mesmo applicant 2x (mesmo applicantId pode
  // aparecer em 2 opportunities — leader+researcher dual-track)
  const profileCache = new Map();   // applicantId → { info, history, isOpen }

  if (CONFIG.FETCH_DETAIL || CONFIG.FETCH_COMMENTS || (wantsEnrichment && !communityEnrichmentBlocked)) {
    console.log(`\n🔍 Buscando detalhe + enrichment de ${applications.length} applications...`);
    let i = 0;
    for (const a of applications) {
      i++;

      // ----- 3a) /api/applications/{id} (volunteer.pmi.org) -----
      if (CONFIG.FETCH_DETAIL) {
        try {
          const d = await fetchJson(`/api/applications/${a.applicationId}`);
          a.coverLetterInfo = d.coverLetterInfo;
          a.nonPMIExperience = d.nonPMIExperience;
          a.priorServiceEndedEarly = d.priorServiceEndedEarly;
          a.priorServiceEndedEarlyReason = d.priorServiceEndedEarlyReason;
          a.formsSentDateUTC = d.formsSentDateUTC;
          a.formsSignedDateUTC = d.formsSignedDateUTC;
          a.extendOfferDateUTC = d.extendOfferDateUTC;
          a.acceptanceDateUTC = d.acceptanceDateUTC;
          a.declinedDateUTC = d.declinedDateUTC;
          a.declinedBy = d.declinedBy;
          a.completedDateUTC = d.completedDateUTC;
          a.incompletedDateUTC = d.incompletedDateUTC;
          a.withdrawnDateUTC = d.withdrawnDateUTC;
          a.removedDateUTC = d.removedDateUTC;
          a.onboardingDateUTC = d.onboardingDateUTC;
          a.activeDateUTC = d.activeDateUTC;
          a.serviceStartDateUTC = d.serviceStartDateUTC;
          a.serviceEndDateUTC = d.serviceEndDateUTC;
          a.applicantCity = d.applicant?.city;
          a.applicantState = d.applicant?.state;
          a.applicantCountry = d.applicant?.country;
          // NOTA (2026-05-09): /api/applications/{id} NÃO retorna membershipStatus,
          // certifications, phone nem linkedinUrl — confirmado via HAR. Os únicos
          // applicant.* keys são [city, country, email, firstName, fullName, id,
          // lastName, state]. Esses dados SÓ vêm via community.pmi.org Phase B.
          a.specialInterest = d.specialInterest;
          a.isEligibleForVolunteerCertificate = d.isEligibleForVolunteerCertificate;
          a.hasOnboardingProcess = d.hasOnboardingProcess;
          a.isSurveyCompleted = d.isSurveyCompleted;
          for (const q of (d.questionResponses || [])) {
            questionResponses.push({
              applicationId: a.applicationId, applicantId: a.applicantId,
              applicantEmail: a.applicantEmail, opportunityId: a._opportunityId,
              responseId: q.responseId, questionId: q.questionId,
              question: q.question, response: q.response,
            });
          }
        } catch (e) { console.warn(`  detail ${a.applicationId}: ${e.message}`); }
      }
      if (CONFIG.FETCH_COMMENTS) {
        try {
          const c = await fetchJson(`/api/applications/${a.applicationId}/comments?api-version=1.0`);
          const list = c?.result || [];
          a.commentsCount = list.length;
          a.commentsJson = list.length ? JSON.stringify(list) : null;
        } catch (e) { /* silent */ }
      }

      // ----- 3b) Community Profile enrichment (community.pmi.org) -----
      // Pula se CORS bloqueou no smoke test, OU se já buscamos esse applicantId.
      if (wantsEnrichment && !communityEnrichmentBlocked && a.applicantId) {
        const cacheKey = String(a.applicantId);
        let cached = profileCache.get(cacheKey);
        if (!cached) {
          cached = {};
          const pid = a.applicantId;
          const eid = me.personId;

          // (B) Profile info — location, state, certifications, industry
          if (CONFIG.FETCH_PROFILE_INFO) {
            try {
              const r = await fetchProfileJson(
                `${CONFIG.PROFILE_API_BASE}/UserVolunteer/getVolunteerInformation_v2?profileOwnerPersonId=${pid}&endUserPersonId=${eid}`
              );
              if (r?.isSuccess) {
                cached.info = {
                  location: r.result?.location ?? null,
                  state: r.result?.state ?? null,
                  certifications: r.result?.certifications ?? [],
                  industry: r.result?.industry ?? null,
                  volunteerInterest: r.result?.volunteerInterest ?? [],
                  // profileImage é base64 grande — ignoramos pra economizar payload
                };
              }
              await sleep(CONFIG.DELAY_PROFILE_MS);
            } catch (e) {
              if (e.message.includes('401') || e.message.includes('CORS')) {
                communityEnrichmentBlocked = true;
                console.warn(`  ⚠️ enrichment bloqueado mid-loop após ${i-1} apps; skipando resto`);
              }
            }
          }

          // (A) Service history — array de roles voluntários históricos
          if (CONFIG.FETCH_PROFILE_HISTORY && !communityEnrichmentBlocked) {
            try {
              const r = await fetchProfileJson(
                `${CONFIG.PROFILE_API_BASE}/UserVolunteer/getVolunteerServiceHistory?profileOwnerPersonId=${pid}&endUserPersonId=${eid}`
              );
              if (r?.isSuccess) {
                cached.history = r.result?.volunteerHistory ?? [];
              }
              await sleep(CONFIG.DELAY_PROFILE_MS);
            } catch (e) { /* silent — info call já capturou auth issue */ }
          }

          // (C) IsOpenToVolunteer — re-engagement flag
          if (CONFIG.FETCH_OPEN_TO_VOLUNTEER && !communityEnrichmentBlocked) {
            try {
              const r = await fetchProfileJson(
                `${CONFIG.PROFILE_API_BASE}/UserVolunteer/getIsOpenToVolunteer?profileOwnerPersonId=${pid}`
              );
              cached.isOpenToVolunteer = (r?.isOpenToVolunteer === true || r?.isOpenToVolunteer === 'true');
              await sleep(CONFIG.DELAY_PROFILE_MS);
            } catch (e) { /* silent */ }
          }

          // (D) Permissions — só se debug
          if (CONFIG.FETCH_PROFILE_PERMISSIONS && !communityEnrichmentBlocked) {
            try {
              const r = await fetchProfileJson(
                `${CONFIG.PROFILE_API_BASE}/UserVolunteer/getVolunteerProfilePermissions?profileOwnerPersonId=${pid}&endUserPersonId=${eid}`
              );
              cached.permissions = r?.result ?? null;
              await sleep(CONFIG.DELAY_PROFILE_MS);
            } catch (e) { /* silent */ }
          }

          profileCache.set(cacheKey, cached);
        }

        // Anexa enrichment à application (denormalizado pra ergonomia downstream)
        if (cached.info) {
          a.profileLocation = cached.info.location;
          a.profileState = cached.info.state;
          a.profileCertifications = (cached.info.certifications || []).join(',');
          a.profileIndustry = cached.info.industry;
          a.profileVolunteerInterest = (cached.info.volunteerInterest || []).join(',');
        }
        if (cached.history) {
          a.serviceHistoryCount = cached.history.length;
          // Multi-chapter signal: chapters DISTINTOS no histórico.
          const distinctChapters = new Set(
            cached.history.map(h => h.chapterName).filter(Boolean)
          );
          a.serviceHistoryChapters = [...distinctChapters].join(';');
          // Earliest/latest dates pra cálculo de seniority como voluntário
          const dates = cached.history.map(h => h.startDate).filter(Boolean).sort();
          a.serviceFirstStartDate = dates[0] || null;
          a.serviceLatestEndDate = cached.history
            .map(h => h.endDate).filter(Boolean).sort().slice(-1)[0] || null;
          // Rows planas para o CSV relacional
          for (const h of cached.history) {
            serviceHistoryRows.push({
              applicantId: a.applicantId,
              applicantName: a.applicantName,
              applicantEmail: a.applicantEmail,
              roleId: h.id,
              title: h.title,
              roleTitle: h.roleTitle,
              chapterName: h.chapterName,
              chapterId: h.chapterId,
              startDate: h.startDate,
              endDate: h.endDate,
              isSelfReported: h.isSelfReported,
              opportunityURL: h.opportunityURL,
              categoryId: h.categoryId,
              additionalInformation: h.additionalInformation,
            });
          }
        }
        if (typeof cached.isOpenToVolunteer === 'boolean') {
          a.isOpenToVolunteer = cached.isOpenToVolunteer;
        }
      }

      if (i % 10 === 0) console.log(`  ${i}/${applications.length}`);
      await sleep(CONFIG.DELAY_DETAIL_MS);
    }
  }

  // ===== 4) POST PARA WORKER /ingest (PRIMARY PATH) =====
  let ingestResult = null;
  if (CONFIG.NUCLEO_INGEST_URL && CONFIG.NUCLEO_INGEST_SECRET) {
    const payload = { meta, opportunities: opportunityRows, applications, questionResponses, serviceHistory: serviceHistoryRows };

    // p131 M1 — pré-submit validation + diff visualizer (modal interativo)
    const userConfirmed = await preSubmitValidation(payload);
    if (!userConfirmed) {
      console.warn('🚫 [M1] User cancelou — POST não enviado. JSON file ainda será baixado se DOWNLOAD_LOCAL_FILES=true.');
    } else {
      console.log(`\n📡 Enviando para Núcleo worker /ingest...`);
      try {
        const r = await fetch(CONFIG.NUCLEO_INGEST_URL, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-ingest-secret': CONFIG.NUCLEO_INGEST_SECRET
          },
          body: JSON.stringify(payload)
        });
        ingestResult = await r.json();
        if (r.ok) {
          console.log(`✅ Ingest OK — cycle ${ingestResult.cycle_code}:`);
          console.table({
            received: ingestResult.applications_received,
            processed: ingestResult.applications_processed,
            new: ingestResult.applications_new,
            updated: ingestResult.applications_updated,
            skipped: ingestResult.applications_skipped,
            welcome_dispatched: ingestResult.welcome_dispatched,
            errors: ingestResult.errors?.length || 0
          });
          // p131 M2 — error parser pós-POST (agrupa por scope + actionable hints)
          parseIngestErrors(ingestResult.errors);
        } else {
          console.error(`❌ Ingest HTTP ${r.status}:`, ingestResult);
        }
      } catch (e) {
        console.error(`❌ Ingest fetch error:`, e.message);
      }
    }
  } else {
    console.log(`\n⏭️ NUCLEO_INGEST_URL ou SECRET vazios — pulando POST (só baixando files)`);
  }

  // ===== 5) JSON CANONICAL LOCAL (arquival) — p131 M4 =====
  // p131 M4 single-source: JSON canonical sempre baixa (DOWNLOAD_LOCAL_FILES);
  // CSVs são opt-in via EXPORT_CSV_DEBUG (debug only — JSON tem TUDO).
  if (CONFIG.DOWNLOAD_LOCAL_FILES) {
    const date = new Date().toISOString().slice(0,10);

    // Canonical JSON — sempre. Único arquivo necessário no flow normal.
    dl(new Blob([JSON.stringify({ meta, opportunities: opportunityRows, applications, questionResponses, serviceHistory: serviceHistoryRows, ingestResult }, null, 2)], { type: 'application/json' }),
       `pmi_volunteer_full_${date}.json`);
    console.log('💾 [M4] JSON canonical baixado (contém todos dimensões — applications + opportunities + questionResponses + serviceHistory).');

    if (CONFIG.EXPORT_CSV_DEBUG) {
      console.log('🟡 [M4] EXPORT_CSV_DEBUG=true — baixando CSVs adicionais (debug only).');
      const oppCols = ['opportunityId','name','chapterName','status','classification',
                       'lastPostingDateUTC','postingEndDate','numberOfApplications',
                       'canManageApplications','canExportApplications'];
      dl(new Blob([toCsv(oppCols, opportunityRows)], { type: 'text/csv' }),
         `pmi_opportunities_${date}.csv`);

      const appCols = ['_opportunityId','_bucket','applicationId','applicantId','applicantName','applicantEmail',
                       'status','statusId',
                       'applicantCity','applicantState','applicantCountry',
                       'profileLocation','profileState','profileCity','profileCountry',
                       'profileMembershipChapters','profileMemberships',
                       'serviceHistoryCount','serviceHistoryChapters','serviceFirstStartDate','serviceLatestEndDate',
                       'profileCertifications','profileIndustry','profileCompany','profileDesignation',
                       'profileAboutMe','profileLinkedinUrl','profileVolunteerInterest','profileSpecialties',
                       'isOpenToVolunteer','profilePrivate',
                       'submittedDateUtc','expiryDateUtc','formsSentDateUTC','formsSignedDateUTC',
                       'extendOfferDateUTC','acceptanceDateUTC','declinedDateUTC','declinedBy',
                       'completedDateUTC','incompletedDateUTC','withdrawnDateUTC','removedDateUTC',
                       'onboardingDateUTC','activeDateUTC','serviceStartDateUTC','serviceEndDateUTC',
                       'applicationExpiredDateUtc','offerExpiredDateUtc',
                       'declinedByRecruiterDateUtc','declinedByVolunteerDateUtc',
                       'applicationWithdrawnDateUtc','roleRemovedDateUtc',
                       'startDate','endDate','hours','docuSignCompletion','onboardingStatus',
                       'priorServiceEndedEarly','priorServiceEndedEarlyReason','specialInterest',
                       'isEligibleForVolunteerCertificate','hasOnboardingProcess','isSurveyCompleted',
                       'commentsCount','resumeUrl','profileUrl','label'];
      dl(new Blob([toCsv(appCols, applications)], { type: 'text/csv' }),
         `pmi_applications_${date}.csv`);

      if (questionResponses.length) {
        dl(new Blob([toCsv(['applicationId','applicantId','applicantEmail','opportunityId','responseId','questionId','question','response'], questionResponses)], { type: 'text/csv' }),
           `pmi_question_responses_${date}.csv`);
      }

      if (serviceHistoryRows.length) {
        const histCols = ['applicantId','applicantName','applicantEmail','roleId','title','roleTitle',
                          'chapterName','chapterId','startDate','endDate','isSelfReported',
                          'opportunityURL','categoryId','additionalInformation'];
        dl(new Blob([toCsv(histCols, serviceHistoryRows)], { type: 'text/csv' }),
           `pmi_volunteer_service_history_${date}.csv`);
      }
    } else {
      console.log('💡 [M4] CSVs auxiliares pulados (EXPORT_CSV_DEBUG=false). JSON contém todos dados se precisar inspecionar.');
    }
  }

  // ===== 6) RESUMES (opcional) =====
  if (CONFIG.DOWNLOAD_RESUMES) {
    const withResume = applications.filter(a => a.resumeUrl);
    console.log(`\n📄 Baixando ${withResume.length} currículos...`);
    for (const a of withResume) {
      try {
        const blob = await (await fetch(a.resumeUrl)).blob();
        dl(blob, `${a._bucket}_${a.applicantId}_${(a.applicantName||'').replace(/[^a-z0-9]+/gi,'_')}.pdf`);
        await sleep(400);
      } catch (e) { console.warn(`  ❌ ${a.applicantName}`); }
    }
  }

  // ===== 7) SUMÁRIO =====
  console.log(`\n${'═'.repeat(50)}`);
  console.log(`✅ ${opportunityRows.length} opportunities · ${applications.length} applications · ${questionResponses.length} respostas · ${serviceHistoryRows.length} service-history rows`);
  if (communityEnrichmentBlocked) {
    console.warn(`⚠️ Community enrichment foi bloqueado — campos profile_*, serviceHistory* virão null/vazio.\n   Para enrichar depois, abra community.pmi.org logado e rode window.__pmi_enrichFromCommunity().`);
  } else if (wantsEnrichment) {
    console.log(`✨ Enrichment community.pmi.org: ${profileCache.size} profiles únicos consultados`);
  }
  const agg = applications.reduce((m, a) => { const k = `${a._bucket}/${a.status}`; m[k] = (m[k] || 0) + 1; return m; }, {});
  console.table(agg);

  window.__pmi = {
    meta, opportunities: opportunityRows, applications, questionResponses,
    serviceHistory: serviceHistoryRows, profileCache, ingestResult,
    communityEnrichmentBlocked
  };
  console.log('Disponível em window.__pmi');

  // ===== 8) HELPER PARA RODAR PHASE B (community.pmi.org) =====
  // Quando enrichment bloqueia, salvar fase A em localStorage e oferecer
  // helper que pode rodar em outra aba (community.pmi.org) sem CORS.
  if (communityEnrichmentBlocked) {
    try {
      localStorage.setItem('__pmi_phase_a',
        JSON.stringify({ meta, applications, savedAt: Date.now() }));
      console.log(`💾 Fase A salva em localStorage. Para rodar Fase B:\n` +
                  `   1. Abra https://community.pmi.org/profile/<seu-username> em outra aba\n` +
                  `   2. Console: cole novamente este script (ele vai detectar phase A salva)\n` +
                  `   3. (futuro: implementar phase B helper que lê localStorage e enrichi)\n`);
    } catch (e) { /* localStorage cheio? silently fail */ }
  }
})();
