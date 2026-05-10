# Ω-A Sweep — i18n Extraction Report (Páginas Públicas)

**Sessão:** p134 Ω-A trilingue Fase A+B públicas
**Scope:** páginas dentro de `src/pages/` (excluindo `admin/`, `api/`, `en/`, `es/`, `oauth/`, `.well-known/`, `404.astro`) + components compartilhados.
**Audience target:** liderança PMI international (LATAM + USA) — site precisa funcionar trilingue sem context loss.

> **Caveat metodológico:** scan baseado em leitura amostral de pages de alto tráfego + grep dirigido. Não é exaustivo linha-por-linha em arquivos de 1500+ linhas (ex.: `attendance.astro` 1500+, `profile.astro` 1833). Strings em scripts client-side dinâmicos (alerts, fallbacks PT-only após `||`, toast messages) podem ter sido perdidas em algumas das pages mais densas.

---

## Sumário Executivo

- **Total pages auditadas:** 45 (pages root + sub-dirs públicos)
- **Pages clean (zero hardcoded user-facing):** ~20 (delegam tudo para sections/components ou usam i18n consistente)
- **Pages com hardcoded:** 25 — variando de 1-3 strings (presentations, certificates) a 30+ (profile, onboarding, gamification, settings/notifications)
- **Total strings hardcoded encontradas (amostradas):** ~280-330 (em ~25 pages + components compartilhados)
- **Total i18n keys propostas:** ~180 únicas (algumas reutilizam keys existentes)
- **Pages 100% PT-only sem nenhum t():** 2 críticas — `governance/glossario.astro`, `settings/notifications.astro`
- **Pages com inline lang dictionaries (anti-pattern leve):** 5 — `about.astro`, `meetings.astro`, `pmi-onboarding/[token].astro`, `interview-booking/[token].astro`, `library.astro` (parcial)
- **Components compartilhados com hardcoded:** Nav (2 strings), AnnouncementBanner (1 + special-case PT→EN/ES), CpmaiSection (1)

### Distribuição por urgência

| Urgência | Quantidade | Exemplos |
|---|---|---|
| **Critical (showstopper trilingue)** | 5 pages | `governance/glossario.astro`, `settings/notifications.astro`, `onboarding.astro`, profile inline maps PT-only, `teams.astro` |
| **High (visible to PMI international)** | 10 pages | `profile.astro`, `attendance.astro`, `gamification.astro`, `workspace.astro`, `governance/my-pending.astro`, `presentations.astro`, `publications.astro`, `boards.astro`, `notifications.astro`, `verify/[code].astro` |
| **Medium (edge cases / minor strings)** | 10 pages | `blog/index.astro`, `blog/[slug].astro`, `volunteer-agreement.astro`, `cpmai.astro`, `interview-booking/[token].astro`, `pmi-onboarding/[token].astro`, `stakeholder.astro`, `publications/submissions.astro`, `initiative/[id].astro` (only title), `tribe/[id].astro` (only title) |

---

## Tabela detalhada (por página)

### 1. `src/pages/onboarding.astro` — Critical (PT structure inline)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 10 | `'Boas-vindas'` (phase title) | `onboarding.phase.welcome` | `'Welcome'` | `'Bienvenida'` |
| 22 | `'Dica: Reserve 15 minutos para preencher com calma. As respostas ajudam na sua alocação.'` | `onboarding.step1.tip` | `'Tip: Reserve 15 minutes to fill it out calmly. Answers help with your allocation.'` | `'Consejo: Reserva 15 minutos para completarlo con calma. Las respuestas ayudan en tu asignación.'` |
| 32 | `'Aguarde até 48h para confirmação. Verifique sua pasta de spam.'` | `onboarding.step2.tip` | `'Wait up to 48h for confirmation. Check your spam folder.'` | `'Espera hasta 48h para la confirmación. Revisa tu carpeta de spam.'` |
| 38 | `'Configuração'` (phase title) | `onboarding.phase.setup` | `'Setup'` | `'Configuración'` |
| 47 | `'Dica: Use o mesmo email...'` | `onboarding.step3.tip` | `'Tip: Use the same email used for registration. If you have issues, reach the WhatsApp group.'` | `'Consejo: Usa el mismo email del registro. Si tienes problemas, escribe al grupo de WhatsApp.'` |
| 56 | `'Adicione foto profissional e LinkedIn...'` | `onboarding.step4.tip` | `'Add a professional photo and LinkedIn. These boost your profile visibility.'` | `'Agrega foto profesional y LinkedIn. Esos datos ayudan en la visibilidad de tu perfil.'` |
| 62 | `'Integração'` (phase title) | `onboarding.phase.engage` | `'Engagement'` | `'Integración'` |
| 74 | `'Dica: Veja a descrição de cada tribo...'` | `onboarding.step5.tip` | `'Tip: Read each tribe description and choose by primary research interest.'` | `'Consejo: Lee la descripción de cada tribu y elige según tu interés principal de investigación.'` |
| 84 | `'Configure seu perfil Credly para sincronizar badges...'` | `onboarding.step6.tip` | `'Set up your Credly profile to auto-sync badges with gamification.'` | `'Configura tu perfil Credly para sincronizar badges automáticamente con la gamificación.'` |
| 90 | `'Produção'` (phase title) | `onboarding.phase.produce` | `'Production'` | `'Producción'` |
| 99 | `'As reuniões de tribo acontecem semanalmente. Sua presença conta pontos na gamificação!'` | `onboarding.step7.tip` | `'Tribe meetings happen weekly. Your attendance earns gamification points!'` | `'Las reuniones de tribu son semanales. Tu asistencia suma puntos en la gamificación.'` |
| 108 | `'Comece com um resumo de artigo ou framework...'` | `onboarding.step8.tip` | `'Start with an article summary or framework. Approved publications earn XP.'` | `'Empieza con un resumen de artículo o framework. Las publicaciones aprobadas suman XP.'` |
| 127 | `'Seu Progresso'` | `onboarding.progressLabel` | `'Your Progress'` | `'Tu Progreso'` |
| 128 | `'etapas'` | `onboarding.stepsLabel` | `'steps'` | `'pasos'` |
| 165 | `Fase ${pi+1} de ${phases.length}` | `onboarding.phaseLabel` (template `'Phase {n} of {total}'`) | `'Phase {n} of {total}'` | `'Fase {n} de {total}'` |
| 215 | `'✓ Marcar como concluído'` | `onboarding.markDone` | `'✓ Mark as done'` | `'✓ Marcar como hecho'` |
| 219 | `'Desfazer'` | `onboarding.undo` | `'Undo'` | `'Deshacer'` |
| 234 | `'Parabéns! Onboarding Completo!'` | `onboarding.completionTitle` | `'Congratulations! Onboarding Complete!'` | `'¡Felicitaciones! ¡Onboarding Completo!'` |
| 235 | `'Você completou todas as etapas...'` | `onboarding.completionDesc` | `'You completed all steps. Now contribute to your tribe!'` | `'Completaste todos los pasos. ¡Ahora contribuye con tu tribu!'` |
| 237 | `'Ver Gamificação'` | `onboarding.viewGamification` | `'View Gamification'` | `'Ver Gamificación'` |
| 397 | `'dias restantes'` | `onboarding.daysLeft` | `'days left'` | `'días restantes'` |

### 2. `src/pages/governance/glossario.astro` — Critical (100% PT, hardcoded `lang="pt-BR"`)

