# Research — PMI chapter mgmt best practices + look-alikes (Wave 2 / p134 Ω-A)

**Date:** 2026-05-09
**Author:** research-agent (general-purpose, Wave 2 council review)
**Scope:** Inform Núcleo IA Hub feature roadmap pilot PMI-CE/GO (vertical PMIS/SaaS pra PMI chapters)
**Method:** WebSearch + WebFetch (10 queries, 2 PDF fetches blocked by image-only encoding — substituídos por chapter-page fetches)

---

## TL;DR (5 lines)

1. **PMI Global gives chapters a policy floor (Charter Renewal Policy 2024) but no integrated platform** — Annual Operating Plan (AOP) + Annual Financial Statement due via email/PDF; per-VP plan template enforced bottom-up by chapters themselves. Núcleo IA Hub already replaces this surface with structured workflows.
2. **Big sister orgs converged on consolidated digital portals**: Toastmasters → Pathways/Base Camp (2024 rebuild); Rotary → My Rotary + DACdb/ClubRunner (3rd-party licensees, $0 to clubs); Lions → Lion Portal (replacing MyLCI/MyLion 2025-2026). All include officer training, member lifecycle, event mgmt, financial reporting.
3. **AMS market is $2.97B in 2026** (+13.9% YoY). Wild Apricot ($60-900/mo), Higher Logic (enterprise $$$$), Mighty Networks ($41+/mo), Bevy ($49-$1000+/mo), ClubExpress (multi-tier chapter-friendly). Dominant feature set: portal + events + payments + comms + workflows.
4. **AI integration in 2026**: predictive analytics + workflow automation + auto-segmentation as table stakes in mature AMS. Frontiers/PMI Journal hardening AI disclosure rules (April 2026 Frontiers guidance, double-blind preserved). Volunteer mgmt sees AI matching + gamification + virtual experiences as growth drivers.
5. **Núcleo IA Hub gap vs sister orgs**: leads on AI-native + governance (V4 + can()) + LGPD; lags on member-portal polish, mobile app, payments, multi-language scale (vs Rotary 20 langs). Sweet spot pilot PMI-CE/GO = exploit lead, defer mobile/payments to phase 2.

---

## PMI Chapter Operations Standards (oficial)

### Source documents identified
- **Chapter Management and Charter Renewal Policy (29-Jul-2024)** — official PMI Global policy. URL: pmi.org governance PDF.
- **Creating Your Chapter's Annual Plan** — LIM breakout deck. URL: pmi.org LIM presentation deck.
- Both PDFs are image-only (scanned slides), so verbatim extraction was blocked. Content below derived from chapter pages citing the policy + secondary AMS literature.

### Chapter Operating Standard (per official policy + chapter implementations)
- **Annual Operating Budget** must be developed and forwarded to the Board of Directors as part of the **annual application for charter renewal**.
- **Annual Financial Statement** on chapter activities must be submitted to the Board **by December 1 of each year**.
- **Per-VP Annual Plans** — every functional VP (Membership, Programs, Professional Development, Marketing, Operations, Applied PM) prepares a portfolio-specific annual plan submitted to Chapter President + Board for approval. Chapters universally adopt this pattern (PMI Dallas, PMI Chicagoland, PMI Cyprus, PMI-SAC, PMI Maine, PMI Rochester all publish it).
- **Officer terms** — most chapters: 1 to 2 year terms with required succession (President-elect → President → Past-President pattern).

### Reporting cadence to PMI Global
| Item | Cadence | Format observed |
|------|---------|-----------------|
| Officer roster | Annually | Online portal (chapter management system, low-tech) |
| Charter renewal application | Annually | Email/PDF + AOP + budget |
| Annual Financial Statement | Annually (Dec 1) | PDF |
| Member roster (sync) | Continuous via PMI Global membership database | API/feed |
| Event reporting | Ad-hoc | Not standardized |

