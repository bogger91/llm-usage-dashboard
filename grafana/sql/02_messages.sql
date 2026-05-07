-- МирГПТ: метрики активности (сообщения, чаты)
-- Экспортировать в data/messages.csv

SELECT
    -- Всего вопросов пользователей за период
    COUNT(m.id) FILTER (WHERE m.role = 'user')                                  AS total_questions,

    -- Всего чатов за период
    COUNT(DISTINCT c.id)                                                        AS total_chats,

    -- Уникальных активных пользователей за период
    COUNT(DISTINCT c.user_id)                                                   AS active_users,

    -- Среднее вопросов на пользователя
    ROUND(
        COUNT(m.id) FILTER (WHERE m.role = 'user')::numeric
        / NULLIF(COUNT(DISTINCT c.user_id), 0),
        1
    )                                                                           AS avg_questions_per_user,

    -- Среднее вопросов на чат
    ROUND(
        COUNT(m.id) FILTER (WHERE m.role = 'user')::numeric
        / NULLIF(COUNT(DISTINCT c.id), 0),
        1
    )                                                                           AS avg_questions_per_chat,

    -- Всего токенов потреблено
    SUM(m.token_count)                                                          AS total_tokens

FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN :'date_from' AND :'date_to';


-- Динамика сообщений по дням (для графика)
-- Экспортировать отдельно в data/messages_daily.csv
SELECT
    DATE(m.created_at)                                                          AS day,
    COUNT(m.id) FILTER (WHERE m.role = 'user')                                  AS questions,
    COUNT(DISTINCT c.user_id)                                                   AS active_users,
    COUNT(DISTINCT c.id)                                                        AS chats
FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN :'date_from' AND :'date_to'
GROUP BY DATE(m.created_at)
ORDER BY day;
