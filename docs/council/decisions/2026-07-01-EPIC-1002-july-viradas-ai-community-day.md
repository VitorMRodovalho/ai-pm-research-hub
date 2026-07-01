# Council Decision Log — EPIC #1002 "Julho 2026: Viradas de Ciclo + AI Community Day"

- **Data:** 2026-07-01
- **Tier:** 3 (council-review estratégico — milestone)
- **Lentes:** product-leader · accountability-advisor · ux-leader · startup-advisor
- **Milestone:** "Julho 2026 — Viradas de Ciclo + AI Community Day" (#3, due 2026-07-16)
- **Issues:** EPIC #1002 · #1003 (fechamento C3) · #1004 (virada de acesso) · #1005 (onboarding) · #1006 (evento) · #1008 (gov PMI-brand/PDU) · #1009 (gov LGPD/ROPA)
- **Correlatas:** #995/#996 (filiação) · #999/#1000/#1001 (reconciliação VEP)

> Grounding (queries read-only ao vivo 2026-07-01): 82 membros ativos · 11 capítulos · ~67 engagements `volunteer` ·
> ciclo 4: 36 approved (33 VEP Active / 2 OfferExtended / 1 Submitted) · 34 pré-onboarding · 0 webinars agendados em julho.
> **Re-aterrar cada número antes de virar decisão formal (ata/comunicado/audit).**

## Contexto

Três viradas encadeadas em 14 dias: encerramento Ciclo 3 (02/07) → início Ciclo 4 + virada de acesso (09/07) →
AI Community Day via Airmeet (16/07, complemento PT-BR do AI Community Day global do PMI). Sessão de dev rodando em
paralelo (recurso limitado). Acesso à plataforma é dirigido por **engagement ativo** (não por ciclo); a máquina de
re-aceite (Camada 5, ADR-0116 / #976) está **dormente**, tornando a virada de acesso **manual**.

## Decisões (convergência das 4 lentes)

### D1 — A virada de acesso (#1004) é o nó crítico; executá-la de forma auditável
Único front sem automação. **Não** acordar a Camada 5 sob pressão. Protocolo obrigatório antes de 09/07:
lista congelada e datada das 3 coortes (mantém/entra/sai) com critério explícito por pessoa → aprovador nomeado
(GP/Presidência) assina antes → execução **100% via RPC** (`admin_offboard_member` / fluxo de onboarding), **zero
`UPDATE`/DDL direto** em `members`/`engagements` → reconciliação pós-corte (09–11/07) arquivada. Reusar o formato
`docs/project-governance/BACKLOG_RECONCILIATION_*`. (product + accountability + ux)

### D2 — Posicionamento PMI é o blocker externo nº 1 (#1008)
Enquadrar como **"aftershow / extensão noturna"** do AI Community Day, nunca evento paralelo/oficial. **Sem claim
de PDU** (certificado = "participação emitido pelo Núcleo IA & GP"). **PMI-GO ratifica** o uso do nome (ADR-0104
— parte contratante), não o Núcleo unilateralmente. Consulta escrita a PMI-GO/Latam esta semana. Nenhum material
público sai antes disso + review de legal-counsel. Risco de fechar o **Path A** se mal conduzido. (startup + accountability)

### D3 — Evento operado FORA da plataforma
Airmeet + reuso de RPCs de certificado existentes (ADR-0098). **Zero migration/feature nova** nesta janela —
preserva 100% do dev para D1. (product)

### D4 — Evento como âncora de onboarding exige guarda-corpos de UX, não features (#1005)
F1 (CRITICAL) barra de status **única** OU aviso textual (checklist não pode dizer "100% pronto" com filiação
pendente — depende de #995/#996). F3 acolher a coorte nova **nominalmente** no fishbowl. F4 definir **um** próximo
passo do dia 17 **antes** do evento. Progressive disclosure dia 9 = máx. 3 coisas. Convite mobile-first (60%+). (ux)

### D5 — Momentum pós-evento planejado antes, não depois (#1006)
Agendar já 11 calls de 15min (1/capítulo) para 17–18/07 · fragmentar VOD em 3 clips (Path A/B/comunidade) ·
segmentar inscritos em 3 funis em 72h · nomear responsável por captura de quotes antes do dia 16. (startup)

### D6 — Governança LGPD dos convidados externos (#1009)
Entrada de ROPA dedicada (base legal Art. 7º V ou I) antes de abrir inscrição · comunicado datado aos 11
presidentes. DPO: Ivan Lourenço Costa (subst. Angeline Prado). (accountability)

## Registro de riscos

| Risco | Sev. | Mitigação | Issue |
|---|---|---|---|
| `UPDATE` direto em `members` sob pressão quebra rastro LGPD | Alta | Só via RPC; lista congelada+assinada; reconciliação pós-corte | #1004 |
| Uso do nome "AI Community Day" sem OK do PMI | Alta | Ratificação PMI-GO/Latam; linguagem cautelar | #1008 |
| Certificado lido como PDU oficial | Média-Alta | "Certificado de participação"; sem quantificar PDU | #1008 |
| Opacidade de status (checklist 100% × filiação pendente) | Alta | Barra única OU aviso textual | #1005 |
| PII de convidados externos sem base legal no ROPA | Média | Entrada de ROPA antes da inscrição | #1009 |
| 11 presidentes surpreendidos pela marca/data | Média | Comunicado formal datado | #1009 |
| Evento canibalizar dev da virada de acesso | Média | Evento fora da plataforma; zero migration | #1006/#1004 |

## Escalonamentos abertos (não executados neste review)
- **legal-counsel** + **c-level-advisor** → linguagem certificado/convite + enquadramento vs. PMI (#1008).
- **senior-software-engineer** → confirmar reuso do RPC de certificado p/ #1006 em <1 sessão.

## Notas de método
- accountability-advisor não tem `execute_sql`; verificou ADRs 0104/0071/0116 + ROPA no repo; **pmi.org bloqueou
  WebFetch (403)** → política de marca/PDU do PMI tratada como **gap de verificação**, não fato checado.
- Métricas de sucesso por front definidas (product) — re-aterrar em cada checkpoint (02/07, 09/07, 16/07).

## Métricas de sucesso (product-leader)
- **C3 (#1003):** 0 engagements `volunteer` de C3 em status não-terminal até 02/07 EOD.
- **Acesso (#1004):** 0 divergência lista-alvo × engagements ativos pós-virada; 0 acesso remanescente de quem saiu.
- **Onboarding (#1005):** % dos 34 pré-onboarding com 1º login + perfil completo em ≤7 dias.
- **Evento (#1006):** inscritos × participantes reais (slot 19–21h BRT) · satisfação pós · certificados emitidos.
