-- МирГПТ: все KPI в одной строке для сверки с дашбордом
-- Запустить целиком (Alt+X) → одна строка результата → сравнить с дашбордом
-- Период: 2026-04-01 — 2026-12-31  (менять через Ctrl+H)

WITH
-- ── Активность ────────────────────────────────────────────────────────
activity AS (
    SELECT
        COUNT(m.id) FILTER (WHERE m.role = 'user')              AS total_questions,
        COUNT(m.id) FILTER (WHERE m.role = 'assistant')         AS total_answers,
        COUNT(DISTINCT c.id)                                    AS total_chats,
        COUNT(DISTINCT c.user_id)                               AS active_users,
        SUM(m.token_count)                                      AS total_tokens,
        ROUND(
            COUNT(m.id) FILTER (WHERE m.role = 'user')::numeric
            / NULLIF(COUNT(DISTINCT c.id), 0)::numeric, 1
        )                                                       AS avg_q_per_chat
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
),

-- ── Пользователи ──────────────────────────────────────────────────────
users AS (
    SELECT
        COUNT(DISTINCT u.id)                                    AS total_users,
        COUNT(DISTINCT u.id) FILTER (
            WHERE u.created_at >= NOW() - INTERVAL '7 days'
        )                                                       AS new_users_7d,
        COUNT(DISTINCT u.id) FILTER (
            WHERE u.created_at >= NOW() - INTERVAL '30 days'
        )                                                       AS new_users_30d,
        COUNT(DISTINCT u.id) FILTER (
            WHERE u.created_at >= NOW() - INTERVAL '90 days'
        )                                                       AS new_users_90d,
        COUNT(DISTINCT u.id) FILTER (
            WHERE m.created_at >= NOW() - INTERVAL '7 days'
        )                                                       AS wau,
        COUNT(DISTINCT u.id) FILTER (
            WHERE m.created_at >= NOW() - INTERVAL '30 days'
        )                                                       AS mau,
        ROUND(
            COUNT(DISTINCT (u.id, DATE(m.created_at)))::numeric
            / NULLIF(DATE_PART('day',
                '2026-12-31'::timestamptz - '2026-04-01'::timestamptz
              )::numeric, 0), 1
        )                                                       AS dau_avg
    FROM users u
    JOIN chats c ON c.user_id = u.id
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND m.role = 'user'
),

-- ── Оценки ────────────────────────────────────────────────────────────
feedback AS (
    SELECT
        COUNT(*) FILTER (WHERE feedback_vote = 'up')            AS likes,
        COUNT(*) FILTER (WHERE feedback_vote = 'down')          AS dislikes,
        COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL)       AS total_votes,
        ROUND(
            COUNT(*) FILTER (WHERE feedback_vote = 'up')::numeric
            / NULLIF(COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL), 0)::numeric * 100, 1
        )                                                       AS like_pct
    FROM messages
    WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND role = 'assistant'
),

-- ── Латентность ───────────────────────────────────────────────────────
latency AS (
    SELECT
        ROUND(AVG((metadata->>'llmMs')::numeric))               AS llm_avg_ms,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY (metadata->>'llmMs')::numeric))            AS llm_median_ms,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
            ORDER BY (metadata->>'llmMs')::numeric))            AS llm_p95_ms,
        ROUND(AVG((metadata->>'ragMs')::numeric))               AS rag_avg_ms,
        ROUND(AVG((metadata->>'ttftMs')::numeric))              AS ttft_avg_ms,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
            ORDER BY (metadata->>'ttftMs')::numeric))           AS ttft_p95_ms
    FROM messages
    WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND role = 'assistant'
      AND metadata->>'llmMs' IS NOT NULL
),

