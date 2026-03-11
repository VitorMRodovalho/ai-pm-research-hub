# 📊 Product Vision: AI & PM Research Hub Analytics V2

Este documento consolida a transição do nosso atual painel de métricas (focado em volume estático) para um modelo de Analytics focado em **Impacto (Educação)** e **Retorno sobre Investimento (ROI de Capítulos)**.

---

## 1. 💾 Para o Time de Dados: Queries e Views (PostgreSQL / Supabase)

Para suportar as histórias de negócio sobre conversão de membros do hub em filiados do PMI, precisamos cruzar as datas de entrada no programa com as datas de filiação.

Abaixo está a query SQL para criar a *View* de Atribuição de Filiação (ROI). 

**Regra de Negócio:** Se um membro do hub realizou a filiação no PMI (`affiliated_since`) em uma janela de até 30 dias antes de entrar no Hub ou até 90 dias depois, o Hub ganha a "Atribuição" dessa conversão.

```sql
-- View: vw_roi_chapter_conversion
-- Objetivo: Mostrar a conversão de filiados por capítulo gerada pelo Hub
CREATE OR REPLACE VIEW public.vw_roi_chapter_conversion AS
SELECT
    m.chapter,
    COUNT(m.id) AS total_membros_ativos,
    SUM(
        CASE WHEN a.is_current = true THEN 1 ELSE 0 END
    ) AS total_filiados_ativos,
    SUM(
        CASE
            WHEN a.affiliated_since IS NOT NULL
                 -- Atribuição: Filiou-se 30 dias antes ou até 90 dias após entrar no Hub
                 AND a.affiliated_since >= (m.created_at - INTERVAL '30 days')
                 AND a.affiliated_since <= (m.created_at + INTERVAL '90 days')
            THEN 1
            ELSE 0
        END
    ) AS conversoes_atribuidas
FROM
    public.members m
LEFT JOIN
    public.member_chapter_affiliations a ON m.id = a.member_id
WHERE
    (m.is_active = true OR m.current_cycle_active = true)
    AND m.chapter IS NOT NULL
GROUP BY
    m.chapter;

COMMENT ON VIEW public.vw_roi_chapter_conversion IS 'Mede as filiações ao PMI influenciadas diretamente pela entrada no Hub de IA.';
```
