# Research — Airmeet landscape + community virtual events

**Session:** p134 Ω-A Wave 2 (council research) · **Date:** 2026-05-09
**Audience:** PM (Vitor) for Núcleo IA Hub decision: **integrate Airmeet** vs **replace** vs **hybrid Zoom + selective Airmeet**.
**Note:** WebFetch tool denied this session — analysis is based on WebSearch summaries (cited). Validate API specifics before commitment.

---

## TL;DR (5 lines)

1. **Airmeet has a real public API** (custom auth `X-Airmeet-Access-Key`/`Secret-Key`, NOT OAuth) + webhooks for `registrant.added`, `attendee.joined`, `session.attendee.joined`, polls — viable for ingest into our `event_attendance` pipeline.
2. **Pricing 2026: $167/mo (annual, ~100 attendees) → $18,000+/yr enterprise**, attendee-based not event-based. Recording included all tiers (480p free, 720p Business+); **transcript download Enterprise-only**; **recordings auto-purge after 60 days** — load-bearing constraint for our certificate workflow.
3. **PMI Latam is a published case study** (since Mar 2020, upgraded to 2000-attendee license Oct 2020, runs monthly "PMI Portunol" across 19 countries). Strong PT/ES multilingue track record via Interprefy integration.
4. **Multilingue PT/ES/EN simultaneous = Interprefy add-on** (~$500–1,000/day platform fee + interpreter rates separate). Not native Airmeet feature — significant add-on cost.
5. **Recommendation: HYBRID, not full integrate or replace.** Keep Zoom for tribe weekly meetings (cheap, working, recording flow OK). Adopt Airmeet selectively for CPMAI Latam + Detroit Summit + LIM-class events where engagement + multilingue + brand quality matter. Build the API integration only for those events. Recording-purge 60d window = MUST mirror to YouTube unlisted within 7d (matches our existing token-gated workflow).

---

## Airmeet API capabilities

**Auth:** Custom headers `X-Airmeet-Access-Key` + `X-Airmeet-Secret-Key` (obtained from community dashboard → Integrations tab). Token issued by auth endpoint, valid 30 days, cacheable. **Not OAuth 2.x** — simpler for server-to-server but no user-delegation flow.

**Endpoints (Public API v2):**
- `1. Event Details` — fetch event metadata, sessions, status
- `2. Manage Registrations` — list participants (invitees, guests, registered); add attendee with custom registration fields
- `3. Manage Event` — CRUD event lifecycle
- `4. Manage Event Series` — series management
- **Recording download:** API returns fresh signed URLs valid 6 hours (must re-fetch each time)

**Webhooks (push to our endpoint):**
- `trigger.airmeet.registrant.added`
- `trigger.airmeet.attendee.joined` (with `airmeetId` query param)
- `trigger.session.attendee.joined` (with `airmeetId` + `sessionId`)
- `trigger.airmeet.polls`
- Microsoft Power Automate connector exists (validates webhook maturity)

**Rate limits:** Not publicly documented. Some user reviews complain "no webhooks" — likely refers to lower tiers; webhooks gated by plan.

**Docs:** https://help.airmeet.com/support/solutions/folders/82000404934 (25 articles, last refreshed Jan 2025).

---

## Airmeet pricing 2026

5 editions, $0–$18,000+. **Charges per attendee, not per registrant** (key advantage for community events with no-shows).

| Tier | Price | Attendee cap | Recording quality | Notable limits |
|---|---|---|---|---|
| **Free** | $0 | 50/event | 480p | Limited features, branding watermark |
| **Standard/Premium Webinars** | **$167/mo** (annual, 16% off) | 100 (scalable to 10K) | 720p? | 2 team members, unlimited session length |
| **Business** | Custom (mid-thousands est.) | Higher | 720p | More integrations, branding |
| **Enterprise** | $18,000/yr+ (custom) | 2000+ | 720p + transcripts | Multi-event, dedicated CSM, SLA |

**Critical constraints:**
- **Recordings retained 60 days only** (community/account creation date), then permanently deleted → MUST export to our R2/YouTube within window
- **Transcript download = Enterprise-only**
- **NPO discount: NOT publicly advertised** — must contact sales (pages reference associations/NPOs as use case but no pricing tier)
- **BR-specific pricing:** Not advertised; Indian-headquartered company (Bangalore), USD billing standard. No tax-residency advantage for BR contracts.

