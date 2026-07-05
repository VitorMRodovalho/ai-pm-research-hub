# Handoff — Reunião Geral 02/07: vídeo publicado, `youtube_url` a vincular, Top 5 oficial (certificados)

**Para:** time da plataforma `ai-pm-research-hub`
**De:** lane de vídeo/comms do PMO (sessão do Pai), 2026-07-03
**Relacionado:** `HANDOVER_2026-07-03_GAMIFICATION_CONCILIATION_C3.md` (mesmo diretório) — o §3 daquele doc está resolvido (ver abaixo).
**Por que chega a vocês:** (1) uma escrita de `youtube_url` que não tem setter MCP; (2) o Top 5 oficial do Ciclo 3, para vocês terem ciência **antes de emitir os certificados**.

---

## 1. AÇÃO — vincular `youtube_url` do evento (não há setter MCP)

O vídeo editado da Reunião Geral de 02/07 está publicado. Falta popular o campo dedicado do evento (só via SQL; `update_event_instance` não cobre `youtube_url`).

- **Evento:** `b0ff819b-dd27-4951-a217-3793ebc62489` — "Reunião Geral — 2026-07-02" (hoje `youtube_url = null`, `is_recorded = false`).
- **Vídeo canônico (público):** https://youtu.be/_O4s6lQW0lM

```sql
-- confirmar a linha primeiro
SELECT id, title, youtube_url, is_recorded FROM events
WHERE id = 'b0ff819b-dd27-4951-a217-3793ebc62489';

-- vincular (confirmar nome da tabela: events vs event_instances no schema de vocês)
UPDATE events
SET youtube_url = 'https://youtu.be/_O4s6lQW0lM', is_recorded = true
WHERE id = 'b0ff819b-dd27-4951-a217-3793ebc62489';
```

> Vincular sempre o link **público/unlisted**, nunca privado (já é público). É DML (não DDL), então `execute_sql` serve; não precisa de migration.

### Estado do YouTube (já aplicado pela lane de vídeo)
- **Editado `_O4s6lQW0lM` → público**, na playlist "Ciclo 3 (2026/1) - Reuniões Gerais". É o canônico. Traz opener branded, pré-stream aparado, **cobertura branded da classificação preliminar** no trecho do ranking (a lista pré-reconciliação foi coberta, com câmera + áudio preservados) e card de errata no fim.
- **Live original `b65gzEY6Ryg` → Não listada** e retitulada "[Gravação da transmissão] … versão bruta"; **removida da playlist** (fica de backup). NÃO vincular esta na plataforma.

---

## 2. §3 (XP no bucket errado) — RESOLVIDO

Verificação ao vivo 2026-07-03 (`get_member_cycle_xp`) vs o handover de ontem: os buckets **se auto-corrigiram** (showcase → `cycle_showcase`, champion → `cycle_artifacts`) com os **totais estáveis**. Era **lag de materialização da view**, não bug de roteamento de RPC. O ranking **por total** sempre foi confiável. Sugestão: rebaixar o §3 de "provável bug" para "lag de view, resolvido", com um sanity-check no `+25` de total do Fabrício (285→310 entre 07-02 e 07-03).

Exemplos (antes 07-02 → agora 07-03, showcase/artifacts/bonus/**total**):
- Ana Carla: 15/0/195/**420** → **85**/0/125/**420**
- Débora: 0/0/375/**515** → 0/**150**/225/**515**
- Fabrício: 0/0/85/**285** → **75**/35/0/**310**

---

## 3. Top 5 OFICIAL do Ciclo 3 — para os certificados

**Números travados ao vivo 2026-07-03 (`get_member_cycle_xp`, `rank_position`, `total_ranked = 77`).**

**Regra de reconhecimento (decisão do gestor, Vitor, 2026-07-03):** a **gestão da plataforma não entra no ranking dos membros** — exclui **Vitor** (gestor, sem tribo, Ciclo 654 / Vitalício 1264) e **Fabrício** (co-GP/deputy, Vitalício 1090). Precedente: no handover da conciliação o Vitor pediu para não se autopontuar.

### Ranking Individual — Ciclo Atual (a premiar/certificar)
| # | Membro | member_id | Ciclo pts |
|---|---|---|---|
| 1 | Fernando Maquiaveli | `c8b930c3-62ec-4d38-881e-307cd57a44f7` | 547 |
| 2 | Marcos Antunes Klemz | `c204ac61-4d39-42f2-8d28-814727b62e90` | 526 |
| 3 | Débora Moura | `a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7` | 515 |
| 4 | Jefferson Pinto | `622ab18b-a8b4-46ff-b151-7bbd34394ed3` | 495 |
| 5 | Hayala Curto | `f64ee70a-5d37-4670-9306-a5efe4666cd3` | 460 |

### Hall da Lenda — XP Vitalício (reconhecimento à parte)
| # | Membro | member_id | Vitalício pts |
|---|---|---|---|
| 1 | Débora Moura | `a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7` | 1080 |
| 2 | Fernando Maquiaveli | `c8b930c3-62ec-4d38-881e-307cd57a44f7` | 1052 |
| 3 | Paulo Alves De Oliveira Junior | `57fcf33c-25a3-4555-b358-a168a4151794` | 1050 |
| 4 | Jefferson Pinto | `622ab18b-a8b4-46ff-b151-7bbd34394ed3` | 850 |
| 5 | Ítalo Soares Nogueira | `c1f428b5-5a8b-419e-9df5-d298994a5256` | 820 |

> ⚠️ O que foi mostrado/anunciado **na reunião** (Ciclo: Ana Carla/Jefferson/Débora; Vitalício com glitch do Paulo) é **pré-reconciliação e está superado** por esta tabela. É por isso que o vídeo cobre aquela classificação. **Certificados/premiação devem seguir ESTA tabela.**

### Texto do anúncio (pronto p/ WhatsApp/plataforma; voz humana, sem travessão)
> 🏆 **Gamificação do Ciclo 3 — destaques.** Pessoal, primeiro obrigado. Cada showcase, cada presença, cada entrega move o Núcleo. Nesta reunião a classificação na tela oscilou por um ajuste de sincronização da plataforma, então segue a versão oficial, já reconciliada. Um combinado: como gestor da comunidade e sem tribo, eu não entro no ranking dos membros — o reconhecimento é de vocês.
> **Top 5 do Ciclo 3:** 🥇 Fernando Maquiaveli · 🥈 Marcos Antunes Klemz · 🥉 Débora Moura · 4º Jefferson Pinto · 5º Hayala Curto.
> 🏅 **Hall da Lenda (XP Vitalício):** 🥇 Débora Moura · 🥈 Fernando Maquiaveli · 🥉 Paulo Alves · 4º Jefferson Pinto · 5º Ítalo Soares Nogueira.
> Confira sua pontuação na plataforma: https://nucleoia.pmigo.org.br

---

## 4. Checklist para o time
- [ ] Rodar o UPDATE do `youtube_url` (§1) e confirmar via `list_initiative_events has_recording:true`.
- [ ] Emitir/conferir os **certificados** do Ciclo 3 seguindo o Top 5 oficial (§3), não o que foi à tela na reunião.
- [ ] Rebaixar/fechar o §3 do handover de gamificação (lag de view, resolvido) após o sanity-check do Fabrício.
- [ ] (opcional) postar o anúncio pelos canais oficiais.
