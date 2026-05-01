import { useState, useMemo, useEffect, useCallback } from 'react';
import type { Lang } from '../../i18n/utils';
import { getPMISupabaseClient } from './supabaseClient';
import EnrichmentCard from './EnrichmentCard';
import InterviewTopicsOptIn from './InterviewTopicsOptIn';

interface OnboardingProgressEntry {
  step_key: string;
  status: 'pending' | 'in_progress' | 'completed' | 'skipped';
  completed_at: string | null;
  evidence_url: string | null;
  notes: string | null;
  sla_deadline: string | null;
}

interface OnboardingStepDef {
  key: string;
  label?: string;
  description?: string;
  is_required?: boolean;
  type?: string;
}

interface VideoScreening {
  pillar: string;
  question_index: number;
  status: 'pending_upload' | 'uploaded' | 'transcribing' | 'transcribed' | 'failed' | 'opted_out';
  uploaded_at: string | null;
}

interface ConsumePayload {
  source_type: 'pmi_application';
  scopes: string[];
  application: {
    id: string;
    applicant_name: string;
    email: string;
    phone: string | null;
    linkedin_url: string | null;
    credly_url: string | null;
    role_applied: string;
    cycle_id: string;
    has_consent: boolean;
    has_revoked: boolean;
    status: string;
  };
  cycle: {
    id: string;
    cycle_code: string;
    title: string;
    phase: string;
    onboarding_steps: OnboardingStepDef[];
  };
  onboarding_progress: OnboardingProgressEntry[];
  video_screenings?: VideoScreening[];
  token_metadata: {
    access_count: number;
    expires_at: string;
    first_access: boolean;
  };
}

type I18nBundle = Record<string, string>;

interface Props {
  token: string;
  initialPayload: ConsumePayload | null;
  i18n: I18nBundle;
  lang: Lang;
  supabaseUrl: string;
  supabaseAnonKey: string;
}

const PILLARS: Array<{ key: VideoScreening['pillar']; questionIndex: number }> = [
  { key: 'background', questionIndex: 1 },
  { key: 'communication', questionIndex: 2 },
  { key: 'proactivity', questionIndex: 3 },
  { key: 'teamwork', questionIndex: 4 },
  { key: 'culture_alignment', questionIndex: 5 },
];

const BOOKING_URL = 'https://calendar.app.google/gh9WjefjcmisVLoh7';

