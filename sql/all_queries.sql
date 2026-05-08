-- МирГПТ: все запросы дашборда
-- Запустить все через Run Script (Alt+X), экспортировать каждую вкладку результатов в CSV
--
-- !! ЗАДАТЬ ПЕРИОД: используйте Ctrl+H в DBeaver и замените даты !!
--    Текущий период: 2026-04-01 — 2026-12-31


-- ══════════════════════════════════════════════════════════════════════
-- 1. СВОДКА → экспортировать как: data/summary.csv
-- ══════════════════════════════════════════════════════════════════════
WITH
users_stats AS (
    SELECT
        COUNT(DISTINCT u.id)                                                    AS total_users,
        COUNT(DISTINCT u.id) FILTER (
            WHERE u.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
        )                                                                       AS new_users,
        ROUND(
            (COUNT(DISTINCT (u.id::text || DATE(m.created_at)::text))::numeric
            / NULLIF(
                DATE_PART('day', '2026-12-31'::timestamptz - '2026-04-01'::timestamptz),
                0
            ))::numeric,
            1
        )                                                                       AS dau_avg,
        COUNT(DISTINCT u.id) FILTER (
            WHERE m.created_at >= NOW() - INTERVAL '7 days'
        )                                                                       AS wau,
        COUNT(DISTINCT u.id) FILTER (
            WHERE m.created_at >= NOW() - INTERVAL '30 days'
        )                                                                       AS mau
    FROM users u
    JOIN chats c ON c.user_id = u.id
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND m.role = 'user'
),
activity_stats AS (
    SELECT
        COUNT(m.id) FILTER (WHERE m.role = 'user')                              AS total_questions,
        COUNT(DISTINCT c.id)                                                    AS total_chats,
        COUNT(DISTINCT c.user_id)                                               AS active_users,
        ROUND(
            (COUNT(m.id) FILTER (WHERE m.role = 'user')::numeric
            / NULLIF(COUNT(DISTINCT c.user_id), 0))::numeric, 1
        )                                                                       AS avg_questions_per_user,
        ROUND(
            (COUNT(m.id) FILTER (WHERE m.role = 'user')::numeric
            / NULLIF(COUNT(DISTINCT c.id), 0))::numeric, 1
        )                                                                       AS avg_questions_per_chat,
        SUM(m.token_count)                                                      AS total_tokens
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
),
ratings_stats AS (
    SELECT
        COUNT(*) FILTER (WHERE m.feedback_vote = 'up')                          AS likes,
        COUNT(*) FILTER (WHERE m.feedback_vote = 'down')                        AS dislikes,
        COUNT(*) FILTER (WHERE m.feedback_vote IS NOT NULL)                     AS total_votes,
        ROUND(
            (COUNT(*) FILTER (WHERE m.feedback_vote = 'up')::numeric
            / NULLIF(COUNT(*) FILTER (WHERE m.feedback_vote IS NOT NULL), 0) * 100)::numeric, 1
        )                                                                       AS like_pct
    FROM messages m
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND m.role = 'assistant'
),
latency_stats AS (
    SELECT
        ROUND(AVG((m.metadata->>'llmMs')::numeric)::numeric, 0)                 AS llm_avg_ms,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY (m.metadata->>'llmMs')::numeric
        )::numeric, 0)                                                          AS llm_median_ms,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
            ORDER BY (m.metadata->>'llmMs')::numeric
        )::numeric, 0)                                                          AS llm_p95_ms,
        ROUND(AVG((m.metadata->>'ragMs')::numeric)::numeric, 0)                 AS rag_avg_ms,
        ROUND(AVG((m.metadata->>'ttftMs')::numeric)::numeric, 0)                AS ttft_avg_ms,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
            ORDER BY (m.metadata->>'ttftMs')::numeric
        )::numeric, 0)                                                          AS ttft_p95_ms
    FROM messages m
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND m.role = 'assistant'
      AND m.metadata->>'llmMs' IS NOT NULL
)
SELECT
    u.total_users, u.new_users, u.dau_avg, u.wau, u.mau,
    a.total_questions, a.total_chats, a.avg_questions_per_user,
    a.avg_questions_per_chat, a.total_tokens,
    r.likes, r.dislikes, r.total_votes, r.like_pct,
    l.llm_avg_ms, l.llm_median_ms, l.llm_p95_ms,
    l.rag_avg_ms, l.ttft_avg_ms, l.ttft_p95_ms