User complaints (G2/Capterra recurring themes):
- **Lifetime deals revoked** mid-2024 → trust signal NEGATIVE for long-term commitments
- Mobile app weak for hosts
- "Pricing changes unpredictable" → flag for contract terms
- Customer service degradation for early adopters

---

## PMI Latam usage signals

**Source:** Airmeet's own published case study (https://www.airmeet.com/hub/case-study/pmi-latam/).

- **Started:** March 2020 (Premium Webinars plan)
- **Upgraded:** October 2020 to **2000-attendee license**
- **Flagship event:** Monthly "PMI Portunol" — single event reaching all **19 countries** in shared language (ES/PT bridge)
- **Changemakers Initiative:** Multi-format (keynote + panel + multi-speaker), parallel tracks in different regional languages **simultaneously**
- **Quality signals:** "HD audio/video, lag-free streams"; "intuitive, browser-based no-download"; engagement features (chat, Q&A, emoji) cited as key

**Validation:** Confirms PMI Latam is **deeply integrated, multi-year customer**. Translation: Núcleo proposing ANY integration with Airmeet has institutional precedent — Natália Tavares' team will recognize the platform name, not raise eyebrows. **This is a credibility booster for the LIM/CPMAI conversation.**

**What we don't know (gaps for diligence):**
- Exact tier PMI Latam pays (likely Enterprise given 2000-attendee + parallel sessions)
- Renewal cycle (lifetime-deal-revocation risk)
- Member satisfaction beyond marketing case study
- Whether Natália's team uses webhooks/API or just the dashboard

**Recommendation for Natália follow-up:** ASK directly: "Vocês exportam attendance via API ou planilha manual? Recordings vão para YouTube ou ficam no Airmeet?" — answer informs our integration depth.

---

## Competitors community-focused (table)

