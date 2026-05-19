-- МирГПТ: все данные дашборда — ОДИН запрос, ОДИН CSV
-- Запустить через Run Script (Alt+X) → один результат → экспортировать как: data/all.csv
--
-- !! ЗАДАТЬ ПЕРИОД: Ctrl+H в DBeaver, заменить даты !!
--    Текущий период: 2026-04-01 — 2026-12-31
--
-- Формат: первая колонка _section указывает тип строки:
--   summary      — 1 строка со всеми скалярными KPI
--   daily        — строки по дням (активность)
--   prompts      — строки по промптам (топ-20)
--   latency_hour — строки по часам суток (латентность)

WITH
-- ── Сводка ────────────────────────────────────────────────────────────
users_stats AS (
    SELECT
        COUNT(DISTINCT u.id)                                                    AS total_users,
        COUNT(DISTINCT u.id) FILTER (
            WHERE u.created_at >= NOW() - INTERVAL '7 days'
        )                                                                       AS new_users_7d,
        COUNT(DISTINCT u.id) FILTER (
            WHERE u.created_at >= NOW() - INTERVAL '30 days'
        )                                                                       AS new_users_30d,
        COUNT(DISTINCT u.id) FILTER (
            WHERE u.created_at >= NOW() - INTERVAL '90 days'
        )                                                                       AS new_users_90d,
        ROUND(
            COUNT(DISTINCT (u.id, DATE(m.created_at)))::numeric
            / NULLIF(
                DATE_PART('day', '2026-12-31'::timestamptz - '2026-04-01'::timestamptz)::numeric,
                0
            ),
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
        COUNT(m.id) FILTER (WHERE m.role = 'assistant')                         AS total_answers,
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
),
-- ── Retention ─────────────────────────────────────────────────────────
first_seen AS (
    SELECT c.user_id, MIN(DATE(m.created_at)) AS d0
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
),
returns AS (
    SELECT f.user_id, f.d0,
        MAX(CASE WHEN DATE(m.created_at) = f.d0 + 1                            THEN 1 ELSE 0 END) AS d1,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0 + 1 AND f.d0 + 7        THEN 1 ELSE 0 END) AS d7,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0 + 1 AND f.d0 + 30       THEN 1 ELSE 0 END) AS d30
    FROM first_seen f
    JOIN chats c2 ON c2.user_id = f.user_id
    JOIN messages m ON m.chat_id = c2.id
    GROUP BY f.user_id, f.d0
),
retention_agg AS (
    SELECT
        ROUND(AVG(d1)::numeric * 100, 1)                                        AS d1_pct,
        ROUND(AVG(d7)::numeric * 100, 1)                                        AS d7_pct,
        ROUND(AVG(d30) FILTER (WHERE d0 <= CURRENT_DATE - 30)::numeric * 100, 1) AS d30_pct
    FROM returns
    WHERE d0 BETWEEN '2026-04-01'::date AND '2026-12-31'::date
),
power AS (
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
    SELECT ROUND(
        (SELECT COUNT(DISTINCT c.user_id) FROM chats c JOIN messages m ON m.chat_id = c.id
         WHERE m.created_at >= NOW() - INTERVAL '1 day')::numeric
        / NULLIF(
            (SELECT COUNT(DISTINCT c.user_id) FROM chats c JOIN messages m ON m.chat_id = c.id
             WHERE m.created_at >= NOW() - INTERVAL '30 days'), 0
        )::numeric, 2
    ) AS s
),
-- ── Качество ──────────────────────────────────────────────────────────
chats_quality AS (
    SELECT
        ROUND(
            SUM(CASE WHEN message_count <= 2 THEN 1 ELSE 0 END)::numeric
            / NULLIF(COUNT(*), 0)::numeric * 100, 1
        )                                                                       AS single_msg_pct,
        SUM(CASE WHEN message_count <= 2 THEN 1 ELSE 0 END)                    AS single_msg_chats
    FROM chats
    WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
),
msg_quality AS (
    SELECT
        ROUND(
            SUM(CASE WHEN role = 'assistant' AND status = 'error' THEN 1 ELSE 0 END)::numeric
            / NULLIF(SUM(CASE WHEN role = 'assistant' THEN 1 ELSE 0 END), 0)::numeric * 100, 1
        )                                                                       AS error_rate_pct,
        ROUND(
            SUM(CASE WHEN role = 'assistant'
                      AND (metadata->>'llmMs')::numeric > 30000 THEN 1 ELSE 0 END)::numeric
            / NULLIF(SUM(CASE WHEN role = 'assistant' THEN 1 ELSE 0 END), 0)::numeric * 100, 1
        )                                                                       AS timeout_rate_pct
    FROM messages
    WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
),
-- ── По дням ───────────────────────────────────────────────────────────
daily_stats AS (
    SELECT
        DATE(m.created_at)                                                      AS day,
        COUNT(m.id) FILTER (WHERE m.role = 'user')                              AS questions,
        COUNT(DISTINCT c.user_id)                                               AS active_users,
        COUNT(DISTINCT c.id)                                                    AS chats,
        COUNT(*) FILTER (WHERE m.role = 'assistant' AND m.feedback_vote = 'up') AS likes,
        COUNT(*) FILTER (WHERE m.role = 'assistant' AND m.feedback_vote = 'down') AS dislikes
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY DATE(m.created_at)
),
-- ── Промпты ───────────────────────────────────────────────────────────
prompts_stats AS (
    SELECT
        COALESCE(s.name, '(без промпта)')                                       AS prompt_name,
        s.category,
        COUNT(DISTINCT c.id)                                                    AS chats_count,
        COUNT(DISTINCT c.user_id)                                               AS unique_users,
        COUNT(m.id) FILTER (WHERE m.feedback_vote = 'up')                       AS likes,
        COUNT(m.id) FILTER (WHERE m.feedback_vote = 'down')                     AS dislikes,
        ROUND(
            (COUNT(DISTINCT c.id)::numeric
            / NULLIF(SUM(COUNT(DISTINCT c.id)) OVER (), 0) * 100)::numeric, 1
        )                                                                       AS pct_of_total,
        ROUND(
            (COUNT(m.id) FILTER (WHERE m.feedback_vote = 'down')::numeric
            / NULLIF(COUNT(m.id) FILTER (WHERE m.feedback_vote IS NOT NULL), 0) * 100)::numeric, 1
        )                                                                       AS dislike_pct
    FROM chats c
    LEFT JOIN skills s ON s.system_prompt = c.system_prompt AND s.tenant_id = c.tenant_id
    LEFT JOIN messages m ON m.chat_id = c.id AND m.role = 'assistant'
    WHERE c.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY s.name, s.category
    ORDER BY chats_count DESC
    LIMIT 20
),
-- ── Латентность по часам ──────────────────────────────────────────────
latency_hour_stats AS (
    SELECT
        EXTRACT(HOUR FROM m.created_at)::int                                    AS hour_of_day,
        ROUND(AVG((m.metadata->>'llmMs')::numeric)::numeric, 0)                 AS llm_avg_ms,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
            ORDER BY (m.metadata->>'llmMs')::numeric
        )::numeric, 0)                                                          AS llm_p95_ms,
        COUNT(*)                                                                AS responses_count
    FROM messages m
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND m.role = 'assistant'
      AND m.metadata->>'llmMs' IS NOT NULL
    GROUP BY EXTRACT(HOUR FROM m.created_at)
)

