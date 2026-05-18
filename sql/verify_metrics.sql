-- МирГПТ: перепроверка корректности показателей дашборда
-- Запустить в DBeaver: Run Script (Alt+X)
-- Период: задать через Ctrl+H → заменить даты ниже
--   date_from = 2026-04-01
--   date_to   = 2026-12-31
--
-- Каждый блок сравнивается с соответствующим CSV, загруженным в дашборд.
-- Ожидаемый результат: все check_* = OK.


-- ══════════════════════════════════════════════════════════════════════
-- ДИАГНОСТИКА 1: какие значения реально хранятся в feedback_vote?
-- Ожидание: видим 'up'/'down' ИЛИ 'like'/'dislike' — но не оба варианта.
-- Если обнаружите другие значения — обновите оба SQL-файла.
-- ══════════════════════════════════════════════════════════════════════
SELECT
    feedback_vote,
    COUNT(*) AS cnt
FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND role = 'assistant'
  AND feedback_vote IS NOT NULL
GROUP BY feedback_vote
ORDER BY cnt DESC;


-- ══════════════════════════════════════════════════════════════════════
-- ДИАГНОСТИКА 2: WAU/MAU — проверка относительно конца периода, не NOW()
-- Дашборд (summary.csv) показывает WAU/MAU как «живые» цифры через NOW().
-- Если данные исторические, корректнее считать от конца периода.
-- Сравните две колонки: если period_end_wau ≠ now_wau — в дашборде ошибка.
-- ══════════════════════════════════════════════════════════════════════
SELECT
    -- Как считает all_queries.sql (от NOW)
    COUNT(DISTINCT u.id) FILTER (
        WHERE m.created_at >= NOW() - INTERVAL '7 days'
    )                                                           AS wau_from_now,
    COUNT(DISTINCT u.id) FILTER (
        WHERE m.created_at >= NOW() - INTERVAL '30 days'
    )                                                           AS mau_from_now,

    -- Как правильно для исторических данных (от конца периода)
    COUNT(DISTINCT u.id) FILTER (
        WHERE m.created_at >= '2026-12-31'::timestamptz - INTERVAL '7 days'
    )                                                           AS wau_from_period_end,
    COUNT(DISTINCT u.id) FILTER (
        WHERE m.created_at >= '2026-12-31'::timestamptz - INTERVAL '30 days'
    )                                                           AS mau_from_period_end
FROM users u
JOIN chats c ON c.user_id = u.id
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND m.role = 'user';


-- ══════════════════════════════════════════════════════════════════════
-- ДИАГНОСТИКА 3: DAU — коллизия при конкатенации строк
-- all_queries.sql использует u.id::text || DATE::text — это даёт коллизии.
-- Проверяем: если две колонки различаются — в all_queries.sql ошибка.
-- ══════════════════════════════════════════════════════════════════════
SELECT
    -- Неверный метод (all_queries.sql) — конкатенация строк, возможны коллизии
    COUNT(DISTINCT (u.id::text || DATE(m.created_at)::text))    AS dau_pairs_concat,

    -- Правильный метод — составной ключ (u.id, date)
    COUNT(DISTINCT (u.id, DATE(m.created_at)))                  AS dau_pairs_correct,

    -- Если равны — коллизий нет; если нет — all_queries.sql занижает DAU
    CASE
        WHEN COUNT(DISTINCT (u.id::text || DATE(m.created_at)::text))
           = COUNT(DISTINCT (u.id, DATE(m.created_at)))
        THEN 'OK — коллизий нет'
        ELSE 'ОШИБКА — коллизии есть, DAU занижен'
    END                                                         AS check_dau,

    ROUND(
        COUNT(DISTINCT (u.id, DATE(m.created_at)))::numeric
        / NULLIF(DATE_PART('day', '2026-12-31'::timestamptz - '2026-04-01'::timestamptz)::numeric, 0),
        1
    )                                                           AS dau_avg_correct
FROM users u
JOIN chats c ON c.user_id = u.id
JOIN messages m ON m.chat_id = c.id
WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
  AND m.role = 'user';


