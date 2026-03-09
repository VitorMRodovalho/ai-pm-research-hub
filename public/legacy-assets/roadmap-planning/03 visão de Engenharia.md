A sua visão de Engenharia de Dados é excepcional. Muitos projetos morrem exatamente aqui: constroem uma interface linda, mas o banco de dados vira um "monstro de Frankenstein" cheio de colunas legadas (`role_old`, `role_new`, `role_v3`), o que impossibilita a geração de relatórios (BI) corretos no futuro.

Você tocou no conceito de Ouro: **Modelagem Dimensional (Star Schema) - Fato e Dimensão.**

Vamos analisar o nosso banco de dados sob essa ótica de longo prazo, respondendo às suas preocupações sobre limites, sujeira legada e transição. Ao final, trago o texto para a nossa documentação de Sustentabilidade.

---

### 1. Limites de Infraestrutura: Vamos bater no teto do Supabase?

A resposta curta é: **Não tão cedo.**
O plano gratuito (Free Tier) do Supabase é um dos mais generosos do mercado:

* **Banco de Dados (PostgreSQL): 500 MB.** Pode parecer pouco para quem está acostumado com HDs de Terabytes, mas dados de texto (JSON, UUIDs, strings) ocupam *KiloBytes*. 500MB acomodam facilmente mais de **200.000 registros históricos**. Para um projeto que roda ciclos de 50 a 200 pessoas a cada 6 meses, vocês têm espaço para décadas.
* **Storage (Fotos/Arquivos): 1 GB.** Se cada foto de perfil for comprimida para 100KB (padrão Web), vocês podem armazenar **10.000 fotos de voluntários**.
* **Edge Functions: 500.000 invocações/mês.** O script de Credly e IA não vão arranhar nem 1% disso.

**Conclusão de Infra:** O projeto é 100% factível de ser mantido no plano gratuito indefinidamente, desde que não comecemos a fazer upload de vídeos pesados ou PDFs gigantes diretamente no banco (para isso, usaríamos links externos do Google Drive/YouTube).

---

### 2. Saneamento e Colunas Legadas (Não vamos deixar "sujeira")

Atualmente, na tabela `members`, temos as colunas antigas (`role` e o array `roles`) e as novas (`operational_role` e `designations`). Como garantimos que isso não vire lixo?

**A Estratégia de Transição (Deprecation Rule):**

1. **Fase de Espelho (Onde estamos agora):** Mantemos as colunas antigas para não quebrar a plataforma atual em produção.
2. **Migração do Frontend:** O time de desenvolvimento muda as páginas (ex: `Profile.astro`, `Admin.astro`) para lerem APENAS `operational_role` e `designations`.
3. **Hard Drop (O Saneamento final):** Assim que a *Wave 3* estiver no ar, nós entraremos no SQL e executaremos a limpeza brutal e definitiva:
```sql
ALTER TABLE public.members DROP COLUMN role;
ALTER TABLE public.members DROP COLUMN roles;
-- Adeus código legado! A tabela fica imaculada.

```



---

### 3. A Arquitetura Dimensional (Star Schema do Núcleo)

Para garantir que amanhã vocês possam plugar o PowerBI, o Metabase ou o próprio Supabase Dashboards e extrair relatórios perfeitos, a nossa modelagem **V3** já está desenhada no conceito de **Fatos e Dimensões**.

**As Dimensões (Tabelas de Contexto - O "Quem", "Onde" e "O que"):**

* `dim_members` (Nossa tabela `members` higienizada): Guarda apenas os dados imutáveis ou de contato atual da pessoa (ID, Nome, Email, LinkedIn, Foto). Não guarda histórico.
* `dim_tribes` (Tabela `tribes`): Guarda o nome da tribo, o tema e os OKRs daquela frente de pesquisa.
* `dim_cycles`: (Futura tabela para a Wave 5) Guardará a data de início e fim de cada ciclo, em vez de deixar isso *hardcoded* nas configurações.

