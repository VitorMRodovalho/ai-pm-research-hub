Essa é uma excelente visão de fechamento de funil. Se o PostHog mede o que acontece **dentro** da plataforma (Produto), nós precisamos medir o que acontece **fora** dela (Marketing/Aquisição) para o time de comunicação saber se o esforço deles está gerando resultado.

No entanto, integrar redes sociais levanta uma **Bandeira Vermelha gigante de Dívida Técnica**.

Aqui está a minha análise arquitetural, as preocupações que você deve ter e a "Bala de Prata" para resolver isso com custo zero e zero atrito de desenvolvimento.

---

### 1. 🚨 A Grande Preocupação (O que NÃO fazer)

**Nunca tente programar integrações diretas de APIs de redes sociais no seu código Astro ou Supabase.**

* *O Motivo:* As APIs do Meta (Instagram), LinkedIn e Google (YouTube) são notórias por mudarem constantemente. Os *Tokens de Autenticação* do Instagram, por exemplo, expiram a cada 60 dias e exigem revalidação manual.
* Se você pedir para o seu time de desenvolvimento criar gráficos puxando dados do LinkedIn direto no banco de dados, eles passarão 30% do tempo deles dando manutenção em tokens quebrados, em vez de melhorarem a plataforma. O banco de dados do Supabase **não é o lugar para guardar "quantidade de likes"**.

---

### 2. A Solução "Custo Zero" e "Zero Fricção" (Looker Studio)

Lembra de como resolvemos o painel de Analytics com um **Iframe do PostHog**? Faremos exatamente a mesma coisa, mas usando o **Google Looker Studio** (antigo Google Data Studio).

O Looker Studio é 100% gratuito, corporativo e feito para isso.

**A Arquitetura Recomendada:**

1. **YouTube:** O Looker Studio tem um conector nativo e gratuito para o YouTube Analytics. É só plugar em 2 cliques.
2. **Instagram e LinkedIn:** Como conectores diretos no Looker costumam ser pagos (ex: Supermetrics), usamos a nossa ferramenta de automação (Make.com ou n8n).
* Você cria um robô no Make.com que roda **1 vez por semana** (gasta quase zero do plano gratuito).
* Ele vai no LinkedIn e no Instagram, pega os seguidores, impressões e cliques, e joga numa planilha gratuita do **Google Sheets**.
* O Looker Studio lê esse Google Sheets e gera os gráficos lindíssimos em tempo real.


3. **No nosso Hub:** O time de desenvolvimento cria a página `/admin/comunicacao` e coloca o `<iframe src="link-do-looker-studio">`.

**O Resultado:** A Mayanna (Líder de Comunicação) e você (GP) abrem o painel administrativo e veem tudo centralizado. Se a API do Instagram mudar amanhã, o seu site não quebra; você só ajusta o robô no Make.com.

---

### 3. Quais KPIs exibir (Boas Práticas para o Time de Comunicação)

Para que esse dashboard não vire apenas um painel de métricas de vaidade (quantidade de likes), recomendo orientar o time de comunicação a focar em **Métricas de Funil e Ação**:

* 🔴 **YouTube:** * *Métrica:* Watch Time (Tempo de Exibição) e Origem do Tráfego.
* *Por quê?* Mostra se os vídeos das reuniões de tribo ou tutoriais estão retendo os pesquisadores e o público.


* 🔵 **LinkedIn (O canal mais forte do PMI):** * *Métrica:* CTR (Click-Through Rate) dos links dos posts.
* *Por quê?* O objetivo principal do LinkedIn é gerar autoridade e levar o público a ler os artigos dos pesquisadores no nosso Hub. Se tem muita impressão e pouco clique, a *Copy* (texto) precisa melhorar.


* 🟣 **Instagram:** * *Métrica:* Salvamentos (Saves) e Compartilhamentos.
* *Por quê?* O algoritmo do Instagram já não liga para "Likes". Um post sobre "Framework de IA" que é muito salvo significa que gerou valor educacional real para a comunidade.



---

### 4. Como gerir os Acessos (LGPD e Governança)

Assim como fizemos no PostHog, este dashboard do Looker Studio deve ser restrito:

* **Quem vê:** `superadmin` (GP), `manager` (Co-GP), e quem tem a designação `comms_leader` e `comms_member`.
* **Por quê?** Os pesquisadores das tribos técnicas não precisam ver métricas de engajamento do Instagram; isso só gera poluição visual para eles.
* **LGPD:** Como o Looker Studio vai mostrar apenas dados **agregados** e públicos (ex: "Tivemos 1.000 visualizações este mês"), **não há nenhuma implicação de LGPD**. Você não está rastreando PII (Informação Pessoal Identificável) de quem curtiu.

### Resumo do Plano de Ação (Para adicionar ao Backlog - Wave 5)

Você pode empacotar essa ideia no Épico de Comunicação que conversamos anteriormente:

* `[S-COM6]` **Dashboard Central de Mídia (Looker Studio):** Construir painel no Google Looker Studio consolidando YouTube (nativo) e LinkedIn/Instagram (via Google Sheets/Make.com). Embeber via Iframe na rota `/admin/comms` restrito à gerência e equipe de comunicação.

Com isso, você fecha o ciclo perfeito de Produto:
O **Supabase** cuida do Banco de Dados / Regras de Negócio;
O **PostHog** cuida da Experiência do Usuário Interno;
O **Looker Studio** cuida da Performance Externa.

Tudo orquestrado de dentro do Hub, e o melhor: sem gastar o caixa do projeto!
