// Демо-данные, повторяющие скриншоты текущего дашборда.
// Заменяются загруженными CSV из DBeaver (тот же формат, что в all_queries.sql).

window.DEMO = {
  summary: {
    total_users: 43,
    new_users: 43,
    dau_avg: 0.3,
    wau: 38,
    mau: 43,
    total_questions: 477,
    total_chats: 110,
    avg_questions_per_user: 11.1,
    avg_questions_per_chat: 4.3,
    total_tokens: 190705,
    likes: 25,
    dislikes: 19,
    total_votes: 44,
    like_pct: 56.8,
    llm_avg_ms: 8169,
    llm_median_ms: 4743,
    llm_p95_ms: 23194,
    rag_avg_ms: 531,
    ttft_avg_ms: 1872,
    ttft_p95_ms: 12379,
  },

  // Сравнение с предыдущим периодом (мок — пока не считается из CSV)
  prev: {
    total_questions: 116,
    wau: 33,
    like_pct: 61.4,
    llm_p95_ms: 19800,
  },

  // По дням (формат как в daily.csv)
  daily: [
    { day: "2026-04-13", questions: 4,  active_users: 2,  chats: 2,  likes: 0,  dislikes: 0 },
    { day: "2026-04-14", questions: 3,  active_users: 1,  chats: 1,  likes: 0,  dislikes: 0 },
    { day: "2026-04-15", questions: 5,  active_users: 2,  chats: 2,  likes: 0,  dislikes: 0 },
    { day: "2026-04-16", questions: 12, active_users: 3,  chats: 3,  likes: 0,  dislikes: 0 },
    { day: "2026-04-17", questions: 14, active_users: 1,  chats: 2,  likes: 0,  dislikes: 0 },
    { day: "2026-04-20", questions: 6,  active_users: 1,  chats: 2,  likes: 0,  dislikes: 0 },
    { day: "2026-04-23", questions: 11, active_users: 2,  chats: 4,  likes: 1,  dislikes: 0 },
    { day: "2026-04-24", questions: 17, active_users: 3,  chats: 5,  likes: 0,  dislikes: 0 },
    { day: "2026-04-27", questions: 18, active_users: 3,  chats: 4,  likes: 0,  dislikes: 0 },
    { day: "2026-04-28", questions: 15, active_users: 3,  chats: 5,  likes: 0,  dislikes: 0 },
    { day: "2026-04-29", questions: 9,  active_users: 1,  chats: 3,  likes: 1,  dislikes: 2 },
    { day: "2026-04-30", questions: 21, active_users: 4,  chats: 6,  likes: 0,  dislikes: 0 },
    { day: "2026-05-04", questions: 8,  active_users: 3,  chats: 4,  likes: 0,  dislikes: 0 },
    { day: "2026-05-05", questions: 76, active_users: 10, chats: 14, likes: 1,  dislikes: 1 },
    { day: "2026-05-06", questions: 187, active_users: 23, chats: 35, likes: 21, dislikes: 11 },
    { day: "2026-05-07", questions: 62, active_users: 14, chats: 12, likes: 1,  dislikes: 5 },
    { day: "2026-05-08", questions: 9,  active_users: 6,  chats: 6,  likes: 0,  dislikes: 0 },
  ],

  // Топ промптов (формат как в prompts.csv)
  prompts: [
    { prompt_name: "(без промпта)",          category: null,            chats_count: 113, unique_users: 45, likes: 24, dislikes: 19, pct_of_total: 93.4, dislike_pct: 44.2 },
    { prompt_name: "Software Engineer",      category: "Engineering",   chats_count: 3,   unique_users: 3,  likes: 1,  dislikes: 0,  pct_of_total: 2.5, dislike_pct: 0 },
    { prompt_name: "Аналитик документов",    category: "Аналитика",     chats_count: 3,   unique_users: 3,  likes: 0,  dislikes: 0,  pct_of_total: 2.5, dislike_pct: null },
    { prompt_name: "Генератор официальных писем", category: "Коммуникации", chats_count: 1, unique_users: 1, likes: 0, dislikes: 0, pct_of_total: 0.8, dislike_pct: null },
    { prompt_name: "Умный саммаризатор",     category: "Обработка текста", chats_count: 1, unique_users: 1, likes: 0,  dislikes: 0,  pct_of_total: 0.8, dislike_pct: null },
  ],

  // Латентность по часам суток
  latency_hour: [
    { hour_of_day: 7,  llm_avg_ms: 3500,  llm_p95_ms: 16000,  responses_count: 8 },
    { hour_of_day: 8,  llm_avg_ms: 3000,  llm_p95_ms: 8000,   responses_count: 12 },
    { hour_of_day: 9,  llm_avg_ms: 31000, llm_p95_ms: 127000, responses_count: 24 },
    { hour_of_day: 10, llm_avg_ms: 5500,  llm_p95_ms: 12500,  responses_count: 31 },
    { hour_of_day: 11, llm_avg_ms: 10500, llm_p95_ms: 21000,  responses_count: 38 },
    { hour_of_day: 12, llm_avg_ms: 5500,  llm_p95_ms: 21000,  responses_count: 26 },
    { hour_of_day: 13, llm_avg_ms: 3500,  llm_p95_ms: 16000,  responses_count: 19 },
    { hour_of_day: 14, llm_avg_ms: 8500,  llm_p95_ms: 26500,  responses_count: 35 },
    { hour_of_day: 15, llm_avg_ms: 11000, llm_p95_ms: 30500,  responses_count: 41 },
    { hour_of_day: 16, llm_avg_ms: 6000,  llm_p95_ms: 14500,  responses_count: 28 },
    { hour_of_day: 17, llm_avg_ms: 8500,  llm_p95_ms: 30500,  responses_count: 33 },
    { hour_of_day: 18, llm_avg_ms: 9500,  llm_p95_ms: 19500,  responses_count: 22 },
    { hour_of_day: 19, llm_avg_ms: 4000,  llm_p95_ms: 14000,  responses_count: 11 },
    { hour_of_day: 20, llm_avg_ms: 2000,  llm_p95_ms: 5000,   responses_count: 4 },
    { hour_of_day: 21, llm_avg_ms: 5500,  llm_p95_ms: 12500,  responses_count: 6 },
  ],

  // Гистограмма латентности (бакеты, мс) — синтетика
  latency_buckets: [
    { bucket: "< 1с",   count: 28,  share: 5.9 },
    { bucket: "1–2с",   count: 71,  share: 14.9 },
    { bucket: "2–5с",   count: 152, share: 31.9 },
    { bucket: "5–10с",  content: 120, count: 120, share: 25.2 },
    { bucket: "10–30с", count: 87,  share: 18.2 },
    { bucket: "≥ 30с",  count: 19,  share: 4.0 },
  ],

  // Метрики, которых пока нет в SQL — синтетические значения для прототипа
  mock: {
    d1_retention: 42,         // %
    d7_retention: 28,         // %
    d30_retention: 14,        // %
    power_users: 7,           // ≥ 20 вопросов / нед
    refusal_rate: 6.1,        // %
    repeat_rate: 14.0,        // %
    long_answer_rate: 11,     // % > 800 токенов
    short_answer_rate: 8,     // % < 50 токенов
    top_user_token_share: 19, // %
    rag_hit_rate: 73,         // %
    error_rate: 1.4,          // %
    timeout_rate: 4.0,        // %  (llmMs > 30000)
    concurrency_peak: 6,      // одновременных запросов
    // Гистограмма глубины разговора (чатов с N вопросов)
    depth_hist: [
      { range: "1",   chats: 24 },
      { range: "2–3", chats: 38 },
      { range: "4–7", chats: 31 },
      { range: "8+",  chats: 17 },
    ],
  },
};
