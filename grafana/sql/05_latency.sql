-- МирГПТ: производительность (время ответа из messages.metadata)
-- Поля metadata: llmMs, ragMs, ttftMs (все в миллисекундах)
-- Экспортировать в data/latency.csv

-- Сводные метрики за период
SELECT
    -- LLM (полное время генерации)
    ROUND(AVG((m.metadata->>'llmMs')::numeric))                                 AS llm_avg_ms,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY (m.metadata->>'llmMs')::numeric
    ))                                                                          AS llm_median_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
        ORDER BY (m.metadata->>'llmMs')::numeric
    ))                                                                          AS llm_p95_ms,

    -- RAG (поиск по базе знаний)
    ROUND(AVG((m.metadata->>'ragMs')::numeric))                                 AS rag_avg_ms,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY (m.metadata->>'ragMs')::numeric
    ))                                                                          AS rag_median_ms,

    -- TTFT (время до первого токена)
    ROUND(AVG((m.metadata->>'ttftMs')::numeric))                                AS ttft_avg_ms,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY (m.metadata->>'ttftMs')::numeric
    ))                                                                          AS ttft_median_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
        ORDER BY (m.metadata->>'ttftMs')::numeric
    ))                                                                          AS ttft_p95_ms,

    COUNT(*)                                                                    AS responses_count

FROM messages m
WHERE m.created_at BETWEEN :'date_from' AND :'date_to'
  AND m.role = 'assistant'
  AND m.metadata IS NOT NULL
  AND m.metadata->>'llmMs' IS NOT NULL;


-- Распределение llmMs по часам суток (для теплокарты)
-- Экспортировать отдельно в data/latency_by_hour.csv
SELECT
    EXTRACT(HOUR FROM m.created_at)                                             AS hour_of_day,
    ROUND(AVG((m.metadata->>'llmMs')::numeric))                                 AS llm_avg_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
        ORDER BY (m.metadata->>'llmMs')::numeric
    ))                                                                          AS llm_p95_ms,
    COUNT(*)                                                                    AS responses_count
FROM messages m
WHERE m.created_at BETWEEN :'date_from' AND :'date_to'
  AND m.role = 'assistant'
  AND m.metadata->>'llmMs' IS NOT NULL
GROUP BY EXTRACT(HOUR FROM m.created_at)
ORDER BY hour_of_day;
