# Plano da Virada C3→C4 — Execução (2026-07-04)

> Complementa (não substitui): `ACCESS_COHORT_FREEZE_2026-07-09_C3-C4.md` (freeze assinado, §2.5
> readiness / §4 reconciliação) e `CYCLE3_CLOSURE_RUNBOOK_2026-07.md`. Este documento cobre a
> camada de PLATAFORMA da virada (registros, título, banners, eventos, tribos/líderes C4) —
> aterrado em discovery de 4 frentes (DB vivo + código + docs + issues) na sessão de 04/07.
> Decisões do owner registradas em §1. Epic: #1002 · onboarding C4: #1005.

## §1 Decisões do owner (2026-07-04, nesta sessão)

| # | Decisão | Escolha |
|---|---|---|
| D1 | Capacidade de tribo | **SSOT em `platform_settings.max_researchers_per_tribe` (=10)** — hardcode 6 morto na mig 335; fluxo híbrido ganhou cap. Ajuste futuro = editar a setting. |
| D2 | Estrutura de tribos C4 | **Por tema: tribo NOVA se tema inédito** (Henrique e Messias → novas); tema com overlap → assume tribo existente ou co-lidera. Caso a caso na alocação do dia 9. |
| D3 | Sucessor da T2 (Agentes Autônomos) | **Shortlist: Honorio (funil, tema aderente) + sondar interno da T2 (5 ativos)**. Decisão até 11/07 (janela §4). T2 fica temporariamente sem líder (exceção consciente do freeze). |
| D4 | Pacote ops imediato | **Executado 04/07** (ver §2) incluindo remarcação da Reunião de Liderança #7 19h→18h (pré-kickoff). ⚠️ Owner ajusta o convite correspondente no Google Calendar. |

## §2 Executado em 04/07 (produção)

- **Banners** (`announcements`, componente global suporta 3 simultâneos): row stale "Ciclo 3 em
  Andamento" inativada · banner **Kick-off 09/07 19h** (link Meet `bpx-bcze-zbt`, expira 10/07) ·
  banner **Save the date: Aftershow Núcleo IA & GP — 16/07** (Airmeet; copy Track-0 do gate #1008 —
  sem nome global, sem PDU; sem link até a sala Airmeet existir). i18n 3/3 nas rows.
- **Kickoff na plataforma**: row `events` `f7ff4167` (`type='geral'`, 09/07 19:00, 90min,
  visibility all) — aparece automaticamente como "próxima reunião" no hero dos logados.
  `home_schedule.kickoff_at` → 09/07 19:00 BRT (countdown público dos anônimos).
- **Conflito de agenda resolvido**: "Reunião de Liderança #7" (09/07) remarcada 19h→**18h**
  via `update_event_instance` (nota no evento). **Pendente humano: mover o convite no Calendar.**
- **Row `cycle_4`** criada via `admin_manage_cycle('create')`: "Ciclo 4 (2026/2)", C4, start
  09/07, `#06B6D4`, sort 5, **`is_current=false`** (flip só no dia 9).
- **Mig 335** (`cycle4_tribe_capacity_ssot`): helper `tribe_capacity_limit()` + `select_tribe` /
  `admin_force_tribe_selection` / `review_tribe_request` consumindo o SSOT; híbrido agora bloqueia
  approve com "Tribo lotada (x/y)". Contract test `cycle4-tribe-capacity-ssot`.
