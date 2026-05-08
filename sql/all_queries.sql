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
        COUNT(*) FILTER (WHERE m.feedback_vote = 'like')                        AS likes,
        COUNT(*) FILTER (WHERE m.feedback_vote = 'dislike')                     AS dislikes,
        COUNT(*) FILTER (WHERE m.feedback_vote IS NOT NULL)                     AS total_votes,
        ROUND(
            (COUNT(*) FILTER (WHERE m.feedback_vote = 'like')::numeric
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
    COUNT(*) FILTER (WHERE m.role = 'assistant' AND m.feedback_vote = 'like')   AS likes,
    COUNT(*) FILTER (WHERE m.role = 'assistant' AND m.feedback_vote = 'dislike') AS dislikes
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
    COUNT(m.id) FILTER (WHERE m.feedback_vote = 'like')                         AS likes,
    COUNT(m.id) FILTER (WHERE m.feedback_vote = 'dislike')                      AS dislikes,
    ROUND(
        (COUNT(DISTINCT c.id)::numeric
        / NULLIF(SUM(COUNT(DISTINCT c.id)) OVER (), 0) * 100)::numeric, 1
    )                                                                           AS pct_of_total,
    ROUND(
        (COUNT(m.id) FILTER (WHERE m.feedback_vote = 'dislike')::numeric
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
-- ДИАГНОСТИКА: реальные значения feedback_vote
-- Запустить если лайки/дизлайки показывают 0
-- ══════════════════════════════════════════════════════════════════════
SELECT
    feedback_vote,
    COUNT(*) AS cnt
FROM messages
WHERE feedback_vote IS NOT NULL
GROUP BY feedback_vote
ORDER BY cnt DESC;