### KPIs PMI Global tracks per chapter (inferred from chapter compass + LIM decks)
- Member growth (net new members)
- Member retention (% renewing)
- Member NPS / satisfaction
- Event count + attendance
- Volunteer count
- Financial health (reserves, dues collection rate)
- Charter compliance (filings on time)
- Awards / recognition (Chapter of the Year tiers)

---

## PMI publications guidelines (Frontiers + Knowledge Hub)

### Project Management Journal (PMI flagship)
- **Double-blind peer review** mandated.
- Submission requires affidavit: not under consideration elsewhere, not previously published, no copyright on portions.
- Editorial team runs **plagiarism + self-plagiarism checks** via software.
- AI-specific 2026 rules: not yet codified by PMI Journal in publicly visible form (search returned no specific 2026 PMI AI policy update — likely behind member portal or via direct editor contact).

### Frontiers (PMI publishes via Frontiers ecosystem when applicable)
- **April 2026 — Frontiers AI Guidance launched** (covers researchers, editors, reviewers). Beyond simple "allowed/not allowed" → practical adoption pathways.
- **AI authorship: prohibited.** Cannot be listed as author or take accountability.
- **AI-generated images: prohibited.** No AI-created figures, illustrations, or visualizations.
- **AI use must be disclosed** in dedicated section of manuscript template.
- **All co-authors verify accuracy** including AI-assisted sections.
- **Reviewers using AI must declare** while preserving confidentiality + integrity.
- Workflow: independent review (~7 days) → interactive review forum (where AI concerns are surfaced).

### PMI Knowledge Hub + ProjectManagement.com
- Members access standards free for download.
- Volunteer-driven content contribution model: webinars, articles, templates.
- 2026 calls open for PMI Global Summit Series presentation submissions.
- PMBOK 8th Edition release marketed as "data-driven + community-informed" (48,000 data points).

---

## Look-alikes feature comparison (mega-table)

| Org / Platform | Member portal | Events | Volunteer mgmt | Financial / Payments | Officer training | License / Pricing |
|----------------|---------------|--------|----------------|----------------------|------------------|-------------------|
| **Toastmasters Pathways + Base Camp** | Yes (rebuilt Oct 2024) — mobile, auto level submissions | Easy-Speak (open source, GPL-style volunteer maintained) handles agenda + roles + reminders + attendance | Built-in role sign-up (Toastmaster, Speaker, Timer, Evaluator…) + auto reminders | Dues via TI HQ | Mandatory Pathways "Introduction to Toastmasters Mentoring" Level 2 of every Path; District-sponsored Club Officer Training | Pathways = TI proprietary; Easy-Speak = community/open-source supplement |
| **Rotary My Rotary + Club Central** | Yes — central database + per-member profile | DACdb / ClubRunner (most popular 3rd-party) with attendance, registration, bulletins | Project mgmt + committees inside DACdb | Foundation reporting + dues via My Rotary | Rotary Learning Center (1,000+ courses, 20+ langs) — virtual badges + leaderboards | DACdb: districts pay, clubs $0; ClubRunner: per-club subscription |
| **Lions LCI / Lion Portal** | Yes — new Lion Portal (consolidates MyLion + MyLCI + Insights) | MyLCI service activity reporting | Built-in service project taxonomy | LCIF donation history + online statements | Online statement + reporting tools | Free to clubs (LCI funded) |
| **Wild Apricot** | Yes — built for nonprofits/associations | Live events + registration | Basic | Dues + payments + invoicing automated | Limited (no full LMS) | $60/mo (100 members) → $900/mo (50K contacts) |
| **Higher Logic Vanilla** | Yes — community + Thrive subscription mgmt | Yes | Yes | Yes (subscription/dues integration) | Yes (LMS-adjacent) | Enterprise — thousands $$/month |
| **Mighty Networks** | Yes — all-in-one community + courses + content + commerce | Native virtual events + live streaming | Limited | Native commerce | Course-style training built-in | $41+/mo |
| **Bevy** | Yes — chapter mgmt + groups + analytics + AI | Virtual / hybrid / in-person + auto check-ins + live streaming + closed captioning | Group Organizer Tools | Limited | Limited | Starter $49/mo (events+discussions); Pro $1,000+/mo (community hub + analytics) |
| **ClubExpress** | Yes | Yes (registration + payments) | Yes (committees, forums, document libraries) | Multi-tier chapter/district/region sync; payments via Stripe/PayPal | Limited | Mid-tier paid (per-club subscription) |
| **Mobilize (Bonterra)** | Yes (volunteer-centric) | Event/shift planning | Deep volunteer mgmt — recruiting, scheduling, dashboards | Integrated with Bonterra fundraising | Limited | Bonterra suite pricing |
| **YourMembership** | Yes — CRM + community + polls/surveys | Customizable event registration | Limited | Auto-renewal + invoicing + e-commerce + donations | Limited | Enterprise paid |
| **Núcleo IA Hub (current)** | Yes — Astro v6 + Supabase | Webinars + tribe events + agenda smart | Selection cycles + onboarding + offboarding + 53 RPC tools | Partner pipeline + (no native dues yet) | Curator track + Pathway-style certifications + Credly | Open-platform (multi-client by design — see project_chapter_pmis_saas_vision_p133.md) |

