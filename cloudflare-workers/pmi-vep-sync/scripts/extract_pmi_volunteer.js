// PMI Volunteer Applications Extractor — Núcleo IA & GP
// =====================================================================
// Cobertura completa do recruiter dashboard:
//   1. Auto-descobre chapters/opportunities do recruiter
//   2. Para cada opportunity, varre as 3 abas (submitted/qualified/rejected)
//   3. Para cada application, busca detalhe + comments (custom Q responses!)
//   4. (Opcional) Auto-POST do JSON para o worker pmi-vep-sync /ingest
//      → upsert em selection_applications + emite onboarding_tokens + envia welcome
//   5. Sempre baixa CSVs + JSON local para arquivo
//
// Uso:
//   1. Login no PMI VEP (https://volunteer.pmi.org/...)
//   2. F12 no recruiter dashboard → Console
//   3. Customize CONFIG abaixo (especialmente NUCLEO_INGEST_URL + SECRET)
//   4. Cole tudo → Enter
//   5. Aguarde 1-3 min (depende do volume) — fica watchando o console
//
// Output:
//   - 3 CSVs + 1 JSON baixados no Downloads (arquivo)
//   - Se NUCLEO_INGEST_URL preenchida: POST para o worker → response no console
//   - window.__pmi disponível pra inspecionar manualmente

(async () => {
  // ===== CONFIG =====
  const CONFIG = {
    // Filtros (null = auto-descobrir tudo do recruiter)
    OPPORTUNITY_IDS: null,           // ou ex: [64966, 64967]

    // Worker /ingest endpoint (deixa em branco para apenas baixar files)
    NUCLEO_INGEST_URL: 'https://pmi-vep-sync.ai-pm-research-hub.workers.dev/ingest',
    NUCLEO_INGEST_SECRET: '',        // PM cola o INGEST_SHARED_SECRET aqui antes de rodar
                                     // (NÃO commit este valor no git — é shared secret do worker)

    // Coleta de dados
    PAGE_SIZE: 50,
    FETCH_DETAIL: true,              // detalhe + question responses por application
    FETCH_COMMENTS: true,            // comments internos por application
    DOWNLOAD_RESUMES: false,         // PDFs (SAS expira ~24h) — true só quando arquivar
    DOWNLOAD_LOCAL_FILES: true,      // baixa CSVs + JSON localmente (arquival)

    // Rate limiting (PMI tolera bem; conservador por segurança)
    DELAY_MS: 200,
    DELAY_DETAIL_MS: 350,
  };

  // ===== UTIL =====
  const fetchJson = async (url) => {
    const r = await fetch(url, { headers: { accept: 'application/json' } });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const dl = (blob, name) => { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); };
  const csvEscape = v => v == null ? '' : `"${String(v).replace(/"/g,'""').replace(/\r?\n/g,' ')}"`;
  const toCsv = (cols, rows) => [cols.join(','), ...rows.map(r => cols.map(c => csvEscape(r[c])).join(','))].join('\n');

  // ===== METADATA =====
  const meta = { extractedAt: new Date().toISOString() };
  const me = await fetchJson('/api/Authorization/user/roles/v2');
  meta.recruiter = { personId: me.personId, name: me.personName, email: me.emailAddress, chapters: me.recruiter };
  console.log(`👤 ${me.personName} — chapters: ${me.recruiter.join(', ')}`);

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

  if (CONFIG.FETCH_DETAIL || CONFIG.FETCH_COMMENTS) {
    console.log(`\n🔍 Buscando detalhe de ${applications.length} applications...`);
    let i = 0;
    for (const a of applications) {
      i++;
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
      if (i % 10 === 0) console.log(`  ${i}/${applications.length}`);
      await sleep(CONFIG.DELAY_DETAIL_MS);
    }
  }

  // ===== 4) POST PARA WORKER /ingest (PRIMARY PATH) =====
  let ingestResult = null;
  if (CONFIG.NUCLEO_INGEST_URL && CONFIG.NUCLEO_INGEST_SECRET) {
    console.log(`\n📡 Enviando para Núcleo worker /ingest...`);
    try {
      const payload = { meta, opportunities: opportunityRows, applications, questionResponses };
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
        if (ingestResult.errors?.length) {
          console.warn('⚠️ Erros encontrados:');
          console.table(ingestResult.errors);
        }
      } else {
        console.error(`❌ Ingest HTTP ${r.status}:`, ingestResult);
      }
    } catch (e) {
      console.error(`❌ Ingest fetch error:`, e.message);
    }
  } else {
    console.log(`\n⏭️ NUCLEO_INGEST_URL ou SECRET vazios — pulando POST (só baixando files)`);
  }

  // ===== 5) CSVs + JSON LOCAL (arquival) =====
  if (CONFIG.DOWNLOAD_LOCAL_FILES) {
    const date = new Date().toISOString().slice(0,10);

    const oppCols = ['opportunityId','name','chapterName','status','classification',
                     'lastPostingDateUTC','postingEndDate','numberOfApplications',
                     'canManageApplications','canExportApplications'];
    dl(new Blob([toCsv(oppCols, opportunityRows)], { type: 'text/csv' }),
       `pmi_opportunities_${date}.csv`);

    const appCols = ['_opportunityId','_bucket','applicationId','applicantId','applicantName','applicantEmail',
                     'status','statusId','applicantCity','applicantState','applicantCountry',
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

    dl(new Blob([JSON.stringify({ meta, opportunities: opportunityRows, applications, questionResponses, ingestResult }, null, 2)], { type: 'application/json' }),
       `pmi_volunteer_full_${date}.json`);
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
  console.log(`✅ ${opportunityRows.length} opportunities · ${applications.length} applications · ${questionResponses.length} respostas`);
  const agg = applications.reduce((m, a) => { const k = `${a._bucket}/${a.status}`; m[k] = (m[k] || 0) + 1; return m; }, {});
  console.table(agg);

  window.__pmi = { meta, opportunities: opportunityRows, applications, questionResponses, ingestResult };
  console.log('Disponível em window.__pmi');
})();
