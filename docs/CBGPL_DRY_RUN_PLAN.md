# Dry-Run Plan — CBGPL 2026 Arena Demo

**Objetivo:** simular o demo de 20min + 5min Q&A em condições próximas às reais antes de 28/Abr. Caçar drift de métricas, falhas de rede, quebras de tempo, e pontos em que a narrativa trava.

**Formato:** 1 sessão principal + 1 sessão de repescagem se algo quebrar.

**Participantes:**
- Demo runner: **Vitor** (GP)
- Timekeeper + Q&A simulator: **Fabrício** (embaixador AIPM)
- Audience proxy + feedback: **Ivan** (sponsor PMI-GO) se disponível
- Optional: 1 líder de tribo que nunca viu o demo (teste de clareza para público externo)

---

## Janela

| Slot | Data | Duração | Propósito |
|---|---|---|---|
| **Dry-run #1** | 22-25/Abr | 60 min | Rehearsal integral + feedback |
| **Dry-run #2 (reserva)** | 25-27/Abr | 45 min | Re-rehearse se #1 revelou issues |
| **Pre-flight** | 27/Abr à noite | 30 min | Teste técnico em notebook real |

Confirmar slot via WhatsApp líderes + comitê CBGPL até 20/Abr.

---

## Pré-flight técnico (checklist de notebook)

Notebook que vai para Gramado:

- [ ] Chrome atualizado, sem extensões visíveis, dark mode OFF
- [ ] 5 tabs pré-abertas, ordem exata:
  1. `nucleoia.vitormr.dev` (não logado)
  2. `nucleoia.vitormr.dev/governance`
  3. `nucleoia.vitormr.dev/admin` (logado como Vitor)
  4. Claude.ai com MCP Núcleo conectado (76 tools visíveis)
  5. `nucleoia.vitormr.dev/tribe/[id]` (pré-escolhido para Act 2)
- [ ] Wi-Fi principal funcional
- [ ] Hotspot 5G do celular testado (backup), senha anotada em papel
- [ ] Pen drive USB-C com: vídeo fallback 3min (`CBGPL_VIDEO_FALLBACK_3MIN.mp4`), screenshots de cada tela (fallback total)
- [ ] Cabo HDMI + adaptador USB-C→HDMI
- [ ] Carregador do notebook + extensão elétrica
- [ ] Telefone em modo avião (evitar push durante demo), mas pronto para virar hotspot
- [ ] Slides backup em PDF (caso browser trave)

---

## Roteiro do Dry-Run #1 (60 min)

### Parte 1 — Preparação (5 min)
- [ ] Vitor abre as 5 tabs na ordem
- [ ] Fabrício inicia cronômetro
- [ ] Gravar a tela (Loom ou OBS) para revisão posterior

### Parte 2 — Demo integral (20 min cronometrados)
Seguir `docs/CBGPL_DEMO_SCRIPT.md` cabo a cabo. **Timekeeper Fabrício dá sinal a cada 5min** (sinalização discreta, não interromper fala).

Meta de tempo por ato:
- Act 1 (público): 5:00 ± 0:30
- Act 2 (membro): 5:00 ± 0:30
- Act 3 (governança): 5:00 ± 0:30
- Act 4 (IA ao vivo): 5:00 ± 0:30

**Sem pausar** para corrigir erros durante o dry-run. Anotar e corrigir depois.

### Parte 3 — Q&A simulado (5 min)
Fabrício (ou Ivan) dispara 3-5 perguntas da lista:

**Perguntas-base** (do demo script):
1. "Quanto custa?"
2. "A IA substitui o líder de projeto?"
3. "Como garantem LGPD?"
4. "Podem replicar para outro capítulo?"

**Perguntas-curveball** (adicionar pressão):
5. "Por que não usam ferramenta existente (Monday, Asana)?"
6. "Quem financia os R$ 0 que vocês citam?"
7. "O que impede alguém de copiar e revender?"
8. "Vargas vai falar antes de vocês. Qual a sua diferenciação?"
9. "Como mediram que a IA amplifica em vez de substituir?"
10. "E quando a OpenAI lançar um gerenciador de projetos nativo?"

Vitor responde em 30-60s por pergunta. Fabrício anota respostas fracas para refinar.

### Parte 4 — Revisão (30 min)
Assistir gravação juntos. Anotar:

- [ ] **Tempo** — onde estourou? Onde sobrou? Seções que cortar ou expandir.
- [ ] **Narrativa** — pontos em que o raciocínio travou ou ficou confuso?
- [ ] **Demonstração técnica** — algum tool call falhou? Algum dado estava errado?
- [ ] **Métricas citadas** — alguma número estava stale (versão antiga de tool count, tests, etc.)?
- [ ] **Linguagem corporal** — se gravou câmera: gesticulação, olhar, postura.
- [ ] **Q&A** — qual pergunta matou? Scriptar resposta melhor.

**Gate de passagem:** demo em 20:00 ± 1:00, zero erro técnico visível ao público, 80% das Q&A com resposta de 30-60s clara.

Se falhar o gate → agendar Dry-Run #2.

---

## Riscos específicos e mitigações

| Risco | Mitigação |
|---|---|
| Wi-Fi Arena cair no meio do Act 4 (IA ao vivo) | Hotspot 5G pronto, pen drive com vídeo 3min como fallback integral |
| Claude.ai lento ou tools list com erro | Tool call pré-cacheado via mesma pergunta 10min antes, screenshot salvo |
| Métricas divergirem (ex: MCP tool count mudou) | Verificar CLAUDE.md no dia 27/Abr, ajustar script verbal |
| Vargas palestrar 1h antes → audiência cansada | Cortar Act 2 (menos relevante), expandir Act 4 |
| Pergunta hostil sobre posicionamento vs Vargas | Responder: "Complementar. Ele aponta a direção, nós trazemos um exemplo operando. Ambos ajudam a comunidade PMI." |
| Notebook travar durante demo | Slides PDF backup + vídeo 3min |
| Pânico cênico | Respiração 4-7-8 pré-entrada, água do lado, assumir que 5% do público está ansioso junto com você |

---

## Output esperado após o dry-run

- [ ] Gravação de 20min + Q&A salva
- [ ] Lista de 5-10 ajustes no `CBGPL_DEMO_SCRIPT.md`
- [ ] Confirmação de métricas atualizadas no script
- [ ] Lista de 10 Q&A com respostas refinadas (anexar ao demo script)
- [ ] Sign-off do comitê (Ivan + Fabrício + líder de tribo convidado) → "Pronto para Gramado"

---

## Stakeholder follow-ups após dry-run

- [ ] WhatsApp comitê: envio de link gravação + resumo de ajustes
- [ ] Email Ivan: confirmar slot no Arena + presença committee no dia
- [ ] DM para Ricardo Vargas (via AIPM): 1-liner com link do vídeo 3min (pré-briefing)
- [ ] LinkedIn post pré-evento (26/Abr): vídeo 3min cut + convite para Arena