-- ══════════════════════════════════════════════════════════════════════
-- ДИАГНОСТИКА 4: Feedback rate — правильный знаменатель
-- JS-код: total_votes / total_questions  ← неверно (вопросы ≠ ответы)
-- Правильно: total_votes / total_assistant_messages
-- ══════════════════════════════════════════════════════════════════════
SELECT
    COUNT(*) FILTER (WHERE role = 'assistant')                  AS total_answers,
    COUNT(*) FILTER (WHERE role = 'user')                       AS total_questions,
    COUNT(*) FILTER (WHERE role = 'assistant'
                       AND feedback_vote IS NOT NULL)           AS total_votes,

    -- Как считает дашборд (неверно — знаменатель вопросы)
    ROUND(
        COUNT(*) FILTER (WHERE role = 'assistant' AND feedback_vote IS NOT NULL)::numeric
        / NULLIF(COUNT(*) FILTER (WHERE role = 'user'), 0)::numeric * 100,
        1
    )                                                           AS feedback_rate_wrong_pct,

    -- Правильно — знаменатель ответы ассистента
    ROUND(
        COUNT(*) FILTER (WHERE role = 'assistant' AND feedback_vote IS NOT NULL)::numeric
        / NULLIF(COUNT(*) FILTER (WHERE role = 'assistant'), 0)::numeric * 100,
        1
    )                                                           AS feedback_rate_correct_pct,

    CASE
        WHEN ROUND(
            COUNT(*) FILTER (WHERE role = 'assistant' AND feedback_vote IS NOT NULL)::numeric
            / NULLIF(COUNT(*) FILTER (WHERE role = 'user'), 0)::numeric * 100, 1)
           = ROUND(
            COUNT(*) FILTER (WHERE role = 'assistant' AND feedback_vote IS NOT NULL)::numeric
            / NULLIF(COUNT(*) FILTER (WHERE role = 'assistant'), 0)::numeric * 100, 1)
        THEN 'OK — совпадают'
        ELSE 'РАСХОЖДЕНИЕ — дашборд показывает неверный % feedback rate'
    END                                                         AS check_feedback_rate

FROM messages
WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz;


-- ══════════════════════════════════════════════════════════════════════
-- ДИАГНОСТИКА 5: Stickiness — CSV-значение vs пересчёт из summary
-- Дашборд игнорирует stickiness из retention.csv и пересчитывает сам:
--   stick = dau_avg / mau  (из summary.csv)
-- Правильная формула: DAU_последнего_дня / MAU_последних_30_дней
-- ══════════════════════════════════════════════════════════════════════
WITH
dau_last AS (
    SELECT COUNT(DISTINCT c.user_id) AS cnt
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at >= '2026-12-31'::timestamptz - INTERVAL '1 day'
      AND m.created_at <  '2026-12-31'::timestamptz
),
mau_last AS (
    SELECT COUNT(DISTINCT c.user_id) AS cnt
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at >= '2026-12-31'::timestamptz - INTERVAL '30 days'
),
dau_avg_calc AS (
    SELECT
        ROUND(
            COUNT(DISTINCT (c.user_id, DATE(m.created_at)))::numeric
            / NULLIF(DATE_PART('day', '2026-12-31'::timestamptz - '2026-04-01'::timestamptz)::numeric, 0),
            1
        ) AS v
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND m.role = 'user'
),
mau_full AS (
    SELECT COUNT(DISTINCT c.user_id) AS cnt
    FROM chats c JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND m.role = 'user'
      AND m.created_at >= NOW() - INTERVAL '30 days'
)
SELECT
    (SELECT cnt FROM dau_last)                                  AS dau_last_day,
    (SELECT cnt FROM mau_last)                                  AS mau_last_30d,
    ROUND(
        (SELECT cnt FROM dau_last)::numeric
        / NULLIF((SELECT cnt FROM mau_last), 0)::numeric,
        3
    )                                                           AS stickiness_correct,

    -- Как считает дашборд: dau_avg / mau (из NOW)
    (SELECT v FROM dau_avg_calc)                                AS dau_avg,
    (SELECT cnt FROM mau_full)                                  AS mau_from_now,
    ROUND(
        (SELECT v FROM dau_avg_calc)
        / NULLIF((SELECT cnt FROM mau_full), 0)::numeric,
        3
    )                                                           AS stickiness_dashboard;