---

## Best practice by chapter function

### Voluntariado (Volunteer Management)
**Best practice (sister orgs + nonprofit research):**
- **5-phase lifecycle**: Recruitment → Onboarding → Engagement → Retention → Evaluation.
- **Onboarding within 48h** of sign-up (welcome message + impact story, NOT liability paperwork first).
- **Quality training reduces churn 83%** (Volunteerhub stat).
- **5 pillars**: compliance, clarification, culture, connection, confidence.
- **Tooling pattern**: Toastmasters auto-assigns roles via Easy-Speak → reminders → attendance auto-credit. Mobilize is the canonical volunteer-mgmt deep platform.

**Núcleo current**: ARM (auto-recruitment / pre-onboarding leaderboard), selection cycles with interview pipeline + scores, gamification + Credly badges. **Lead position.**

### Membros (Membership Lifecycle)
**Best practice:**
- **States to track**: Prospect → Applicant → Active → Honorary → Alumni → (re-engaged) → Inactive.
- **DACdb model**: explicit Active/Honorary/Alumni/Interact/Rotaract/Guests/Prospects categories with cross-state migration tooling.
- **Auto-renewal + dues automation** is the #1 retention lever for AMS platforms.
- **Per-member self-service portal** baseline (every sister org).

**Núcleo current**: V4 engagements model (ADR-0006), persons + members bridge, alumni re-engagement pipeline, offboarding records. **Lead structurally; lag on dues/payments.**

### Eventos / Treinamento
**Best practice:**
- **Recurring meeting agenda automation** (Easy-Speak gold standard for Toastmasters-style; DACdb for Rotary).
- **Attendance tracking** with auto-reminders + role accountability.
- **Hybrid/virtual + auto check-ins + closed captioning** (Bevy 2025-2026 baseline).
- **Officer + member training tied to platform progress** (Pathways model — completion auto-flows to Club Central).
- **1,000+ course library** (Rotary Learning Center bench).

**Núcleo current**: webinars source-of-truth (ADR), tribe events, attendance ranking, agenda smart, action items, meeting notes. **Lead on AI-assist + governance.**

### Marketing / Comms
**Best practice:**
- **Multi-channel**: email newsletters + bulletins + texts + social media auto-distribution.
- **Templates + scheduling**: ClubRunner ezBulletin one-click distribution.
- **PMail + PText** (DACdb) for segmented push.
- **Storytelling repository**: Rotary Showcase pattern — public storytelling with metrics.

**Núcleo current**: comms dashboard, comms metrics by channel, comms pipeline, hub announcements. **Parity-to-lead.**

