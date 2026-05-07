-- МирГПТ: оценки сообщений (like / dislike)
-- Экспортировать в data/ratings.csv

-- Итоговое соотношение за период
SELECT
    COUNT(*) FILTER (WHERE m.feedback_vote = 'like')                            AS likes,
    COUNT(*) FILTER (WHERE m.feedback_vote = 'dislike')                         AS dislikes,
    COUNT(*) FILTER (WHERE m.feedback_vote IS NOT NULL)                         AS total_votes,
    ROUND(
        COUNT(*) FILTER (WHERE m.feedback_vote = 'like')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE m.feedback_vote IS NOT NULL), 0) * 100,
        1
    )                                                                           AS like_pct

FROM messages m
JOIN chats c ON c.id = m.chat_id
WHERE m.created_at BETWEEN :'date_from' AND :'date_to'
  AND m.role = 'assistant';


-- Динамика оценок по дням (для графика)
-- Экспортировать отдельно в data/ratings_daily.csv
SELECT
    DATE(m.created_at)                                                          AS day,
    COUNT(*) FILTER (WHERE m.feedback_vote = 'like')                            AS likes,
    COUNT(*) FILTER (WHERE m.feedback_vote = 'dislike')                         AS dislikes
FROM messages m
JOIN chats c ON c.id = m.chat_id
WHERE m.created_at BETWEEN :'date_from' AND :'date_to'
  AND m.role = 'assistant'
  AND m.feedback_vote IS NOT NULL
GROUP BY DATE(m.created_at)
ORDER BY day;


-- Худшие промпты по доле дизлайков
-- Экспортировать отдельно в data/ratings_by_prompt.csv
SELECT
    COALESCE(s.name, '(без промпта)')                                           AS prompt_name,
    COUNT(*) FILTER (WHERE m.feedback_vote = 'like')                            AS likes,
    COUNT(*) FILTER (WHERE m.feedback_vote = 'dislike')                         AS dislikes,
    ROUND(
        COUNT(*) FILTER (WHERE m.feedback_vote = 'dislike')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE m.feedback_vote IS NOT NULL), 0) * 100,
        1
    )                                                                           AS dislike_pct
FROM messages m
JOIN chats c ON c.id = m.chat_id
LEFT JOIN skills s ON s.system_prompt = c.system_prompt
                   AND s.tenant_id = c.tenant_id
WHERE m.created_at BETWEEN :'date_from' AND :'date_to'
  AND m.role = 'assistant'
  AND m.feedback_vote IS NOT NULL
GROUP BY s.name
HAVING COUNT(*) FILTER (WHERE m.feedback_vote IS NOT NULL) >= 5
ORDER BY dislike_pct DESC
LIMIT 10;
