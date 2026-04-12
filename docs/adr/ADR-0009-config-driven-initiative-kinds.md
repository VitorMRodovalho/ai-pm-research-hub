# ADR-0009: Config-Driven Initiative Kinds — Code-to-Config Extensibility

- Status: Accepted
- Data: 2026-04-11
- Aprovado por: Vitor (PM) em 2026-04-11
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Modelo de Domínio V4 — Decisão 6/6

## Contexto

Se a plataforma é reutilizável por outros projetos voluntários (roadmap declarado) e mesmo dentro do Núcleo vai suportar grupos de estudo, workshops, congressos, book clubs e tipos futuros ainda desconhecidos, **cada novo tipo de iniciativa não pode exigir intervenção de desenvolvedor**.

Hoje: CPMAI foi criado via migration + código custom + 7 tabelas dedicadas. Congresso CBGPL está sendo montado da mesma forma. Este padrão:
- Cria dívida técnica por iniciativa.
- Bloqueia managers que querem experimentar.
- Impede adoção externa da plataforma.
- Confunde modelo de domínio (casos especiais proliferando).

Plataformas maduras de gestão de projetos / voluntariado (Asana, Monday, Trello para projetos; Catchafire, Idealist para voluntariado) separam **engine** (código) de **instanciação** (config). Adotamos o mesmo princípio para manter "plataforma" como característica real.

## Decisão

1. **`initiative_kinds` é tabela de configuração**, editável via admin UI por `manager`/`deputy_manager`:
   ```sql
   initiative_kinds (
     slug text PK,                      -- 'research_tribe', 'study_group', 'congress', 'workshop', 'book_club'
     display_name text,
     description text,
     icon text,
     default_duration_days int,
     max_concurrent_per_org int NULL,   -- ex: só 8 research_tribes simultâneas
     allowed_engagement_kinds text[],   -- quais engagement_kinds podem participar
     required_engagement_kinds text[],  -- ex: study_group precisa ter 1 owner
     has_board boolean,                 -- se cria board por default
     has_meeting_notes boolean,         -- se tem atas
     has_deliverables boolean,
     has_attendance_tracking boolean,
     has_certificate boolean,
     certificate_template_id uuid NULL,
     custom_fields_schema jsonb,        -- JSON schema de campos extras (ex: CPMAI = {max_enrollment, exam_date, domains})
     lifecycle_states text[],           -- ex: draft, open, active, concluded, archived
     created_at, updated_at, created_by
   );
   ```
2. **Admin UI em `/admin/initiative-kinds`** permite manager criar/editar kinds sem mexer em código. Campos customizados via form builder simples (tipo, label, required, validation).
3. **CPMAI, congresso, workshops migram para esta abstração** — `cpmai_courses` vira `initiatives WHERE kind='study_group'` + metadata jsonb com campos domain-específicos.
4. **Engine genérica** de board, atas, attendance, deliverables, certificados — funciona para qualquer kind que tenha a feature habilitada. Não tem código `if (kind == 'cpmai')` em lugar nenhum.
5. **Extensão via hooks (futuro)** — kinds podem declarar hooks em RPCs específicas (ex: CPMAI tem hook `on_progress_update` que calcula aptidão para mock exam). Out of scope para V4 inicial; documentado como extensão futura.
6. **Primeira org (Núcleo IA) recebe seed de kinds inicial** que replica o estado atual: `research_tribe`, `study_group`, `congress`, `workshop`. Novas orgs começam com kinds padrão + podem adicionar os seus.

## Consequências

**Positivas:**
- **Plataforma verdadeira** — criar novo tipo de iniciativa = preencher um form.
- **Outras orgs adotam sem fork** — PMI-CE pode criar "mentoring circle" sem pedir código.
- **Elimina casos especiais** — código do CPMAI deixa de existir como ilha.
- **Experimentação barata** — manager testa um formato novo em 10 minutos.

**Negativas / custos:**
- Maior investimento inicial da refatoração — engine genérica exige mais cuidado de modelagem.
- Custom fields JSON não são type-safe no código. Mitigação: validação via JSON schema em RPC + TypeScript types gerados.
- Migração do CPMAI existente (7 tabelas) para initiative + metadata é delicada. Shadow mode + backfill.
- Form builder é UI de alta complexidade. MVP: campos fixos limitados.

**Neutras:**
- Feature-flags por kind — alguns kinds podem habilitar features que outros não têm. Engine precisa de defaults.

## Alternativas consideradas

- **(A) Kinds hardcoded em enum + código por kind** (status atual) — rejeitado, limita roadmap.
- **(B) Plugin system com JS sandbox** — rejeitado, complexidade não justificada para o estágio.
- **(C) Config-driven com engine genérica (escolhida)** — sweet spot entre simplicidade e flexibilidade.

## Relações com outros ADRs

- Depende de ADR-0005 (initiative é primitivo)
- Depende de ADR-0008 (engagement_kinds também é config)
- Referencia ADR-0004 (kinds podem ser global ou por-org)

## Critérios de aceite

- [ ] Tabela `initiative_kinds` criada com seed inicial (research_tribe, study_group, congress, workshop, book_club)
- [ ] Admin UI `/admin/initiative-kinds` lista e edita kinds
- [ ] CPMAI migrado de `cpmai_courses` para `initiatives WHERE kind='study_group'` com metadata
- [ ] Engine de board/atas/attendance/deliverables funciona para qualquer kind sem código especial
- [ ] Criação de kind novo sem deploy funciona end-to-end (teste: manager cria "book_club", cria initiative, adiciona engagements, board aparece)
- [ ] Custom fields validados via JSON schema
- [ ] Documentação em `/admin/initiative-kinds` explica como criar kinds novos