### Financeiro
**Best practice:**
- **Annual budget approval workflow** with multi-signatory + audit trail (per PMI Charter Renewal).
- **Online statements + dues collection** (Lions, Wild Apricot, ClubExpress).
- **Payment processing native** (Stripe/PayPal/credit cards) — table stakes 2026.
- **Donations + e-commerce** (YourMembership, Mighty Networks).

**Núcleo current**: partner pipeline + interactions + audit log; **no native dues/payments**. **Major gap vs commercial AMS** — but PMI chapters in BR currently use bank transfer + PIX + manual reconciliation, so gap = future-state, not blocker for pilot.

### Comitês (Ética / Auditoria / Conselho)
**Best practice:**
- **PMI Ethics Review Committee** model: 15 volunteer members, 3-year term, complaint intake → triage by Staff Liaison + ERC Chair → formal review.
- **Informal chapter-level resolution preferred** before escalating to PMI Global.
- **PMI Code of Ethics**: transparency, fairness, conflict-of-interest disclosure, NDAs.
- **Audit committee separate from finance** (governance hygiene).
- **Advisory board** — most chapters have non-voting senior advisors, formal terms.

**Núcleo current**: governance change log, decision log, ratification chains v2.7, signature workflows. **Lead on workflow; lag on dedicated ethics intake form / advisory board UX.**

---

## AI integration trends 2026

| Trend | Adoption signal | Núcleo position |
|-------|-----------------|-----------------|
| **AI member matching** (mentor ↔ mentee, volunteer ↔ project) | Volunteerhub, Galaxy Digital flag as 2026 must-have | Partial (cv_extracted_text + ARM pre-screen) |
| **AI workflow automation** (auto-segment, predictive churn) | AMS ($2.97B market) baseline 2026 | Strong (cron triggers, MCP 284 tools) |
| **AI-assisted content (with disclosure)** | Frontiers Apr-2026 guidance live | Aligned (LGPD-ready disclosure surface) |
| **Gamification + virtual experience** | Mighty Networks, Bevy, Rotary Learning Center badges | Strong (XP, leaderboards, Credly) |
| **RAG over knowledge base** | LangChain/LlamaIndex production pattern (LangGraph 35-50% gain @ +200-400ms latency) | Strong (search_knowledge, wiki FTS, 4 prompts + 3 resources) |
| **AI peer review aids** | Frontiers most reviewers now use AI; policy keeping up | Open opportunity (PMI Frontiers PT-BR market gap) |
| **Conversational chatbot for member queries** | EdTech case: 40% admin-time reduction (LangGraph student progress agent) | Strong (MCP server with 284 tools, claude.ai connector) |

---

## Gap analysis Núcleo IA Hub vs best practices

### Where Núcleo leads
1. **AI-native architecture** — MCP server (284 tools), 3-tier council, RAG-ready knowledge layer. None of the sister orgs have this.
2. **Governance + ratification chains** — V4 authority model + can() + ratification workflow are more rigorous than DACdb/ClubRunner committee modules.
3. **LGPD compliance** — Art. 18 cycle complete (consent + export + delete + anon cron 5y). Sister orgs have GDPR but BR-specific gaps.
4. **Selection / recruitment funnel** — ARM cycle3 / cycle4 is more sophisticated than Toastmasters/Rotary recruiting (which are "show up at meeting" model).
5. **Multi-client by design** — confirmed p133 (project_multi_client_architecture_principle.md). Pilot PMI-CE/GO ready.
6. **Wiki + knowledge integration** — public + private wiki, FTS, structured for LLM retrieval. Better than PMI ProjectManagement.com user-contributed model.