**Major issue:** página fixa em `lang="pt-BR"` (linha 59), ignora language switch. Conteúdo dinâmico (HTML extraído da Política) é PT-only por design (governance docs originais), mas chrome/labels devem ser i18n.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 59 | `lang="pt-BR"` (hardcoded) | usar `lang` prop dinâmico | n/a (refactor) | n/a (refactor) |
| 63 | `'Glossário Canônico'` | `glossario.title` | `'Canonical Glossary'` | `'Glosario Canónico'` |
| 66 | `'Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos'` | `glossario.subtitle` | `'AI & Project Management Study and Research Hub'` | `'Núcleo de Estudios e Investigación en IA y Gestión de Proyectos'` |
| 69 | `'AI & PM Study and Research Hub'` (italic) | n/a (canonical EN brand — keep) | (keep) | (keep) |
| 74 | `'📖 Espelho dinâmico da Cláusula 13...'` | `glossario.banner` | `'📖 Dynamic mirror of Clause 13 of the Publication & IP Policy. This page updates automatically when a new policy version is locked. In case of interpretive divergence, the official Policy text prevails (Clause 13.5).'` | `'📖 Espejo dinámico de la Cláusula 13 de la Política de Publicación y PI. Esta página se actualiza automáticamente cuando una nueva versión de la Política se sella. En caso de divergencia interpretativa, prevalece el texto oficial de la Política (Cláusula 13.5).'` |
| 83 | `'O glossário será publicado a partir da próxima versão...'` | `glossario.notYetLocked` | `'The glossary will be published from the next locked version of the Policy. Currently under curator review.'` | `'El glosario se publicará a partir de la próxima versión sellada de la Política. Actualmente en revisión por curadores.'` |
| 93 | `'Versão'` (label) | `glossario.versionLabel` | `'Version'` | `'Versión'` |
| 95 | `'✅ Vigente · Lacrada'` / `'⏳ Em revisão · Draft pendente curadoria'` | `glossario.statusLocked` / `glossario.statusDraft` | `'✅ Current · Locked'` / `'⏳ Under review · Draft pending curation'` | `'✅ Vigente · Sellada'` / `'⏳ En revisión · Borrador pendiente curaduría'` |
| 96 | `' em '` (date connector) | `glossario.lockedOn` | `' on '` | `' el '` |
| 101 | `'Versão lacrada vigente: ... Existe draft em revisão pendente: ...'` | `glossario.draftBanner` (with `{currentVersion}`/`{draftVersion}`) | `'Current locked version: {currentVersion}. There is a pending draft under review: {draftVersion}.'` | `'Versión sellada vigente: {currentVersion}. Existe un borrador en revisión pendiente: {draftVersion}.'` |
| 115 | `'⏳ Visualizar próxima versão em revisão'` | `glossario.viewDraftSummary` | `'⏳ Preview next version under review'` | `'⏳ Ver próxima versión en revisión'` |
| 119 | `'Este conteúdo está em revisão pelos curadores...'` | `glossario.draftWarning` | `'This content is under curator review and not yet ratified. In case of divergence, the locked version above prevails.'` | `'Este contenido está en revisión por los curadores y aún no ha sido ratificado. En caso de divergencia, prevalece la versión sellada arriba.'` |
| 134 | `'Histórico de versões da Política'` | `glossario.history` | `'Policy version history'` | `'Historial de versiones de la Política'` |
| 140 | `'✅ Lacrada'` / `'⏳ Draft'` | `glossario.lockedShort` / `glossario.draftShort` | `'✅ Locked'` / `'⏳ Draft'` | `'✅ Sellada'` / `'⏳ Borrador'` |
| 141 | `'(vigente)'` | `glossario.currentTag` | `'(current)'` | `'(vigente)'` |
| 152 | `'Política de Publicação e Propriedade Intelectual completa: '` | `glossario.fullPolicy` | `'Full Publication & Intellectual Property Policy: '` | `'Política de Publicación y Propiedad Intelectual completa: '` |
| 153 | `'acesso restrito a curadores via plataforma'` | `glossario.restrictedAccess` | `'curator-only access via platform'` | `'acceso restringido a curadores vía plataforma'` |
| 156 | `'Núcleo IA & GP — projeto voluntário interinstitucional sediado em PMI Goiás (PMI-GO).'` | `glossario.footer` | `'Núcleo IA & GP — interinstitutional volunteer project hosted at PMI Goiás (PMI-GO).'` | `'Núcleo IA & GP — proyecto voluntario interinstitucional con sede en PMI Goiás (PMI-GO).'` |

### 3. `src/pages/settings/notifications.astro` — Critical (100% PT-only, no `t()` at all)

**Major issue:** zero i18n. Todas labels, descriptions, buttons em PT inline. Deve ser refatorada de cima.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 8 | title `'Preferências de Notificação — Núcleo IA'` | `settings.notifications.metaTitle` | `'Notification Preferences — Núcleo IA'` | `'Preferencias de Notificación — Núcleo IA'` |
| 10 | `'Preferências de Notificação'` | `settings.notifications.heading` | `'Notification Preferences'` | `'Preferencias de Notificación'` |
| 11-13 | `'Controle como você recebe comunicações... aos sábados (12:00 UTC / 09:00 BRT).'` | `settings.notifications.intro` | `'Control how you receive platform communications. By default, we group everything in a weekly digest on Saturdays (12:00 UTC / 09:00 BRT).'` | `'Controla cómo recibes las comunicaciones de la plataforma. Por defecto, agrupamos todo en un resumen semanal los sábados (12:00 UTC / 09:00 BRT).'` |
| 16 | `'Carregando preferências…'` | `settings.notifications.loading` | `'Loading preferences…'` | `'Cargando preferencias…'` |
| 20 | `'Modo de entrega'` | `settings.notifications.deliveryMode` | `'Delivery mode'` | `'Modo de entrega'` |
| 21 | `'Escolha como receber emails de notificação:'` | `settings.notifications.deliveryDesc` | `'Choose how to receive notification emails:'` | `'Elige cómo recibir correos de notificación:'` |
| 25 | `'Resumo semanal'` | `settings.notifications.modeWeekly` | `'Weekly digest'` | `'Resumen semanal'` |
| 27 | `'(Padrão) Receba 1 email consolidado aos sábados...'` | `settings.notifications.modeWeeklyDesc` | `'(Default) Receive 1 consolidated email on Saturdays with cards, events, publications, and governance from the week.'` | `'(Por defecto) Recibe 1 correo consolidado los sábados con tarjetas, eventos, publicaciones y gobernanza de la semana.'` |
| 33 | `'Receber tudo imediato'` | `settings.notifications.modeImmediate` | `'Receive everything immediately'` | `'Recibir todo inmediato'` |
| 35 | `'Cada notificação vira um email separado...'` | `settings.notifications.modeImmediateDesc` | `'Each notification becomes a separate email (high frequency — typically 5-10 emails/week).'` | `'Cada notificación se convierte en un correo separado (alta frecuencia — típicamente 5-10 correos/semana).'` |
| 41 | `'Apenas in-app (sem emails)'` | `settings.notifications.modeSuppress` | `'In-app only (no emails)'` | `'Solo in-app (sin correos)'` |
| 43 | `'Não receba nenhum email...'` | `settings.notifications.modeSuppressDesc` | `'Receive no emails. Notifications stay only on the platform.'` | `'No recibas ningún correo. Las notificaciones quedan solo en la plataforma.'` |
| 49 | `'Personalizado por tipo'` | `settings.notifications.modeCustom` | `'Custom per type'` | `'Personalizado por tipo'` |
| 51 | `'(Em breve — W3) Configure cada tipo de notificação separadamente.'` | `settings.notifications.modeCustomDesc` | `'(Coming soon — W3) Configure each notification type separately.'` | `'(Próximamente — W3) Configura cada tipo de notificación por separado.'` |
| 57 | `'Resumo semanal'` (section heading) | `settings.notifications.weeklyDigestSection` | `'Weekly digest'` | `'Resumen semanal'` |
| 60 | `'Receber resumo semanal aos sábados'` | `settings.notifications.weeklyDigestLabel` | `'Receive weekly digest on Saturdays'` | `'Recibir resumen semanal los sábados'` |
| 62-64 | `'Desmarcar pula o resumo mesmo no modo "Resumo semanal"...'` | `settings.notifications.weeklyDigestHint` | `'Unchecking skips the digest even in "Weekly digest" mode. Useful if you want NO emails but want to keep default mode for re-enabling later.'` | `'Desmarcar omite el resumen incluso en modo "Resumen semanal". Útil si no quieres recibir NADA por correo pero mantienes el modo por defecto para cuando reactives.'` |
| 67 | `'Salvar preferências'` | `settings.notifications.saveBtn` | `'Save preferences'` | `'Guardar preferencias'` |
| 71 | `'Silenciar tipos específicos (W3)'` | `settings.notifications.muteSection` | `'Mute specific types (W3)'` | `'Silenciar tipos específicos (W3)'` |
| 72-75 | `'Marque tipos de notificação que você NÃO quer receber por email...'` | `settings.notifications.muteHint` | `'Mark notification types you do NOT want to receive by email. Useful even in "Weekly digest" mode — these types will be excluded from the digest.'` | `'Marca los tipos de notificación que NO quieres recibir por correo. Útil incluso en modo "Resumen semanal" — esos tipos se excluirán del resumen.'` |
| 77 | `'Salvar tipos silenciados'` | `settings.notifications.saveMutedBtn` | `'Save muted types'` | `'Guardar tipos silenciados'` |

