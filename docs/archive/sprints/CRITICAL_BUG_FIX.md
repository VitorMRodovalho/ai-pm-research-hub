# CRITICAL_BUG_FIX

**Alvo:** Contador 0/6 e Curatorship Kick-off

**Contexto:** Bugs residuais de produção estão afetando a percepção de valor do portal.

**Missão:**

1. **Fix Contador:** No `TribesSection.astro`, verifique por que `updateUI()` está renderizando zero. Verifique se a variável `TRIBE_IDS` está sendo populada corretamente antes da chamada da RPC `count_tribe_slots`. Adicione logs de depuração no client-side para rastrear o JSON de retorno.
2. **Fix Curatorship:** Depure o acesso à rota `/admin/curatorship`. Remova qualquer lógica que force o logout em caso de Tier insuficiente; em vez disso, redirecione para `/admin` com um Toast de erro. Verifique se o middleware está validando corretamente o `MEMBER` antes de processar a página.
3. **Comms Dashboard:** Resolva o estado de "CARREGANDO" infinito na seção de métricas por canal. Verifique se a tabela `comms_metrics_daily` possui dados para os últimos 14 dias; se estiver vazia, mostre um "Empty State" em vez de um loader infinito.