### Where Núcleo lags
1. **Mobile app** — every sister org has dedicated mobile (Pathways Oct-2024 mobile, Lion Portal mobile, Mighty Networks app). Núcleo is responsive web only.
2. **Payments / dues automation** — no native payment processor. AMS table stakes.
3. **Multi-language scale** — Núcleo trilingual (PT/EN/ES); Rotary Learning Center has 20+ languages.
4. **Community discussions / forums** — Higher Logic + Mighty Networks + Bevy all have forum-as-core. Núcleo only has cards/comments.
5. **External dispatch volume** — Resend 5 req/s cap (sediment p92) limits bulk comms vs ClubRunner ezBulletin one-click model.
6. **Public marketplace / showcase** — Rotary Showcase storytelling model with public metrics not yet matched.
7. **Officer succession + bylaws automation** — chapters today use Word docs; sister orgs don't fully automate either, but PMI Global is starting to push toward digital-native governance.

---

## Recommendation Núcleo IA Hub roadmap (priority by chapter function, pilot PMI-CE/GO lens)

### Tier 1 — Pilot must-have (próximos 60 dias)
1. **Diretoria-scoped session** — multi-client pilot enablement. Already strategic anchor (p133). Wave A.
2. **AOP / per-VP plan workflow** — replicate the per-VP annual plan submission pattern (PMI Dallas / Cyprus / SAC observed). Use existing initiatives + cards model + ratification chain. Adds 1 view + RPC.
3. **Annual financial statement template** — PDF export of partner+events+budget for Dec 1 deadline.
4. **Charter renewal checklist** — calendar-driven, with ratification gate for President sign-off.
5. **Ethics intake form** — model on PMI ERC pattern, 1 form + workflow → audit log + decision log.
6. **Officer roster export** — PMI Global submission format (CSV with name, role, term).

### Tier 2 — Quick wins (60-180 dias)
1. **Member self-service portal completeness** — every Pathways/Lion Portal/My Rotary has full self-service. Audit Núcleo gaps (profile completeness, attendance history, certificates, ratifications).
2. **Newsletter templates + scheduled distribution** — emulate ezBulletin/PMail.
3. **Public chapter dashboard** — Rotary Showcase pattern. Public metrics: members, events, certifications, impact.
4. **Mobile-first PWA** — defer native app, ship PWA + offline cache.
5. **Volunteer matching AI** — feed cv_extracted_text + member designations into LLM matcher → suggest committee placement.

### Tier 3 — Strategic (180+ dias, post-pilot)
1. **Native dues/payments** — Stripe/PIX. Required only when chapters charge dues platform-wide.
2. **Community discussion forum** — only if pilot users request; risk of becoming WhatsApp v2.
3. **PMI Global integration** — real API push of officer roster + member sync (currently file-based).
4. **Detroit + LIM + CPMAI multi-país events** — international event mgmt edge cases.
5. **AI peer review assist for PMI Frontiers PT-BR pipeline** — capture Frontiers Apr-2026 disclosure rules in workflow; offer chapter-published peer review.

### Anti-recommendations (do NOT build)
- **Native LMS** — Pathways/Rotary Learning Center are mature; partner with PMI Global instead.
- **Native video conferencing** — Zoom/Meet integration is enough; Bevy goes too deep.
- **Custom wiki engine** — already on Obsidian + GitHub sync; don't reinvent.
- **Membership site competing with Wild Apricot** — wrong layer; Núcleo is the *governance + AI* layer above the AMS.

---

## Sources