### 4. `src/pages/profile.astro` — High (1833 lines, lots of inline maps)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 177 | `'Campos obrigatórios pendentes: '` | `profile.requiredFieldsPending` | `'Required fields pending: '` | `'Campos obligatorios pendientes: '` |
| 220 | fallback `'Líder de Comunicação'` | use `t('profile.oprole.commsLeader', lang)` (key existe) | `'Comms Leader'` | `'Líder de Comunicación'` |
| 222 | fallbacks `'Alumni'` / `'Observador'` | `profile.oprole.alumni` / `profile.oprole.observer` | `'Alumni'` / `'Observer'` | `'Alumni'` / `'Observador'` |
| 230 | fallbacks `'Comms Leader'` / `'Comms Member'` | already PT/EN; need ES | n/a | `'Comms Leader'` / `'Comms Member'` (or `'Líder Comms'` / `'Miembro Comms'`) |
| 335, 408 | `'Could not load cycle history. Some data may be incomplete.'` (toast) | `profile.toast.loadCycleHistoryError` | (already EN) | `'No se pudo cargar el historial de ciclos. Algunos datos pueden estar incompletos.'` |
| 477-484 | `fieldLabels = { pmi_id: 'PMI ID', phone: 'Telefone', address: 'Endereço', city: 'Cidade', state: 'Estado', country: 'País', birth_date: 'Data de Aniversário' }` | usar keys existentes (`profile.field.*`) ou novas (`profile.fieldLabel.address`, `profile.fieldLabel.birthDate` etc.) | EN equivalents | ES equivalents (`'Dirección'`, `'Ciudad'`, `'Estado'`, `'País'`, `'Fecha de Cumpleaños'`) |
| 495 | `'✏️ Preencher'` (button label override) | `profile.fillBtn` | `'✏️ Fill in'` | `'✏️ Completar'` |
| 713 | fallback `'GP — visão global de todas as tribos'` | `profile.week.gpGlobal` | `'GP — global view of all tribes'` | `'GP — visión global de todas las tribus'` |
| 720 | fallback `'?'` (day name) | n/a (defensive) | (keep) | (keep) |
| 728 | `'restantes'` em `daysLeft + 'd restantes'` | `profile.daysLeft` (template `'{n}d left'`) | `'{n}d left'` | `'{n}d restantes'` |
| 775 | fallback `'Ver entregas no Admin'` | `profile.week.viewDeliverablesAdmin` | `'View deliverables in Admin'` | `'Ver entregas en Admin'` |
| 907 | fallback `'Membro'` | already covered by `profile.defaultName` | (keep) | (keep) |
| 928 | `'—'` (chapter fallback) | n/a | (keep) | (keep) |
| 1005 | `<label>Nome</label>` | `profile.nameLabel` | `'Name'` | `'Nombre'` |
| 1054 | `'PMI-CPMAI™'` | n/a (brand) | (keep) | (keep) |
| 1066 | `'(opcional — preenche endereço automaticamente)'` | `profile.cepHint` | `'(optional — auto-fills address)'` | `'(opcional — completa la dirección automáticamente)'` |
| 1075 | `'Endereço'` | `profile.fieldLabel.address` | `'Address'` | `'Dirección'` |
| 1076 | `'(usado apenas no Termo de Voluntariado · LGPD)'` | `profile.addressHint` | `'(used only in the Volunteer Agreement · LGPD)'` | `'(usado solo en el Acuerdo de Voluntariado · LGPD)'` |
| 1078 | placeholder `'Rua, número, complemento, bairro'` | `profile.addressPlaceholder` | `'Street, number, complement, district'` | `'Calle, número, complemento, barrio'` |
| 1083 | `'Cidade'` | `profile.fieldLabel.city` | `'City'` | `'Ciudad'` |
| 1084 | placeholder `'Ex: Goiânia'` | `profile.cityPlaceholder` | `'e.g. Goiânia'` | `'Ej: Goiânia'` |
| 1088 | `'Estado'` | `profile.fieldLabel.state` | `'State'` | `'Estado'` |
| 1089 | placeholder `'Ex: GO, SP, CE'` | `profile.statePlaceholder` | `'e.g. GO, SP, CE'` | `'Ej: GO, SP, CE'` |
| 1093 | `'País'` | `profile.fieldLabel.country` | `'Country'` | `'País'` |
| 1094 | placeholder `'Ex: Brasil'` | `profile.countryPlaceholder` | `'e.g. Brazil'` | `'Ej: Brasil'` |
| 1100 | `'Data de Aniversário'` | `profile.fieldLabel.birthDate` | `'Birthday'` | `'Fecha de Cumpleaños'` |
| 1101 | `'(dd/mm — sem ano, LGPD)'` | `profile.birthDateHint` | `'(dd/mm — no year, LGPD)'` | `'(dd/mm — sin año, LGPD)'` |
| 1103 | placeholder `'dd/mm (ex: 24/07)'` | `profile.birthDatePlaceholder` | `'dd/mm (e.g. 24/07)'` | `'dd/mm (ej: 24/07)'` |
| 1109 | `'🔒 Preferências de Privacidade (LGPD)'` | `profile.privacyTitle` | `'🔒 Privacy Preferences (LGPD)'` | `'🔒 Preferencias de Privacidad (LGPD)'` |
| 1113 | `'Compartilhar meu telefone/WhatsApp com outros membros do Núcleo'` | `profile.shareWhatsappLabel` | `'Share my phone/WhatsApp with other Núcleo members'` | `'Compartir mi teléfono/WhatsApp con otros miembros del Núcleo'` |
| 1117 | `'Compartilhar meu endereço/cidade com outros membros'` + sublabel `'(não recomendado — padrão: privado)'` | `profile.shareAddressLabel` + `profile.shareAddressHint` | `'Share my address/city with other members'` + `'(not recommended — default: private)'` | `'Compartir mi dirección/ciudad con otros miembros'` + `'(no recomendado — por defecto: privado)'` |
| 1121 | `'Compartilhar minha data de aniversário (dd/mm) para felicitações institucionais'` | `profile.shareBirthDateLabel` | `'Share my birthday (dd/mm) for institutional greetings'` | `'Compartir mi fecha de cumpleaños (dd/mm) para felicitaciones institucionales'` |
| 1125-1126 | `'Endereço e telefone são sempre usados no Termo de Voluntariado...'` + link `'Ler Política de Privacidade'` | `profile.privacyDisclaimer` + `profile.readPrivacyPolicy` | `'Address and phone are always used in the Volunteer Agreement. These options control only whether other members can see them on your public profile.'` + `'Read Privacy Policy'` | `'Dirección y teléfono se usan siempre en el Acuerdo de Voluntariado. Estas opciones controlan solo si otros miembros pueden verlos en tu perfil público.'` + `'Leer Política de Privacidad'` |
| 1136 | `'🔒 Email, capítulo, papel e tribo são geridos pelo GP.'` | `profile.gpManagedFields` | `'🔒 Email, chapter, role, and tribe are managed by GP.'` | `'🔒 Email, capítulo, rol y tribu son gestionados por el GP.'` |
| 1141 | `'🔒 Seus Direitos LGPD'` | `profile.lgpdTitle` | `'🔒 Your LGPD Rights'` | `'🔒 Tus Derechos LGPD'` |
| 1142 | `'Exerça seus direitos garantidos pela Lei Geral de Proteção de Dados (Lei 13.709/2018).'` | `profile.lgpdSubtitle` | `'Exercise your rights guaranteed by the Brazilian General Data Protection Law (Law 13,709/2018).'` | `'Ejerce tus derechos garantizados por la Ley General de Protección de Datos brasileña (Ley 13.709/2018).'` |
| 1148 | `'Exportar meus dados'` | `profile.lgpd.exportTitle` | `'Export my data'` | `'Exportar mis datos'` |
| 1149 | `'Baixar JSON com todos os seus dados pessoais e contribuições (portabilidade)'` | `profile.lgpd.exportDesc` | `'Download JSON with all your personal data and contributions (portability)'` | `'Descargar JSON con todos tus datos personales y contribuciones (portabilidad)'` |
| 1156 | `'Política de Privacidade'` | reuse `profile.readPrivacyPolicy` | (above) | (above) |
| 1157 | `'Ler política completa, dados coletados e finalidades'` | `profile.lgpd.privacyDesc` | `'Read full policy, collected data, and purposes'` | `'Leer política completa, datos recopilados y finalidades'` |
| 1164 | `'Apagar meus dados pessoais'` | `profile.lgpd.deleteTitle` | `'Delete my personal data'` | `'Borrar mis datos personales'` |
| 1165 | `'Limpa endereço, telefone, aniversário. Preserva nome, email e histórico de contribuições (Direito ao Esquecimento — irreversível)'` | `profile.lgpd.deleteDesc` | `'Clears address, phone, birthday. Preserves name, email, and contribution history (Right to be Forgotten — irreversible)'` | `'Borra dirección, teléfono, cumpleaños. Preserva nombre, email e historial de contribuciones (Derecho al Olvido — irreversible)'` |
| 1196 | `'Métodos de Login Vinculados'` (fallback) | reuse `profile.linkedProvidersTitle` | `'Linked Login Methods'` | `'Métodos de Inicio de Sesión Vinculados'` |
| 1197 | `'Vincule provedores adicionais para fazer login com qualquer um deles.'` (fallback) | reuse `profile.linkedProvidersDesc` | `'Link additional providers to log in with any of them.'` | `'Vincula proveedores adicionales para iniciar sesión con cualquiera de ellos.'` |
| 1312 | toast `'Foto excede 2MB'` | `profile.toast.photoTooLarge` | `'Photo exceeds 2MB'` | `'La foto excede 2MB'` |
| 1326 | toast `'Foto atualizada!'` | `profile.toast.photoUpdated` | `'Photo updated!'` | `'¡Foto actualizada!'` |
| 1338 | toast `'Max 500KB'` | `profile.toast.signatureTooLarge` | `'Max 500KB'` | `'Máx 500KB'` |
| 1339 | toast `'PNG only'` | `profile.toast.signaturePngOnly` | `'PNG only'` | `'Solo PNG'` |
| 1352 | toast `'Assinatura salva!'` | `profile.toast.signatureSaved` | `'Signature saved!'` | `'¡Firma guardada!'` |
| 1354 | toast `'Erro'` (fallback) | reuse `common.errorGeneric` | `'Error'` | `'Error'` |
| 1366 | toast `'Assinatura removida'` | `profile.toast.signatureRemoved` | `'Signature removed'` | `'Firma eliminada'` |
| 1391 | toast `'Nome precisa ter pelo menos 2 caracteres'` | `profile.toast.nameMinLength` | `'Name must be at least 2 characters'` | `'El nombre debe tener al menos 2 caracteres'` |
| 1517-1522 | confirm prompt block (`'ATENÇÃO: Esta ação é IRREVERSÍVEL.\n\nSerão apagados:\n• Endereço...'`) | `profile.deleteConfirmPrompt` (multiline) | full EN translation | full ES translation |
| 1526 | toast `'Supabase indisponível'` | `profile.toast.supabaseDown` | `'Supabase unavailable'` | `'Supabase no disponible'` |
| 1531 | toast `'Confirmação inválida. Digite o texto exato.'` | `profile.toast.confirmInvalid` | `'Invalid confirmation. Type the exact text.'` | `'Confirmación inválida. Escribe el texto exacto.'` |
| 1535 | toast `'Dados pessoais apagados. A página será recarregada.'` | `profile.toast.dataDeleted` | `'Personal data deleted. The page will reload.'` | `'Datos personales eliminados. La página se recargará.'` |
| 1538 | toast `'Erro ao apagar dados'` | `profile.toast.deleteError` | `'Error deleting data'` | `'Error al borrar datos'` |
| 1544 | toast `'Supabase indisponível'` | reuse `profile.toast.supabaseDown` | (above) | (above) |
| 1557 | toast `'Dados exportados com sucesso'` | `profile.toast.exportSuccess` | `'Data exported successfully'` | `'Datos exportados con éxito'` |
| 1666 | `'⏳ Buscando...'` | `profile.cep.searching` | `'⏳ Searching...'` | `'⏳ Buscando...'` |
| 1671 | `'❌ CEP não encontrado'` | `profile.cep.notFound` | `'❌ CEP not found'` | `'❌ CEP no encontrado'` |
| 1684 | hardcoded `'Brasil'` set on country | n/a (data write — keep) | (keep) | (keep) |
| 1685 | `'✓ Endereço preenchido'` | `profile.cep.filled` | `'✓ Address filled'` | `'✓ Dirección completada'` |
| 1687 | `'❌ Erro ao consultar CEP'` | `profile.cep.error` | `'❌ Error querying CEP'` | `'❌ Error al consultar CEP'` |
| 1702 | `'🔵 Google'`, `'🔷 LinkedIn'`, `'🟦 Microsoft'`, `'📧 Email'` | n/a (provider names — keep) | (keep) | (keep) |
| 1704 | `'Nenhum provedor vinculado'` | `profile.noLinkedProviders` | `'No linked providers'` | `'Ningún proveedor vinculado'` |
| 1728 | alert `'Erro: cliente não inicializado'` | `profile.toast.clientNotReady` | `'Error: client not initialized'` | `'Error: cliente no inicializado'` |
| 1737 | alert `'Erro ao vincular: ' + msg` | `profile.toast.linkError` (template `'Error linking: {msg}'`) | `'Error linking: {msg}'` | `'Error al vincular: {msg}'` |
| 1737 | fallback `'Erro desconhecido'` | reuse `profile.unknownError` (existe) | (above) | (above) |