export default function PMIOnboardingPortal({
  token, initialPayload, i18n, lang, supabaseUrl, supabaseAnonKey
}: Props) {
  const [payload, setPayload] = useState<ConsumePayload | null>(initialPayload);
  const [busyConsent, setBusyConsent] = useState(false);
  const [busyStep, setBusyStep] = useState<string | null>(null);
  const [busyVideo, setBusyVideo] = useState<string | null>(null);
  const [uploadState, setUploadState] = useState<Record<string, { progress: number; status: 'uploading' | 'finalizing' | 'error'; error?: string }>>({});
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [collapsedPillar, setCollapsedPillar] = useState<Record<string, boolean>>({});
  const [replaceConfirmPillar, setReplaceConfirmPillar] = useState<string | null>(null);
  const [optInterviewConfirm, setOptInterviewConfirm] = useState(false);
  const [optInterviewBusy, setOptInterviewBusy] = useState(false);
  const [revertInterviewConfirm, setRevertInterviewConfirm] = useState(false);
  const [revertInterviewBusy, setRevertInterviewBusy] = useState(false);
  const [profileLinkedin, setProfileLinkedin] = useState(initialPayload?.application?.linkedin_url ?? '');
  const [profileCredly, setProfileCredly] = useState(initialPayload?.application?.credly_url ?? '');
  const [profilePhone, setProfilePhone] = useState(initialPayload?.application?.phone ?? '');
  const [profileBusy, setProfileBusy] = useState(false);
  const [profileSavedAt, setProfileSavedAt] = useState<number | null>(null);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [enrichmentStatus, setEnrichmentStatus] = useState<any | null>(null);

  const sb = useMemo(() => getPMISupabaseClient(supabaseUrl, supabaseAnonKey), [supabaseUrl, supabaseAnonKey]);

  const loadEnrichmentStatus = useCallback(async () => {
    if (!sb || !token) return;
    try {
      const { data, error } = await sb.rpc('get_application_enrichment_status', { p_token: token });
      if (error) {
        // Token may not have profile_completion scope yet (pre-portal-active gate); silently ignore
        return;
      }
      setEnrichmentStatus(data);
    } catch { /* swallow */ }
  }, [sb, token]);

  useEffect(() => {
    loadEnrichmentStatus();
  }, [loadEnrichmentStatus, payload?.application?.has_consent]);
  const T = (k: string) => i18n[k] ?? k;

  if (!payload) {
    return (
      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-6">
        <p>{T('pmi.onboarding.loading')}</p>
      </div>
    );
  }

  const { application: app, cycle, onboarding_progress: progress, token_metadata } = payload;
  const videoScreenings = payload.video_screenings ?? [];
  const isInterviewMode = videoScreenings.length >= 5 && videoScreenings.every(v => v.status === 'opted_out');
  const videosUploadedCount = videoScreenings.filter(v => ['uploaded','transcribing','transcribed'].includes(v.status)).length;

  const expiresAtDate = new Date(token_metadata.expires_at);
  const daysLeft = Math.max(0, Math.floor((expiresAtDate.getTime() - Date.now()) / 86400000));

  const roleLabel = (() => {
    const map: Record<string, string> = {
      researcher: lang === 'en-US' ? 'Researcher' : lang === 'es-LATAM' ? 'Investigador' : 'Pesquisador',
      leader: lang === 'en-US' ? 'Tribe Leader' : lang === 'es-LATAM' ? 'Líder de Tribu' : 'Líder de Tribo',
      manager: lang === 'en-US' ? 'Project Manager' : lang === 'es-LATAM' ? 'Gerente de Proyecto' : 'Gerente de Projeto',
      both: lang === 'en-US' ? 'Researcher / Leader' : lang === 'es-LATAM' ? 'Investigador / Líder' : 'Pesquisador / Líder',
    };
    return map[app.role_applied] ?? app.role_applied;
  })();

  const pillarLabel = (key: string): string => {
    const pt: Record<string, string> = {
      background: 'Background', communication: 'Comunicação', proactivity: 'Proatividade',
      teamwork: 'Trabalho em equipe', culture_alignment: 'Alinhamento cultural'
    };
    const en: Record<string, string> = {
      background: 'Background', communication: 'Communication', proactivity: 'Proactivity',
      teamwork: 'Teamwork', culture_alignment: 'Culture alignment'
    };
    const es: Record<string, string> = {
      background: 'Background', communication: 'Comunicación', proactivity: 'Proactividad',
      teamwork: 'Trabajo en equipo', culture_alignment: 'Alineación cultural'
    };
    const map = lang === 'en-US' ? en : lang === 'es-LATAM' ? es : pt;
    return map[key] ?? key;
  };

  const pillarQuestionFallback = (key: string): string => {
    const pt: Record<string, string> = {
      background: 'Conte sua trajetória profissional e formação relacionadas a Gerenciamento de Projetos e Inteligência Artificial.',
      communication: 'Descreva uma situação onde sua comunicação fez diferença num projeto.',
      proactivity: 'Conte um exemplo de iniciativa sua que gerou impacto em um time ou organização.',
      teamwork: 'Descreva uma colaboração em time que você considera bem-sucedida e por quê.',
      culture_alignment: 'Por que o Núcleo IA & GP? O que te atrai dessa proposta?'
    };
    const en: Record<string, string> = {
      background: 'Tell us about your professional and academic background in Project Management and AI.',
      communication: 'Describe a situation where your communication made a difference in a project.',
      proactivity: 'Share an example of your initiative that generated impact in a team or organization.',
      teamwork: 'Describe a teamwork experience you consider successful and why.',
      culture_alignment: 'Why Núcleo IA & GP? What attracts you to this initiative?'
    };
    const es: Record<string, string> = {
      background: 'Cuéntanos sobre tu trayectoria profesional y formación en Gestión de Proyectos e IA.',
      communication: 'Describa una situación donde su comunicación marcó la diferencia en un proyecto.',
      proactivity: 'Comparta un ejemplo de su iniciativa que generó impacto en un equipo u organización.',
      teamwork: 'Describa una colaboración en equipo que considere exitosa y por qué.',
      culture_alignment: '¿Por qué Núcleo IA & GP? ¿Qué le atrae de esta propuesta?'
    };
    const map = lang === 'en-US' ? en : lang === 'es-LATAM' ? es : pt;
    return map[key] ?? '';
  };

  const handleConsentToggle = async (grant: boolean) => {
    setBusyConsent(true);
    setErrorMsg(null);
    try {
      const fnName = grant ? 'give_consent_via_token' : 'revoke_consent_via_token';
      const { error } = await sb.rpc(fnName, { p_token: token, p_consent_type: 'ai_analysis' });
      if (error) throw new Error(error.message);
      setPayload({
        ...payload,
        application: { ...app, has_consent: grant, has_revoked: !grant }
      });
    } catch (e: any) {
      setErrorMsg(e?.message ?? String(e));
    } finally {
      setBusyConsent(false);
    }
  };

  const handleProfileSave = async () => {
    setProfileBusy(true);
    setProfileError(null);
    setProfileSavedAt(null);
    try {
      const { error } = await sb.rpc('update_application_profile_via_token', {
        p_token: token,
        p_linkedin_url: profileLinkedin.trim() || null,
        p_credly_url: profileCredly.trim() || null,
        p_phone: profilePhone.trim() || null,
      });
      if (error) throw new Error(error.message);
      setPayload({
        ...payload,
        application: {
          ...app,
          linkedin_url: profileLinkedin.trim() || app.linkedin_url,
          credly_url: profileCredly.trim() || app.credly_url,
          phone: profilePhone.trim() || app.phone,
        },
      });
      setProfileSavedAt(Date.now());
    } catch (e: any) {
      setProfileError(e?.message ?? String(e));
    } finally {
      setProfileBusy(false);
    }
  };

  const handleStepUpdate = async (stepKey: string, newStatus: 'completed' | 'in_progress') => {
    setBusyStep(stepKey);
    setErrorMsg(null);
    try {
      const { error } = await sb.rpc('update_pmi_onboarding_step', {
        p_token: token,
        p_step_key: stepKey,
        p_status: newStatus,
        p_evidence_url: null,
      });
      if (error) throw new Error(error.message);
      setPayload({
        ...payload,
        onboarding_progress: progress.map(p =>
          p.step_key === stepKey
            ? { ...p, status: newStatus, completed_at: newStatus === 'completed' ? new Date().toISOString() : null }
            : p
        )
      });
    } catch (e: any) {
      setErrorMsg(e?.message ?? String(e));
    } finally {
      setBusyStep(null);
    }
  };

  const handleVideoOptOut = async (pillar: string, questionIndex: number) => {
    setBusyVideo(pillar);
    setErrorMsg(null);
    try {
      const { error } = await sb.rpc('register_video_screening', {
        p_token: token,
        p_pillar: pillar,
        p_question_index: questionIndex,
        p_question_text: pillarQuestionFallback(pillar),
        p_storage_provider: 'opted_out',
      });
      if (error) throw new Error(error.message);
      const newScreening: VideoScreening = {
        pillar, question_index: questionIndex,
        status: 'opted_out', uploaded_at: null
      };
      setPayload({
        ...payload,
        video_screenings: [...videoScreenings.filter(v => v.pillar !== pillar), newScreening]
      });
      setCollapsedPillar(s => ({ ...s, [pillar]: true }));
    } catch (e: any) {
      setErrorMsg(e?.message ?? String(e));
    } finally {
      setBusyVideo(null);
    }
  };

  const handleOptInterviewAll = async () => {
    setOptInterviewBusy(true);
    setErrorMsg(null);
    try {
      const { error } = await sb.rpc('opt_out_all_pillars', { p_token: token });
      if (error) throw new Error(error.message);
      const optedScreenings: VideoScreening[] = PILLARS.map(p => ({
        pillar: p.key,
        question_index: p.questionIndex,
        status: 'opted_out',
        uploaded_at: null,
      }));
      setPayload({
        ...payload,
        video_screenings: optedScreenings,
        application: { ...app, status: 'interview_pending' },
      });
      setUploadState({});
      setCollapsedPillar({});
      setOptInterviewConfirm(false);
    } catch (e: any) {
      setErrorMsg(e?.message ?? String(e));
    } finally {
      setOptInterviewBusy(false);
    }
  };

  const handleRevertInterview = async () => {
    setRevertInterviewBusy(true);
    setErrorMsg(null);
    try {
      const { error } = await sb.rpc('revert_interview_optout', { p_token: token });
      if (error) throw new Error(error.message);
      setPayload({
        ...payload,
        video_screenings: [],
        application: { ...app, status: app.status === 'interview_pending' ? 'screening' : app.status },
      });
      setRevertInterviewConfirm(false);
      setCollapsedPillar({});
    } catch (e: any) {
      setErrorMsg(e?.message ?? String(e));
    } finally {
      setRevertInterviewBusy(false);
    }
  };

  const handleReplaceVideo = (pillar: string) => {
    setReplaceConfirmPillar(null);
    setUploadState(s => {
      const next = { ...s };
      delete next[pillar];
      return next;
    });
    setPayload({
      ...payload,
      video_screenings: videoScreenings.filter(v => v.pillar !== pillar),
    });
    setCollapsedPillar(s => ({ ...s, [pillar]: false }));
  };

  const handleVideoUpload = async (pillar: string, questionIndex: number, file: File) => {
    setUploadState(s => ({ ...s, [pillar]: { progress: 0, status: 'uploading' } }));

    try {
      // Client-side validation
      if (!file.type.startsWith('video/')) {
        throw new Error(T('pmi.onboarding.videoErrorMime'));
      }
      const MAX_SIZE = 500 * 1024 * 1024;
      if (file.size > MAX_SIZE) {
        throw new Error(T('pmi.onboarding.videoErrorSize'));
      }

      // 1. Init: get Drive resumable upload URL
      const initRes = await sb.functions.invoke('pmi-video-init-upload', {
        body: {
          token,
          pillar,
          question_index: questionIndex,
          filename: file.name,
          size_bytes: file.size,
          mime_type: file.type,
        },
      });
      if (initRes.error) throw new Error(`init: ${initRes.error.message ?? initRes.error}`);
      const init = initRes.data as { upload_url: string; final_filename: string; folder_id: string };
      if (!init?.upload_url) throw new Error('init: no upload_url returned');

      // 2. Upload chunks directly to Drive resumable URL
      const CHUNK_SIZE = 8 * 1024 * 1024; // 8 MB
      let offset = 0;
      let driveFile: any = null;
      while (offset < file.size) {
        const end = Math.min(offset + CHUNK_SIZE, file.size);
        const chunk = file.slice(offset, end);
        const res = await fetch(init.upload_url, {
          method: 'PUT',
          headers: {
            'Content-Range': `bytes ${offset}-${end - 1}/${file.size}`,
          },
          body: chunk,
        });

        if (res.status === 200 || res.status === 201) {
          driveFile = await res.json();
          setUploadState(s => ({ ...s, [pillar]: { progress: 100, status: 'finalizing' } }));
          break;
        } else if (res.status === 308) {
          const range = res.headers.get('Range');
          if (range) {
            const m = range.match(/bytes=\d+-(\d+)/);
            offset = m ? parseInt(m[1]!, 10) + 1 : end;
          } else {
            offset = end;
          }
          const pct = Math.floor((offset / file.size) * 100);
          setUploadState(s => ({ ...s, [pillar]: { progress: pct, status: 'uploading' } }));
        } else {
          const errBody = await res.text().catch(() => '');
          throw new Error(`Drive upload ${res.status}: ${errBody.slice(0, 200)}`);
        }
      }

      if (!driveFile?.id) throw new Error('Drive did not return a file id');

      // 3. Finalize: register_video_screening
      const finalizeRes = await sb.functions.invoke('pmi-video-finalize-upload', {
        body: {
          token,
          pillar,
          question_index: questionIndex,
          question_text: pillarQuestionFallback(pillar),
          drive_file_id: driveFile.id,
          drive_file_name: init.final_filename,
          drive_folder_id: init.folder_id,
        },
      });
      if (finalizeRes.error) throw new Error(`finalize: ${finalizeRes.error.message ?? finalizeRes.error}`);

      // Optimistic UI update
      const newScreening: VideoScreening = {
        pillar, question_index: questionIndex,
        status: 'uploaded', uploaded_at: new Date().toISOString()
      };
      setPayload({
        ...payload,
        video_screenings: [...videoScreenings.filter(v => v.pillar !== pillar), newScreening]
      });
      setUploadState(s => {
        const next = { ...s };
        delete next[pillar];
        return next;
      });
      setCollapsedPillar(s => ({ ...s, [pillar]: true }));
    } catch (e: any) {
      const msg = e?.message ?? String(e);
      setUploadState(s => ({ ...s, [pillar]: { progress: 0, status: 'error', error: msg } }));
    }
  };

  const togglePillarCollapse = (pillar: string) => {
    setCollapsedPillar(s => ({ ...s, [pillar]: !s[pillar] }));
  };

  const completedCount = progress.filter(p => p.status === 'completed' || p.status === 'skipped').length;
  const totalCount = progress.length;
  const completionPct = totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0;

  const isInPreOnboarding = ['submitted', 'screening', 'objective_eval', 'objective_cutoff', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval'].includes(app.status);
  const isApproved = app.status === 'approved';

  return (
    <div className="space-y-6">
      <div className="bg-gradient-to-br from-blue-50 to-indigo-50 border border-blue-200 rounded-xl p-6">
        <h1 className="text-2xl md:text-3xl font-bold text-gray-900 mb-2">
          {T('pmi.onboarding.greeting').replace('{name}', app.applicant_name.split(/\s+/)[0] ?? '')}
        </h1>
        <p className="text-gray-700">
          {T('pmi.onboarding.intro')
            .replace('{role}', roleLabel)
            .replace('{cycle}', cycle.title)}
        </p>
        <div className="mt-4 flex flex-wrap gap-2 text-sm">
          <span className="bg-white border border-blue-200 text-blue-800 px-3 py-1 rounded-full">
            {T('pmi.onboarding.cycleCode')}: <strong>{cycle.cycle_code}</strong>
          </span>
          <span className="bg-white border border-blue-200 text-blue-800 px-3 py-1 rounded-full">
            {T('pmi.onboarding.role')}: <strong>{roleLabel}</strong>
          </span>
          <span className="bg-white border border-blue-200 text-blue-800 px-3 py-1 rounded-full">
            {T('pmi.onboarding.status')}: <strong>{app.status}</strong>
          </span>
        </div>
      </div>

      <div className="bg-amber-50 border border-amber-200 rounded-lg p-4 text-sm text-amber-900">
        ⏰ {T('pmi.onboarding.expires').replace('{days}', String(daysLeft))}
      </div>

      <section className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
        <h2 className="text-lg font-semibold text-gray-900 mb-2">
          {T('pmi.onboarding.consentTitle')}
        </h2>
        <p className="text-gray-600 text-sm mb-4">
          {T('pmi.onboarding.consentBody')}
        </p>
        <div className="flex items-center gap-3 flex-wrap">
          {app.has_consent && !app.has_revoked ? (
            <>
              <span className="bg-green-100 text-green-800 px-3 py-1 rounded-full text-sm font-medium">
                ✓ {T('pmi.onboarding.consentGranted')}
              </span>
              <button
                disabled={busyConsent}
                onClick={() => handleConsentToggle(false)}
                className="text-sm text-gray-600 underline hover:text-red-700 disabled:opacity-50"
              >
                {T('pmi.onboarding.revokeConsent')}
              </button>
            </>
          ) : (
            <>
              <span className="bg-gray-100 text-gray-800 px-3 py-1 rounded-full text-sm">
                {T('pmi.onboarding.consentNotGranted')}
              </span>
              <button
                disabled={busyConsent}
                onClick={() => handleConsentToggle(true)}
                className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white px-4 py-2 rounded-lg font-medium text-sm"
              >
                {busyConsent ? '...' : T('pmi.onboarding.grantConsent')}
              </button>
            </>
          )}
        </div>
      </section>

      {/* p86 Wave 5b-2: AI-augmented self-improvement cards (Card B + Card A) */}
      {enrichmentStatus?.has_analysis && (
        <>
          <InterviewTopicsOptIn
            token={token}
            sb={sb}
            areasToProbe={Array.isArray(enrichmentStatus.areas_to_probe) ? enrichmentStatus.areas_to_probe : []}
            T={T}
          />
          {enrichmentStatus.should_offer_enrichment && (
            <EnrichmentCard
              token={token}
              sb={sb}
              status={enrichmentStatus}
              T={T}
              onEnriched={() => { setTimeout(() => loadEnrichmentStatus(), 8000); }}
            />
          )}
        </>
      )}

      <section className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
        <h2 className="text-lg font-semibold text-gray-900 mb-2">
          👤 {T('pmi.onboarding.profileTitle')}
        </h2>
        <p className="text-sm text-gray-600 mb-4">
          {T('pmi.onboarding.profileBody')}
        </p>
        <div className="space-y-3">
          <div>
            <label htmlFor="profile-linkedin" className="block text-sm font-medium text-gray-700 mb-1">
              💼 {T('pmi.onboarding.profileLinkedinLabel')}
            </label>
            <input
              id="profile-linkedin"
              type="url"
              inputMode="url"
              value={profileLinkedin}
              onChange={(e) => setProfileLinkedin(e.target.value)}
              placeholder="https://www.linkedin.com/in/seu-perfil"
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:ring-2 focus:ring-blue-400 focus:border-blue-400"
              autoComplete="url"
            />
          </div>
          <div>
            <label htmlFor="profile-credly" className="block text-sm font-medium text-gray-700 mb-1">
              🏅 {T('pmi.onboarding.profileCredlyLabel')}
            </label>
            <input
              id="profile-credly"
              type="url"
              inputMode="url"
              value={profileCredly}
              onChange={(e) => setProfileCredly(e.target.value)}
              placeholder="https://www.credly.com/users/seu-username"
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:ring-2 focus:ring-blue-400 focus:border-blue-400"
              autoComplete="url"
            />
            <p className="text-xs text-gray-500 mt-1">{T('pmi.onboarding.profileCredlyHint')}</p>
          </div>
          <div>
            <label htmlFor="profile-phone" className="block text-sm font-medium text-gray-700 mb-1">
              📱 {T('pmi.onboarding.profilePhoneLabel')}
            </label>
            <input
              id="profile-phone"
              type="tel"
              inputMode="tel"
              value={profilePhone}
              onChange={(e) => setProfilePhone(e.target.value)}
              placeholder="+55 62 91234-5678"
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:ring-2 focus:ring-blue-400 focus:border-blue-400"
              autoComplete="tel"
            />
            <p className="text-xs text-gray-500 mt-1">{T('pmi.onboarding.profilePhoneHint')}</p>
          </div>

          {profileError && (
            <div className="bg-red-50 border border-red-200 rounded-md p-2 text-xs text-red-800 break-words" role="alert">
              ⚠️ {profileError}
            </div>
          )}

          <div className="flex flex-col sm:flex-row sm:items-center gap-2 pt-1">
            <button
              type="button"
              disabled={profileBusy}
              onClick={handleProfileSave}
              className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white px-4 py-2 rounded-md font-medium text-sm w-full sm:w-auto"
            >
              {profileBusy ? '...' : T('pmi.onboarding.profileSaveButton')}
            </button>
            {profileSavedAt && Date.now() - profileSavedAt < 6000 && (
              <span className="text-sm text-green-700 font-medium" aria-live="polite">
                ✓ {T('pmi.onboarding.profileSavedFeedback')}
              </span>
            )}
          </div>
        </div>
        <p className="text-xs text-gray-500 italic mt-4">
          {T('pmi.onboarding.profileFooterHint')}
        </p>
      </section>

      {totalCount > 0 && (
        <section className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
          <div className="flex justify-between items-center mb-3">
            <h2 className="text-lg font-semibold text-gray-900">
              {T('pmi.onboarding.progressTitle')}
            </h2>
            <span className="text-sm text-gray-600">
              {completedCount} / {totalCount} ({completionPct}%)
            </span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2 mb-4">
            <div
              className="bg-blue-600 h-2 rounded-full transition-all"
              style={{ width: `${completionPct}%` }}
            />
          </div>
          <ul className="divide-y divide-gray-100">
            {progress.map(step => {
              const def = cycle.onboarding_steps.find(s => s.key === step.step_key) ?? null;
              const label = def?.label ?? step.step_key;
              const desc = def?.description;
              const done = step.status === 'completed' || step.status === 'skipped';
              return (
                <li key={step.step_key} className="py-3 flex items-start gap-3">
                  <div className={`mt-1 w-5 h-5 rounded-full flex-shrink-0 flex items-center justify-center text-xs ${done ? 'bg-green-500 text-white' : 'bg-gray-200 text-gray-500'}`}>
                    {done ? '✓' : ''}
                  </div>
                  <div className="flex-1">
                    <div className="font-medium text-gray-900">{label}</div>
                    {desc && <div className="text-sm text-gray-600 mt-0.5">{desc}</div>}
                    {step.completed_at && (
                      <div className="text-xs text-gray-500 mt-1">
                        {T('pmi.onboarding.completedOn')}: {new Date(step.completed_at).toLocaleDateString(lang === 'en-US' ? 'en-US' : 'pt-BR')}
                      </div>
                    )}
                  </div>
                  {!done && (
                    <button
                      disabled={busyStep === step.step_key}
                      onClick={() => handleStepUpdate(step.step_key, 'completed')}
                      className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white px-3 py-1 rounded text-sm flex-shrink-0"
                    >
                      {busyStep === step.step_key ? '...' : T('pmi.onboarding.markDone')}
                    </button>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {isInPreOnboarding && (
        <section className="bg-blue-50 border border-blue-200 rounded-xl p-6">
          <h2 className="text-lg font-semibold text-blue-900 mb-2">
            📋 {T('pmi.onboarding.evaluationPhase')}
          </h2>
          <p className="text-blue-800 text-sm">
            {T('pmi.onboarding.evaluationBody')}
          </p>
        </section>
      )}

      {isApproved && (
        <section className="bg-green-50 border border-green-200 rounded-xl p-6">
          <h2 className="text-lg font-semibold text-green-900 mb-2">
            🎉 {T('pmi.onboarding.approvedTitle')}
          </h2>
          <p className="text-green-800 text-sm mb-4">
            {T('pmi.onboarding.approvedBody')}
          </p>
          <a
            href={lang === 'en-US' ? '/en/onboarding' : lang === 'es-LATAM' ? '/es/onboarding' : '/onboarding'}
            className="inline-block bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg font-medium"
          >
            {T('pmi.onboarding.goToFullOnboarding')} →
          </a>
        </section>
      )}

      {/* Video screening — 5 pillars × question + opt-out + Drive Resumable upload */}
      <section className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
        <h2 className="text-lg font-semibold text-gray-900 mb-2">
          🎥 {T('pmi.onboarding.videoScreeningTitle')}
        </h2>
        <p className="text-sm text-gray-600 mb-3">
          {T('pmi.onboarding.videoScreeningIntro')}
        </p>
        {!isInterviewMode && (
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 text-xs text-blue-900 mb-4">
            💡 {T('pmi.onboarding.videoPersistenceHint')}
          </div>
        )}

        {!isInterviewMode && (
          <div className="bg-gradient-to-r from-purple-50 to-indigo-50 border border-purple-200 rounded-lg p-4 mb-4">
            <div className="flex items-start gap-3">
              <div className="text-2xl flex-shrink-0">📞</div>
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-gray-900 mb-1">
                  {T('pmi.onboarding.interviewCtaTitle')}
                </div>
                <p className="text-sm text-gray-700 mb-3">{T('pmi.onboarding.interviewCtaBody')}</p>
                <button
                  type="button"
                  onClick={() => setOptInterviewConfirm(true)}
                  className="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded-lg font-medium text-sm w-full sm:w-auto"
                >
                  {T('pmi.onboarding.interviewCtaButton')}
                </button>
              </div>
            </div>
          </div>
        )}

        {isInterviewMode && (
          <div className="bg-purple-50 border-2 border-purple-200 rounded-xl p-6">
            <div className="flex items-start gap-3 mb-4">
              <div className="text-3xl flex-shrink-0">📞</div>
              <div className="flex-1 min-w-0">
                <div className="text-lg font-semibold text-purple-900">
                  ✓ {T('pmi.onboarding.interviewSelectedTitle')}
                </div>
                <p className="text-sm text-purple-800 mt-1">
                  {T('pmi.onboarding.interviewSelectedBody')}
                </p>
              </div>
            </div>
            <a
              href={BOOKING_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 w-full sm:w-auto bg-purple-600 hover:bg-purple-700 active:bg-purple-800 text-white px-6 py-3 rounded-lg font-semibold"
            >
              📅 {T('pmi.onboarding.interviewScheduleButton')}
            </a>
            <p className="text-xs text-purple-700 mt-3">
              {T('pmi.onboarding.interviewScheduleHint')}
            </p>
            <button
              type="button"
              onClick={() => setRevertInterviewConfirm(true)}
              className="text-xs text-gray-600 underline hover:text-blue-700 mt-4 block"
            >
              ← {T('pmi.onboarding.interviewRevertLink')}
            </button>
          </div>
        )}

        {!isInterviewMode && (<>
        <ul className="space-y-3">
          {PILLARS.map(p => {
            const existing = videoScreenings.find(v => v.pillar === p.key);
            const status = existing?.status ?? 'pending';
            const optedOut = status === 'opted_out';
            const uploaded = ['uploaded','transcribing','transcribed'].includes(status);
            const isDone = optedOut || uploaded;
            const collapsed = isDone && (collapsedPillar[p.key] ?? true);
            const upState = uploadState[p.key];
            const inlineError = upState?.status === 'error' ? upState.error : null;

            return (
              <li key={p.key} className="border border-gray-200 rounded-lg overflow-hidden">
                <button
                  type="button"
                  onClick={() => isDone && togglePillarCollapse(p.key)}
                  disabled={!isDone}
                  className={`w-full text-left p-4 flex items-center justify-between gap-3 ${isDone ? 'hover:bg-gray-50 cursor-pointer' : 'cursor-default'}`}
                  aria-expanded={!collapsed}
                >
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-gray-900">
                      {p.questionIndex}. {pillarLabel(p.key)}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    {optedOut && (
                      <span className="bg-purple-100 text-purple-800 px-2 py-0.5 sm:px-3 sm:py-1 rounded-full text-xs font-medium whitespace-nowrap">
                        ✓ {T('pmi.onboarding.videoOptedOut')}
                      </span>
                    )}
                    {uploaded && (
                      <span className="bg-green-100 text-green-800 px-2 py-0.5 sm:px-3 sm:py-1 rounded-full text-xs font-medium whitespace-nowrap">
                        ✓ {T('pmi.onboarding.videoUploaded')}
                      </span>
                    )}
                    {isDone && (
                      <span className="text-gray-400 text-sm" aria-hidden="true">
                        {collapsed ? '▸' : '▾'}
                      </span>
                    )}
                  </div>
                </button>

                {!collapsed && (
                  <div className="px-4 pb-4 border-t border-gray-100 pt-3">
                    <div className="text-sm text-gray-700 mb-3">
                      {pillarQuestionFallback(p.key)}
                    </div>

                    {upState?.status === 'uploading' && (
                      <div className="w-full mb-2" role="progressbar" aria-valuenow={upState.progress} aria-valuemin={0} aria-valuemax={100} aria-label={T('pmi.onboarding.videoUploading')}>
                        <div className="text-xs text-blue-700 mb-1">
                          {T('pmi.onboarding.videoUploading')} {upState.progress}%
                        </div>
                        <div className="w-full bg-gray-200 rounded-full h-1.5">
                          <div className="bg-blue-600 h-1.5 rounded-full transition-all" style={{ width: `${upState.progress}%` }} />
                        </div>
                      </div>
                    )}

                    {upState?.status === 'finalizing' && (
                      <div className="text-xs text-blue-700 mb-2" aria-live="polite">{T('pmi.onboarding.videoFinalizing')}</div>
                    )}

                    {inlineError && (
                      <div className="bg-red-50 border border-red-200 rounded-md p-2 text-xs text-red-800 mb-2 break-words" role="alert">
                        ⚠️ {inlineError}
                      </div>
                    )}

                    {isDone && (
                      <div className="flex flex-col sm:flex-row gap-2">
                        <button
                          type="button"
                          onClick={() => setReplaceConfirmPillar(p.key)}
                          className="text-xs text-gray-700 underline hover:text-blue-700 text-left sm:text-center"
                        >
                          {T('pmi.onboarding.videoReplaceButton')}
                        </button>
                      </div>
                    )}

                    {!isDone && !upState && (
                      <div className="flex flex-col sm:flex-row sm:items-center gap-2">
                        <label className="bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white px-3 py-2 rounded text-sm font-medium cursor-pointer inline-flex items-center justify-center gap-1 w-full sm:w-auto">
                          📹 {T('pmi.onboarding.videoRecordButton')}
                          <input
                            type="file"
                            accept="video/*"
                            capture="user"
                            className="hidden"
                            onChange={(e) => {
                              const f = e.target.files?.[0];
                              if (f) handleVideoUpload(p.key, p.questionIndex, f);
                              e.target.value = '';
                            }}
                          />
                        </label>
                        <label className="bg-white border border-blue-600 hover:bg-blue-50 text-blue-700 px-3 py-2 rounded text-sm font-medium cursor-pointer inline-flex items-center justify-center gap-1 w-full sm:w-auto">
                          📁 {T('pmi.onboarding.videoChooseFileButton')}
                          <input
                            type="file"
                            accept="video/*"
                            className="hidden"
                            onChange={(e) => {
                              const f = e.target.files?.[0];
                              if (f) handleVideoUpload(p.key, p.questionIndex, f);
                              e.target.value = '';
                            }}
                          />
                        </label>
                      </div>
                    )}

                    {upState?.status === 'error' && (
                      <div className="flex flex-col sm:flex-row gap-2 mt-2">
                        <button
                          type="button"
                          onClick={() => setUploadState(s => { const n = { ...s }; delete n[p.key]; return n; })}
                          className="text-xs text-blue-700 underline hover:text-blue-900 text-left"
                        >
                          {T('pmi.onboarding.videoTryAgain')}
                        </button>
                      </div>
                    )}
                  </div>
                )}
              </li>
            );
          })}
        </ul>
        <p className="text-xs text-gray-500 mt-4 italic">
          {T('pmi.onboarding.videoUploadHint')}
        </p>
        </>)}

        {replaceConfirmPillar && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4" role="dialog" aria-modal="true">
            <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6">
              <h3 className="text-lg font-semibold text-gray-900 mb-2">
                {T('pmi.onboarding.videoReplaceConfirmTitle')}
              </h3>
              <p className="text-sm text-gray-700 mb-4">
                {T('pmi.onboarding.videoReplaceConfirmBody')}
              </p>
              <div className="flex flex-col sm:flex-row-reverse gap-2">
                <button
                  type="button"
                  onClick={() => handleReplaceVideo(replaceConfirmPillar)}
                  className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded font-medium text-sm w-full sm:w-auto"
                >
                  {T('pmi.onboarding.videoReplaceConfirmYes')}
                </button>
                <button
                  type="button"
                  onClick={() => setReplaceConfirmPillar(null)}
                  className="bg-white border border-gray-300 hover:bg-gray-50 text-gray-700 px-4 py-2 rounded font-medium text-sm w-full sm:w-auto"
                >
                  {T('pmi.onboarding.videoReplaceConfirmNo')}
                </button>
              </div>
            </div>
          </div>
        )}

        {optInterviewConfirm && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4" role="dialog" aria-modal="true">
            <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6">
              <h3 className="text-lg font-semibold text-gray-900 mb-2">
                📞 {T('pmi.onboarding.interviewConfirmTitle')}
              </h3>
              <p className="text-sm text-gray-700 mb-4">
                {videosUploadedCount > 0
                  ? T('pmi.onboarding.interviewConfirmBodyWithVideos').replace('{count}', String(videosUploadedCount))
                  : T('pmi.onboarding.interviewConfirmBody')}
              </p>
              <div className="flex flex-col sm:flex-row-reverse gap-2">
                <button
                  type="button"
                  disabled={optInterviewBusy}
                  onClick={handleOptInterviewAll}
                  className="bg-purple-600 hover:bg-purple-700 disabled:bg-purple-400 text-white px-4 py-2 rounded font-medium text-sm w-full sm:w-auto"
                >
                  {optInterviewBusy ? '...' : T('pmi.onboarding.interviewConfirmYes')}
                </button>
                <button
                  type="button"
                  disabled={optInterviewBusy}
                  onClick={() => setOptInterviewConfirm(false)}
                  className="bg-white border border-gray-300 hover:bg-gray-50 text-gray-700 px-4 py-2 rounded font-medium text-sm w-full sm:w-auto"
                >
                  {T('pmi.onboarding.interviewConfirmNo')}
                </button>
              </div>
            </div>
          </div>
        )}

        {revertInterviewConfirm && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4" role="dialog" aria-modal="true">
            <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6">
              <h3 className="text-lg font-semibold text-gray-900 mb-2">
                {T('pmi.onboarding.interviewRevertConfirmTitle')}
              </h3>
              <p className="text-sm text-gray-700 mb-4">
                {T('pmi.onboarding.interviewRevertConfirmBody')}
              </p>
              <div className="flex flex-col sm:flex-row-reverse gap-2">
                <button
                  type="button"
                  disabled={revertInterviewBusy}
                  onClick={handleRevertInterview}
                  className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white px-4 py-2 rounded font-medium text-sm w-full sm:w-auto"
                >
                  {revertInterviewBusy ? '...' : T('pmi.onboarding.interviewRevertConfirmYes')}
                </button>
                <button
                  type="button"
                  disabled={revertInterviewBusy}
                  onClick={() => setRevertInterviewConfirm(false)}
                  className="bg-white border border-gray-300 hover:bg-gray-50 text-gray-700 px-4 py-2 rounded font-medium text-sm w-full sm:w-auto"
                >
                  {T('pmi.onboarding.interviewRevertConfirmNo')}
                </button>
              </div>
            </div>
          </div>
        )}
      </section>

      <footer className="text-center text-sm text-gray-600 pt-6 border-t border-gray-200">
        {T('pmi.onboarding.contactFooter')}{' '}
        <a href="mailto:nucleoia@pmigo.org.br" className="underline">nucleoia@pmigo.org.br</a>
      </footer>

      {errorMsg && (
        <div className="fixed bottom-4 right-4 bg-red-100 border border-red-300 text-red-800 rounded-lg p-3 shadow-lg max-w-sm">
          <div className="font-bold text-sm">⚠️ {T('pmi.onboarding.errorTitle')}</div>
          <div className="text-xs mt-1 break-words">{errorMsg}</div>
          <button onClick={() => setErrorMsg(null)} className="text-xs underline mt-1">×</button>
        </div>
      )}
    </div>
  );
}
