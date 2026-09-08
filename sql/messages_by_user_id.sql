-- МирГПТ: все сообщения конкретного пользователя
-- Использование в DBeaver: Ctrl+H, задать :'user_id', выполнить (F5 / Ctrl+Enter)
--
-- В таблице messages нет колонки user_id — связь идёт через chats.user_id,
-- поэтому обязателен JOIN с chats (см. grafana/sql/02_messages.sql, 04_ratings.sql).


-- ══════════════════════════════════════════════════════════════════════
-- Сообщения пользователя, самые новые сверху
-- ══════════════════════════════════════════════════════════════════════
SELECT
    m.id                                                                          AS message_id,
    m.chat_id,
    m.role,
    m.created_at,
    m.token_count,
    m.feedback_vote,
    m.metadata
FROM messages m
JOIN chats c ON c.id = m.chat_id
WHERE c.user_id = :'user_id'
ORDER BY m.created_at DESC
LIMIT 200;


-- ══════════════════════════════════════════════════════════════════════
-- То же самое, но только за период (те же :'date_from' / :'date_to',
-- что и в остальных запросах)
-- ══════════════════════════════════════════════════════════════════════
SELECT
    m.id                                                                          AS message_id,
    m.chat_id,
    m.role,
    m.created_at,
    m.token_count,
    m.feedback_vote,
    m.metadata
FROM messages m
JOIN chats c ON c.id = m.chat_id
WHERE c.user_id = :'user_id'
  AND m.created_at BETWEEN :'date_from' AND :'date_to'
ORDER BY m.created_at DESC;