### 5. `src/pages/teams.astro` — Critical (heavy hardcoded)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 11 | `'Projetos e Frentes'` | `teams.title` | `'Projects and Initiatives'` | `'Proyectos e Iniciativas'` |
| 12 | `'Navegação única de Ativas, Subprojetos operacionais e Legado para consulta histórica.'` | `teams.subtitle` | `'Single navigation for Active, Operational subprojects, and Legacy for historical reference.'` | `'Navegación única de Activas, Subproyectos operativos y Legado para consulta histórica.'` |
| 18 | `'Acesso restrito a membros ativos da plataforma.'` | `teams.accessDenied` | `'Access restricted to active platform members.'` | `'Acceso restringido a miembros activos de la plataforma.'` |
| 23 | `'🟢 Ativas (Pesquisa)'` | `teams.activeSection` | `'🟢 Active (Research)'` | `'🟢 Activas (Investigación)'` |
| 28 | `'⚙️ Subprojetos (Operação)'` | `teams.operationalSection` | `'⚙️ Subprojects (Operations)'` | `'⚙️ Subproyectos (Operaciones)'` |
| 33 | `'🏛️ Legado (Read-only)'` | `teams.legacySection` | `'🏛️ Legacy (Read-only)'` | `'🏛️ Legado (Solo lectura)'` |
| 48 | `'READ ONLY'` | n/a (technical, keep) | (keep) | (keep) |
| 87 | fallback `'Tribo'` | `teams.tribeFallback` (or reuse existing key) | `'Tribe'` | `'Tribu'` |
| 88 | `'Operacional'` / `'Pesquisa'` | `teams.tribeTypeOperational` / `teams.tribeTypeResearch` | `'Operational'` / `'Research'` | `'Operativa'` / `'Investigación'` |
| 121 | fallback `'Pesquisa ativa do ciclo'` | `teams.activeResearchFallback` | `'Active research of the cycle'` | `'Investigación activa del ciclo'` |
| 131 | `'Subprojeto'` / `'Operacional'` | `teams.subprojectLabel` / reuse | `'Subproject'` / `'Operational'` | `'Subproyecto'` / `'Operativa'` |
| 135-137 | `'Piloto (2024)'`, `'Ciclo 1 (2025/1)'`, `'Ciclo 2 (2025/2)'` | use cycle DB labels | (DB-driven; consider `cycle_label` from RPC) | (DB-driven) |
| 145 | `'Sem tribos ativas cadastradas.'` | `teams.emptyActive` | `'No active tribes registered.'` | `'Sin tribus activas registradas.'` |
| 146 | `'Sem subprojetos operacionais cadastrados.'` | `teams.emptyOperational` | `'No operational subprojects registered.'` | `'Sin subproyectos operativos registrados.'` |
| 150 | `'Sem tribos legadas registradas.'` | `teams.emptyLegacy` | `'No legacy tribes registered.'` | `'Sin tribus legadas registradas.'` |

