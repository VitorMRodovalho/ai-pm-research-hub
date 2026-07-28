# Prompt de arranque — próxima sessão (2026-07-21)

> Ordem recomendada (dano ativo → risco → enhancement; DDL serializa):
> **A) #1450 + #1445 (selection/VEP)** → **B) #1424 (Resend)** → **C) #1423 (Wave 1 DDL)** → **D) #1448 + #1449 (gamificação)** → **E) #485**.
> Começar por A. Colar o bloco abaixo numa sessão limpa.

---

Sessão de trabalho no ai-pm-research-hub. Antes de agir: ler MEMORY.md, `git fetch`, e re-aterrar TODO número ao vivo (grounding obrigatório). Regras da casa: DDL só via apply_migration byte-igual ao arquivo + migration repair + NOTIFY + **deletar o phantom row HHMMSS** que o apply_migration MCP cria (mordeu o ADR-0097 em 20/07); NÃO aplicar 2ª DDL enquanto a 1ª PR não mergeou (entanglement de captura — serializar); merge só na sessão main; sem em-dash em entregáveis; Assisted-By nunca Co-Authored-By; 1 agente de conselho por subação.

Prioridade e sequência (ratificadas 2026-07-21): #1450 → #1445 → #1424 → #1423 → #1448/#1449 → #485.

## Sessão A (agora) — Selection/VEP

### 1. #1450 — candidatos VEP importados convidados a agendar entrevista ANTES da objetiva
Regressão confirmada ao vivo (20/07). Fluxo desenhado: entrevista só após objetiva; líder → `selection_cycles.interview_booking_url` (link Núcleo grupo); pesquisador → round-robin dos `interview_booking_url` do comitê (calendário Vitor+Fabricio). Gate: `schedule_interview` exige AI analysis + 2 peer evals + `objective_score`; convite sai por `notify_selection_cutoff_approved`.
Estado anômalo: 2 pesquisadores em `interview_pending` **sem** objective_score (null), 1 peer eval, `cutoff_approved_email_sent_at=null` — Sarah Caroline Mazeu Branco + Jonas Thimoteo (ciclo `08c1e301` cycle4-2026). Transição SEM audit log.
Leak: `src/pages/minha-candidatura.astro` mostra o CTA "agende" puramente por `status='interview_pending'`.
Arranque: (a) re-aterrar o estado dos 2 + confirmar se TIVERAM objetiva antes do re-import de 20/07 23:15 (hipótese nº1: re-import limpou score e manteve status avançado — ver p472-vep-reimport-status-freeze / p693-vep-terminal-status-honor); (b) checar recompute/consistency crons (472_corr5, 705_eval_queue) que possam derivar interview_pending; (c) fix: gatear o convite/CTA pela objetiva concluída (mesma condição do schedule_interview), não só por status; garantir que re-import não avance status nem deixe interview_pending órfão de score. Guard test. Sarah/Jonas já foram aceitos pelo owner — NÃO mexer no estado deles sem decisão (evitar fricção); decidir seguir vs voltar à fila.

### 2. #1445 — bucket de reconciliação "approved + oferta VEP retirada + member ativo"
`get_vep_divergence_report()` não tem bucket para approved + `vep_status_raw IN (OfferNotExtended/Withdrawn/Declined)` + member ativo → invisível no /admin/vep-reconciliation (caso Hector, resolvido à mão). Fix: novo bucket + ação de offboard alcançável no card (reusar `admin_offboard_member inactive`, sem duplicar path). DDL (CREATE OR REPLACE da RPC) — serializa. Guard test.

## Depois (sessões seguintes)
- **B) #1424** Resend 100/dia estoura fim de semana (EF, sem DDL, paralelo). Aterrar volume real de sáb vs cota; escolher Plano A-E. Ver [[reference-resend-email-quota-lanes]].
- **C) #1423** bridge órfão `manage_initiative_engagement` remove não re-deriva `members.initiative_id` (DDL/trigger). Fix análogo ao #1270 (limpar AMBAS colunas no mesmo UPDATE). Invariante AO. Precedente [[reference-dual-write-demotion-clear-both-columns]].
- **D) #1448 + #1449** gamificação: certs vitalícias somem no Ciclo Atual (Henrique 270pts vitalício, certs 2024-25 pré-ciclo-4; verificar get_member_xp_pillars('cycle')) + tooltip de breakdown por categoria (auditar próprio + topo).
- **E) #485** recorrência flexível + timezone + GCal sync + (comentário 21/07) exposição MCP `create_series` + edição em série 3-escopos (this/this_and_following/all). priority:low.
