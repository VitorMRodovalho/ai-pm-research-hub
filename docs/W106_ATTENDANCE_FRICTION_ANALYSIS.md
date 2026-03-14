# W106 — Attendance Journey Friction Analysis
**Data: 2026-03-15 | Base: 783 registros, 96 eventos, 56 membros | Ciclos 1-3**

---

## 1. Resumo Executivo

O Núcleo tem um problema de retenção previsível e tratável. A cada ciclo, ~30% dos membros somem entre o kickoff e o final. O dropout acontece em 3 ondas distintas, e cada uma tem uma causa e intervenção diferente. Com os dados históricos agora no banco, é possível prever e intervir antes que a perda se consolide.

**Números-chave:**
- Retenção C1 (kickoff → final): 19 → 10 (~53%)
- Retenção C2 (kickoff → final): 30 → 17 (~57%)
- Dropout C3 (kickoff → 1ª geral, 7 dias): 41 → 23 (44% faltaram)
- Horas de impacto acumuladas: **877h** (49% da meta anual de 1.800h)
- Core team (≥75% presença): apenas 3 pessoas (Vitor, Fabricio, Andressa)

---

## 2. Curva de Retenção — Ciclo 1

Dos 19 membros no kickoff C1 (25/Fev/2025), a retenção ao longo de 26 reuniões gerais:

| Fase | Período | Retenção | Padrão |
|------|---------|----------|--------|
| Mês 1 (R1-R3) | Fev-Mar | 89% → 79% | **Dropout suave** — 2-4 pessoas saem cedo |
| Mês 2-3 (R5-R11) | Abr-Mai | 68% → 58% | **Estabilização** — core team se forma |
| Mês 4-5 (R12-R17) | Mai-Jun | 63% → 37% | **Fadiga do meio** — queda acentuada |
| Mês 6-7 (R18-R26) | Jul-Set | 37% → 47% | **Recuperação parcial** — proximidade do C2 reativa |

**Insight:** A retenção NÃO é linear descendente. Ela cai, estabiliza, cai de novo, e depois recupera antes do próximo ciclo. O ponto mais crítico é o **mês 4-5** ("fadiga do meio"), não o início.

### Visualização (C1: 19 membros iniciais)

```
100% ████████████████████████████ R1  (kickoff)
 89% █████████████████████████    R2  (1ª semana)
 79% ██████████████████████       R3  (2ª semana)
 68% ███████████████████          R5  (mês 1)
 58% ████████████████             R6-R11 (mês 2-3, estabilização)
 63% █████████████████            R12 (pico pontual)
 37% ██████████                   R16-R18 (FADIGA DO MEIO)
 47% █████████████                R19-R26 (recuperação pré-C2)
```

---

## 3. Curva de Retenção — Ciclo 2

Dos 30 membros no kickoff C2 (10/Set/2025):

| Reunião | Data | Retidos | % |
|---------|------|---------|---|
| Kickoff | 10/Set | 30 | 100% |
| R2 | 24/Set | 21 | 70% |
| R3 | 08/Out | 19 | 63% |
| R5 | 22/Out | 20 | 67% |
| R6 | 05/Nov | 16 | 53% |
| R8 | 19/Nov | 11 | 37% |
| R9 | 03/Dez | 17 | 57% |
| R10 | 12/Dez | 20 | 67% |

**Insight:** Mesmo padrão do C1 — queda forte na 1ª semana (30% dropout), estabilização, fadiga em Nov, e recuperação em Dez (encerramento do ciclo atrai de volta). A reunião de encerramento/celebração funciona como reativação.

---

## 4. Dropout C3 — Análise em Profundidade (Dado Acionável)

Kickoff C3 (05/Mar): 41 presentes
Geral C3 #1 (12/Mar): 23 presentes
**18 faltaram à 1ª reunião regular (44%)**

### Classificação dos 18 que faltaram

**Veteranos (31+ presenças C1/C2) — 6 pessoas:**

| Nome | Tribo | Score C1/C2 | Risco |
|------|-------|-------------|-------|
| Fabricio Costa | ROI & Portfólio | 58 | BAIXO — #1 histórico, provavelmente pontual |
| Gustavo Batista | Agentes Autônomos | 31 | MÉDIO — 2º semestre C2 mais irregular |
| Débora Moura | Agentes Autônomos | 24 | MÉDIO — líder de tribo C2, perfil de engajamento em tribo > geral |
| Rodrigo Grilo | ROI & Portfólio | 22 | MÉDIO — caiu em jun-ago C1 mas voltou |
| Francisco José | Inclusão & Comunicação | 20 | MÉDIO — mais ativo em tribo do que geral |
| Cíntia Simões | Cultura & Change | 16 | ALTO — participação declinante no C2 |

**Recomendação:** Veteranos com score >20 provavelmente voltam sozinhos. Cíntia (16, tendência de queda) é o caso que merece atenção do líder da T4.