-- ══ ИТОГ: все секции в одном CSV ══════════════════════════════════════
-- Колонки: _section | summary-cols | shared(likes/dislikes) | daily-cols | prompts-cols | latency_hour-cols

SELECT 'summary' AS _section,
    -- Пользователи
    u.total_users, u.new_users_7d, u.new_users_30d, u.new_users_90d,
    u.dau_avg, u.wau, u.mau,
    -- Активность
    a.total_questions, a.total_answers, a.total_chats,
    a.avg_questions_per_user, a.avg_questions_per_chat, a.total_tokens,
    -- Оценки
    r.likes, r.dislikes, r.total_votes, r.like_pct,
    -- Латентность (сводная)
    l.llm_avg_ms, l.llm_median_ms, l.llm_p95_ms,
    l.rag_avg_ms, l.ttft_avg_ms, l.ttft_p95_ms,
    -- Retention
    ret.d1_pct, ret.d7_pct, ret.d30_pct,
    (SELECT power_users FROM power)                                             AS power_users,
    (SELECT s FROM stickiness)                                                  AS stickiness,
    -- Качество
    cq.single_msg_pct, cq.single_msg_chats,
    mq.error_rate_pct, mq.timeout_rate_pct,
    -- NULL для daily-only колонок
    NULL::date    AS day,
    NULL::numeric AS questions,
    NULL::numeric AS active_users,
    NULL::numeric AS chats,
    -- NULL для prompts-only колонок
    NULL::text    AS prompt_name,
    NULL::text    AS category,
    NULL::numeric AS chats_count,
    NULL::numeric AS unique_users,
    NULL::numeric AS pct_of_total,
    NULL::numeric AS dislike_pct,
    -- NULL для latency_hour-only колонок
    NULL::numeric AS hour_of_day,
    NULL::numeric AS responses_count
