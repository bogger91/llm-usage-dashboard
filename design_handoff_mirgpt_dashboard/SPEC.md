# Дашборд МирГПТ v2 — спецификация (CSV‑only, без API)

**Аудитория:** разработчик дополняет фронт‑прототип новыми метриками и приводит SQL‑запросы для DBeaver, чтобы аналитик мог их выгружать.
**Бэкенда нет.** Источник данных — CSV‑файлы, которые аналитик выгружает из DBeaver и загружает в дашборд через шапку.

---

## 0. Что уже есть

| Файл | Назначение | Статус |
|---|---|---|
| `Dashboard v2.html` | Разметка, стили, шапка с CSV‑аплоадером | готов |
| `dashboard-v2.js` | Рендер плиток/графиков (Chart.js), парсинг CSV (Papa Parse), переключатель периода | требует расширения под NEW‑метрики |
| `dashboard-v2-demo.js` | `window.DEMO` — заглушка, которой подменяются недогруженные CSV | оставить |
| `share.js` | Экспорт offline‑снапшота (инлайнит JS, шрифты, Chart.js) | готов, без изменений |
| `Proposal.html` | Документ обоснования v2 | архив |

Дизайн‑система: Inter + JetBrains Mono, монохром + 3 акцента (good/warn/bad), 12 px бордеры, 6 px радиусы. Не менять без согласования.

---

## 1. Цели реализации

1. Расширить набор CSV‑файлов и парсеров под все метрики с пометкой **NEW** (сейчас они показываются из мок‑набора `STATE.mock`).
2. Дать аналитику готовые SQL‑запросы для DBeaver — по одному на каждый CSV.
3. Сохранить дизайн как есть; только подключить новые поля к существующим плиткам и графикам.
4. Шеринг через `share.js` — оставить без изменений.

**Не делаем:** API, бэкенд, авторизацию, автообновление, многотенантность, A/B, drill‑down.

---

## 2. CSV‑источники

Сейчас дашборд ждёт 4 файла. Расширим до 6, чтобы покрыть NEW‑метрики.

| # | Имя | Что в нём | Когда обновлять |
|---|---|---|---|
| 1 | `summary.csv` | Скалярные KPI за период (одна строка) | каждый раз перед просмотром |
| 2 | `daily.csv` | Серия по датам — для линейных графиков | каждый раз |
| 3 | `prompts.csv` | Топ системных промптов с метриками | каждый раз |
| 4 | `latency.csv` | Гистограмма латентности (8 бакетов) + p95 по 24 часам | каждый раз |
| 5 | **NEW** `retention.csv` | D1 / D7 retention, power users, stickiness | раз в неделю |
| 6 | **NEW** `quality.csv` | Refusal, repeat, error, timeout по дням | каждый раз |

Все файлы — UTF‑8, разделитель `,`, заголовок в первой строке.

---

## 3. SQL для DBeaver

Все запросы — Postgres (адаптировать под боевые имена таблиц). Параметры `:period_start`, `:period_end` подставлять руками или через DBeaver «Edit → SQL Variables».

Предполагаем:
- `messages(id, user_id, chat_id, prompt_id, ts, role, tokens_in, tokens_out, latency_ms, ttft_ms, rag_ms, status, refused, error_code, content)`
- `feedback(message_id, user_id, value /* like|dislike */, ts)`
- `prompts(id, title)`

### 3.1 `summary.csv`

```sql
WITH base AS (
  SELECT * FROM messages
  WHERE role = 'assistant' AND ts BETWEEN :period_start AND :period_end
),
fb AS (
  SELECT message_id, value FROM feedback
  WHERE ts BETWEEN :period_start AND :period_end
)
SELECT
  COUNT(*) AS answers,
  COUNT(DISTINCT user_id) AS wau,
  AVG(CASE WHEN f.value = 'like' THEN 1.0 WHEN f.value = 'dislike' THEN 0 END) AS csat,
  COUNT(f.message_id)::float / NULLIF(COUNT(*), 0) AS feedback_rate,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms/1000.0) AS p95,
  10 AS sla_p95,
  SUM(CASE WHEN f.value = 'like' THEN 1 ELSE 0 END) AS likes,
  SUM(CASE WHEN f.value = 'dislike' THEN 1 ELSE 0 END) AS dislikes,
  AVG(CASE WHEN refused THEN 1.0 ELSE 0 END) AS refusal_rate,
  AVG(tokens_out) AS tokens_per_answer,
  SUM(latency_ms)/1000.0 / NULLIF(COUNT(DISTINCT chat_id), 0) AS gpu_sec_per_chat,
  SUM(tokens_out)::float / NULLIF(SUM(latency_ms)/1000.0, 0) AS throughput_tok_s,
  AVG(CASE WHEN prompt_id IS NOT NULL THEN 1.0 ELSE 0 END) AS skill_coverage,
  AVG(latency_ms)/1000.0 AS avg_latency,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms/1000.0) AS median_latency,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms/1000.0) AS p95_latency,
  AVG(ttft_ms)/1000.0 AS ttft,
  AVG(rag_ms)/1000.0 AS rag_latency,
  AVG(CASE WHEN status >= 500 THEN 1.0 ELSE 0 END) AS error_rate,
  AVG(CASE WHEN error_code = 'timeout' OR latency_ms > 30000 THEN 1.0 ELSE 0 END) AS timeout_rate
FROM base b LEFT JOIN fb f ON f.message_id = b.id;
```

