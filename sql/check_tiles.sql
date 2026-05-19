-- МирГПТ: проверка каждой плитки дашборда
-- Запускать по одному блоку (выделить → F5 или Ctrl+Enter в DBeaver)
-- Период: 2026-04-01 — 2026-12-31  (менять через Ctrl+H)


-- ══════════════════════════════════════════════════════════════════════
-- HERO: Вопросы
-- Дашборд: большая цифра в первой карточке
-- ══════════════════════════════════════════════════════════════════════
SELECT COUNT(m.id) AS total_questions
FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND m.role = 'user';


-- ══════════════════════════════════════════════════════════════════════
-- HERO: WAU (активных за последние 7 дней периода)
-- Дашборд: вторая карточка hero
-- ══════════════════════════════════════════════════════════════════════
SELECT COUNT(DISTINCT c.user_id) AS wau
FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at >= '2026-12-31'::timestamptz - INTERVAL '7 days'
  AND m.created_at <  '2026-12-31'::timestamptz
  AND m.role = 'user';


-- ══════════════════════════════════════════════════════════════════════
-- HERO: % лайков (CSAT)
-- Дашборд: третья карточка hero, число без знака %
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE feedback_vote = 'up')                    AS likes,
    COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL)               AS total_votes,
    ROUND(
        COUNT(*) FILTER (WHERE feedback_vote = 'up')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL), 0)::numeric * 100,
        1
    )                                                               AS like_pct
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant';


-- ══════════════════════════════════════════════════════════════════════
-- HERO: P95 латентности (в секундах)
-- Дашборд: четвёртая карточка hero
-- ══════════════════════════════════════════════════════════════════════
SELECT
    ROUND(
        PERCENTILE_CONT(0.95) WITHIN GROUP (
            ORDER BY (metadata->>'llmMs')::numeric
        )::numeric / 1000,
        1
    )                                                               AS llm_p95_sec
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant'
  AND metadata->>'llmMs' IS NOT NULL;


-- ══════════════════════════════════════════════════════════════════════
-- D1 Retention (%)
-- Дашборд: плитка «D1»
-- ══════════════════════════════════════════════════════════════════════
WITH first_seen AS (
    SELECT c.user_id, MIN(DATE(m.created_at)) AS d0
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
),
returns AS (
    SELECT f.user_id,
        MAX(CASE WHEN DATE(m.created_at) = f.d0 + 1 THEN 1 ELSE 0 END) AS came_back
    FROM first_seen f
    JOIN chats c ON c.user_id = f.user_id
    JOIN messages m ON m.chat_id = c.id
    GROUP BY f.user_id
)
SELECT ROUND(AVG(came_back)::numeric * 100, 1) AS d1_pct
FROM returns;


-- ══════════════════════════════════════════════════════════════════════
-- D7 Retention (%)
-- Дашборд: плитка «D7»
-- ══════════════════════════════════════════════════════════════════════
WITH first_seen AS (
    SELECT c.user_id, MIN(DATE(m.created_at)) AS d0
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
),
returns AS (
    SELECT f.user_id,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0 + 1 AND f.d0 + 7 THEN 1 ELSE 0 END) AS came_back
    FROM first_seen f
    JOIN chats c ON c.user_id = f.user_id
    JOIN messages m ON m.chat_id = c.id
    GROUP BY f.user_id
)
SELECT ROUND(AVG(came_back)::numeric * 100, 1) AS d7_pct
FROM returns;


-- ══════════════════════════════════════════════════════════════════════
-- D30 Retention (%)
-- Дашборд: плитка «D30»
-- Считаем только пользователей, у которых прошло ≥ 30 дней до конца периода
-- ══════════════════════════════════════════════════════════════════════
WITH first_seen AS (
    SELECT c.user_id, MIN(DATE(m.created_at)) AS d0
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
),
returns AS (
    SELECT f.user_id, f.d0,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0 + 1 AND f.d0 + 30 THEN 1 ELSE 0 END) AS came_back
    FROM first_seen f
    JOIN chats c ON c.user_id = f.user_id
    JOIN messages m ON m.chat_id = c.id
    GROUP BY f.user_id, f.d0
)
SELECT ROUND(AVG(came_back)::numeric * 100, 1) AS d30_pct
FROM returns
WHERE d0 <= '2026-12-31'::date - 30;