-- ══════════════════════════════════════════════════════════════════════
-- ДИАГНОСТИКА 6: D30 Retention — отсутствует в SQL
-- Плитка tD30 в дашборде всегда будет «Н/Д» если не добавить расчёт.
-- Вот корректный запрос для D30:
-- ══════════════════════════════════════════════════════════════════════
WITH first_seen AS (
    SELECT c.user_id, MIN(DATE(m.created_at)) AS d0
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
    GROUP BY c.user_id
),
returns AS (
    SELECT f.user_id, f.d0,
        MAX(CASE WHEN DATE(m.created_at) = f.d0 + 1 THEN 1 ELSE 0 END)                     AS d1,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0 + 1 AND f.d0 + 7  THEN 1 ELSE 0 END) AS d7,
        MAX(CASE WHEN DATE(m.created_at) BETWEEN f.d0 + 1 AND f.d0 + 30 THEN 1 ELSE 0 END) AS d30
    FROM first_seen f
    JOIN chats c2 ON c2.user_id = f.user_id
    JOIN messages m ON m.chat_id = c2.id
    GROUP BY f.user_id, f.d0
)
SELECT
    ROUND(AVG(d1)::numeric  * 100, 1)                          AS d1_pct,
    ROUND(AVG(d7)::numeric  * 100, 1)                          AS d7_pct,
    ROUND(AVG(d30)::numeric * 100, 1)                          AS d30_pct,
    COUNT(*)                                                    AS cohort_size,

    -- D30 можно считать только для пользователей, у которых d0 + 30 <= конца периода
    COUNT(*) FILTER (WHERE d0 <= '2026-12-31'::date - 30)      AS d30_eligible_users,
    ROUND(
        AVG(d30) FILTER (WHERE d0 <= '2026-12-31'::date - 30)::numeric * 100,
        1
    )                                                           AS d30_pct_eligible
FROM returns
WHERE d0 BETWEEN '2026-04-01'::date AND '2026-12-31'::date;


-- ══════════════════════════════════════════════════════════════════════
-- ИТОГО: сводная проверка ключевых KPI из summary.csv
-- Запустите этот блок последним и сравните с тем, что показывает дашборд.
-- ══════════════════════════════════════════════════════════════════════
WITH
activity AS (
    SELECT
        COUNT(m.id) FILTER (WHERE m.role = 'user')              AS total_questions,
        COUNT(m.id) FILTER (WHERE m.role = 'assistant')         AS total_answers,
        COUNT(DISTINCT c.id)                                    AS total_chats,
        COUNT(DISTINCT c.user_id)                               AS active_users,
        SUM(m.token_count)                                      AS total_tokens
    FROM chats c
    JOIN messages m ON m.chat_id = c.id
    WHERE m.created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
),
-- Подставьте 'up' или 'like' по результату ДИАГНОСТИКИ 1
feedback AS (
    SELECT
        COUNT(*) FILTER (WHERE feedback_vote IN ('up','like'))   AS likes,
        COUNT(*) FILTER (WHERE feedback_vote IN ('down','dislike')) AS dislikes,
        COUNT(*) FILTER (WHERE feedback_vote IS NOT NULL)        AS total_votes
    FROM messages
    WHERE created_at BETWEEN '2026-04-01'::timestamptz AND '2026-12-31'::timestamptz
      AND role = 'assistant'
),
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
)
SELECT
    a.total_questions,
    a.total_answers,
    a.total_chats,
    a.active_users,
    a.total_tokens,
    f.likes,
    f.dislikes,
    f.total_votes,
    ROUND(f.likes::numeric / NULLIF(f.total_votes, 0)::numeric * 100, 1)    AS like_pct,
    -- Feedback rate правильный (знаменатель = ответы)
    ROUND(f.total_votes::numeric / NULLIF(a.total_answers, 0)::numeric * 100, 1) AS feedback_rate_pct,
    l.llm_avg_ms,
    l.llm_median_ms,
    l.llm_p95_ms,
    l.rag_avg_ms,
    l.ttft_avg_ms,
    l.ttft_p95_ms
FROM activity a, feedback f, latency l;
