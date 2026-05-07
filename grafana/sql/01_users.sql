-- МирГПТ: метрики пользователей
-- Экспортировать в data/users.csv

SELECT
    -- Всего уникальных пользователей за период
    COUNT(DISTINCT u.id)                                                        AS total_users,

    -- Новые пользователи за период (зарегистрировались впервые)
    COUNT(DISTINCT u.id) FILTER (
        WHERE u.created_at BETWEEN :'date_from' AND :'date_to'
    )                                                                           AS new_users,

    -- DAU: среднее уникальных пользователей в день за период
    ROUND(
        COUNT(DISTINCT (u.id, DATE(m.created_at)))::numeric
        / NULLIF(DATE_PART('day', :'date_to'::timestamptz - :'date_from'::timestamptz), 0),
        1
    )                                                                           AS dau_avg,

    -- WAU: уникальных пользователей за последние 7 дней
    COUNT(DISTINCT u.id) FILTER (
        WHERE m.created_at >= NOW() - INTERVAL '7 days'
    )                                                                           AS wau,

    -- MAU: уникальных пользователей за последние 30 дней
    COUNT(DISTINCT u.id) FILTER (
        WHERE m.created_at >= NOW() - INTERVAL '30 days'
    )                                                                           AS mau

FROM users u
JOIN chats c ON c.user_id = u.id
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN :'date_from' AND :'date_to'
  AND m.role = 'user';
