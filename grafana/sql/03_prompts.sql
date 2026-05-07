-- МирГПТ: топ системных промптов / скиллов
-- Экспортировать в data/prompts.csv

-- Топ скиллов по количеству чатов (через skills.name, сматченных по system_prompt)
SELECT
    COALESCE(s.name, '(без промпта)')                                           AS prompt_name,
    s.category                                                                  AS category,
    COUNT(DISTINCT c.id)                                                        AS chats_count,
    COUNT(DISTINCT c.user_id)                                                   AS unique_users,
    -- доля от всех чатов за период
    ROUND(
        COUNT(DISTINCT c.id)::numeric
        / NULLIF(SUM(COUNT(DISTINCT c.id)) OVER (), 0) * 100,
        1
    )                                                                           AS pct_of_total

FROM chats c
LEFT JOIN skills s ON s.system_prompt = c.system_prompt
                   AND s.tenant_id = c.tenant_id
WHERE c.created_at BETWEEN :'date_from' AND :'date_to'
GROUP BY s.name, s.category
ORDER BY chats_count DESC
LIMIT 20;
