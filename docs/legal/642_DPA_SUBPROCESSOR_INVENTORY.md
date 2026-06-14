# #642 — DPA Sub-operator Inventory and PostHog PII Guard

Date: 2026-06-13
Status: implementation-ready inventory for DPA Anexo I; legal sign-off still required before signing.

## Scope

This inventory covers processors/sub-operators used by the Hub as implemented in this repository. It is meant to support the DPA package before formal signing, not to replace counsel review.

## Product PII Rule

PostHog is product analytics only. The Hub must not send direct identifiers such as name, email, phone, LinkedIn URL, PMI ID, free-text search terms, candidate/applicant names, or profile text to PostHog.

Implemented guard:

- Authenticated users are identified as `member:<member_uuid>`.
- Person properties are limited to chapter, operational role, designations, superadmin flag, and cycle-active flag.
- A central sanitizer redacts sensitive property keys and values before event capture.
- Free-text search analytics send length/count metadata, not the query body.

## Direct Operators / Sub-operators

| Provider | Hub use | Data categories | Region / transfer note | Official subprocessor source | DPA note |
|---|---|---|---|---|---|
| Supabase | PostgreSQL, Auth, Storage, Realtime, Edge Functions | Member profile data, authentication identifiers, governance records, attendance, selection/onboarding data, files | Project region is documented locally as `sa-east-1`; Supabase DPA Schedule 3 controls authorized subprocessors | https://supabase.com/downloads/docs/Supabase%2BDPA%2B250314.pdf | Must be attached/referenced in platform DPA pack. |
| Cloudflare | Workers SSR, CDN, KV/session, security headers, optional Browser Rendering binding | HTTP requests, session cookies/tokens in transit, rendered app traffic, worker logs | Global edge processing; provider page lists current Cloudflare service subprocessors | https://www.cloudflare.com/gdpr/subprocessors/cloudflare-services/ | Required as application hosting/network operator. |
| PostHog | Optional product analytics and session recording, gated by consent | Pseudonymous member ID, role/chapter segmentation, event metadata. No direct PII after #642 guard. | Current project uses US PostHog host when configured; provider page lists core subprocessors | https://posthog.com/subprocessors | Must remain optional. DPA must describe analytics minimization and consent gate. |
| Sentry | Browser error monitoring and global error handlers | Error stack/context; may include URLs and runtime metadata. Application code must avoid adding PII extras. | Region depends on Sentry project setting; provider list updated June 1, 2026 | https://sentry.io/legal/subprocessors/ | Add to DPA and verify project data location. |
| Resend | Transactional emails, campaign emails, webhooks for delivery/open/click | Recipient email, message metadata, delivery/open/click event metadata | Provider subprocessor list is US-centered and includes email/infra/support subprocessors | https://resend.com/legal/subprocessors | Required for notification/campaign flows. |
| Google | Google OAuth, Google Drive integration, Workspace artifacts | OAuth identifiers, institutional Drive files/folder metadata where configured | Google Cloud/Workspace subprocessor lists apply depending on service used | https://cloud.google.com/terms/subprocessors and https://workspace.google.com/terms/subprocessors/ | Drive integration is PM-configured; DPA should mark it enabled only when vault credentials are seeded. |
| Microsoft | Microsoft/Azure OIDC auth | OAuth identifiers and login metadata | Microsoft Trust Center points to Online Services subprocessor list | https://www.microsoft.com/en-us/trust-center/privacy/data-access | Auth-only use; include if Microsoft login remains enabled. |
| LinkedIn | LinkedIn OIDC auth | OAuth identifiers and login metadata | LinkedIn customer subprocessors page covers relevant enterprise services | https://www.linkedin.com/legal/l/customer-subprocessors | Auth-only use; include if LinkedIn login remains enabled. |
| OpenAI | Conditional video transcription via Whisper in `analyze-application-video` | Candidate video/audio and transcript only after explicit voice biometric consent | Official OpenAI subprocessor list updated June 2, 2026 | https://openai.com/policies/sub-processor-list/ | Blocked unless consent + DPA/transfer basis are confirmed for the selection flow. |
| Anthropic | Conditional AI triage/briefing and video analysis suggestions | Prompt inputs, candidate/interview context only when feature enabled | Anthropic Trust Center exposes current subprocessors | https://trust.anthropic.com/subprocessors | Blocked unless DPA coverage is confirmed for the specific AI feature. |

## DPA Anexo I Checklist

- [ ] Confirm which optional processors are enabled in production env: PostHog, Sentry, Google Drive, OpenAI, Anthropic.
- [ ] Attach or link current provider DPA/subprocessor pages in the final DPA pack.
- [ ] Subscribe to provider subprocessor update feeds where offered: PostHog, Cloudflare, Sentry, OpenAI.
- [ ] Record project regions/settings for Supabase, Sentry, PostHog, and Cloudflare account.
- [ ] For AI processors, do not enable candidate/video flows until the specific consent and DPA gates are signed off.
- [ ] Re-run `npm test` before signing if analytics or privacy code changes again.

## Code References

- `src/lib/analytics.ts` — central PostHog property sanitizer.
- `src/layouts/BaseLayout.astro` — consent-gated PostHog init and pseudonymous identify.
- `src/components/nav/Nav.astro` — duplicate name/email-bearing PostHog identify removed.
- `tests/contracts/642-posthog-pii-subprocessors.test.mjs` — regression lock for the PII guard and this inventory.