**Retornantes (1-10 presenças) — 3 pessoas:**

| Nome | Tribo | Score | Risco |
|------|-------|-------|-------|
| Denis Vasconcelos | ROI & Portfólio | 8 | ALTO — irregular no C2, requer acompanhamento |
| Maria Luiza | Inclusão & Comunicação | 5 | ALTO — participou pouco no C2 |
| Ana Carla Cavalcante | Inclusão & Comunicação | 1 | CRÍTICO — líder T8, quase nenhum histórico |

**Recomendação:** Ana Carla é líder da T8 e tem 1 presença histórica. Isso é um sinal de alarme para a tribo inteira. Requer intervenção direta do GP.

**Novatos C3 (0 presenças anteriores) — 5 pessoas:**

| Nome | Tribo | Risco |
|------|-------|-------|
| Vinicyus Saraiva | Governança & Trustworthy AI | ALTO |
| Marcel Fleming | TMO & PMO do Futuro | ALTO — é líder da T3! |
| Letícia R. Vieira | TMO & PMO do Futuro | ALTO |
| Stephania Marta | ROI & Portfólio | ALTO |
| Leandro Mota | Radar Tecnológico | ALTO |

**Recomendação:** Marcel Fleming é líder da T3 e faltou à 1ª geral. Dois líderes de tribo (Marcel + Ana Carla) faltaram — isso compromete a cohesão das tribos. Padrão histórico mostra que novatos que faltam à 1ª reunião regular têm <30% de chance de se manterem ativos.

### Quem NÃO foi ao kickoff NEM à geral (desaparecidos)

| Nome | Tribo | Tipo | Ação |
|------|-------|------|------|
| Andressa Martins | Agentes Autônomos | Veterana (54!) | Confirmar se está ativa no C3 |
| Italo Soares | ROI & Portfólio | Veterano (51!) | Confirmar se está ativo no C3 |
| Lídia Do Vale | TMO & PMO do Futuro | Veterana (34) | Era líder T4 C2 — confirmar status C3 |
| Ricardo Santos | Agentes Autônomos | Novo | Possível desistência silenciosa |
| Wellinghton Barboza | Talentos & Upskilling | Novo | Possível desistência silenciosa |
| Leonardo Chaves | Radar Tecnológico | Novo | Possível desistência silenciosa |
| Lorena Almeida | Radar Tecnológico | Retornante (4) | Possível desistência silenciosa |

**Alerta crítico:** Andressa (54) e Italo (51) são o #2 e #4 em presença histórica. Se eles saíram do C3, é uma perda enorme. Confirmar com urgência.

---

## 5. Distribuição de Engajamento (Membros Operacionais, C1+C2)

| Bucket | Membros | % | Perfil |
|--------|---------|---|--------|
| A: ≥75% (Core) | 3 | 6% | Vitor, Fabricio, Andressa — "espinha dorsal" |
| B: 50-74% (Regular) | 5 | 10% | Italo, Mayanna, Marcos Costa, Rodrigo, Lídia |
| C: 25-49% (Occasional) | 1 | 2% | Gustavo |
| D: 1-24% (At risk) | 15 | 31% | João Coelho, Leticia, Débora, Luciana... |
| E: 0% (Ghost/C3-only) | 26 | 52% | Novatos C3 + inativos |

**Insight:** A distribuição é bimodal — tem um grupo pequeno muito engajado (8 pessoas, Buckets A+B) e uma cauda longa de baixo engajamento. Não existe "classe média" de engajamento. Isso é típico de comunidades voluntárias.

**A regra 8/50:** 8 pessoas (16%) geram mais de 50% da presença total. Se qualquer um desses 8 sair, o impacto é desproporcional.

---

## 6. Retenção por Tribo (C1+C2)

| Tribo | Reuniões | Avg/reunião | Membros únicos | Retenção* |
|-------|----------|-------------|----------------|-----------|
| T6: ROI & Portfólio | 15 | 4.5 | 7 | ⭐ Melhor |
| T3: TMO & PMO (C2) | 29 | 3.8 | 6 | Boa |
| T4: Cultura & Change | 16 | 3.4 | 6 | Regular |
| T5: Talentos & Upskilling | 5 | 2.6 | 4 | Fraca |

*Retenção medida como % de membros que participam de >50% das reuniões da tribo.

**T6 destaque:** Maior média por reunião e mais reuniões registradas. Débora (líder C2) conseguiu manter cohesão. Membros fixos: Débora, João Coelho, Letícia, Francisco — todos com 10+ presenças de tribo.

**T5 alerta:** Apenas 5 reuniões registradas, avg 2.6. Roberto Macêdo liderava mas a tribo era pequena. No C3, T5 (Talentos & Upskilling) não tem dados de tribo ainda.

**T1, T2, T7, T8:** Sem dados de tribo no C1/C2 (tribos novas ou reestruturadas no C3). T1 (Radar Tecnológico) teve sua 1ª reunião em 09/Mar — ainda em fase de formação.

