# Aviso retroativo LGPD Art. 18 §IV — candidato Eduardo Luz (ciclo 4-2026)

**Status:** PM-approved interim text (Angeline async produzirá texto legal-grade definitivo sob issue [#334](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/334)).
**Template version:** `interim_v1`
**Use:** dispatch único do PM via e-mail oficial `nucleoia@pmigo.org.br` (NÃO via plataforma).
**Registro:** PR p238 #332 — `lgpd_record_retroactive_notification` RPC grava em `pii_access_log` no momento do envio.
**Janela:** 30 dias corridos para resposta; manutenção tácita pós-prazo; direito de exclusão permanece exercitável após.

## Metadata

| Campo | Valor |
|---|---|
| Destinatário | Eduardo Luz |
| E-mail | `eduardoluz.pm@gmail.com` |
| `application_id` | `e780d8a9-55e0-4a6c-9370-4acc24a9619d` |
| Ciclo | `cycle4-2026` (id `08c1e301-9f7b-4d01-a13c-43ac7775c0f7`) |
| Status | `interview_pending` |
| `pmi_video_screenings.id` afetado (background pillar) | `6afb7e26-b806-4028-a8d5-0a22d1a0584b` |
| `transcription` length | 2428 chars |
| `drive_file_id` | `14bA9rCezVD0Usko-S28ZtJnXd63MwsO6` |
| `drive_file_name` | `cycle3-2026-b2__opp64967__e780d8a9-eduardo-luz__researcher__p1-background__20260507-2103.mp4` |
| Outros pilares (não transcritos, bloqueio correto p207) | communication, proactivity, teamwork, culture_alignment |
| `selection_evaluation_ai_suggestions` row (background) | `90b556be` (claude-haiku-4-5; `consumed_at=NULL`; não consumida — não influenciou nota humana final) |
| Consentimento na época | `consent_ai_analysis_at` presente; `consent_voice_biometric_at` NULL (Art. 11 §I gap retroativo) |
| Bloqueio técnico imediato | trigger `trg_pmi_video_screening_voice_consent` aplicado 07/2026 (canonical row `20260520231254`) |
| Formulário forward de consentimento destacado | shipped p238 PR #340 (`PMIOnboardingPortal.tsx` amber section + i18n `pmi.onboarding.voiceConsent*` + `privacy.s4.openaiWhisper`) |

## Texto pt-BR (primary)

**Assunto:** `Aviso LGPD — sobre o processamento do seu vídeo de candidatura ao Núcleo IA & GP (ciclo 4-2026)`

```
Olá Eduardo,

Estamos enviando este aviso para esclarecer um aspecto técnico do processamento da
sua candidatura ao Núcleo IA & GP, conforme a Lei Geral de Proteção de Dados (LGPD,
Lei 13.709/2018).

Em 07/05/2026, você gravou e enviou um vídeo de resposta (pilar Background) como
parte do processo de screening do ciclo 4-2026. Naquele momento, a plataforma
realizou a transcrição automatizada desse áudio por meio do OpenAI Whisper
(subprocessador, EUA), com o objetivo de subsidiar a avaliação humana posterior do
comitê de seleção. Essa transcrição foi gerada sob o seu consentimento genérico
de análise por IA (campo interno `consent_ai_analysis_at`).

Identificamos posteriormente que o tratamento de dado pessoal sensível biométrico
de voz exige, pelo Art. 11, §1º, inciso I da LGPD, um consentimento DESTACADO E
ESPECÍFICO — distinto do consentimento genérico de análise por IA. Seu
consentimento original cobriu a análise por IA, mas não foi obtido como
consentimento destacado para o dado biométrico de voz especificamente. Tratamos
isso como uma lacuna retroativa de base legal que precisamos corrigir com
transparência.

A plataforma já implementou as seguintes correções:

  1. Bloqueio técnico imediato (07/2026): nenhuma nova transcrição de vídeo é
     gerada sem consentimento destacado de voz. Os outros pilares que você gravou
     (Comunicação, Proatividade, Trabalho em Equipe, Alinhamento Cultural) NÃO
     foram transcritos porque o bloqueio entrou em vigor antes do processamento
     deles.

  2. Formulário de consentimento destacado no portal do candidato (referência
     técnica: PR p238 #340, página /pmi-onboarding/[token], seção amarela
     destacada): todas as gravações futuras passam a exigir esse consentimento
     específico antes do upload.

  3. Este aviso retroativo, com a oferta do direito de exclusão garantido pelo
     Art. 18, §IV da LGPD.

Suas opções:

  a) MANTER OS DADOS: a transcrição (2428 caracteres do pilar Background) e o
     arquivo de áudio original no Google Drive da organização permanecem
     disponíveis para a avaliação humana do comitê de seleção, exclusivamente
     para fins desta candidatura ao ciclo 4-2026.

  b) SOLICITAR A EXCLUSÃO: basta responder este e-mail (ou escrever para
     nucleoia@pmigo.org.br) com a frase "SOLICITO EXCLUSÃO LGPD ART 18". Em
     até 30 dias corridos:

       • a transcrição será removida do banco de dados da plataforma;
       • o arquivo de áudio original será excluído do Google Drive da
         organização;
       • você receberá confirmação por escrito do procedimento, com o
         identificador interno da operação de auditoria.

     Sua candidatura ao ciclo 4-2026 PROSSEGUE NORMALMENTE em qualquer caso —
     ela não é prejudicada pela escolha. Caso opte pela exclusão, a avaliação do
     pilar "Background" será reconduzida via entrevista 1:1 ao vivo via Google
     Meet, sem ônus.

Caso não receba sua resposta em 30 dias corridos, presumiremos como sua decisão
a manutenção dos dados conforme o status atual (manutenção tácita), mas o
direito de solicitar a exclusão permanece exercitável a qualquer momento futuro,
pelo mesmo canal.

Estamos à disposição para esclarecimentos. Pedimos desculpas pela necessidade
deste aviso retroativo — a remediação foi tratada como prioridade máxima
assim que a lacuna foi identificada.

Atenciosamente,

Vitor Maia Rodovalho
Líder do Núcleo IA & GP (PMI Goiás)
nucleoia@pmigo.org.br

---
Referências internas (para sua auditoria):
- ID da candidatura: e780d8a9-55e0-4a6c-9370-4acc24a9619d
- ID do registro de vídeo afetado (pilar Background):
  6afb7e26-b806-4028-a8d5-0a22d1a0584b
- ID do arquivo no Google Drive da organização:
  14bA9rCezVD0Usko-S28ZtJnXd63MwsO6
- Notificação enviada conforme PR p238 #341 (template "interim_v1";
  texto definitivo legal-grade pendente sob issue #334)
- Bases legais citadas: LGPD Art. 11 §1º I (dado biométrico de voz,
  sensível), Art. 18 §IV (direito de exclusão), Art. 9 (informação
  clara sobre o tratamento)
```

## English fallback (en-US)

**Subject:** `LGPD notice — about processing of your video screening for the Núcleo IA & GP application (cycle 4-2026)`

```
Hello Eduardo,

We are sending this notice to clarify a technical aspect of how your application
to Núcleo IA & GP was processed, in accordance with Brazil's General Data
Protection Law (LGPD, Law 13.709/2018).

On 2026-05-07 you recorded and uploaded a video response (Background pillar) as
part of the cycle 4-2026 screening process. At that time, our platform performed
automated transcription of the audio via OpenAI Whisper (subprocessor, USA) to
support subsequent human evaluation by the selection committee. That
transcription was generated under your generic AI-analysis consent (internal
field `consent_ai_analysis_at`).

We subsequently identified that processing of voice biometric sensitive personal
data requires, under Article 11, §1, item I of the LGPD, a HIGHLIGHTED AND
SPECIFIC consent — distinct from the generic AI-analysis consent. Your original
consent covered the AI analysis, but was not obtained as a highlighted consent
specifically for the voice biometric data. We are treating this as a
retroactive legal-basis gap that we must correct transparently.

The platform has already implemented the following corrections:

  1. Immediate technical block (2026-07): no new video transcription is
     generated without a highlighted voice consent. The other pillars you
     recorded (Communication, Proactivity, Teamwork, Culture Alignment) were
     NOT transcribed because the block took effect before they were processed.

  2. Highlighted consent form in the candidate portal (technical reference: PR
     p238 #340, page /pmi-onboarding/[token], amber-highlighted section): all
     future recordings now require this specific consent before upload.

  3. This retroactive notice, offering you the right to deletion guaranteed by
     Article 18, §IV of the LGPD.

Your options:

  a) KEEP THE DATA: the transcription (2428 characters of the Background
     pillar) and the original audio file in the organization's Google Drive
     remain available for human evaluation by the selection committee,
     exclusively for the purpose of this cycle 4-2026 application.

  b) REQUEST DELETION: simply reply to this email (or write to
     nucleoia@pmigo.org.br) with the phrase "REQUEST LGPD ART 18 DELETION".
     Within 30 calendar days:

       • the transcription will be removed from the platform's database;
       • the original audio file will be deleted from the organization's
         Google Drive;
       • you will receive written confirmation of the procedure, including
         the internal audit operation identifier.

     Your cycle 4-2026 application PROCEEDS NORMALLY in either case — it is
     not harmed by your choice. If you opt for deletion, the "Background"
     pillar evaluation will be rebuilt via a live 1:1 interview on Google
     Meet, at no cost to you.

If we do not receive your response within 30 calendar days, we will presume
your decision to maintain the data as currently stored (tacit retention), but
the right to request deletion remains exercisable at any future moment
through the same channel.

We are available for clarification. We apologize for the need for this
retroactive notice — the remediation was treated with top priority as soon
as the gap was identified.

Best regards,

Vitor Maia Rodovalho
Lead, Núcleo IA & GP (PMI Goiás chapter)
nucleoia@pmigo.org.br

---
Internal references (for your audit):
- application id: e780d8a9-55e0-4a6c-9370-4acc24a9619d
- affected video screening id (Background pillar):
  6afb7e26-b806-4028-a8d5-0a22d1a0584b
- Google Drive file id (organization Drive):
  14bA9rCezVD0Usko-S28ZtJnXd63MwsO6
- Notice dispatched per PR p238 #341 (template "interim_v1";
  legal-grade text pending under issue #334)
- Legal bases cited: LGPD Art. 11 §1 I (voice biometric, sensitive
  personal data), Art. 18 §IV (right to deletion), Art. 9 (clear
  information about processing)
```

## Operational checklist (PM/dispatcher)

1. PM (or designated DPO) reviews this template + adjusts wording if Angeline (issue #334) has stronger language available.
2. PM dispatches the pt-BR text via email from `nucleoia@pmigo.org.br` to `eduardoluz.pm@gmail.com`. EN fallback offered if Eduardo requests it.
3. After dispatch (or same-day batch), call the audit RPC:
   ```sql
   SELECT public.lgpd_record_retroactive_notification(
     p_application_id := 'e780d8a9-55e0-4a6c-9370-4acc24a9619d',
     p_template_version := 'interim_v1',
     p_lang := 'pt-BR',
     p_notification_method := 'email',
     p_dispatched_at := now()
   );
   ```
4. Save sent-email evidence (Gmail "Sent" thread URL or message-id) in PM's offline records — this is the chain anchor.
5. Set a 30-day reminder. If no response by deadline → log a `lgpd_art_18_retroactive_notification_tacit_retention` follow-up via the same RPC with `p_template_version='interim_v1.tacit_close'`.
6. If Eduardo requests deletion:
   - PM logs into the organization's Google Workspace as admin and deletes the Drive file `14bA9rCezVD0Usko-S28ZtJnXd63MwsO6` (move to trash or hard-delete; capture confirmation screenshot).
   - PM calls `lgpd_execute_retroactive_deletion()` with the video id, deletion reason, and Drive deletion confirmation reference (saved to `deletion_artifacts` jsonb).
   - RPC clears `pmi_video_screenings.transcription` for the affected row, and inserts the audit record in `pii_access_log`.
   - PM replies to Eduardo confirming the operation, citing the `pii_access_log.id` of the deletion audit row as the chain identifier.
7. After deletion, the affected `pmi_video_screenings` row has `transcription IS NULL` → satisfies sibling C3 (#333) invariant U precondition.

## Cross-references

- Parent decomposition (closed p236): #218 + #221
- Sibling shipped p238: #331 (W2 forward UI + i18n)
- Sibling blocked / blocking: #333 (invariant U), #334 (Angeline legal-grade template), #335 (ADR-0094)
- LGPD Art. 11 §1 I (dado biométrico sensível) · Art. 18 §IV (direito de exclusão) · Art. 9 (informação clara) · Art. 48 §1 (notificação ANPD — coordenar sob #334 se aplicável)
- Wave 1 emergency block (canonical row `20260520231254`): blocks new transcriptions absent voice consent
- Forward UI capture (canonical row `20260805000022`): captures destacado consent + SHA-256 evidence going forward