Запустить **дважды**: один раз для текущего периода, второй — для предыдущего равного. Объединить в одну CSV с двумя строками (`period: current/previous`) — парсер `dashboard-v2.js` уже это умеет.

### 3.2 `daily.csv`

```sql
SELECT
  ts::date AS date,
  COUNT(*) FILTER (WHERE role = 'assistant') AS answers,
  COUNT(DISTINCT user_id) AS users,
  COUNT(*) FILTER (WHERE id IN (SELECT message_id FROM feedback WHERE value = 'like')) AS likes,
  COUNT(*) FILTER (WHERE id IN (SELECT message_id FROM feedback WHERE value = 'dislike')) AS dislikes,
  COUNT(*) FILTER (WHERE id IN (SELECT message_id FROM feedback)) AS feedback,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms/1000.0) AS p95,
  COUNT(*) FILTER (WHERE status >= 500) AS errors
FROM messages
WHERE role = 'assistant' AND ts BETWEEN :period_start AND :period_end
GROUP BY ts::date ORDER BY 1;
```

### 3.3 `prompts.csv`

```sql
SELECT
  COALESCE(p.title, 'без промпта') AS prompt,
  COUNT(*) AS uses,
  AVG(m.latency_ms)/1000.0 AS avg_latency,
  AVG(CASE WHEN f.value = 'like' THEN 1.0 WHEN f.value = 'dislike' THEN 0 END) AS csat,
  COUNT(f.message_id)::float / NULLIF(COUNT(*), 0) AS feedback_rate
FROM messages m
LEFT JOIN prompts p ON p.id = m.prompt_id
LEFT JOIN feedback f ON f.message_id = m.id
WHERE m.role = 'assistant' AND m.ts BETWEEN :period_start AND :period_end
GROUP BY p.title
ORDER BY uses DESC LIMIT 20;
```

### 3.4 `latency.csv`

Объединяем 8‑бакетную гистограмму и 24‑часовой p95 в одну CSV с колонкой `kind`:

```sql
SELECT 'bucket' AS kind, bucket::text AS x, cnt AS y FROM (
  SELECT width_bucket(latency_ms/1000.0, 0, 16, 8) AS bucket, COUNT(*) AS cnt
  FROM messages WHERE role = 'assistant' AND ts BETWEEN :period_start AND :period_end
  GROUP BY 1
) b
UNION ALL
SELECT 'hour' AS kind,
       EXTRACT(hour FROM ts AT TIME ZONE 'Europe/Moscow')::text AS x,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms/1000.0) AS y
FROM messages WHERE role = 'assistant' AND ts BETWEEN :period_start AND :period_end
GROUP BY 2 ORDER BY 1, x::int;
```

### 3.5 `retention.csv` — NEW

```sql
WITH first_seen AS (
  SELECT user_id, MIN(ts::date) AS d0 FROM messages
  WHERE ts >= :period_start - interval '7 day' AND ts <= :period_end
  GROUP BY user_id
),
returns AS (
  SELECT f.user_id, f.d0,
    MAX(CASE WHEN m.ts::date = f.d0 + 1 THEN 1 ELSE 0 END) AS d1,
    MAX(CASE WHEN m.ts::date BETWEEN f.d0 + 1 AND f.d0 + 7 THEN 1 ELSE 0 END) AS d7
  FROM first_seen f JOIN messages m ON m.user_id = f.user_id
  GROUP BY f.user_id, f.d0
),
power AS (
  SELECT COUNT(*) AS power_users FROM (
    SELECT user_id FROM messages
    WHERE role = 'assistant' AND ts BETWEEN :period_start AND :period_end
    GROUP BY user_id
    HAVING COUNT(*) >= 10 * GREATEST(1, EXTRACT(week FROM age(:period_end, :period_start)))
  ) t
),
stickiness AS (
  SELECT
    (SELECT COUNT(DISTINCT user_id) FROM messages WHERE ts >= :period_end - interval '1 day' AND ts < :period_end)::float
    / NULLIF((SELECT COUNT(DISTINCT user_id) FROM messages WHERE ts >= :period_end - interval '30 day'), 0) AS s
)
SELECT
  AVG(d1)::float AS d1,
  AVG(d7)::float AS d7,
  (SELECT power_users FROM power) AS power,
  (SELECT s FROM stickiness) AS stickiness
FROM returns WHERE d0 BETWEEN :period_start AND :period_end;
```

### 3.6 `quality.csv` — NEW

