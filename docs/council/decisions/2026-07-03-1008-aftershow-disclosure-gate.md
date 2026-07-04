# Decision: Enquadramento Aftershow Núcleo IA & GP vs. AI Community Day (PMI Global) — issue #1008

**Date:** 2026-07-01 (proposta council) · **2026-07-03 (ratificada)**
**Decided by:** PM/GP (Vitor) — in-session (AskUserQuestion), sessão dev 2026-07-03
**Status:** Accepted
**Path impact:** preserva A (condicional a gate); reforça C (sinal de comunidade sem espera)

## Decision

Rebatizar o evento local para **"Aftershow Núcleo IA & GP"** (não usar "AI Community Day" como nome
próprio). Duas trilhas de publicação:

- **Track 0 (zero-risco, liberada):** save-the-date com nome só-Núcleo, sem PDU, com disclaimer de
  não-endosso. Pré-condições operacionais: entrada de ROPA G.1 registrada (feita 2026-07-03) + aviso de
  privacidade no fluxo de inscrição.
- **Track 1 (gated):** qualquer copy que referencie o nome global / PDU / Standard trava até resposta
  **escrita** da Presidência PMI-GO ao memo §4 (enviado com pedido de encaminhamento à PMI Latam).

**Gate A hard cutoff: 2026-07-09 EOD.** Sem resposta escrita até lá → fallback **Track-0-only permanente**
(nome próprio, zero linguagem de PDU), sem extensões.

Decisões acessórias ratificadas na mesma sessão (2026-07-03):
- **Certificado do evento:** template C3 reusado (`type='participation'`, carga 2h), assinatura dual
  GP + Co-GP; linguagem travada Opção A (sem claim de PDU); Opção B (autodeclaração com categoria CCR)
  só se PMI confirmar por escrito.
- **Keynote:** prioridade = expert do AI Standard (outreach imediato); fallback = presidente de capítulo,
  decisão até 07/07.
- **LGPD convidados externos (#1009):** consentimento Art. 7 I, retenção 1 ano, deleção separada do cron
  de membros, formulário nativo Airmeet, certificado de não-membro via caminho ancorado em `persons`
  (dev a especificar). ROPA G.1 em `docs/audit/LGPD_ROPA_PUBLIC_SURFACES.md`.
- **Comunicado aos 11 presidentes (#1009 Gap 2):** unificado com o convite formal de co-host (uma
  comunicação datada, canal registrado), enviado junto com a janela do memo.

## Rationale

PMI-GO é parte contratante legal (ADR-0104) — board contra-assina certificados pessoalmente. Precedente
Trentim firewall (2026-05-09) e p207 (violação documentada de credibilidade é incompatível com narrativa
Path A). Reuso do nome = concorrência desleal (Lei 9.279/96 art. 195) + implied endorsement. Verificado
2026-07-03: nenhum documento interno de governança contém cláusula de aprovação prévia de marca (ADR-0104
é parte-contratante; grep em docs/) — o risco residual é a política externa de trademark do PMI, coberta
pelo memo + INPI check (pré-condição Track 1).

## Cross-refs

`docs/project-governance/EVENT_1008_AI_COMMUNITY_DAY_DISCLOSURE_GATE.md` (gate de registro) ·
`docs/project-governance/EVENT_1006_AFTERSHOW_16-07_EVENT_PLAN.md` (plano executável) ·
issues #1008 #1006 #1009 #1002 · ROPA G.1