### 6. `src/pages/governance/my-pending.astro` — High (inline gate labels + dates)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 53-64 | `GATE_LABELS = { curator: 'Curador', leader: 'Liderança', leader_awareness: 'Ciência das lideranças', submitter_acceptance: 'Aceite do GP', president_go: 'Presid. PMI-GO', ... }` | reuse `ipagr.gate.*` keys (existem!) | reuse | reuse |
| 73 | `'hoje'`, `'há 1 dia'`, `'há ' + d + ' dias'` | `governance.myPending.today`, `.dayAgo`, `.daysAgo` (template `'{n} days ago'`) | `'today'`, `'1 day ago'`, `'{n} days ago'` | `'hoy'`, `'hace 1 día'`, `'hace {n} días'` |
| 107 | `'Em revisão'` / `'Aprovado'` | reuse `ipagr.sidebar.chainStatus.review` / `.approved` (existem) | reuse | reuse |
| 124 | `'Versão'` (label) | reuse `ipagr.versionLabel` (existe) | reuse | reuse |
| 125 | `' aberta '` (date prefix) | `governance.myPending.openedFor` | `' opened '` | `' abierta '` |
| 129 | `'Revisar e assinar →'` | `governance.myPending.reviewAndSign` | `'Review and sign →'` | `'Revisar y firmar →'` |
| 145 | `'Cliente Supabase indisponível.'` | reuse `profile.toast.supabaseDown` (or `common.supabaseDown`) | `'Supabase client unavailable.'` | `'Cliente Supabase no disponible.'` |
| 161 | `'Erro: ' + msg` | `governance.myPending.errorPrefix` (template `'Error: {msg}'`) | `'Error: {msg}'` | `'Error: {msg}'` |

### 7. `src/pages/about.astro` — Medium (inline lang dictionaries — anti-pattern leve)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 9-13 | inline `titles = { 'pt-BR': 'Sobre o Núcleo — IA & Gerenciamento de Projetos', 'en-US': '...', 'es-LATAM': '...' }` | refactor → `about.metaTitle` | (already EN) | (already ES) |
| 14-18 | inline `descriptions` map | refactor → `about.metaDesc` | (already EN) | (already ES) |
| 31 | hardcoded `"Núcleo de Estudos e Pesquisa em IA & Gerenciamento de Projetos"` (JSON-LD) | n/a (machine-readable schema, keep PT canonical) | (keep) | (keep) |

**Pattern observation:** about, meetings, pmi-onboarding, interview-booking todos usam o mesmo "inline lang dict" anti-pattern. Sugestão: criar helper `getMetaForLang(prefix, lang)` ou migrar para keys i18n consistentes.

### 8. `src/pages/meetings.astro` — Medium (same pattern as about)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 9-13 | `titles` inline map | `meetings.metaTitle` | (already EN) | (already ES) |
| 14-18 | `descriptions` inline map | `meetings.metaDesc` | (already EN) | (already ES) |

### 9. `src/pages/workspace.astro` — High

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 244 | fallback day names `['Dom','Seg','Ter','Qua','Qui','Sex','Sáb']` | already have `common.days.*` keys; ensure JSON bundle includes them | (keys exist) | (keys exist) |
| 417 | fallback `'Dia ' + slot.day_of_week` | `workspace.dayFallback` | `'Day {n}'` | `'Día {n}'` |
| 541 | hardcoded `'CPMAI Prep Course'` (subproject label) | `workspace.subproject.cpmai` | `'CPMAI Prep Course'` (keep) | `'Curso Preparación CPMAI'` |
| 602-606 | `STATUS_PT = { draft: 'rascunho', submitted: 'submetidos', under_review: 'em revisão', revision_requested: 'revisão solicitada', accepted: 'aceitos', rejected: 'rejeitados', published: 'publicados', presented: 'apresentados' }` | reuse `publications.status.*` keys (existem em pt-BR) | reuse | reuse |
| 637 | `aria-label="Dismiss"` | `common.dismiss` (key existe?) ou `workspace.checkinDismiss` | `'Dismiss'` | `'Descartar'` |
| 668, 673, 780 | toast `'Error'` | reuse `common.errorGeneric` | `'Error'` | `'Error'` |
| 728 | template `'${daysLeft}d restantes'` | reuse `profile.daysLeft` (proposto acima) | `'{n}d left'` | `'{n}d restantes'` |