-- ══════════════════════════════════════════════════════════════════════
-- Power Users (количество)
-- Дашборд: плитка «Power», порог ≥ 10 ответов/нед
-- ══════════════════════════════════════════════════════════════════════
SELECT COUNT(*) AS power_users
FROM (
    SELECT c.user_id
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.role = 'assistant'
      AND m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
    HAVING COUNT(*) >= 10 * GREATEST(1,
        EXTRACT(week FROM AGE('2026-12-31'::timestamptz, '2026-04-01'::timestamptz))
    )
) t;


-- ══════════════════════════════════════════════════════════════════════
-- Stickiness (DAU/MAU)
-- Дашборд: плитка «Stickiness», значение 0.00–1.00
-- ══════════════════════════════════════════════════════════════════════
SELECT
    ROUND(
        (SELECT COUNT(DISTINCT c.user_id)
         FROM chats c JOIN messages m ON m.chat_id = c.id
         WHERE m.created_at >= NOW() - INTERVAL '1 day')::numeric
        / NULLIF(
            (SELECT COUNT(DISTINCT c.user_id)
             FROM chats c JOIN messages m ON m.chat_id = c.id
             WHERE m.created_at >= NOW() - INTERVAL '30 days'),
            0
        )::numeric,
        2
    ) AS stickiness;


-- ══════════════════════════════════════════════════════════════════════
-- Feedback Rate (% ответов с оценкой)
-- Дашборд: плитка «Feedback rate»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL)               AS total_votes,
    COUNT(*)                                                        AS total_answers,
    ROUND(
        COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL)::numeric
        / NULLIF(COUNT(*), 0)::numeric * 100,
        1
    )                                                               AS feedback_rate_pct
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant';


-- ══════════════════════════════════════════════════════════════════════
-- Лайки : Дизлайки
-- Дашборд: плитка «Лайки / Дизлайки» с баром
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE feedback_vote = 'up')                    AS likes,
    COUNT(*) FILTER (WHERE feedback_vote = 'down')                  AS dislikes,
    ROUND(
        COUNT(*) FILTER (WHERE feedback_vote = 'down')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL), 0)::numeric * 100,
        0
    )                                                               AS dislike_pct
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant';


-- ══════════════════════════════════════════════════════════════════════
-- % однократных чатов (single message)
-- Дашборд: плитка «Однократные чаты»
-- Чат считается однократным если в нём ≤ 2 сообщений (1 вопрос + 1 ответ)
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE msg_count <= 2)                          AS single_msg_chats,
    COUNT(*)                                                        AS total_chats,
    ROUND(
        COUNT(*) FILTER (WHERE msg_count <= 2)::numeric
        / NULLIF(COUNT(*), 0)::numeric * 100,
        1
    )                                                               AS single_msg_pct
FROM (
    SELECT c.id, COUNT(m.id) AS msg_count
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE c.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.id
) t;


-- ══════════════════════════════════════════════════════════════════════
-- Среднее вопросов на чат
-- Дашборд: плитка «Вопросов на чат»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(m.id) FILTER (WHERE m.role = 'user')                      AS total_questions,
    COUNT(DISTINCT c.id)                                            AS total_chats,
    ROUND(
        COUNT(m.id) FILTER (WHERE m.role = 'user')::numeric
        / NULLIF(COUNT(DISTINCT c.id), 0)::numeric,
        1
    )                                                               AS avg_questions_per_chat
FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz;


-- ══════════════════════════════════════════════════════════════════════
-- Токенов на ответ
-- Дашборд: плитка «Токенов / ответ»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    SUM(m.token_count)                                              AS total_tokens,
    COUNT(m.id) FILTER (WHERE m.role = 'assistant')                 AS total_answers,
    ROUND(
        SUM(m.token_count)::numeric
        / NULLIF(COUNT(m.id) FILTER (WHERE m.role = 'assistant'), 0)::numeric
    )                                                               AS tokens_per_answer
FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz;