FROM users_stats u, activity_stats a, ratings_stats r, latency_stats l,
     retention_agg ret, chats_quality cq, msg_quality mq

UNION ALL

SELECT 'daily',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,  -- users
    NULL, NULL, NULL, NULL, NULL, NULL,         -- activity
    d.likes, d.dislikes, NULL, NULL,            -- оценки (shared)
    NULL, NULL, NULL, NULL, NULL, NULL,         -- latency summary
    NULL, NULL, NULL, NULL, NULL,               -- retention
    NULL, NULL, NULL, NULL,                     -- quality
    d.day, d.questions, d.active_users, d.chats, -- daily
    NULL, NULL, NULL, NULL, NULL, NULL,         -- prompts
    NULL, NULL                                  -- latency_hour
FROM daily_stats d

UNION ALL

SELECT 'prompts',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,  -- users
    NULL, NULL, NULL, NULL, NULL, NULL,         -- activity
    p.likes, p.dislikes, NULL, NULL,            -- оценки (shared)
    NULL, NULL, NULL, NULL, NULL, NULL,         -- latency summary
    NULL, NULL, NULL, NULL, NULL,               -- retention
    NULL, NULL, NULL, NULL,                     -- quality
    NULL, NULL, NULL, NULL,                     -- daily
    p.prompt_name, p.category, p.chats_count, p.unique_users, p.pct_of_total, p.dislike_pct,
    NULL, NULL                                  -- latency_hour
FROM prompts_stats p

UNION ALL

SELECT 'latency_hour',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,  -- users
    NULL, NULL, NULL, NULL, NULL, NULL,         -- activity
    NULL, NULL, NULL, NULL,                     -- оценки
    lh.llm_avg_ms, NULL, lh.llm_p95_ms, NULL, NULL, NULL,  -- latency (shared cols)
    NULL, NULL, NULL, NULL, NULL,               -- retention
    NULL, NULL, NULL, NULL,                     -- quality
    NULL, NULL, NULL, NULL,                     -- daily
    NULL, NULL, NULL, NULL, NULL, NULL,         -- prompts
    lh.hour_of_day, lh.responses_count         -- latency_hour
FROM latency_hour_stats lh

ORDER BY
    CASE _section
        WHEN 'summary'      THEN 1
        WHEN 'daily'        THEN 2
        WHEN 'prompts'      THEN 3
        WHEN 'latency_hour' THEN 4
    END,
    day    NULLS LAST,
    hour_of_day NULLS LAST;