-- ── Качество ──────────────────────────────────────────────────────────
quality AS (
    SELECT
        ROUND(
            SUM(CASE WHEN msg_count <= 2 THEN 1 ELSE 0 END)::numeric
            / NULLIF(COUNT(*), 0)::numeric * 100, 1
        )                                                       AS single_msg_pct,
        ROUND(
            SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)::numeric
            / NULLIF(COUNT(*), 0)::numeric * 100, 1
        )                                                       AS error_rate_pct,
        ROUND(
            SUM(CASE WHEN (metadata->>'llmMs')::numeric > 30000 THEN 1 ELSE 0 END)::numeric
            / NULLIF(COUNT(*), 0)::numeric * 100, 1
        )                                                       AS timeout_rate_pct
    FROM (
        SELECT c.id,
            COUNT(m.id)                                         AS msg_count,
            MAX(CASE WHEN m.role = 'assistant' THEN m.status END) AS status,
            MAX(CASE WHEN m.role = 'assistant'
                THEN m.metadata->>'llmMs' END)                  AS llm_ms_str,
            MAX(CASE WHEN m.role = 'assistant'
                THEN m.metadata END)                            AS metadata
        FROM chats c
        JOIN messages m ON m.chat_id = c.id
        WHERE c.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
        GROUP BY c.id
    ) t
),

-- ── Retention ─────────────────────────────────────────────────────────
first_seen AS (
    SELECT c.user_id, MIN(DATE(m.created_at)) AS d0
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
),
returns AS (
    SELECT f.user_id, f.d0,
        MAX(CASE WHEN DATE(m.created_at) = f.d0 + 1             THEN 1 ELSE 0 END) AS d1,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0+1 AND f.d0+7  THEN 1 ELSE 0 END) AS d7,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0+1 AND f.d0+30 THEN 1 ELSE 0 END) AS d30
    FROM first_seen f
    JOIN chats c ON c.user_id = f.user_id
    JOIN messages m ON m.chat_id = c.id
    GROUP BY f.user_id, f.d0
),
retention AS (
    SELECT
        ROUND(AVG(d1)::numeric * 100, 1)                        AS d1_pct,
        ROUND(AVG(d7)::numeric * 100, 1)                        AS d7_pct,
        ROUND(AVG(d30) FILTER (WHERE d0 <= CURRENT_DATE - 30)::numeric * 100, 1) AS d30_pct
    FROM returns
),

-- ── Power users & Stickiness ──────────────────────────────────────────
power AS (
    SELECT COUNT(*) AS power_users
    FROM (
        SELECT c.user_id
        FROM chats c JOIN messages m ON m.chat_id = c.id
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
    ) AS stickiness
),

-- ── Skill coverage ────────────────────────────────────────────────────
skill AS (
    SELECT ROUND(
        COUNT(*) FILTER (WHERE s.name IS NOT NULL)::numeric
        / NULLIF(COUNT(*), 0)::numeric * 100, 1
    ) AS skill_coverage_pct
    FROM chats c
    LEFT JOIN skills s ON s.system_prompt = c.system_prompt AND s.tenant_id = c.tenant_id
    WHERE c.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
)

-- ── Итог: одна строка ─────────────────────────────────────────────────
SELECT
    -- Пользователи
    u.total_users,
    u.new_users_7d,
    u.new_users_30d,
    u.new_users_90d,
    u.wau,
    u.mau,
    u.dau_avg,
    -- Активность
    a.total_questions,
    a.total_answers,
    a.total_chats,
    a.avg_q_per_chat,
    a.total_tokens,
    ROUND(a.total_tokens::numeric / NULLIF(a.total_answers, 0)::numeric) AS tokens_per_answer,
    -- Оценки
    f.likes,
    f.dislikes,
    f.total_votes,
    f.like_pct,
    ROUND(f.total_votes::numeric / NULLIF(a.total_answers, 0)::numeric * 100, 1) AS feedback_rate_pct,
    -- Латентность (в секундах)
    ROUND(l.llm_avg_ms    / 1000.0, 2) AS llm_avg_sec,
    ROUND(l.llm_median_ms / 1000.0, 2) AS llm_median_sec,
    ROUND(l.llm_p95_ms    / 1000.0, 2) AS llm_p95_sec,
    ROUND(l.rag_avg_ms    / 1000.0, 2) AS rag_avg_sec,
    ROUND(l.ttft_avg_ms   / 1000.0, 2) AS ttft_avg_sec,
    ROUND(l.ttft_p95_ms   / 1000.0, 2) AS ttft_p95_sec,
    -- Качество
    q.single_msg_pct,
    q.error_rate_pct,
    q.timeout_rate_pct,
    -- Retention
    r.d1_pct,
    r.d7_pct,
    r.d30_pct,
    -- Power & Stickiness
    p.power_users,
    s.stickiness,
    -- Skill
    sk.skill_coverage_pct
FROM activity a, users u, feedback f, latency l, quality q,
     retention r, power p, stickiness s, skill sk;