FROM users_stats u, activity_stats a, ratings_stats r, latency_stats l;


-- ══════════════════════════════════════════════════════════════════════
-- 2. ДИНАМИКА ПО ДНЯМ → экспортировать как: data/daily.csv
-- ══════════════════════════════════════════════════════════════════════
SELECT
    DATE(m.created_at)                                                          AS day,
    COUNT(m.id) FILTER (WHERE m.role = 'user')                                  AS questions,
    COUNT(DISTINCT c.user_id)                                                   AS active_users,
    COUNT(DISTINCT c.id)                                                        AS chats,
    COUNT(*) FILTER (WHERE m.role = 'assistant' AND m.feedback_vote = 'up')     AS likes,
    COUNT(*) FILTER (WHERE m.role = 'assistant' AND m.feedback_vote = 'down')   AS dislikes
FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
GROUP BY DATE(m.created_at)
ORDER BY day;


-- ══════════════════════════════════════════════════════════════════════
-- 3. ТОП ПРОМПТОВ → экспортировать как: data/prompts.csv
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COALESCE(s.name, '(без промпта)')                                           AS prompt_name,
    s.category,
    COUNT(DISTINCT c.id)                                                        AS chats_count,
    COUNT(DISTINCT c.user_id)                                                   AS unique_users,
    COUNT(m.id) FILTER (WHERE m.feedback_vote = 'up')                           AS likes,
    COUNT(m.id) FILTER (WHERE m.feedback_vote = 'down')                         AS dislikes,
    ROUND(
        (COUNT(DISTINCT c.id)::numeric
        / NULLIF(SUM(COUNT(DISTINCT c.id)) OVER (), 0) * 100)::numeric, 1
    )                                                                           AS pct_of_total,
    ROUND(
        (COUNT(m.id) FILTER (WHERE m.feedback_vote = 'down')::numeric
        / NULLIF(COUNT(m.id) FILTER (WHERE m.feedback_vote IS NOT NULL), 0) * 100)::numeric, 1
    )                                                                           AS dislike_pct
FROM chats c
LEFT JOIN skills s ON s.system_prompt = c.system_prompt AND s.tenant_id = c.tenant_id
LEFT JOIN messages m ON m.chat_id = c.id AND m.role = 'assistant'
WHERE c.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
GROUP BY s.name, s.category
ORDER BY chats_count DESC
LIMIT 20;


-- ══════════════════════════════════════════════════════════════════════
-- 4. ЛАТЕНТНОСТЬ ПО ЧАСАМ → экспортировать как: data/latency_hour.csv
-- ══════════════════════════════════════════════════════════════════════
SELECT
    EXTRACT(HOUR FROM m.created_at)                                             AS hour_of_day,
    ROUND(AVG((m.metadata->>'llmMs')::numeric)::numeric, 0)                     AS llm_avg_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
        ORDER BY (m.metadata->>'llmMs')::numeric
    )::numeric, 0)                                                              AS llm_p95_ms,
    COUNT(*)                                                                    AS responses_count
FROM messages m
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND m.role = 'assistant'
  AND m.metadata->>'llmMs' IS NOT NULL
GROUP BY EXTRACT(HOUR FROM m.created_at)
ORDER BY hour_of_day;


