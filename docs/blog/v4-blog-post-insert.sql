-- Blog post: V4 Domain Model refactor — revised with 3-persona feedback
-- Status: draft (publish after PM review)
-- Run via Supabase MCP execute_sql or psql

INSERT INTO blog_posts (
  slug, title, excerpt, body_html,
  category, tags, status, is_featured,
  author_member_id, published_at, organization_id
)
VALUES (
  'v3-domain-model-v4-plataforma-replicavel',

  -- title (jsonb, UNDER 70 chars each)
  '{"pt-BR": "Como a IA reconstruiu nossa plataforma em 2 dias", "en-US": "How AI rebuilt our platform in 2 days", "es-LATAM": "Cómo la IA reconstruyó nuestra plataforma en 2 días"}'::jsonb,

  -- excerpt (jsonb) — TL;DR for LinkedIn preview + og:description
  '{"pt-BR": "O Núcleo IA & Gerenciamento de Projetos do PMI-GO reconstruiu a arquitetura completa da sua plataforma em parceria com IA. Resultado: permissões baseadas em engajamento real, proteção LGPD por tipo de vínculo, e uma infraestrutura pronta para qualquer capítulo replicar.", "en-US": "The PMI-GO AI & Project Management Research Hub rebuilt its entire platform architecture in partnership with AI. Result: engagement-based permissions, LGPD protection by engagement type, and infrastructure ready for any chapter to replicate.", "es-LATAM": "El Núcleo IA & Gestión de Proyectos del PMI-GO reconstruyó la arquitectura completa de su plataforma en alianza con IA. Resultado: permisos basados en participación real, protección LGPD por tipo de vínculo e infraestructura lista para que cualquier capítulo la replique."}'::jsonb,

  -- body_html (jsonb) — full HTML in 3 languages
  jsonb_build_object(
    'pt-BR', '
<h2>TL;DR</h2>
<ul>
<li><strong>Permissões agora vêm do seu engajamento real</strong> — não de um rótulo fixo atribuído manualmente.</li>
<li><strong>Seus dados pessoais têm proteção diferenciada</strong> por tipo de vínculo, com ciclo LGPD Art. 18 implementado (acesso, exportação, anonimização).</li>
<li><strong>A plataforma está pronta para crescer</strong> — outros capítulos PMI podem rodar sua própria instância na mesma infraestrutura.</li>
</ul>

<h2>Sua plataforma ficou mais flexível</h2>
<p>Se você é pesquisador, líder de tribo ou voluntário do Núcleo IA, a mudança mais importante é simples: <strong>a plataforma agora entende o que você faz, não apenas o cargo que alguém te atribuiu</strong>.</p>
<p>Antes, um "líder de tribo" tinha permissões fixas — mesmo se estivesse afastado ou tivesse mudado de função. Agora, suas permissões derivam automaticamente do seu vínculo ativo: se você lidera a Tribo 3, tem permissão para gerenciar a Tribo 3. Se você sai, a permissão se ajusta. Sem burocracia, sem atraso, sem risco de acesso indevido.</p>

<h2>A história por trás: IA construindo uma plataforma de IA</h2>
<p>Este projeto tem uma particularidade que vale registrar: <strong>a reconstrução arquitetural foi executada em parceria com Claude (Anthropic) via Claude Code</strong>, com a IA atuando como par de programação sob direção de um PM humano.</p>
<p>O PM (Vitor) tomou todas as decisões de arquitetura: quais problemas resolver, qual modelo de domínio adotar, quais trade-offs aceitar, quando pausar para observar regressões. A IA executou: escreveu migrações, criou testes, fez auditorias de consistência, gerou documentação técnica. A cada passo, um agente guardião verificava se as decisões anteriores estavam sendo respeitadas.</p>
<p>O resultado: 16 migrações de banco, 10 tabelas novas, 1.184 testes automatizados — tudo entregue em 2 dias de trabalho intensivo, com a IA como par de programação. Sem a IA, essa escala de refatoração levaria semanas. Mas sem o PM, a IA não saberia o que construir.</p>
<p>Um detalhe importante: entre cada fase do refator, a IA executava uma auditoria automática — um "agente guardião" que verificava se os 1.184 testes continuavam passando, se o build estava limpo, se nenhuma decisão anterior havia sido violada. Esse ciclo de validação contínua é o que permitiu mover rápido sem quebrar nada. É também um padrão que outros times de engenharia podem replicar: decisões humanas, execução assistida, validação automatizada.</p>
<p>É um caso de uso real de IA em gestão de projetos — exatamente o que o Núcleo pesquisa.</p>

<h2>O que mudou para você</h2>
<h3>Antes e depois: um exemplo concreto</h3>
<p><strong>Antes:</strong> Maria era pesquisadora da Tribo 5. Um administrador precisava definir manualmente que ela era "researcher" no sistema. Se ela fosse convidada para ser palestrante em um webinar, alguém precisava mudar o cargo dela — e lembrar de voltar depois.</p>
<p><strong>Depois:</strong> Maria tem um vínculo de pesquisadora na Tribo 5 e outro de palestrante no webinar. Cada vínculo tem suas próprias permissões, base legal LGPD e prazo de retenção de dados. Quando o webinar termina, o vínculo de palestrante expira automaticamente — e com ele, o acesso e a obrigação de reter seus dados.</p>

<h3>Perguntas frequentes</h3>
<ul>
<li><strong>Preciso fazer alguma coisa?</strong> Não. Todos os vínculos foram migrados automaticamente. Se você tinha acesso antes, continua tendo.</li>
<li><strong>Meus dados sobreviveram?</strong> Sim. Nenhum dado foi perdido. Seus certificados, presenças, contribuições — tudo está lá.</li>
<li><strong>A Tribo 3 ainda é a Tribo 3?</strong> Sim. As tribos continuam funcionando como antes. Por baixo, elas agora são "iniciativas" — um conceito mais genérico que permite criar grupos de estudo, congressos e workshops usando a mesma plataforma. Mas no seu dia a dia, nada muda.</li>
<li><strong>E se eu participo de mais de uma tribo?</strong> Agora isso é modelado corretamente. Cada vínculo é independente, com suas próprias permissões e ciclo de vida.</li>
</ul>

<h2>De uma plataforma sob medida para uma plataforma replicável</h2>
<p>O Núcleo IA nasceu como plataforma exclusiva do PMI-GO. Com esta atualização, a infraestrutura técnica está pronta para que outros capítulos PMI operem suas próprias instâncias na mesma base — cada um com seus membros, iniciativas e governança isolados.</p>
<p>É importante ser honesto: <strong>a infraestrutura está pronta, mas ainda não há uma segunda organização operando</strong>. O modelo foi validado com testes de isolamento (uma organização não consegue ver dados da outra), e o design suporta multi-tenancy real. O isolamento é enforçado no nível do banco de dados via políticas RLS restritivas — não é um filtro de aplicação que pode ser contornado.</p>
<p>O modelo também é config-driven: criar um novo tipo de iniciativa (grupo de estudo, congresso, workshop) é preencher um formulário no painel administrativo. Não exige código novo. Pilotos com capítulos interessados são o próximo passo.</p>

<h2>LGPD: implementação técnica sólida, revisão jurídica em andamento</h2>
<p>A plataforma implementa tecnicamente os direitos do Art. 18 da LGPD:</p>
<ul>
<li><strong>Acesso (Art. 18 II):</strong> qualquer membro pode consultar seus dados pessoais.</li>
<li><strong>Exportação (Art. 18 V):</strong> exportação completa em formato estruturado, incluindo pessoa, vínculos e certificados.</li>
<li><strong>Anonimização (Art. 18 IV):</strong> cron mensal aplica anonimização por tipo de vínculo, respeitando o prazo de retenção configurado (30 dias para palestrantes, 2 anos para candidatos, 5 anos para voluntários).</li>
<li><strong>Consentimento (Art. 18 IX):</strong> gate de consentimento na primeira autenticação, com registro de base legal por tipo de vínculo (contrato para voluntários, consentimento para palestrantes, interesse legítimo para contatos de parceiros).</li>
</ul>
<p>A base legal de cada tipo de vínculo está configurada conforme o Art. 7 da LGPD: contrato voluntário (Art. 7 V), consentimento (Art. 7 I) e interesse legítimo (Art. 7 IX). <strong>A revisão jurídica da configuração por tipo de vínculo está em andamento com o DPO do PMI-GO</strong> (Ivan Lourenço Costa), que avaliará se cada combinação de base legal e prazo de retenção está adequada ao contexto específico do Núcleo.</p>

<h2>Para os curiosos: por dentro da arquitetura</h2>
<p><em>Esta seção é técnica. Se você não é de tecnologia, pode pular direto para "O que vem pela frente" sem perder nada.</em></p>

<h3>Decisões de arquitetura (ADRs)</h3>
<p>Cada decisão estrutural foi documentada como um Architecture Decision Record antes da implementação:</p>
<ul>
<li><strong>ADR-0004:</strong> Organizations como entidade first-class — multi-tenancy com isolamento via RLS RESTRICTIVE.</li>
<li><strong>ADR-0005:</strong> Initiative como primitivo de domínio — tribos, grupos de estudo, congressos são "tipos de iniciativa" (config-driven).</li>
<li><strong>ADR-0006:</strong> Person + Engagement — identidade separada de vínculo. Uma pessoa pode ter múltiplos vínculos simultâneos.</li>
<li><strong>ADR-0007:</strong> Authority derivada de engajamento — <code>can(person, action)</code> como gate único. RLS usa helpers <code>rls_can(action)</code>.</li>
<li><strong>ADR-0008:</strong> Lifecycle por tipo de vínculo — retenção LGPD, expiração e anonimização configuráveis por kind.</li>
<li><strong>ADR-0009:</strong> Tipos de iniciativa config-driven — criar um novo tipo = preencher formulário no admin, sem código.</li>
</ul>

<h3>Números da execução</h3>
<ul>
<li>7 fases (0 a 7), cada uma deployável e reversível independentemente</li>
<li>16 migrações de banco aplicadas, todas com rollback documentado</li>
<li>10 tabelas novas: organizations, chapters, initiative_kinds, initiatives, engagement_kinds, persons, engagements, engagement_kind_permissions, auth_engagements (view), initiative_member_progress</li>
<li>40 tabelas existentes receberam <code>organization_id</code> com backfill 100%</li>
<li>13 tabelas receberam <code>initiative_id</code> com dual-write triggers</li>
<li>36 políticas RLS reescritas em 24 tabelas — zero referências diretas a <code>operational_role</code></li>
<li>70 ferramentas MCP (56 leitura + 14 escrita) — 14 gates de escrita migrados para <code>can()</code></li>
<li>1.184 testes automatizados passando, zero falhas</li>
<li>Shadow mode de 48h entre fases críticas, com validação de divergências</li>
</ul>

<h3>Validação de shadow</h3>
<p>O sistema antigo e o novo rodaram em paralelo. Resultado: 70 de 71 membros com resultado idêntico nos dois sistemas. A única divergência: um líder que havia solicitado desligamento ainda tinha permissão no sistema antigo (bug de design — não verificava atividade). O sistema novo negou corretamente o acesso. Melhoria de segurança aprovada pelo PM.</p>

<h2>O que vem pela frente</h2>
<ul>
<li><strong>Congresso CBGPL:</strong> a plataforma vai gerenciar submissões, avaliações e agenda do congresso — usando o mesmo motor de iniciativas.</li>
<li><strong>Grupo de estudos CPMAI:</strong> já migrado para o modelo genérico. Herlon (GP) e Pedro (SME) lideram o grupo do 2º semestre de 2026.</li>
<li><strong>Pilotos multi-org:</strong> capítulos interessados em replicar a plataforma podem entrar em contato.</li>
</ul>

<h2>Quer conhecer?</h2>
<p>A plataforma está em <a href="https://nucleoia.vitormr.dev">nucleoia.vitormr.dev</a>. Se você é de um capítulo PMI e quer explorar o modelo para sua realidade, entre em contato com o Núcleo IA & Gerenciamento de Projetos do PMI-GO.</p>
',

    'en-US', '
<h2>TL;DR</h2>
<ul>
<li><strong>Permissions now come from your actual engagement</strong> — not from a manually assigned fixed label.</li>
<li><strong>Your personal data has differentiated protection</strong> by engagement type, with LGPD Art. 18 cycle implemented (access, export, anonymization).</li>
<li><strong>The platform is ready to scale</strong> — other PMI chapters can run their own instance on the same infrastructure.</li>
</ul>

<h2>Your platform just got more flexible</h2>
<p>If you are a researcher, tribe leader, or volunteer at Nucleo IA, the most important change is simple: <strong>the platform now understands what you do, not just a title someone assigned to you</strong>.</p>
<p>Before, a "tribe leader" had fixed permissions — even if they were on leave or had changed roles. Now, your permissions derive automatically from your active engagement: if you lead Tribe 3, you have permission to manage Tribe 3. If you leave, the permission adjusts. No bureaucracy, no delay, no risk of unauthorized access.</p>

<h2>The story behind it: AI building an AI platform</h2>
<p>This project has a noteworthy aspect: <strong>the architectural rebuild was executed in partnership with Claude (Anthropic) via Claude Code</strong>, with AI acting as a pair programmer under the direction of a human PM.</p>
<p>The PM (Vitor) made every architectural decision: which problems to solve, which domain model to adopt, which trade-offs to accept, when to pause and observe for regressions. The AI executed: wrote migrations, created tests, ran consistency audits, generated technical documentation. At each step, a guardian agent verified that previous decisions were being respected.</p>
<p>The result: 16 database migrations, 10 new tables, 1,184 automated tests — all delivered in 2 days of intensive work, with AI as a pair programmer. Without AI, this scale of refactoring would take weeks. But without the PM, the AI would not know what to build.</p>
<p>One important detail: between each phase of the refactor, the AI ran an automated audit — a "guardian agent" that verified whether all 1,184 tests still passed, whether the build was clean, whether any previous decision had been violated. This continuous validation cycle is what allowed moving fast without breaking anything. It is also a pattern other engineering teams can replicate: human decisions, AI-assisted execution, automated validation.</p>
<p>It is a real-world use case of AI in project management — exactly what the Research Hub studies.</p>

<h2>What changed for you</h2>
<h3>Before and after: a concrete example</h3>
<p><strong>Before:</strong> Maria was a researcher in Tribe 5. An administrator had to manually define her as a "researcher" in the system. If she was invited to speak at a webinar, someone had to change her role — and remember to change it back afterwards.</p>
<p><strong>After:</strong> Maria has a researcher engagement in Tribe 5 and a speaker engagement for the webinar. Each engagement has its own permissions, LGPD legal basis, and data retention period. When the webinar ends, the speaker engagement expires automatically — and with it, the access and the obligation to retain her data.</p>

<h3>Frequently asked questions</h3>
<ul>
<li><strong>Do I need to do anything?</strong> No. All engagements were migrated automatically. If you had access before, you still have it.</li>
<li><strong>Did my data survive?</strong> Yes. No data was lost. Your certificates, attendance records, contributions — everything is there.</li>
<li><strong>Is Tribe 3 still Tribe 3?</strong> Yes. Tribes continue working as before. Under the hood, they are now "initiatives" — a more generic concept that allows creating study groups, congresses, and workshops using the same platform. But in your daily experience, nothing changes.</li>
<li><strong>What if I participate in more than one tribe?</strong> That is now modeled correctly. Each engagement is independent, with its own permissions and lifecycle.</li>
</ul>

<h2>From a bespoke platform to a replicable one</h2>
<p>Nucleo IA was born as a platform exclusive to PMI-GO. With this update, the technical infrastructure is ready for other PMI chapters to operate their own instances on the same foundation — each with their own members, initiatives, and governance, fully isolated.</p>
<p>To be transparent: <strong>the infrastructure is ready, but no second organization is operating yet</strong>. The model was validated with isolation tests (one organization cannot see another''s data), and the design supports real multi-tenancy. Isolation is enforced at the database level via restrictive RLS policies — it is not an application-level filter that can be bypassed.</p>
<p>The model is also config-driven: creating a new initiative type (study group, congress, workshop) means filling out a form in the admin panel. No new code required. Pilots with interested chapters are the next step.</p>

<h2>LGPD: strong technical implementation, legal review in progress</h2>
<p>The platform technically implements LGPD Art. 18 data subject rights:</p>
<ul>
<li><strong>Access (Art. 18 II):</strong> any member can view their personal data.</li>
<li><strong>Export (Art. 18 V):</strong> complete export in structured format, including person, engagements, and certificates.</li>
<li><strong>Anonymization (Art. 18 IV):</strong> monthly cron applies anonymization by engagement type, respecting the configured retention period (30 days for speakers, 2 years for candidates, 5 years for volunteers).</li>
<li><strong>Consent (Art. 18 IX):</strong> consent gate on first authentication, with legal basis recorded per engagement type (contract for volunteers, consent for speakers, legitimate interest for partner contacts).</li>
</ul>
<p>The legal basis for each engagement type is configured per LGPD Art. 7: volunteer contract (Art. 7 V), consent (Art. 7 I), and legitimate interest (Art. 7 IX). <strong>The legal review of per-engagement-type configuration is in progress with the PMI-GO DPO</strong> (Ivan Lourenco Costa), who will assess whether each legal basis and retention period combination is appropriate for the specific context.</p>

<h2>For the curious: inside the architecture</h2>
<p><em>This section is technical. If you are not in tech, feel free to skip ahead to "What''s next" without missing anything.</em></p>

<h3>Architecture Decision Records (ADRs)</h3>
<p>Each structural decision was documented as an ADR before implementation:</p>
<ul>
<li><strong>ADR-0004:</strong> Organizations as a first-class entity — multi-tenancy with RESTRICTIVE RLS isolation.</li>
<li><strong>ADR-0005:</strong> Initiative as the domain primitive — tribes, study groups, congresses are "initiative types" (config-driven).</li>
<li><strong>ADR-0006:</strong> Person + Engagement — identity separated from engagement. One person can have multiple simultaneous engagements.</li>
<li><strong>ADR-0007:</strong> Authority derived from engagement — <code>can(person, action)</code> as the single gate. RLS uses <code>rls_can(action)</code> helpers.</li>
<li><strong>ADR-0008:</strong> Per-type lifecycle — LGPD retention, expiration, and anonymization configurable per engagement kind.</li>
<li><strong>ADR-0009:</strong> Config-driven initiative types — creating a new type means filling out a form in admin, no code required.</li>
</ul>

<h3>Execution numbers</h3>
<ul>
<li>7 phases (0 through 7), each independently deployable and reversible</li>
<li>16 database migrations applied, all with documented rollback</li>
<li>10 new tables: organizations, chapters, initiative_kinds, initiatives, engagement_kinds, persons, engagements, engagement_kind_permissions, auth_engagements (view), initiative_member_progress</li>
<li>40 existing tables received <code>organization_id</code> with 100% backfill</li>
<li>13 tables received <code>initiative_id</code> with dual-write triggers</li>
<li>36 RLS policies rewritten across 24 tables — zero direct references to <code>operational_role</code></li>
<li>70 MCP tools (56 read + 14 write) — 14 write gates migrated to <code>can()</code></li>
<li>1,184 automated tests passing, zero failures</li>
<li>48-hour shadow mode between critical phases, with divergence validation</li>
</ul>

<h3>Shadow validation</h3>
<p>The old and new systems ran in parallel. Result: 70 of 71 members produced identical results in both systems. The single divergence: a leader who had requested departure still had permission in the old system (a design bug — it did not check activity status). The new system correctly denied access. This security improvement was approved by the PM.</p>

<h2>What''s next</h2>
<ul>
<li><strong>CBGPL Congress:</strong> the platform will manage submissions, evaluations, and scheduling — using the same initiative engine.</li>
<li><strong>CPMAI Study Group:</strong> already migrated to the generic model. Herlon (PM) and Pedro (SME) lead the H2 2026 cohort.</li>
<li><strong>Multi-org pilots:</strong> chapters interested in replicating the platform can get in touch.</li>
</ul>

<h2>Want to learn more?</h2>
<p>The platform is at <a href="https://nucleoia.vitormr.dev">nucleoia.vitormr.dev</a>. If you are from a PMI chapter and want to explore the model for your reality, reach out to the AI & Project Management Research Hub at PMI-GO.</p>
',

    'es-LATAM', '
<h2>TL;DR</h2>
<ul>
<li><strong>Los permisos ahora vienen de tu participación real</strong> — no de una etiqueta fija asignada manualmente.</li>
<li><strong>Tus datos personales tienen protección diferenciada</strong> por tipo de vínculo, con el ciclo LGPD Art. 18 implementado (acceso, exportación, anonimización).</li>
<li><strong>La plataforma está lista para crecer</strong> — otros capítulos PMI pueden operar su propia instancia en la misma infraestructura.</li>
</ul>

<h2>Tu plataforma se volvió más flexible</h2>
<p>Si eres investigador, líder de tribu o voluntario del Núcleo IA, el cambio más importante es simple: <strong>la plataforma ahora entiende lo que haces, no solo el cargo que alguien te asignó</strong>.</p>
<p>Antes, un "líder de tribu" tenía permisos fijos — incluso si estaba ausente o había cambiado de función. Ahora, tus permisos se derivan automáticamente de tu vínculo activo: si lideras la Tribu 3, tienes permiso para gestionar la Tribu 3. Si te retiras, el permiso se ajusta. Sin burocracia, sin demora, sin riesgo de acceso indebido.</p>

<h2>La historia detrás: IA construyendo una plataforma de IA</h2>
<p>Este proyecto tiene un aspecto notable: <strong>la reconstrucción arquitectónica fue ejecutada en alianza con Claude (Anthropic) vía Claude Code</strong>, con la IA actuando como par de programación bajo la dirección de un PM humano.</p>
<p>El PM (Vitor) tomó todas las decisiones de arquitectura: qué problemas resolver, qué modelo de dominio adoptar, qué trade-offs aceptar, cuándo pausar para observar regresiones. La IA ejecutó: escribió migraciones, creó tests, realizó auditorías de consistencia, generó documentación técnica. En cada paso, un agente guardián verificaba que las decisiones anteriores estuvieran siendo respetadas.</p>
<p>El resultado: 16 migraciones de base de datos, 10 tablas nuevas, 1.184 tests automatizados — todo entregado en 2 días de trabajo intensivo, con la IA como par de programación. Sin la IA, esta escala de refactorización llevaría semanas. Pero sin el PM, la IA no sabría qué construir.</p>
<p>Un detalle importante: entre cada fase del refactor, la IA ejecutaba una auditoría automática — un "agente guardián" que verificaba si los 1.184 tests seguían pasando, si el build estaba limpio, si alguna decisión anterior había sido violada. Este ciclo de validación continua es lo que permitió avanzar rápido sin romper nada. Es también un patrón que otros equipos de ingeniería pueden replicar: decisiones humanas, ejecución asistida, validación automatizada.</p>
<p>Es un caso de uso real de IA en gestión de proyectos — exactamente lo que el Núcleo investiga.</p>

<h2>Qué cambió para ti</h2>
<h3>Antes y después: un ejemplo concreto</h3>
<p><strong>Antes:</strong> María era investigadora de la Tribu 5. Un administrador necesitaba definir manualmente que ella era "researcher" en el sistema. Si era invitada como ponente en un webinar, alguien tenía que cambiar su rol — y recordar revertirlo después.</p>
<p><strong>Después:</strong> María tiene un vínculo de investigadora en la Tribu 5 y otro de ponente en el webinar. Cada vínculo tiene sus propios permisos, base legal LGPD y plazo de retención de datos. Cuando el webinar termina, el vínculo de ponente expira automáticamente — y con él, el acceso y la obligación de retener sus datos.</p>

<h3>Preguntas frecuentes</h3>
<ul>
<li><strong>¿Necesito hacer algo?</strong> No. Todos los vínculos fueron migrados automáticamente. Si tenías acceso antes, lo sigues teniendo.</li>
<li><strong>¿Mis datos sobrevivieron?</strong> Sí. Ningún dato se perdió. Tus certificados, asistencias, contribuciones — todo sigue ahí.</li>
<li><strong>¿La Tribu 3 sigue siendo la Tribu 3?</strong> Sí. Las tribus siguen funcionando como antes. Por debajo, ahora son "iniciativas" — un concepto más genérico que permite crear grupos de estudio, congresos y talleres usando la misma plataforma. Pero en tu día a día, nada cambia.</li>
<li><strong>¿Y si participo en más de una tribu?</strong> Ahora eso está modelado correctamente. Cada vínculo es independiente, con sus propios permisos y ciclo de vida.</li>
</ul>

<h2>De una plataforma a medida a una replicable</h2>
<p>El Núcleo IA nació como plataforma exclusiva del PMI-GO. Con esta actualización, la infraestructura técnica está lista para que otros capítulos PMI operen sus propias instancias en la misma base — cada uno con sus miembros, iniciativas y gobernanza aislados.</p>
<p>Es importante ser transparente: <strong>la infraestructura está lista, pero aún no hay una segunda organización operando</strong>. El modelo fue validado con pruebas de aislamiento (una organización no puede ver datos de otra), y el diseño soporta multi-tenancy real. El aislamiento se aplica a nivel de base de datos vía políticas RLS restrictivas — no es un filtro de aplicación que pueda ser evitado.</p>
<p>El modelo también es config-driven: crear un nuevo tipo de iniciativa (grupo de estudio, congreso, taller) significa llenar un formulario en el panel de administración. No se requiere código nuevo. Pilotos con capítulos interesados son el próximo paso.</p>

<h2>LGPD: implementación técnica sólida, revisión jurídica en curso</h2>
<p>La plataforma implementa técnicamente los derechos del Art. 18 de la LGPD:</p>
<ul>
<li><strong>Acceso (Art. 18 II):</strong> cualquier miembro puede consultar sus datos personales.</li>
<li><strong>Exportación (Art. 18 V):</strong> exportación completa en formato estructurado, incluyendo persona, vínculos y certificados.</li>
<li><strong>Anonimización (Art. 18 IV):</strong> cron mensual aplica anonimización por tipo de vínculo, respetando el plazo de retención configurado (30 días para ponentes, 2 años para candidatos, 5 años para voluntarios).</li>
<li><strong>Consentimiento (Art. 18 IX):</strong> gate de consentimiento en la primera autenticación, con registro de base legal por tipo de vínculo (contrato para voluntarios, consentimiento para ponentes, interés legítimo para contactos de socios).</li>
</ul>
<p>La base legal de cada tipo de vínculo está configurada conforme al Art. 7 de la LGPD: contrato voluntario (Art. 7 V), consentimiento (Art. 7 I) e interés legítimo (Art. 7 IX). <strong>La revisión jurídica de la configuración por tipo de vínculo está en curso con el DPO del PMI-GO</strong> (Ivan Lourenço Costa), quien evaluará si cada combinación de base legal y plazo de retención es adecuada al contexto específico del Núcleo.</p>

<h2>Para los curiosos: dentro de la arquitectura</h2>
<p><em>Esta sección es técnica. Si no eres de tecnología, puedes saltar directamente a "Qué viene después" sin perderte nada.</em></p>

<h3>Decisiones de arquitectura (ADRs)</h3>
<p>Cada decisión estructural fue documentada como un Architecture Decision Record antes de la implementación:</p>
<ul>
<li><strong>ADR-0004:</strong> Organizations como entidad de primera clase — multi-tenancy con aislamiento vía RLS RESTRICTIVE.</li>
<li><strong>ADR-0005:</strong> Initiative como primitivo de dominio — tribus, grupos de estudio, congresos son "tipos de iniciativa" (config-driven).</li>
<li><strong>ADR-0006:</strong> Person + Engagement — identidad separada de vínculo. Una persona puede tener múltiples vínculos simultáneos.</li>
<li><strong>ADR-0007:</strong> Authority derivada de engagement — <code>can(person, action)</code> como gate único. RLS usa helpers <code>rls_can(action)</code>.</li>
<li><strong>ADR-0008:</strong> Lifecycle por tipo de vínculo — retención LGPD, expiración y anonimización configurables por kind.</li>
<li><strong>ADR-0009:</strong> Tipos de iniciativa config-driven — crear un nuevo tipo significa llenar un formulario en admin, sin código.</li>
</ul>

<h3>Números de la ejecución</h3>
<ul>
<li>7 fases (0 a 7), cada una deployable y reversible de forma independiente</li>
<li>16 migraciones de base de datos aplicadas, todas con rollback documentado</li>
<li>10 tablas nuevas: organizations, chapters, initiative_kinds, initiatives, engagement_kinds, persons, engagements, engagement_kind_permissions, auth_engagements (vista), initiative_member_progress</li>
<li>40 tablas existentes recibieron <code>organization_id</code> con backfill al 100%</li>
<li>13 tablas recibieron <code>initiative_id</code> con triggers de dual-write</li>
<li>36 políticas RLS reescritas en 24 tablas — cero referencias directas a <code>operational_role</code></li>
<li>70 herramientas MCP (56 lectura + 14 escritura) — 14 gates de escritura migrados a <code>can()</code></li>
<li>1.184 tests automatizados pasando, cero fallos</li>
<li>Shadow mode de 48 horas entre fases críticas, con validación de divergencias</li>
</ul>

<h3>Validación de shadow</h3>
<p>El sistema antiguo y el nuevo corrieron en paralelo. Resultado: 70 de 71 miembros produjeron resultados idénticos en ambos sistemas. La única divergencia: un líder que había solicitado desvinculación todavía tenía permiso en el sistema antiguo (un bug de diseño — no verificaba estado de actividad). El sistema nuevo denegó correctamente el acceso. Esta mejora de seguridad fue aprobada por el PM.</p>

<h2>Qué viene después</h2>
<ul>
<li><strong>Congreso CBGPL:</strong> la plataforma gestionará envíos, evaluaciones y agenda — usando el mismo motor de iniciativas.</li>
<li><strong>Grupo de estudios CPMAI:</strong> ya migrado al modelo genérico. Herlon (GP) y Pedro (SME) lideran el grupo del 2do semestre de 2026.</li>
<li><strong>Pilotos multi-org:</strong> capítulos interesados en replicar la plataforma pueden ponerse en contacto.</li>
</ul>

<h2>¿Quieres conocer más?</h2>
<p>La plataforma está en <a href="https://nucleoia.vitormr.dev">nucleoia.vitormr.dev</a>. Si eres de un capítulo PMI y quieres explorar el modelo para tu realidad, contacta al Núcleo IA & Gestión de Proyectos del PMI-GO.</p>
'
  ),

  'case-study',
  ARRAY['arquitetura-software', 'ia-gestao-projetos', 'lgpd', 'pmi', 'caso-de-uso', 'v3.0.0'],
  'draft',
  true,
  '880f736c-3e76-4df4-9375-33575c190305',
  NULL,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'
);
