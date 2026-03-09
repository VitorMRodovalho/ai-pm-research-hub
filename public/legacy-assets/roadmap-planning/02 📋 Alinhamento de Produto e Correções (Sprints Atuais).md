📋 Alinhamento de Produto e Correções (Sprints Atuais)
Para: Equipa de Desenvolvimento / Engenharia de Dados
Contexto: Ajustes de hierarquia, correção de bugs de UX mobile e saneamento de dados para o Ciclo 3.

1. Ajuste Arquitetural: Hierarquia de Gestão (Deputy PM)
O Problema: Atualmente, o operational_role do Fabrício Costa está como manager. Sendo a ordenação alfabética, a interface coloca-o na mesma hierarquia do Gerente de Projeto (Vitor).
A Solução: Precisamos diferenciar o GP principal do Co-GP (Vice-GP).

Ação (Base de Dados): Adicionar um novo nível ao operational_role chamado deputy_manager.

Ação (Frontend): Atualizar a lógica de ordenação e os "badges" visuais no perfil.

Nível 2.0: manager (Exibição: Gerente de Projeto).

Nível 2.5: deputy_manager (Exibição: Deputy PM ou Co-Gerente).

Script SQL de correção:

SQL
UPDATE public.members 
SET operational_role = 'deputy_manager' 
WHERE name ILIKE '%Fabricio Costa%';
2. 🐛 BUG CRÍTICO: Input da URL do Credly (Mobile)
O Problema: Utilizadores (Sarah e Fabrício) tentaram colar a URL pública do Credly através do Chrome no iPhone (iOS) e a ação de "Copy/Paste" está impossibilitada ou a falhar na gravação.
Causas Prováveis para a Equipa investigar:

Validação Regex muito estrita: O frontend pode estar a bloquear o paste se a URL copiada do telemóvel vier com parâmetros extra (ex: ?lang=en ou /) que não passam no padrão esperado pelo formulário Astro.

Estado do Formulário (UI): O campo pode estar a perder o foco no mobile ao colar, ou o botão de "Guardar" não está a ser ativado pelo evento de onPaste.

Ação: Testar exaustivamente o formulário da página de Perfil (Profile.astro) em ambiente mobile (iOS Safari/Chrome). Garantir que o campo aceita a colagem e faz o trim() (limpeza de espaços) da URL antes de enviar para o Supabase.

3. Saneamento de Dados (Correções Pontuais)
Alguns dados ficaram perdidos nas migrações anteriores ou estavam incorretos no espelho atual do Ciclo 3. A equipa deve correr este patch SQL:

SQL
-- 1. Restaurar o LinkedIn da Sarah (possivelmente perdido em higienização anterior)
UPDATE public.members 
SET linkedin_url = 'https://www.linkedin.com/in/sarahrodovalho/' 
WHERE name ILIKE '%Sarah Faria%';

-- 2. Corrigir o Papel do Roberto Macêdo (Ele foi Líder nas V1/V2, mas não no Ciclo 3)
UPDATE public.members 
SET operational_role = 'sponsor' -- ou 'researcher', dependendo do papel atual dele
WHERE name ILIKE '%Roberto Macêdo%';
4. Diretriz de Arquitetura (Fim do "Legado")
Nota do GP para a Equipa de Engenharia:
A dificuldade que tivemos nas últimas semanas a gerir quem é Líder, quem foi Líder, e quem tem que "tag", prova que a tabela atual members chegou ao limite.
A partir de agora, a tabela members deve ser tratada apenas como um espelho (snapshot) do momento atual. O tagueamento real, promoções, e entradas/saídas ao longo do tempo têm de ser geridos através da tabela de factos member_cycle_history (aprovada no modelo V3). Uma pessoa pode estar ativa para uma "tag/função" no Ciclo 2 e desligada no Ciclo 3. A arquitetura de frontend deve começar a consumir o histórico de ciclos para renderizar a timeline, deixando a tabela members apenas para dados de contacto e autenticação.

O que isto resolve:
Hierarquia: Coloca o Fabrício formalmente como o seu braço direito (Deputy PM), sem ofuscar a liderança do projeto.

Bug do Credly: Coloca um alerta vermelho para os programadores de frontend reverem o comportamento do formulário em telemóveis.

Limpeza: Resolve imediatamente os problemas da Sarah e do Roberto.

Visão de Futuro: Formaliza à equipa que o seu pensamento (tabelas separadas por ciclo) é a lei arquitetural a seguir de agora em diante.