- **Higiene**: `tribes.quadrant_name` da T2 corrigido ("The Augmented Practitioner"→"AI Project
  Management", era dado errado desde o seed).
- **PR #1101** (strings "Ciclo 3"→"Ciclo 4": i18n 3/3 + 4 inline + fallback `cycles.ts`) —
  **MERGEAR SÓ NO DIA 9**, par do flip.

## §3 Fatos aterrados que governam o plano

- **Coorte de continuidade**: dos 70 engagements volunteer ativos, **40 = entrantes C4** (termo
  30/06/2027; 36 ainda `guest` até assinar — freeze §2.5) e **~29 = continuantes C3 com termo até
  dez/2026+** (15× 19/12 · 7× 31/12 · 5× fev–abr/27 · 2 sem fim GP/co-GP). **Nenhum termo vence
  em jun/jul** → continuantes NÃO re-assinam; o que falta é REGISTRO (ver §4.3).
- **Pertencimento a ciclo** = `member_cycle_history` (+ `members.cycles[]`). C3: 63 rows/56
  ativas. **Não existe RPC de roll-forward** — na virada C2→C3 foi manual.
- **Deadline de seleção de tribo**: `home_schedule.selection_deadline_at` **já está em
  17/07 23:59 BRT** ✔ (§2.5 item 2 concluído na sessão de 03/07; o freeze doc ainda cita o valor
  antigo).
- **Funil de líderes C4** (vivo 04/07): approved = Henrique Diniz (#1, 512,55) e Messias Reis
  (#3); final_eval = João Henrique, Honorio; entrevista = Jhonathan (scheduled), Adailson, Felipe
  (pending). Track pesquisador com vocação de liderança (doc interno 04/07): Luana Andrade
  (**#1 geral, 298,5**; T5/T8 fit) e Luiz Ramom (280,5; T7 fit) — aprovados como pesquisadores,
  sem candidatura formal a líder ainda.
- **Elegibilidade a resolver**: João Henrique (PMI-SP), Felipe (PMI-ES), Messias (sem capítulo) —
  fora dos 5 capítulos federados; Luana (PMI-MG intenção não concretizada).
- **Tribos C3**: 7 ativas + T3 inativa. Líderes continuantes: Hayala (T1), Fernando (T4),
  Jefferson (T5), Fabricio (T6), Marcos (T7), Ana Carla (T8). Débora (T2) sai na virada.
  Alocados em tribos: 25 pesquisadores + 9 sem tribo.
- **Criação de tribo nova** = `admin_upsert_tribe` + `admin_upsert_legacy_tribe` + row em
  `initiatives kind='research_tribe'` com `legacy_tribe_id` (`create_initiative` BLOQUEIA
  research_tribe por design; a ponte initiatives não é automática — gap §6.2).
- **Quadrantes**: `tribes.quadrant` 1–4 + tabela `quadrants` seedada. **Verticais**:
  `initiatives kind='community_vertical'` (5 ativas: Construção, ESG, Negócio, PMO, Ágil) —
  modelo 3 eixos do #661. Tagging de tema = quadrant na tribo + vertical via iniciativa.
- **Onboarding steps** são globais (sem `applies_to_role`) — líderes recebem os mesmos 5 passos
  dos pesquisadores (accept_terms/join_whatsapp/platform_access/kick_off/profile_complete).
- **Vídeo de captação**: `tribes.video_url` + `video_duration` (precedente C3: 8 vídeos).

## §4 Runbook do DIA 9 (09/07) — ordem de execução

1. **Flip do ciclo**: `admin_manage_cycle('set_current', 'cycle_4')` + fechar C3
   (`admin_manage_cycle('update', 'cycle_3', ..., p_end => '2026-07-08')`).
2. **Mergear PR #1101** (strings) — Pages auto-deploya; site amanhece "Ciclo 4".
3. **Roll-forward de registro dos continuantes** (§3): INSERT em `member_cycle_history`
   (`cycle_code='cycle_4'`, `cycle_start='2026-07-09'`, tribe/role snapshot atual) para os ~29
   continuantes + append `'cycle_4'` em `members.cycles`. Executar via migration governada com
   query de coorte (termo ativo end_date ≥ 2026-12-01 e não-entrante) — e capturar antes/depois.
   *(Issue de follow-up: RPC `admin_roll_cycle_membership` para institucionalizar — §6.1.)*
4. **Exit Débora** (freeze §2.3b): `admin_offboard_member(p_new_status=>'alumni',
   p_reason_category=>'end_of_cycle')` — sem `p_reassign_to` ainda (sucessor D3 até 11/07);
   board_items dela ficam para reassign na nomeação. NÃO revogar Drive antes do offboard.
5. **Alocação dos 2 líderes C4 aprovados** (Henrique, Messias — assinam PRIMEIRO na campanha
   §2.5): criar as tribos novas (D2; ver §5.1) + alocação direta (líder não usa select_tribe).
6. **Entrantes**: conforme assinam o termo → `request_tribe_assignment` (janela até 17/07;
   cap SSOT ativo). Kickoff 19h no Meet `bpx-bcze-zbt` (banner + hero já apontam).
7. **Reconciliação §4 do freeze** (09–11/07): `list_offboarding_records(p_since=>'2026-07-03')`
   = exatamente {tribo-7 researcher, tribo-2 leader}; recheck leak 2a/2c = 0; enter 2d
   loginable==active_eng.
8. **Residuais #1003 na mesma janela**: fechar batch `cycle3-2026-b2` · arquivar 196 cards C3 +
   25 done-unarchived (precedente C2: tag de ciclo + arquivamento) · champion `general` (gestor).

## §5 Pós-virada — onboarding adicional de LÍDERES (09–17/07)

### §5.1 Criar tribo nova (por líder aprovado com tema inédito — D2)
Checklist por tribo: `admin_upsert_tribe` (nome, quadrant 1–4 conforme tema, quadrant_name,
leader_member_id, meeting_link) → `admin_upsert_legacy_tribe` (cycle_code='cycle_4') → row em
`initiatives` (kind='research_tribe', legacy_tribe_id, board auto se has_board) → verificar
dual-write (`members.tribe_id` via trigger) → Drive folder + link.
Mapeamento inicial (dos temas do funil): Henrique → Q3 (AI & PM Centre lusófono; ponte Q2) ·
Messias → Q2 (modelo de complexidade). Aderências a EXISTENTES (não criar): Honorio→T2 (agentes),
Ramom→T7 (governança pública), Luana→T5/T8 (multiplicação), João H↔Felipe (overlap PMO/evolução —
diferenciar escopo ou co-liderança se ambos aprovarem).

### §5.2 Passos extra de onboarding do líder (dev — issue própria)
1. `onboarding_steps.applies_to_role text[]` (migration) + seed dos passos de líder:
   **refinar tema** (1 parágrafo + quadrante + vertical quando houver) · **artefatos programados
   6/12/18 meses** (roadmap) · **vídeo de captação** (subir link → `tribes.video_url`) ·
   **revisar pendências da tribo** (cards herdados, membros, Drive).
2. Modelo de roadmap: `initiatives.metadata.roadmap` jsonb `{h6:[], h12:[], h18:[]}` na V1
   (sem DDL novo além do step) + render na página da tribo; V2 avalia tabela própria se o
   pipeline editorial consumir. Precedente C3: artifacts com due único 30/06 (mig
   `20260314170000`) — o modelo 6/12/18 é NOVO por decisão do owner.
3. Insumo: materiais extraídos dos 8 vídeos C3 (prompt no PMO — §7) guiam o formato do vídeo
   e o refinamento de tema dos novos líderes.

### §5.3 Sucessão T2 (D3)
Até 11/07: acelerar final_eval do Honorio + sondagem dos 5 ativos da T2. Nomeado o sucessor:
se vindo do funil → `promote_to_leader_track` + assinar termo + alocação direta; se interno →
caminho alternativo (sem application C4 — gap conhecido do promote; tratar via engagement
role='leader' direto + cache trigger). Reassign dos board_items da Débora na nomeação.
Protocolo formal de handover = issue #1020 (pending-successor state) — usar este caso como piloto.

## §6 Gaps sistêmicos a fechar (semântica/tabelas — sustentabilidade)

1. **Roll-forward de ciclo sem RPC** (§4.3): institucionalizar `admin_roll_cycle_membership`
   (coorte por termo vigente → member_cycle_history + members.cycles) — a virada C5 não deve
   repetir INSERT manual.
2. **Ponte tribes→initiatives não automática na criação**: `admin_upsert_tribe` não cria a
   initiative irmã (e `create_initiative` bloqueia research_tribe). Fechar com trigger ou RPC
   composto `admin_create_research_tribe`.
3. **`onboarding_steps` role-agnóstico** (§5.2.1).
4. **FK `tribes.quadrant`→`quadrants` comentada** desde a mig 20260402010000 (o dado errado da
   T2 provou o risco) — ativar a constraint.
5. **Freeze doc §2.5 cita deadline stale** (09/03) já corrigido em prod (17/07) — anotar no doc
   na próxima revisão governada.

## §7 Vídeos das 8 tribos C3 → insumo do PMO

Prompt de extração + tabela tribo→líder→link entregue ao PMO pai em
`~/projects/_pmo/youtube/cycle3-assets/TRIBE-VIDEOS-EXTRACTION-PROMPT.md`. Saída esperada por
vídeo: tema como apresentado, promessas de entregáveis, estrutura de pitch (roteiro/duração),
quadrante implícito, o que reusar/evitar no formato C4 — alimenta §5.2.3 e o kit do líder novo.

## §8 Fora do escopo desta virada (rastreado)

Evento 16/07: sala Airmeet até 07/07 (link no evento `07c26b3d` + banner) · #1098 cert convidado
externo (até 14/07) · #1008 Trilha 1 aguarda PMI-GO · #1094 fecha com permalink de 06/07 ·
landing C4 R3–R9 (`cycle4_landing_redesign_target.md`, sessão dedicada) · heatmap (spec com
pré-requisitos LGPD; bug PT=1 do `get_public_country_reach` é R1 independente) · verticais ghost
(discovery aguardando PM) · pré-onboarding gamificado (EPIC #873, diferido).