-- ══════════════════════════════════════════════════════════════════════
-- GPU-секунд на чат
-- Дашборд: плитка «GPU-сек / чат»
-- Считается как: sum(llmMs) / 1000 / кол-во чатов
-- ══════════════════════════════════════════════════════════════════════
SELECT
    ROUND(SUM((metadata->>'llmMs')::numeric) / 1000)               AS total_llm_sec,
    COUNT(DISTINCT chat_id)                                         AS total_chats,
    ROUND(
        SUM((metadata->>'llmMs')::numeric) / 1000
        / NULLIF(COUNT(DISTINCT chat_id), 0)::numeric,
        1
    )                                                               AS gpu_sec_per_chat
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant'
  AND metadata->>'llmMs' IS NOT NULL;


-- ══════════════════════════════════════════════════════════════════════
-- Throughput (токенов / GPU-сек)
-- Дашборд: плитка «Throughput»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    ROUND(
        SUM(m.token_count)::numeric
        / NULLIF(SUM((m.metadata->>'llmMs')::numeric) / 1000, 0)::numeric,
        1
    )                                                               AS throughput_tok_per_gpu_sec
FROM chats c
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND m.role = 'assistant'
  AND m.metadata->>'llmMs' IS NOT NULL;


-- ══════════════════════════════════════════════════════════════════════
-- Skill Coverage (% чатов с системным промптом)
-- Дашборд: плитка «Skill coverage»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE s.name IS NOT NULL)                      AS chats_with_skill,
    COUNT(*)                                                        AS total_chats,
    ROUND(
        COUNT(*) FILTER (WHERE s.name IS NOT NULL)::numeric
        / NULLIF(COUNT(*), 0)::numeric * 100,
        1
    )                                                               AS skill_coverage_pct
FROM chats c
LEFT JOIN skills s ON s.system_prompt = c.system_prompt
                   AND s.tenant_id = c.tenant_id
WHERE c.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz;


-- ══════════════════════════════════════════════════════════════════════
-- LLM avg / median / P95 (в секундах)
-- Дашборд: плитки «LLM avg», «LLM median», «LLM P95»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    ROUND(AVG((metadata->>'llmMs')::numeric)::numeric / 1000, 2)   AS llm_avg_sec,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY (metadata->>'llmMs')::numeric
    )::numeric / 1000, 2)                                          AS llm_median_sec,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
        ORDER BY (metadata->>'llmMs')::numeric
    )::numeric / 1000, 2)                                          AS llm_p95_sec
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant'
  AND metadata->>'llmMs' IS NOT NULL;


-- ══════════════════════════════════════════════════════════════════════
-- TTFT avg / P95 (в секундах)
-- Дашборд: плитки «TTFT avg», «TTFT P95»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    ROUND(AVG((metadata->>'ttftMs')::numeric)::numeric / 1000, 2)  AS ttft_avg_sec,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
        ORDER BY (metadata->>'ttftMs')::numeric
    )::numeric / 1000, 2)                                          AS ttft_p95_sec
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant'
  AND metadata->>'ttftMs' IS NOT NULL;


-- ══════════════════════════════════════════════════════════════════════
-- RAG avg (в секундах)
-- Дашборд: плитка «RAG avg»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    ROUND(AVG((metadata->>'ragMs')::numeric)::numeric / 1000, 2)   AS rag_avg_sec
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant'
  AND metadata->>'ragMs' IS NOT NULL;


-- ══════════════════════════════════════════════════════════════════════
-- Error Rate (%)
-- Дашборд: плитка «Error rate»
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE status = 'error')                        AS error_count,
    COUNT(*)                                                        AS total_answers,
    ROUND(
        COUNT(*) FILTER (WHERE status = 'error')::numeric
        / NULLIF(COUNT(*), 0)::numeric * 100,
        1
    )                                                               AS error_rate_pct
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant';


-- ══════════════════════════════════════════════════════════════════════
-- Timeout Rate (%)
-- Дашборд: плитка «Timeout», порог > 30 000 мс
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE (metadata->>'llmMs')::numeric > 30000)  AS timeout_count,
    COUNT(*)                                                        AS total_answers,
    ROUND(
        COUNT(*) FILTER (WHERE (metadata->>'llmMs')::numeric > 30000)::numeric
        / NULLIF(COUNT(*), 0)::numeric * 100,
        1
    )                                                               AS timeout_rate_pct
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant'
  AND metadata->>'llmMs' IS NOT NULL;