```sql
WITH seq AS (
  SELECT chat_id, ts, lower(content) AS q,
         LAG(lower(content)) OVER (PARTITION BY chat_id ORDER BY ts) AS prev_q
  FROM messages WHERE role = 'user' AND ts BETWEEN :period_start AND :period_end
),
repeats AS (
  SELECT ts::date AS date,
         AVG(CASE WHEN prev_q IS NOT NULL AND (q = prev_q OR levenshtein(q, prev_q) <= 5) THEN 1.0 ELSE 0 END) AS repeat_rate
  FROM seq GROUP BY 1
)
SELECT
  m.ts::date AS date,
  AVG(CASE WHEN m.refused THEN 1.0 ELSE 0 END) AS refusal_rate,
  AVG(CASE WHEN m.status >= 500 THEN 1.0 ELSE 0 END) AS error_rate,
  AVG(CASE WHEN m.error_code = 'timeout' OR m.latency_ms > 30000 THEN 1.0 ELSE 0 END) AS timeout_rate,
  COALESCE(r.repeat_rate, 0) AS repeat_rate
FROM messages m LEFT JOIN repeats r ON r.date = m.ts::date
WHERE m.role = 'assistant' AND m.ts BETWEEN :period_start AND :period_end
GROUP BY m.ts::date, r.repeat_rate ORDER BY 1;
```

> Требуется расширение `fuzzystrmatch` для `levenshtein`. Если флага `refused` в логе нет — заменить на регексп по тексту ответа.

---

## 4. Этапы

### Этап 1 — Парсеры в `dashboard-v2.js` (полдня)

В `dashboard-v2.js` уже есть аплоадер для 4 файлов. Добавить ещё 2:

1. В шапке `Dashboard v2.html`, в блоке `.upload`, добавить две кнопки‑слота: «Retention» и «Качество».
2. В `dashboard-v2.js` добавить хэндлеры `parseRetention(rows)` и `parseQuality(rows)`:
   ```js
   function parseRetention(rows) {
     const r = rows[0]; // одна строка
     STATE.summary.d1 = num(r.d1);
     STATE.summary.d7 = num(r.d7);
     STATE.summary.power = num(r.power);
     STATE.summary.stickiness = num(r.stickiness);
     STATE.source.retention = 'csv';
   }
   function parseQuality(rows) {
     // рассчитываем средние за период
     const avg = (k) => rows.reduce((s, r) => s + num(r[k]), 0) / rows.length;
     STATE.summary.refusal_rate = avg('refusal_rate');
     STATE.summary.error_rate   = avg('error_rate');
     STATE.summary.timeout_rate = avg('timeout_rate');
     STATE.summary.repeat_rate  = avg('repeat_rate');
     STATE.source.quality = 'csv';
   }
   ```
3. Удалить из `STATE.mock` ключи, которые теперь приходят из CSV. Оставить мок только как fallback при незагруженном файле.
4. Бар источников в шапке расширить с 4 до 6 пунктов (`summary / daily / prompts / latency / retention / quality`).

**Acceptance:** при загрузке всех 6 CSV ни одно значение в дашборде не приходит из `STATE.mock`.

### Этап 2 — Документация SQL для аналитика (час)

Создать в репо файл `sql/queries.sql` с 6 запросами из §3, разделить комментариями:

```sql
-- ============================================================
-- 1. summary.csv  — экспорт: «Save Result Set as CSV»
-- ============================================================
... (запрос §3.1)

-- ============================================================
-- 2. daily.csv
-- ============================================================
...
```

В DBeaver: правый клик по результату → **Export Data → CSV**, разделитель `,`, кодировка UTF‑8, заголовок включить.

**Acceptance:** аналитик за 5 минут получает все 6 файлов и кидает в дашборд.

### Этап 3 — Шеринг (без изменений)

`share.js` уже работает. После загрузки CSV нажатие «Поделиться» собирает single‑file HTML с зашитыми данными — отправляется в чат команды.

---

## 5. Acceptance criteria

- [ ] В дашборде есть 6 CSV‑слотов в шапке.
- [ ] Загрузка каждого CSV меняет соответствующую плашку с «демо» на «CSV».
- [ ] Все плитки с пометкой NEW читают свои значения из загруженных файлов, а не из мок‑набора.
- [ ] Снапшот через «Поделиться» открывается оффлайн и показывает те же цифры.
- [ ] Файл `sql/queries.sql` лежит рядом с дашбордом и копируется в DBeaver as‑is.

---

## 6. Open questions для аналитика/продакта

1. Есть ли в `messages` поле `refused`, или нужен текстовый детектор?
2. Поля `ttft_ms`, `rag_ms`, `tokens_in/out` — логируются?
3. Что считать «использованием скилла» — `prompt_id IS NOT NULL` или вызов tool?
4. Тайм‑зона для группировки по часам — Europe/Moscow.
5. Период «всё» — на сколько данных смотрим (тяжесть запроса).

Уточнить до старта Этапа 1.