-- ══════════════════════════════════════════════════════════════════════
-- 5. RETENTION → экспортировать как: data/retention.csv
--    Результат: одна строка (d1, d7, power, stickiness)
--    d1 / d7 возвращаются как доли 0–1, дашборд умножает на 100
-- ══════════════════════════════════════════════════════════════════════
WITH first_seen AS (
    -- Первый день активности каждого пользователя за период
    SELECT c.user_id, MIN(DATE(m.created_at)) AS d0
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
),
returns AS (
    -- Вернулся ли пользователь на следующий день (D1) и в течение недели (D7)
    SELECT f.user_id, f.d0,
        MAX(CASE WHEN DATE(m.created_at) = f.d0 + 1 THEN 1 ELSE 0 END)                    AS d1,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0 + 1 AND f.d0 + 7 THEN 1 ELSE 0 END) AS d7
    FROM first_seen f
    JOIN chats c2 ON c2.user_id = f.user_id
    JOIN messages m ON m.chat_id = c2.id
    GROUP BY f.user_id, f.d0
),
power AS (
    -- Power users: суммарно ≥ 10 ответов на пользователя за каждую неделю периода
    SELECT COUNT(*) AS power_users FROM (
        SELECT c.user_id
        FROM chats c
        JOIN messages m ON m.chat_id = c.id
        WHERE m.role = 'assistant'
          AND m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
        GROUP BY c.user_id
        HAVING COUNT(*) >= 10 * GREATEST(1,
            EXTRACT(week FROM AGE('2026-12-31'::timestamptz, '2026-04-01'::timestamptz))
        )
    ) t
),
stickiness AS (
    -- DAU/MAU на дату конца периода
    SELECT
        (SELECT COUNT(DISTINCT c.user_id)
         FROM chats c JOIN messages m ON m.chat_id = c.id
         WHERE m.created_at >= '2026-12-31'::timestamptz - INTERVAL '1 day'
           AND m.created_at <  '2026-12-31'::timestamptz)::float
        / NULLIF(
            (SELECT COUNT(DISTINCT c.user_id)
             FROM chats c JOIN messages m ON m.chat_id = c.id
             WHERE m.created_at >= '2026-12-31'::timestamptz - INTERVAL '30 days'),
            0
        ) AS s
)
SELECT
    AVG(d1)::float                      AS d1,
    AVG(d7)::float                      AS d7,
    (SELECT power_users FROM power)     AS power,
    (SELECT s FROM stickiness)          AS stickiness
FROM returns
WHERE d0 BETWEEN '2026-04-01'::date AND '2026-12-31'::date;


-- ══════════════════════════════════════════════════════════════════════
-- 6. КАЧЕСТВО → экспортировать как: data/quality.csv
--    Результат: одна строка
-- ══════════════════════════════════════════════════════════════════════
WITH chats_stats AS (
    SELECT
        ROUND(
            SUM(CASE WHEN message_count <= 2 THEN 1 ELSE 0 END)::numeric
            / NULLIF(COUNT(*), 0) * 100,
            1
        )                                                                       AS single_msg_pct,
        SUM(CASE WHEN message_count <= 2 THEN 1 ELSE 0 END)                    AS single_msg_chats,
        COUNT(*)                                                                AS total_chats
    FROM chats
    WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
),
msg_stats AS (
    SELECT
        -- Error rate: доля ответов ассистента со статусом ошибки
        ROUND(
            SUM(CASE WHEN role = 'assistant' AND status = 'error' THEN 1 ELSE 0 END)::numeric
            / NULLIF(SUM(CASE WHEN role = 'assistant' THEN 1 ELSE 0 END), 0) * 100,
            1
        )                                                                       AS error_rate,
        -- Timeout rate: доля ответов где llmMs > 30 000 мс
        ROUND(
            SUM(CASE WHEN role = 'assistant'
                      AND (metadata->>'llmMs')::numeric > 30000 THEN 1 ELSE 0 END)::numeric
            / NULLIF(SUM(CASE WHEN role = 'assistant' THEN 1 ELSE 0 END), 0) * 100,
            1
        )                                                                       AS timeout_rate
    FROM messages
    WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
)
SELECT
    c.single_msg_pct,
    c.single_msg_chats,
    c.total_chats,
    m.error_rate,
    m.timeout_rate
FROM chats_stats c, msg_stats m;