| Tool | API / Webhooks | Pricing 2026 | Multilingue | NPO discount | Status |
|---|---|---|---|---|---|
| **Airmeet** | Yes (REST + webhooks, custom auth) | $167/mo → $18K/yr Enterprise | Via Interprefy add-on | Not advertised | Active, growing concerns on trust |
| **RingCentral Events (ex-Hopin)** | Yes (acquired Hopin's API) | $99/mo Starter → $799/mo Growth → custom Enterprise | Native + add-ons | Limited | **Hopin liquidated UK Feb 2024**; product alive at RingCentral |
| **Bizzabo** | Yes, robust ("Event Experience OS") | Custom (mid-5-figs typical) | Via add-ons | Limited | Strong marketing/registration analytics; enterprise focus |
| **Brella** | Yes | $5K+/event typical | Limited | Some | **AI matchmaking specialist**, NOT streaming — networking-only |
| **Eventify** | Yes (Content API) | $50/mo (multi-event annual) → $249–$1199/event | Limited | Not clear | App-first; community channels native |
| **Sched** | Limited | **Free <50 attendees**; 20% off NPO | No | **Yes (20%)** | Best for schedule mgmt, not full virtual venue |
| **Mighty Networks** | Yes | $39/mo Community → $179/mo Business | Limited | Limited | **Community-first, events secondary** — good for sustained engagement |
| **vFairs** | Yes | $5K+/event typical | Native multilingue | Yes | Trade-show/expo focus |
| **Zoom Events + Webinars** | Yes (mature OAuth API) | $79/mo Webinar 500 → Events tiers | Native interpretation (Zoom Interpretation feature, Zoom Webinars Plus) | **Yes (Zoom for Schools/NPO)** | Industry default; less "engagement", more reliable |
| **Welcome (welcome.app)** | Limited | Custom enterprise | Limited | Limited | High-production studio events; not community |
| **Whova** | Yes | $1.5K–8K/event | Limited | Yes | Conference-focused, mobile app strong |

**Key insight:** Hopin's collapse (Aug 2023 sold to RingCentral, Feb 2024 UK liquidation) **left a market hole** — Airmeet capitalized but is showing trust strain (lifetime-deal revocation). RingCentral Events is the institutional safe-bet but lacks Airmeet's community-engagement DNA.

---

## Recording + certificate workflow

**Airmeet path:**
1. Event ends → recording auto-generated (480p free / 720p paid)
2. **Within 60 days:** Pull download URL via API (`Download Session Recordings`), URL valid 6h → mirror to our R2 or YouTube unlisted
3. Webhook `trigger.session.attendee.joined` fires → ingest into `event_attendance` table → trigger `attendance_threshold` check → auto-issue certificate via existing `issue_certificate` MCP RPC
4. Certificate links back to recording URL (token-gated via our existing flow, NOT Airmeet's expiring URL)

**Critical gotcha:** Recording retention 60 days = HARD deadline. Must build a daily cron `airmeet_recording_mirror` that fetches recently-ended events and mirrors. **If we miss the 60d window, recording is gone forever** — no retrieval, even with paid plan.

**YouTube auto-upload:** No native Airmeet→YouTube upload (only **live RTMP stream during event** to YouTube/FB). Post-event mirror = our responsibility. Pipedream/Zapier integration exists but adds 3rd-party dependency.

**Auto-certificate via attendance threshold:** Already a Núcleo strength (we have `issue_certificate` + `register_attendance` + threshold logic). Webhook → ingest → existing logic handles the rest. Estimated integration: ~2 days dev + 1 day testing.

---

## Multilingue PT/ES/EN simultaneous

**Airmeet itself does NOT provide live translation.** Integration with **Interprefy** (third-party).

**How it works:**
- Airmeet stage shows "Translate" button → modal lets attendee pick target language
- Attendee mutes stage audio, hears translated audio overlay
- Setup: form with event details, source lang, target langs → Interprefy issues private token key → entered in Airmeet event dashboard

**Cost stack (Interprefy):**
- **Platform fee:** $500–$1,000/day "with minimal configuration"
- **Interpreter rates:** Separate, billed by Interprefy or you bring your own
- **AI translation alternative:** Cheaper but lower quality (Wordly, KUDO are competitors)
- Plans bundled hours, valid 12 months — scales with org event volume

**For Núcleo CPMAI Latam (PT/ES, 2 langs, 2h event, 2 sessions):**
- Estimate: **$1,500–$3,000 per event** (platform + 2 interpreters PT↔ES) for a single 2-hour session
- Annual (12 events): **~$25,000–35,000/yr** — material cost line, must be sponsored or chartered budget
- **Cheaper alternative for pilot:** AI-only translation via Wordly (~$300–500/event), lower quality but viable for internal study group format

**Hardware:** None for attendees (browser audio). For interpreters: noise-cancelling headset + stable internet (RSI standard).

---

## Look-alikes (nonprofit/community precedent)

| Org | Platform | Pattern | Lesson for Núcleo |
|---|---|---|---|
| **Toastmasters (Easy-Speak)** | **Zoom Pro** ($150/yr) + Easy-Speak for meeting mgmt | Easy-Speak emails Zoom links, tracks roles, members download recordings before next meeting | Zoom is enough for weekly recurring small-group meetings; meeting MGMT layer (Easy-Speak) is what they pay for, not the venue |
| **Rotary Club** | Zoom + Eventbrite | Mixed — district events on bigger platforms, club meetings on Zoom | Reinforces "Zoom for recurring + bigger platform for flagship" hybrid |
| **CNCF (KubeCon, KubeCrash)** | **Hopin/RingCentral Events** for virtual track + in-person main; sched.com for agenda | Tier their platform stack by event scale | Matches our hybrid recommendation perfectly |
| **DevOpsDays** | Zoom + Streamyard for streaming + Discord for community | Lean stack, community-driven | Validates "best-of-breed > all-in-one" pattern |
| **PMI WDC AI in PM CoP** (Northeastern Arlington) | Zoom Webinars + LinkedIn Live | Zoom default for chapter CoPs across PMI | Matches PMI institutional default — NOT Airmeet for chapter-level |

**Synthesis:** **PMI Latam regional uses Airmeet for flagship/regional reach; PMI chapter-level (incl. WDC, BR chapters) defaults to Zoom.** Núcleo position = chapter-level execution + regional aspiration. Hybrid is the institutionally-aligned posture.

---

## Recommendation Núcleo IA Hub

**HYBRID — keep Zoom default + selectively integrate Airmeet for high-stakes events.**

### Why not full integrate
- Cost (Enterprise $18K+/yr unjustified at current event volume)
- Trust risk (lifetime-deal revocation precedent → contract risk for multi-year roadmap)
- Mobile/host UX gaps (hurts our 60+ volunteers including non-tech)
- 60-day recording retention adds operational complexity for ALL events

### Why not full replace
- Airmeet has real PMI Latam credibility — institutional fit when working WITH PMI Latam (Natália's team) on co-branded events
- Multilingue Interprefy integration is real and proven
- Engagement features (lounges, networking) outclass Zoom for **conference-format** events

### HYBRID architecture (proposed)

| Event class | Platform | Reason |
|---|---|---|
| **Tribe weekly meetings** (4-15 attendees) | Zoom Pro | Cheap, recording flow proven, members familiar |
| **Workgroup sprints + governance** | Zoom Pro | Same |
| **Núcleo monthly webinar** (~50–150) | **Zoom Webinar** ($79/mo) | Token-gated YouTube mirror already works; cert flow already works |
| **CPMAI study groups** | Zoom (pilot) → **Airmeet if multilingue PT/ES needed** | Pilot cheap; upgrade if Latam scale demands |
| **CPMAI Latam multi-country** | **Airmeet + Interprefy** | Multilingue + 19-country reach is Airmeet's exact strength |
| **Detroit Summit / LIM-class** | **Airmeet (Enterprise) co-branded with PMI Latam** | Natália's team already has the license; piggyback |
| **Chapter pilots (PMI-GO/CE diretorias)** | Zoom (default per PMI institutional norm) | Match buyer expectation |

### Integration roadmap (if Hybrid path chosen)

1. **Phase 0 (defer):** Build NOTHING until first concrete CPMAI Latam co-event is calendarized (real demand)
2. **Phase 1 (~4 days dev):** Webhook ingest `attendee.joined` → `event_attendance` table; reuses existing `issue_certificate` flow; daily cron `airmeet_recording_mirror` → YouTube unlisted (within 7d, well within 60d)
3. **Phase 2 (~3 days dev):** Registration sync — push our event registrations TO Airmeet via `Manage Registrations` API (so attendees don't double-register); pull post-event attendance back
4. **Phase 3 (only if volume warrants):** Negotiate Núcleo's own Enterprise license (or NPO sub-license under PMI Latam's Enterprise account if Natália's team agrees — much cheaper)

**Cost ceiling for go/no-go:** If Airmeet quotes >$3,000/yr standalone for Núcleo's volume, **defer and ride PMI Latam's license** for co-branded events only.

### Open questions for Natália meeting

1. Quem opera tecnicamente o Airmeet de PMI Latam? (Tech contact = our integration counterpart)
2. PMI Latam's Airmeet license tier — sub-account possible for Núcleo as institutional partner?
3. Recording exports — fluxo manual ou API automatizada?
4. Interprefy contract — Núcleo pode piggyback ou license separada necessária?

---

## Sources

- [Airmeet Public API Introduction (Knowledge Base)](https://help.airmeet.com/support/solutions/articles/82000467794-airmeet-public-api-introduction)
- [Airmeet Webhooks docs](https://help.airmeet.com/support/solutions/articles/82000878498-airmeet-webhooks)
- [Manage Registrations API](https://help.airmeet.com/support/solutions/articles/82000909769-2-manage-registrations-airmeet-public-api)
- [Event Details API](https://help.airmeet.com/support/solutions/articles/82000909768-1-event-details-airmeet-public-api)
- [Manage Event API](https://help.airmeet.com/support/solutions/articles/82000909770-3-manage-event-airmeet-public-api)
- [Integrations, APIs & Webhooks folder](https://help.airmeet.com/support/solutions/folders/82000404934)
- [Airmeet Power Automate connector](https://help.airmeet.com/support/solutions/articles/82000879966-integrate-airmeet-with-power-automate)
- [Airmeet Microsoft Connectors](https://learn.microsoft.com/en-us/connectors/airmeet/)
- [Airmeet Pricing (official)](https://www.airmeet.com/hub/pricing/)
- [Airmeet Pricing on TrustRadius](https://www.trustradius.com/products/airmeet/pricing)
- [Airmeet Pricing on G2](https://www.g2.com/products/airmeet-virtual-events-webinar-platform/pricing)
- [Airmeet Pricing on Capterra](https://www.capterra.com/p/204793/Airmeet/pricing/)
- [Airmeet plans Knowledge Base](https://help.airmeet.com/support/solutions/articles/82000453871-what-are-airmeet-plans-and-pricing-)
- [Airmeet Reviews G2](https://www.g2.com/products/airmeet-virtual-events-webinar-platform/reviews)
- [Airmeet Reviews Capterra](https://www.capterra.com/p/204793/Airmeet/reviews/)
- [PMI Latam Case Study (Airmeet)](https://www.airmeet.com/hub/case-study/pmi-latam/)
- [PMI Latam Programs site](https://pmilatam.com/)
- [PMI Latam Eventos (PT-BR)](https://www.pmi.org/america-latina/eventos)
- [Set up Multi-Language Interpretation on Airmeet via Interprefy](https://help.airmeet.com/support/solutions/articles/82000660138-set-up-multi-language-interpretation-on-airmeet-via-interprefy)
- [Interprefy Pricing](https://www.interprefy.com/pricing)
- [Interprefy RSI cost comparison](https://www.interprefy.com/resources/blog/how-much-does-remote-simultaneous-interpretation-rsi-cost)
- [Interprefy online events translation cost](https://www.interprefy.com/resources/blog/online-events-with-live-language-translation-options-and-cost)
- [Airmeet recording access](https://help.airmeet.com/support/solutions/articles/82000443239-how-to-access-session-recording-for-an-airmeet-event-)
- [Airmeet recording 60-day retention](https://help.airmeet.com/support/solutions/articles/82000476705-are-the-sessions-recorded-where-can-i-access-these-)
- [Airmeet transcripts download (Enterprise)](https://help.airmeet.com/support/solutions/articles/82000910084-how-to-view-download-transcripts-for-your-airmeet-session-)
- [Hopin → RingCentral acquisition (TechCrunch)](https://techcrunch.com/2023/08/02/hopin-ringcentral/)
- [Hopin's collapse analysis](https://www.headcountcoffee.com/blogs/corporate-legends-lost-empires/the-collapse-of-hopin-how-a-virtual-event-unicorn-imploded-post-pandemic)
- [RingCentral Events (formerly Hopin)](https://www.ringcentral.com/rc-events.html)
- [Brella vs Hopin](https://www.brella.io/brella-vs-hopin)
- [Best Hopin Alternatives (Airmeet's own list)](https://www.airmeet.com/hub/hopin-alternative/)
- [Eventify Pricing](https://eventify.io/pricing)
- [Mighty Networks as Hopin alternative](https://www.mightynetworks.com/resources/hopin-alternatives)
- [Sched (NPO 20% discount)](https://sched.com/blog/hopin-alternative/)
- [Best Nonprofit Virtual Event Platforms](https://sourceforge.net/software/virtual-event-platforms/for-nonprofit/)
- [Airmeet for Associations & NPOs (marketing page)](https://www.airmeet.com/hub/associations-and-not-for-profit-organizations/)
- [Toastmasters Easy-Speak Zoom integration](https://easy-speak.org/kb.php?mode=article&k=286)
- [CNCF Hopin usage example (KubeCrash)](https://community.cncf.io/events/details/cncf-cloud-native-silicon-valley-presents-kubecrash-a-free-virtual-day-of-cloud-native-talks/)
- [Zoom Webinars Plus & Events API](https://developers.zoom.us/docs/api/rest/zoom-events-api/)
- [Compare Zoom Events vs Airmeet (Capterra)](https://www.capterra.com/compare/157062-204793/Zoom-Video-Webinar-vs-Airmeet)
- [Switch to Airmeet from Zoom (Airmeet's own page)](https://www.airmeet.com/hub/airmeet-vs-zoom/)
- [Virtual Event Platform Comparison Guide 2025 (Airmeet)](https://www.airmeet.com/hub/blog/the-ultimate-virtual-event-platform-comparison-guide-2025/)
- [Top 10 Brella Alternatives 2026 (G2)](https://www.g2.com/products/brella/competitors/alternatives)
- [Best Bizzabo Alternatives (Whova)](https://whova.com/blog/bizzabo-alternatives/)