### 10. `src/pages/attendance.astro` — High

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 64 | `'📊 Quadro de Presença'` | `attendance.tabs.grid` | `'📊 Attendance Grid'` | `'📊 Cuadro de Asistencia'` |
| 91 | `<option>Todos os tipos</option>` | reuse `attendance.filterAllTypes` (verificar se existe; senão criar) | `'All types'` | `'Todos los tipos'` |
| 94 | `<option>Todas as Tribos</option>` | reuse `attendance.filterAllTribes` (verificar) | `'All Tribes'` | `'Todas las Tribus'` |
| 98 | placeholder `'🔍 Buscar evento...'` | `attendance.searchEventPlaceholder` | `'🔍 Search event...'` | `'🔍 Buscar evento...'` |

(Pages 1500+ lines; deeper scan needed for full list. Given file size limit, rec: separate dedicated audit pass on attendance.astro with focused script-section read.)

### 11. `src/pages/gamification.astro` — High

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 466 | `value="Certificado de Participação"` (default text) | `gamification.cert.bulkTitleDefault` | `'Certificate of Participation'` | `'Certificado de Participación'` |
| 469 | `<label>Período de</label>` | `gamification.cert.periodFrom` | `'Period from'` | `'Período desde'` |
| 470 | placeholder `'Ciclo 1 (Mai 2024)'` | `gamification.cert.periodFromPlaceholder` | `'Cycle 1 (May 2024)'` | `'Ciclo 1 (May 2024)'` |
| 473 | `<label>Período até</label>` | `gamification.cert.periodTo` | `'Period to'` | `'Período hasta'` |
| 474 | placeholder `'Ciclo 3 (Mar 2026)'` | `gamification.cert.periodToPlaceholder` | `'Cycle 3 (Mar 2026)'` | `'Ciclo 3 (Mar 2026)'` |
| 477 | `<label>Idioma</label>` | `gamification.cert.languageLabel` | `'Language'` | `'Idioma'` |
| 490 | `<option>Todas as tribos</option>` | reuse `gamification.allTribes` ou criar | `'All tribes'` | `'Todas las tribus'` |
| 525 | placeholder `'Buscar...'` | reuse `common.search` (existe) | `'Search'` | `'Buscar'` |

### 12. `src/pages/presentations.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 25 | placeholder `"Buscar apresentacao ou replay"` | `pres.searchPlaceholder` | `'Search presentation or replay'` | `'Buscar presentación o replay'` |
| 154 | `'Geral'` (badge for non-tribe) | `pres.generalBadge` | `'General'` | `'General'` |
| 170 | fallback `'Gravacao'` | reuse `pres.recording` (existe; só falta passar via i18n) | (keep — comes from PI.recording) | (keep) |
| 176 | fallback `'Deliberacoes'` | reuse `pres.deliberations` | (above) | (above) |

### 13. `src/pages/notifications.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 129 | toast `'Todas marcadas como lidas'` | `notifications.toast.allRead` | `'All marked as read'` | `'Todas marcadas como leídas'` |
| 134 | toast `'Erro: ' + msg` | reuse `governance.myPending.errorPrefix` ou `common.errorPrefix` | (above) | (above) |

### 14. `src/pages/blog/index.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 58 | `'Featured'` (badge) | `blog.featuredBadge` | `'Featured'` | `'Destacado'` |
| 64 | `'views'` (count suffix) | `blog.viewsSuffix` | `'views'` | `'vistas'` |

### 15. `src/pages/blog/[slug].astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 81 | template `'${count} views'` | reuse `blog.viewsSuffix` | (above) | (above) |

### 16. `src/pages/publications.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 114 | `<option value="other">Outro</option>` | reuse `publications.target.other` (verify existe) | `'Other'` | `'Otro'` |
| 126 | `<button>Salvar</button>` | reuse `common.save` (existe) | (above) | (above) |
| 138 | `'Governança global'` (badge) | `publications.globalGovernanceBadge` | `'Global governance'` | `'Gobernanza global'` |
| 162 | `'BibTeX'` | n/a (technical name, keep) | (keep) | (keep) |
| 173-176 | `TYPE_LABELS = { article: 'Artigo', framework: 'Framework', toolkit: 'Toolkit', case_study: 'Case Study', webinar_recording: 'Webinar', ebook: 'E-book', podcast: 'Podcast' }` | reuse `publications.type*` keys (parcialmente existem); criar `.typeEbook`, `.typePodcast` se ausentes | EN values | ES values (`'Artículo'`, etc.) |
| 196 | toast `'BibTeX copiado!'` | `publications.bibtexCopied` | `'BibTeX copied!'` | `'¡BibTeX copiado!'` |

### 17. `src/pages/publications/submissions.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 142 | `<option value="zero_cost">Zero cost</option><option value="author">Author</option><option value="chapter">Chapter</option><option value="sponsor">Sponsor</option>` | `publications.cost.zeroCost`, `.author`, `.chapter`, `.sponsor` | (already EN) | `'Costo cero'`, `'Autor'`, `'Capítulo'`, `'Patrocinador'` |
| 147 | `<button>Cancelar</button>` | reuse `common.cancel` (existe) | (above) | (above) |
| 194 | toast `'Preencha título e nome do alvo'` | `publications.toast.fillRequired` | `'Fill in title and target name'` | `'Completa título y nombre del objetivo'` |

### 18. `src/pages/boards.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 43 | `'Global'` (scope badge) | `boards.globalBadge` | `'Global'` | `'Global'` |
| 48 | `'cards'` (count suffix) | `boards.cardsSuffix` | `'cards'` | `'tarjetas'` |
| 50 | fallback `'Board'` | `boards.fallbackName` | `'Board'` | `'Tablero'` |

### 19. `src/pages/volunteer-agreement.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 53 | `'PMI Goiás — Núcleo de Estudos e Pesquisa em IA & GP'` (header brand) | `volunteer.headerBrand` (or refactor to use `t()`) | `'PMI Goiás — AI & PM Study and Research Hub'` | `'PMI Goiás — Núcleo de Estudios e Investigación en IA & GP'` |

### 20. `src/pages/cpmai.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 15 | `'🚀 Area do Participante — acessar dashboard, eventos e materiais →'` | `cpmai.participantAreaCta` | `'🚀 Participant Area — access dashboard, events, and materials →'` | `'🚀 Área del Participante — accede al dashboard, eventos y materiales →'` |

### 21. `src/pages/initiative/[id].astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 73 | title `"Iniciativa"` (hardcoded) | reuse `initiative.pageTitle` (criar se não existe) | `'Initiative'` | `'Iniciativa'` |

### 22. `src/pages/tribe/[id].astro` — Medium

(Most strings via TRIBE_I18N map and components; no major hardcoded user-facing strings detected in initial scan. The `staticFallback` source already i18n-ified per tribe in `src/lib/tribes/catalog.ts`.)