### PMI official
- [PMI Chapter Management & Charter Renewal Policy (Jul 2024)](https://www.pmi.org/-/media/pmi/documents/public/pdf/governance/chapter-management-and-charter-renewal-policy---final_29july2024.pdf)
- [Creating Your Chapter's Annual Plan (LIM deck)](https://www.pmi.org/-/media/pmi/documents/public/pdf/lim/breakout-presentation-decks/creating-your-chapters-annual-plan.pdf)
- [PMI Standards & Publications](https://www.pmi.org/standards)
- [PMI Strategic Plan 2021-2025](https://www.pmi.org/leadership-central/-/media/c82deb743a6742fdbd1ba553d1357bae.ashx)
- [PMI Want to Form a New Chapter](https://www.pmi.org/membership/chapters/formation)
- [PMI Code of Ethics & Professional Conduct](https://www.pmi.org/about/ethics)
- [PMI Ethics Case Procedures v4.0](https://www.pmi.org/-/media/pmi/documents/public/pdf/ethics/ethics-complaints/ethics-case-procedures.pdf)
- [PMI Ethics Complaint Form](https://www.pmi.org/-/media/pmi/documents/public/pdf/ethics/ethics-complaints/ethics-complaint-form.pdf?la=en)
- [Project Management Journal Submissions](https://www.pmi.org/learning/project-management-journal/submissions)
- [Project Management Journal Author Guidelines (Sage)](https://journals.sagepub.com/author-instructions/pmx)
- [ProjectManagement.com — Contribute Content](https://www.projectmanagement.com/pages/192846/contribute-content-to-projectmanagement-com)
- [PMI Cyprus Chapter Board Structure Policy](https://www.pmi.org/-/media/pmi/chapters/cyprus/pdf/pmi-cyprus-chapter-board-structure-policy.pdf)

### PMI chapters (per-VP plan + role examples)
- [PMI Dallas — Board Roles & Responsibilities](https://pmidallas.org/Board_Roles_and_Responsibilities)
- [PMI Maine — Board Roles & Responsibilities](https://pmimaine.org/Board_Roles_and_Responsibilities)
- [PMI Puget Sound — Officers, Roles & Responsibilities](https://pugetsoundpmi.org/Officers_Roles_and_Responsibilities)
- [PMI Chicagoland — Executive Board Roles](https://pmichicagoland.org/executiveboardroles)
- [PMI Lakeshore — Position Guides](https://pmiloc.org/Position_Guides)
- [PMI Central Illinois — Board Responsibilities](https://pmi-cic.org/Board_Responsibilities)
- [PMI-SAC — VP Operations](https://pmisac.com/documents/vp-operations-roles-responsibilities/)
- [PMI Rochester — Board Roles](https://www.pmirochester.org/board-of-directors-roles-responsibilities)
- [PMI Quad City — Policies & Procedures](https://pmiqc.org/Policies_and_Procedures)

### Toastmasters
- [Toastmasters Pathways — Achievements & Awards](https://www.toastmasters.org/Education/Pathways/Achievements%20and%20Awards)
- [Club Officer Guide to 2025 Pathways Enhancements](https://content.toastmasters.org/image/upload/club-officer-guide-to-2025-pathways-enhancements.pdf)
- [Toastmasters Europe — easySPEAK overview](https://www.toastmasterseurope.org/what-is-easyspeak/)
- [easy-Speak Home](https://easy-speak.org/)
- [easy-Speak Application Overview](https://easy-speak.org/kb.php?mode=article&k=9)
- [Pathways Mentor Program — D4](https://www.d4tm.org/toastmasters-pathways/pathways-mentor-program)
- [Pathways Mentor Program — D42](https://d42tm.org/pathways-mentor-program/)

### Rotary
- [DACdb Home](https://www.dacdb.org/)
- [DACdb Features](https://www.dacdb.org/features/)
- [Rotary Online Learning Center — Article](https://www.rotary.org/en/our-world-stay-connected-through-rotarys-online-learning-center)
- [Discover the Rotary Learning Center: 1,000+ Courses](https://elevaterotary.org/rotary-learning-center/)
- [Service Project Center](https://spc.rotary.org/)
- [ClubRunner — Rotary](https://site.clubrunner.ca/page/rotary)
- [ClubRunner — Members & Contacts](https://site.clubrunner.ca/page/members-contacts)

### Lions
- [Lion Portal Resources (LCI)](https://www.lionsclubs.org/en/resources-for-members/digital-products/portal-updates)
- [Service Reporting (LCI)](https://www.lionsclubs.org/en/member-resource-center/service/resources/service-journey/service-reporting)
- [Membership Reports Toolbox (LCI)](https://www.lionsclubs.org/en/resources-for-members/resource-center/membership-report-toolbox)
- [Online Statements (LCI)](https://www.lionsclubs.org/en/resources-for-members/online-statements)
- [Multiple District 19 Secretary's Handbook 2025-2026](https://lionsmd19.org/downloads/secretary-manual.pdf)

### AMS / Community platforms
- [Wild Apricot Alternatives 2026 (Mighty Networks)](https://www.mightynetworks.com/resources/wild-apricot-alternatives)
- [Mighty Networks vs Higher Logic 2025](https://www.mightynetworks.com/resources/mighty-networks-vs-higher-logic)
- [Top Community Management Software 2026 Buyers Guide](https://www.mightynetworks.com/resources/community-management-software)
- [Bevy Home](https://bevy.com/)
- [Bevy G2 Reviews](https://www.g2.com/products/bevy/reviews)
- [Bevy Pricing (Capterra)](https://www.capterra.com/p/185978/Bevy/)
- [Mobilize Platform Features](https://join.mobilize.us/platform/)
- [Mobilize / Bonterra](https://www.bonterratech.com/product/mobilize)
- [21 Best AMS for 2026 (Protech)](https://protechassociates.com/association-answers/association-management-software/)
- [Top 20+ AMS Picks 2026 (Fonteva)](https://fonteva.com/best-association-management-software/)
- [Best AMS 2026 (Capterra)](https://www.capterra.com/association-management-software/)
- [ClubExpress 2026 Profile (Software Advice)](https://www.softwareadvice.com/nonprofit/clubexpress-profile/)
- [YourMembership vs ClubExpress (GetApp)](https://www.getapp.com/customer-management-software/a/yourmembership-com/compare/clubexpress/)
- [15 Best Membership Mgmt Software for Nonprofits (Neon One)](https://neonone.com/resources/blog/best-membership-management-software-nonprofits-neo/)

### Volunteer mgmt + AI trends
- [Funraise — Nonprofit Volunteer Management Guide 2026](https://www.funraise.org/blog/getting-the-most-out-of-your-nonprofits-volunteers)
- [Volunteer Trends 2026 (Momentive)](https://momentivesoftware.com/blog/volunteer-trends/)
- [Volunteer Engagement 2025 → 2026 (Nonprofit Learning Lab)](https://www.nonprofitlearninglab.org/post/volunteer-engagement-in-2025-how-to-plan-for-2026)
- [Volunteer Onboarding for Retention (VolunteerHub)](https://volunteerhub.com/blog/how-to-build-a-volunteer-onboarding-process-that-improves-retention)
- [The Definitive Handbook for Volunteer Management 2026 (Galaxy Digital)](https://www.galaxydigital.com/blog/volunteer-management)

### AI publishing + RAG frameworks
- [Frontiers AI Practical Guidance Apr-2026](https://www.frontiersin.org/news/2026/04/13/frontiers-launches-unique-ai-practical-guidance-for-researchers-editors-and)
- [Frontiers AI Author Guidelines](https://www.frontiersin.org/journals/artificial-intelligence/for-authors/author-guidelines)
- [Most peer reviewers now use AI (Frontiers Dec-2025)](https://www.frontiersin.org/news/2025/12/15/most-peer-reviewers-now-use-ai-and-publishing-policy-must-keep-pace)
- [Frontiers in Immunology AI Policy 2026 (Manusights)](https://manusights.com/blog/frontiers-in-immunology-ai-policy)
- [LangChain vs LlamaIndex 2026 (DasRoot)](https://dasroot.net/posts/2026/01/langchain-vs-llamaindex-llm-framework-2026/)
- [Production RAG 2026 (Kolekar)](https://rahulkolekar.com/production-rag-in-2026-langchain-vs-llamaindex/)
- [LLM Frameworks Compared 2026 (Morph)](https://www.morphllm.com/llm-frameworks)