---

## 7. Horas de Impacto — Cálculo Real

| Tipo | Eventos | Pessoas×Evento | Horas | % do total |
|------|---------|----------------|-------|-----------|
| Reunião Geral | 34 | 483 | 556 | 63% |
| Reunião Tribo | 58 | 246 | 246 | 28% |
| Kickoff | 1 | 41 | 62 | 7% |
| Liderança | 3 | 13 | 13 | 2% |
| **Total** | **96** | **783** | **877** | **100%** |

**Meta anual: 1.800h | Atual: 877h (49%)**
**Mês: 3 de 12 (25% do ano)**
**Projeção linear: on track (49% realizado em 25% do tempo)**

**Insight:** As reuniões gerais são responsáveis por 63% das horas de impacto. Se a presença nas gerais cair, o KPI de horas cai desproporcionalmente. O kickoff sozinho gerou 62h (7%) em uma única reunião — eventos com alta presença são multiplicadores de impacto.

---

## 8. As 3 Ondas de Dropout (Padrão Identificado)

Com base nos dados de C1 e C2, o dropout segue 3 ondas previsíveis:

### Onda 1: "No-show" (Semana 1-2)
- **Quando:** Kickoff → 1ª reunião regular
- **Tamanho:** 30-44% dos participantes do kickoff
- **Quem:** Mistura de curiosos, conflito de horário, e quem "só queria ver"
- **Causa:** Expectativa vs realidade. Kickoff é inspiracional, reunião regular é trabalho.
- **Intervenção:** Mensagem individual do líder de tribo nas primeiras 48h pós-ausência: "Sentimos sua falta, aqui está o que discutimos, sua contribuição é importante para X."

### Onda 2: "Fadiga do meio" (Mês 3-5)
- **Quando:** Após estabilização inicial, a presença cai novamente
- **Tamanho:** 15-20% adicionais
- **Quem:** Membros que participaram regularmente mas perderam momentum
- **Causa:** Falta de entregas tangíveis. O membro não vê seu trabalho se tornando resultado.
- **Intervenção:** Mini-entregas visíveis (publicar rascunho, apresentar para o grupo, receber feedback). Cada contribuição precisa de "acknowledgement" público.

### Onda 3: "Recuperação pré-encerramento" (Último mês)
- **Quando:** Último mês do ciclo
- **Tamanho:** +10-15% voltam
- **Quem:** Membros que sumiram mas querem o "crédito" da participação
- **Causa:** FOMO + reconhecimento na cerimônia de encerramento
- **Intervenção:** Manter. A celebração de fim de ciclo é a ferramenta de reativação mais eficaz. O sistema de gamificação pode amplificar isso.

---

## 9. Recomendações Prioritárias

### Imediata (esta semana)
1. **Contatar Marcel Fleming e Ana Carla Cavalcante** — dois líderes de tribo que faltaram à 1ª geral. Se líderes somem, a tribo desmorona.
2. **Confirmar status de Andressa (54) e Italo (51)** — veteranos ausentes de ambos os eventos C3.
3. **WhatsApp individual para os 5 novatos** que faltaram à geral — janela de recuperação é de ~2 semanas.

### Curto prazo (W134a → dashboard)
4. **Implementar o lançamento de presença** para que os dados continuem sendo capturados sem planilha.
5. **Configurar alertas de 3 faltas consecutivas** — teria detectado Cíntia, Denis e Maria Luiza no C2 antes de sumirem.

### Médio prazo (W134b → dashboard completo)
6. **Visão "Você vs Tribo vs Geral"** para cada membro — cria accountability social.
7. **Heatmap de presença por tribo** no dashboard do GP — identifica tribos em risco antes que o problema se espalhe.

### Estratégico
8. **Meta de retenção por ciclo:** definir target (sugestão: reter 70% do kickoff até o final do ciclo). Hoje está em ~55%.
9. **"Mini-entregas" a cada 4 semanas** — combate a Onda 2 (fadiga do meio). Cada tribo deve ter uma entrega visível a cada mês.
10. **Reconhecimento contínuo** no portal — não esperar a celebração de fim de ciclo. Gamificação (XP por presença, por entrega) já está na arquitetura.

---

## 10. Próximos Passos Analíticos

Com o dashboard de presença implementado (W134), as seguintes análises se tornam possíveis em tempo real:

- **Correlação presença × produção:** membros mais presentes produzem mais board_items?
- **Efeito líder:** tribos cujo líder tem >80% de presença retêm melhor?
- **Horário e dia:** reuniões em certos dias/horários retêm melhor? (dados de `meeting_day` + `meeting_time_start` das tribos)
- **Capítulo de origem:** PMI-GO retém diferente de PMI-CE? (dados de chapter no member table)

Esses são inputs para o executive report (W105) e para calibrar as metas do C4.