### 23. `src/pages/verify/[code].astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 31 | `'PMI®, PMBOK®, PMP® e PMI-CPMAI™ são marcas registradas do PMI, Inc.'` | `verify.trademarkNotice` | `'PMI®, PMBOK®, PMP®, and PMI-CPMAI™ are registered trademarks of PMI, Inc.'` | `'PMI®, PMBOK®, PMP® y PMI-CPMAI™ son marcas registradas de PMI, Inc.'` |

### 24. `src/pages/pmi-onboarding/[token].astro` — Medium (inline lang dicts pattern)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 39-42 | inline `pageTitle` lang map | `pmi.onboarding.metaTitle` | (already EN) | (already ES) |
| 44-47 | inline `pageDesc` lang map | `pmi.onboarding.metaDesc` | (above) | (above) |
| 55-57 | inline `'Link expirado ou inválido'` lang map | `pmi.onboarding.expiredTitle` | (already EN) | (already ES) |
| 60-62 | inline `'O link de onboarding não é mais válido...'` lang map | `pmi.onboarding.expiredBody` | (above) | (above) |

### 25. `src/pages/interview-booking/[token].astro` — Medium (inline t() with full dicts)

(Has its own local `t()` helper with PT/EN/ES dicts inline lines 48-100+ — already trilingue but fragmented. Recommend migration to global `t()` for consistency.)

### 26. `src/pages/stakeholder.astro` — Medium

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 36 | `title="Fechar"` | reuse `common.close` (existe) | (above) | (above) |

### 27. Other pages — clean or already i18n'd

- `src/pages/index.astro` — clean (delegates to sections)
- `src/pages/library.astro` — fully i18n'd via WORKSPACE_I18N (only minor — emoji literals that aren't translatable)
- `src/pages/governance.astro` — clean (delegates to GovernancePage React component)
- `src/pages/initiatives.astro` — fully i18n'd
- `src/pages/webinars.astro` — fully i18n'd
- `src/pages/help.astro` — i18n'd via DB-driven journeys (some inline `langCode === 'en' ? ... : ...` switches that work but break the `t()` pattern)
- `src/pages/changelog.astro` — fully i18n'd
- `src/pages/projects.astro` — fully i18n'd
- `src/pages/certificates.astro` — fully i18n'd
- `src/pages/privacy.astro` — fully i18n'd (heavy use of S3_ROWS / S6_ROWS table generation)
- `src/pages/me/re-engagement/[id].astro` — fully i18n'd
- `src/pages/minha-candidatura.astro` — fully i18n'd
- `src/pages/docs/mcp.astro` — fully i18n'd (with inline DOMAIN_LABELS jsonb dict + `t()`)
- `src/pages/governance/ip-agreement.astro` — fully i18n'd
- `src/pages/blog/index.astro` — mostly i18n'd (only "Featured" + "views" hardcoded)
- `src/pages/boards/[id].astro` — clean (delegates to BoardEngine)
- `src/pages/report.astro` — clean (delegates to ReportPage React)
- `src/pages/governance/preview.astro` — redirect only
- `src/pages/rank.astro`, `src/pages/ranks.astro`, `src/pages/artifacts.astro` — redirects
- `src/pages/404.astro` — excluded per scope
- (governance/glossario, settings/notifications already covered above)

---

## Components compartilhados

### `src/components/nav/Nav.astro`

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 120 | `tierAdmin: 'Admin'` | `nav.tierAdmin` (criar se não existe) | `'Admin'` | `'Admin'` |
| 121 | `tierSuperadmin: 'Superadmin'` | `nav.tierSuperadmin` | `'Superadmin'` | `'Superadmin'` |

### `src/components/ui/AnnouncementBanner.astro`

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 48-49 | special-case translation `'Entrar na Reunião Geral'` → `'Join General Meeting'` / `'Unirse a la Reunión General'` | refactor to read `announcement.link_text_en` / `link_text_es` from DB (já existe `title_en/es` + `message_en/es`) | n/a | n/a |
| 64 | `title="Fechar"` | reuse `common.close` | (above) | (above) |