**Os Fatos (Tabelas de Ação - O "Quando" e "Quanto"):**

* `fact_cycle_history` (Nossa `member_cycle_history`): Toda vez que um ciclo fecha, ela cruza *Qual Membro* + *Qual Ciclo* + *Qual Papel* + *Qual Tribo*. Isso permite responder: *"Quantos pesquisadores tivemos ativos no PMI-GO em 2024?"*
* `fact_attendance` (Nossa tabela `attendance`): Cruza *Membro* + *Evento* + *XP Ganho*.
* `fact_artifacts`: Cruza *Membro* + *Tribo* + *Tipo de Artefato* (Artigo, Postagem do time de Comunicação).

Essa modelagem impede anomalias. Se a "Tribo 3" mudar de nome no Ciclo 4, os artefatos do Ciclo 3 não vão "quebrar" ou perder a referência, porque as tabelas Fato estão amarradas ao "Ciclo", garantindo a rastreabilidade correta.

---

### 4. Documentação: Sustentabilidade e Stack Tecnológico

Conforme alinhamos, redigi o texto oficial para adicionar ao nosso `README.md` resgatado ou ao nosso `KNOWLEDGE_BASE.md`. Isso protege a sua visão como CPO e serve de "vacina" contra futuros voluntários que queiram inserir ferramentas caras sem necessidade.

Pode repassar este bloco para o time incluir na documentação:

```markdown
## 🌍 Governança Financeira, Sustentabilidade e Tech Stack

O Núcleo IA & GP adota uma política de **"Custo Zero e Alto Valor" (Zero-Cost, High-Value Architecture)**. Sendo uma iniciativa voluntária ligada à comunidade PMI, a nossa arquitetura foi intencionalmente desenhada para não depender de licenças de software pagas, garantindo que o projeto possa existir indefinidamente e ser replicado por outros capítulos sem entraves orçamentários.

### O Nosso Stack "Custo Zero" (Free Tiers)
* **Frontend & Hospedagem:** Astro + Cloudflare Pages (Gratuito, CDN global, limite de banda livre).
* **Banco de Dados & Autenticação:** Supabase / PostgreSQL (Plano gratuito acomoda até 500MB de dados estruturados e 500.000 requisições *serverless*, suficiente para dezenas de milhares de registros históricos).
* **Automações Agnostic:** Priorizamos o uso de Webhooks internos (Edge Functions) e plataformas de plano gratuito robusto (ex: Make.com / n8n) para integrações, ao invés de soluções Enterprise caras.
* **Inteligência Artificial Nativa:** As funcionalidades de IA da plataforma (Assistente de Copy, Análise de Credly) consomem APIs com *Free Tiers* generosos (como Google Gemini / Groq), mantendo o processamento fora da fatura do projeto.

### Política de Adoção de Novas Ferramentas (Tech for Good)
Antes de incorporar ferramentas de terceiros ao nosso fluxo (Kanban, CRMs, etc.), deve-se avaliar:
1. A funcionalidade pode ser construída no nosso próprio painel administrativo (`/admin`) usando o nosso banco de dados relacional? (Prioridade Alta).
2. Se a ferramenta externa for indispensável, o provedor oferece *Grants* (doações de licença) para associações sem fins lucrativos (Non-Profits)? O Núcleo utilizará o CNPJ dos Capítulos PMI parceiros para requerer isenção total.
3. A ferramenta aceita parcerias de permuta em troca de visibilidade ("Powered By") no rodapé da nossa plataforma?

Qualquer dado externo deve ser orquestrado por eventos para o nosso Hub. O Hub é, e sempre será, a única Fonte da Verdade (Source of Truth) para gamificação e métricas do projeto.

```

O projeto está com a base sólida! Banco de dados saneado, arquitetura escalável e documentação blindada. Podemos fechar os requisitos do Backend com chave de ouro!