### `src/components/sections/CpmaiSection.astro`

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 96 | fallback `'Membro sem nome'` | `cpmai.unnamedMember` | `'Unnamed member'` | `'Miembro sin nombre'` |
| 102 | fallback `'PMI-CPMAI'` | n/a (brand) | (keep) | (keep) |
| 117 | fallback `'Certificado em'` | reuse `profile.cpmaiCertifiedIn` (existe) | (above) | (above) |
| 118 | fallback `'View badge →'` | reuse `cpmai.viewBadge` (já lido via DOM #cpmai-view-text) | (above) | (above) |

### Sample dos sections homepage (não scaneados linha-a-linha — fortemente i18n'd na amostra)

`HomepageHero`, `NucleoSection`, `ChaptersSection`, `PlatformStatsSection`, `QuadrantsSection`, `TribesSection`, `RulesSection`, `KpiSection`, `TrailSection`, `TeamSection`, `VisionSection`, `WeeklyScheduleSection`, `ResourcesSection` — usam `t(... , lang)` consistente. Não detectados hardcoded em scan amostral.

(Recomendação: scan dirigido das sections em sweep posterior se quiser confirmação 100%.)

---

## Pages com maior volume estimado de hardcoded (top 10)

1. **`profile.astro`** — ~50+ strings (formulários, toasts, LGPD, signature, providers)
2. **`onboarding.astro`** — ~25 strings (4 phases × ~6 strings cada + completion)
3. **`gamification.astro`** — ~10 strings (bulk cert section)
4. **`settings/notifications.astro`** — ~20 strings (página inteira PT-only)
5. **`governance/glossario.astro`** — ~15 strings (página inteira PT-only)
6. **`workspace.astro`** — ~10 strings (STATUS_PT map, fallbacks, toasts)
7. **`teams.astro`** — ~12 strings (sections, empty states, role labels)
8. **`governance/my-pending.astro`** — ~13 strings (gate labels + dates)
9. **`publications.astro`** — ~8 strings (TYPE_LABELS, badges, toasts)
10. **`attendance.astro`** — ~5+ strings (parcial — file too large to scan fully)

---

## Duplicações detectadas (mesma string em N+ pages — candidata a key shared)

- `'Carregando...'` / `'Loading...'` — já existe `common.loading`. Ainda usado hardcoded em alguns lugares (recomendado replace inline em `boards.astro` line 36 fallback, etc.)
- `'Salvar'` / `'Save'` — já existe `common.save`. Ainda hardcoded em `publications.astro:126`, `settings/notifications.astro:67,77`, profile (multiple).
- `'Cancelar'` / `'Cancel'` — já existe `common.cancel`. Ainda hardcoded em `publications/submissions.astro:147`.
- `'Fechar'` / `'Close'` — já existe `common.close`. Ainda hardcoded em `stakeholder.astro:36`, `AnnouncementBanner.astro:64`, modal close buttons em vários lugares.
- `'Erro'` / `'Error'` — `common.errorGeneric` existe (`'Ocorreu um erro. Tente novamente.'`); para toast curto criar `common.error` = `'Erro'` / `'Error'` / `'Error'`.
- `'Buscar'` / `'Search'` — já existe `common.search`. Ainda hardcoded em `gamification.astro:525`, `presentations.astro:25`.
- `'Todas as tribos'` / `'All tribes'` — duplicado em `gamification.astro:490`, `attendance.astro:94`. Criar `common.allTribes`.
- `'Todos os tipos'` / `'All types'` — `attendance.astro:91`. Criar `common.allTypes`.
- `'Membros ativos'`, `'tribos'`, `'pesquisadores'` etc. — geralmente já em `hero.stat.*`, `admin.analytics.*`. Verificar antes de criar duplicate.
- Date relative formats (`'hoje'`, `'há X dias'`) — duplicado em `governance/my-pending.astro:73` e potencialmente em `profile.astro:134` (`history.summary`). Criar `common.timeAgo.*`.

---

## Convenção sugerida pra novas keys

### Namespace por feature
- **Por página:** `<page>.* `(ex: `glossario.*`, `teams.*`, `onboarding.*`)
- **Por feature compartilhada:** `<feature>.*` (ex: `profile.*`, `volunteer.*`, `ipagr.*`)
- **Compartilhadas:** `common.*` (ex: `common.loading`, `common.save`, `common.allTribes`)
- **Por componente isolado:** `comp.<componentName>.*` (ex: `comp.kanban.*`, `comp.report.*`)

### Sub-namespacing
- Para grupos relacionados, usar dot notation: `profile.lgpd.exportTitle`, `profile.cep.searching`
- Para fallbacks de role/status: `profile.oprole.*`, `profile.desig.*` (já estabelecido)
- Para toasts: `<page>.toast.*` (ex: `profile.toast.photoUpdated`)

### Templates com placeholders
- Use `{name}` placeholder: `'You have {n} pending items'` → `t(...).replace('{n}', String(n))`
- Pattern já estabelecido no codebase (`{cycle}`, `{year}`, `{count}`, `{matched}`, `{total}`, etc.)

### Datas relativas (sugestão nova)
```
common.time.justNow       → 'agora mesmo' / 'just now' / 'justo ahora'
common.time.minutesAgo    → 'há {n}min' / '{n}min ago' / 'hace {n}min'
common.time.hoursAgo      → 'há {n}h' / '{n}h ago' / 'hace {n}h'
common.time.daysAgo       → 'há {n} dia(s)' / '{n} day(s) ago' / 'hace {n} día(s)'
common.time.today         → 'hoje' / 'today' / 'hoy'
common.time.yesterday     → 'ontem' / 'yesterday' / 'ayer'
```

### Anti-pattern a evitar
- `STATUS_PT = { draft: 'rascunho', ... }` mapas inline PT-only — sempre migrar para `t()` com fallback PT
- Inline lang dicts `{ 'pt-BR': '...', 'en-US': '...', 'es-LATAM': '...' }` em frontmatter Astro — usar `t()` consistente
- `t('key', '')` com fallback vazio — viola convenção (sempre passar PT-BR fallback)

---

## Recomendações de priorização para sweep aplicação

1. **Fase 1 (Critical, vai pra demo PMI international):**
   - `governance/glossario.astro` — refatorar para usar `lang` prop dinâmico + i18n keys
   - `settings/notifications.astro` — refatorar página inteira (atualmente 100% PT)
   - `onboarding.astro` — i18n nas phase labels + tips + completion
   - `teams.astro` — i18n sections + empty states

2. **Fase 2 (High, exposição boards/dashboards):**
   - `profile.astro` — heavy refactor (campos LGPD, signature, toasts) — file 1833 linhas, considerar break em multiple commits
   - `gamification.astro` — bulk cert section
   - `workspace.astro` — STATUS_PT map + day fallback + toasts
   - `governance/my-pending.astro` — reuse `ipagr.gate.*` keys + criar `governance.myPending.*`
   - `attendance.astro` — sweep dedicado (file too large for single scan)
   - `presentations.astro` — search placeholder + general badge
   - `publications.astro` — TYPE_LABELS map + toasts
   - `notifications.astro` — toasts

3. **Fase 3 (Medium, polish):**
   - `about.astro` + `meetings.astro` + `pmi-onboarding/[token].astro` + `interview-booking/[token].astro` — refactor inline lang dicts → consistent `t()` usage
   - `blog/index.astro` + `blog/[slug].astro` — Featured + views suffix
   - `boards.astro` — Global badge + cards suffix
   - `verify/[code].astro` — trademark notice
   - `volunteer-agreement.astro` — header brand
   - `cpmai.astro` — participant area CTA
   - `initiative/[id].astro` — page title
   - `stakeholder.astro` — close button title
   - components: `Nav.astro`, `AnnouncementBanner.astro`, `CpmaiSection.astro`

4. **Verify (need closer scan):**
   - `attendance.astro` (1500+ lines)
   - `profile.astro` (1833 lines) — completar scan da segunda metade
   - `gamification.astro` (>500 lines, scanned partial)
   - sections em `src/components/sections/` — confirmar que zero hardcoded
   - components em `src/components/workspace/`, `src/components/cpmai/`, `src/components/governance/` — não scaneados (delegate de pages que estão clean)

---

## Estimativa de esforço

- **Fase 1 (critical):** ~4-6 horas (4 pages, ~80 strings novas + refactor estrutural de 2 pages PT-only)
- **Fase 2 (high):** ~6-10 horas (10 pages, ~120 strings, sweep focado attendance/profile)
- **Fase 3 (medium):** ~3-5 horas (12 pages, ~30 strings simples)
- **Add to dictionaries:** ~180 keys × 3 línguas = 540 entries em pt-BR/en-US/es-LATAM
- **Test:** `npx astro build` + visual smoke por página em /pt /en /es

---

## Notas de cautela (sediment p124 i18n race conditions)

- **Mesmo após adicionar keys**, garantir que `usePageI18n()` consegue ler — para Astro pages com React islands, o bundle precisa estar em `<script id="page-i18n">` (ver `buildPageI18n(['namespace'], lang)` calls). Várias pages que adicionarão keys novas vão precisar update do `buildPageI18n` array (ex: `governance/my-pending.astro` já carrega `['governance', 'common']` — keys novas em `governance.myPending.*` ficam dentro do namespace existente).
- **Validar fallback PT-BR** em cada `t('key', 'PT-BR fallback')` — convenção já estabelecida (`memory/feedback_t_fallback_must_be_non_empty.md`).
- **NUNCA usar sed em TSX** para substituir strings (`memory/feedback_sed_batch_i18n.md`) — usar Edit tool por linha.
- **Inline lang dictionaries** em `about.astro` / `meetings.astro` / `pmi-onboarding/[token].astro` são "trilingue funcional mas fora do sistema" — refactor é nice-to-have, não bloqueador (já funcionam nas 3 línguas).
- **Pages que carregam DB content jsonb (`title_i18n`, `description_i18n`)** — não tocar; código já lê `[langKey] || ['pt'] || fallback`. Issue só nos chrome/labels.

---

## Próximos passos sugeridos (post-relatório)

1. PM revisa este report + decide priorização (Fase 1 only? ou full Fase 1+2+3?)
2. Para cada página priorizada:
   - Add keys em `pt-BR.ts`, `en-US.ts`, `es-LATAM.ts` (mesmas keys nos 3 dicts — invariante GC-097)
   - Use Edit tool (não sed) para refactor das pages
   - Atualizar `buildPageI18n([...])` arrays se namespace novo
   - Smoke `npx astro build` após cada página
3. Para os 2 cases críticos (`glossario`, `settings/notifications`) — full rewrite estrutural com `lang` prop + `t()` calls; pode envolver atualizar layouts ou helpers.
4. Em commit final, rodar `npm test` (i18n parity test deve passar) e `npx astro build`.
