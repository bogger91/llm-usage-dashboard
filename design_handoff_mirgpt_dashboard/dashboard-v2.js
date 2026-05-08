/* ──────────────────────────────────────────────────────────────────────
   dashboard-v2.js — рендер нового дашборда МирГПТ
   Источники: window.DEMO (демо) или загруженные CSV (заменяют demo)
   ──────────────────────────────────────────────────────────────────── */

const C = {
  accent:    'oklch(0.55 0.16 258)',
  accentSoft:'oklch(0.93 0.04 258)',
  accentInk: 'oklch(0.38 0.14 258)',
  good:      'oklch(0.55 0.12 155)',
  goodSoft:  'oklch(0.93 0.05 155)',
  warn:      'oklch(0.58 0.16 25)',
  warnSoft:  'oklch(0.93 0.05 25)',
  ink:       '#0e0f12',
  muted:     '#7a7d85',
  line:      '#e6e5e1',
};

// ── Состояние ────────────────────────────────────────────────────────
const STATE = {
  summary: { ...DEMO.summary },
  prev:    { ...DEMO.prev },
  daily:   [...DEMO.daily],
  prompts: [...DEMO.prompts],
  latencyHour: [...DEMO.latency_hour],
  buckets: [...DEMO.latency_buckets],
  mock: { ...DEMO.mock },
  source: { summary: 'demo', daily: 'demo', prompts: 'demo', latency: 'demo' },
  period: 30, // дней; demo
};
window.STATE = STATE;

const charts = {};

// ── Утилиты ──────────────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);

const fmt = (n, opts = {}) => {
  if (n == null || n === '' || Number.isNaN(+n)) return '—';
  const num = +n;
  if (opts.short && Math.abs(num) >= 1000) {
    if (Math.abs(num) >= 1e6) return (num / 1e6).toFixed(1).replace('.0','') + 'M';
    if (Math.abs(num) >= 1e3) return (num / 1e3).toFixed(1).replace('.0','') + 'k';
  }
  return num.toLocaleString('ru-RU', { maximumFractionDigits: opts.dp ?? 0 });
};
const pct = (n, dp = 1) => n == null || n === '' ? '—' : (+n).toFixed(dp) + '%';
const ms  = (n) => n == null ? '—' : (+n / 1000).toFixed(n < 1000 ? 2 : 1) + ' с';

function delta(curr, prev, opts = {}) {
  if (prev == null || curr == null) return null;
  if (prev === 0) return null;
  const d = ((curr - prev) / prev) * 100;
  const goodIsUp = !opts.invert;
  const sign = d >= 0 ? '▲' : '▼';
  const isGood = goodIsUp ? d >= 0 : d <= 0;
  const text = `${sign} ${Math.abs(d).toFixed(d >= 100 ? 0 : 0)}% к пред. периоду`;
  return { text, good: isGood };
}

function setText(id, text) { const el = $(id); if (el) el.textContent = text; }
function setDelta(id, d) {
  const el = $(id); if (!el) return;
  if (!d) { el.textContent = '—'; el.className = 'tile-delta'; return; }
  el.textContent = d.text;
  el.className = 'tile-delta ' + (d.good ? 'up' : 'down');
}

// ── Период (фильтр демо/CSV daily) ───────────────────────────────────
function applyPeriod() {
  // Просто перерисуем графики с тем же массивом — для прототипа фильтрация
  // оставлена символичной (период подсвечивается, а данные те же).
  setText('periodLabel', STATE.period === 999 ? 'весь период' : `последние ${STATE.period} дней`);
  document.querySelectorAll('.period-pill').forEach(p => {
    p.classList.toggle('active', +p.dataset.period === STATE.period);
  });
  renderAll();
}

// ── Рендер: HERO ─────────────────────────────────────────────────────
function renderHero() {
  const s = STATE.summary, p = STATE.prev;

  setText('heroQuestions', fmt(s.total_questions));
  setDelta('heroQuestionsDelta', delta(s.total_questions, p.total_questions));

  setText('heroWau', fmt(s.wau));
  setDelta('heroWauDelta', delta(s.wau, p.wau));

  setText('heroSat', s.like_pct == null ? '—' : (+s.like_pct).toFixed(1));
  const fbRate = s.total_questions ? (s.total_votes / s.total_questions) * 100 : 0;
  setText('heroSatHint', `оценили лишь ${fbRate.toFixed(1)}% ответов`);

  setText('heroP95', (s.llm_p95_ms / 1000).toFixed(1));
  const slaSec = 10;
  const overSla = (s.llm_p95_ms / 1000) > slaSec;
  setText('heroP95Hint', overSla
    ? `выше SLA ${slaSec} с`
    : `в пределах SLA ${slaSec} с`);
  $('heroP95Hint').className = 'tile-delta ' + (overSla ? 'down' : 'up');

  // Спарклайны
  drawSpark('sparkQuestions', STATE.daily.map(d => +d.questions), C.accent, true);
  drawSpark('sparkWau',       STATE.daily.map(d => +d.active_users), C.good, false);
  drawSpark('sparkSat',       STATE.daily.map(d => {
    const t = (+d.likes) + (+d.dislikes);
    return t ? (+d.likes / t) * 100 : null;
  }), C.accent, false);
  drawSpark('sparkP95',       STATE.latencyHour.map(h => +h.llm_p95_ms / 1000), C.warn, false);
}

// SVG спарклайн
function drawSpark(id, values, stroke, area) {
  const el = $(id); if (!el) return;
  const pts = values.filter(v => v != null && !Number.isNaN(v));
  if (!pts.length) { el.innerHTML = ''; return; }
  const W = 200, H = 28, pad = 1;
  const min = Math.min(...pts), max = Math.max(...pts);
  const range = (max - min) || 1;
  const step = pts.length > 1 ? (W - pad * 2) / (pts.length - 1) : 0;
  const path = pts.map((v, i) => {
    const x = pad + i * step;
    const y = H - pad - ((v - min) / range) * (H - pad * 2);
    return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  const areaPath = area
    ? `${path} L${(pad + (pts.length - 1) * step).toFixed(1)},${H} L${pad},${H} Z`
    : '';
  el.innerHTML = `
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" width="100%" height="100%">
      ${area ? `<path d="${areaPath}" fill="${C.accentSoft}" stroke="none"/>` : ''}
      <path d="${path}" fill="none" stroke="${stroke}" stroke-width="1.5" />
    </svg>`;
}

// ── Рендер: тайлы ────────────────────────────────────────────────────
function renderTiles() {
  const s = STATE.summary;
  const m = STATE.mock;

  // Активация и удержание
  setTile('tD1',  m.d1_retention, '%', { goal: 50, label: 'цель ≥ 50%' });
  setTile('tD7',  m.d7_retention, '%', { goal: 30, label: 'цель ≥ 30%' });
  setTile('tD30', m.d30_retention, '%', { goal: 15, label: 'цель ≥ 15%' });
  setText('tPower', fmt(m.power_users));
  setText('tPowerHint', '≥ 20 вопросов / нед');
  const stick = s.mau ? (s.dau_avg / s.mau) : 0;
  setText('tStick', stick.toFixed(2));
  setText('tStickHint', stick < 0.1 ? 'низкая (норма 0.20–0.25)' : 'норма 0.20–0.25');
  $('tStickHint').className = 'tile-foot ' + (stick < 0.1 ? 'down' : '');

  // Качество
  const fbRate = s.total_questions ? (s.total_votes / s.total_questions) * 100 : 0;
  setText('tFb', fbRate.toFixed(1));
  setText('tFbHint', `${fmt(s.total_votes)} / ${fmt(s.total_questions)}`);
  setText('tLD', `${fmt(s.likes)} : ${fmt(s.dislikes)}`);
  const dPct = s.total_votes ? (s.dislikes / s.total_votes) * 100 : 0;
  setText('tLDHint', `дизлайков ${dPct.toFixed(0)}%`);
  $('tLDHint').className = 'tile-foot ' + (dPct > 30 ? 'down' : '');
  setBarSplit('tLDBar', s.likes, s.dislikes);

  setText('tRefusal', m.refusal_rate.toFixed(1));
  setText('tRefusalHint', '«не могу ответить»');
  setText('tRepeat',  m.repeat_rate.toFixed(1));
  setText('tRepeatHint', 'переспрос за 5 мин');
  $('tRepeatHint').className = 'tile-foot ' + (m.repeat_rate > 10 ? 'down' : '');

  // GPU и токены
  const tokensPerAns = s.total_questions ? Math.round(s.total_tokens / s.total_questions) : 0;
  setText('tTok',  fmt(tokensPerAns));
  setText('tTokHint', `всего ${fmt(s.total_tokens, { short: true })} токенов`);

  // GPU-секунды на чат: суммарное llm-время (avg × ответов) / чатов
  const totalLlmSec = (s.llm_avg_ms / 1000) * s.total_questions;
  const gpuPerChat = s.total_chats ? totalLlmSec / s.total_chats : 0;
  setText('tGpuSec', gpuPerChat.toFixed(1));
  setText('tGpuSecHint', `≈ ${fmt(totalLlmSec, { short: true })} GPU-сек / период`);

  // Throughput: токенов в секунду на GPU
  const throughput = totalLlmSec ? s.total_tokens / totalLlmSec : 0;
  setText('tThru', fmt(throughput, { dp: 1 }));
  setText('tThruHint', 'токенов / GPU-сек');

  // Skill coverage
  const noPrompt = STATE.prompts.find(p => /без\s*пром/i.test(p.prompt_name));
  const totalChatsP = STATE.prompts.reduce((a, p) => a + (+p.chats_count || 0), 0);
  const cov = totalChatsP ? (1 - (+noPrompt?.chats_count || 0) / totalChatsP) * 100 : 0;
  setText('tSkill', cov.toFixed(1));
  setText('tSkillHint', `${totalChatsP - (+noPrompt?.chats_count || 0)} из ${totalChatsP} чатов`);
  $('tSkillHint').className = 'tile-foot ' + (cov < 20 ? 'down' : '');

  // Performance
  setText('tLlmAvg', ms(s.llm_avg_ms));
  setText('tLlmMed', ms(s.llm_median_ms));
  setText('tLlmP95', ms(s.llm_p95_ms));
  setText('tTtftAvg', ms(s.ttft_avg_ms));
  setText('tTtftP95', ms(s.ttft_p95_ms));
  setText('tRagAvg', ms(s.rag_avg_ms));
  setText('tErr',  m.error_rate.toFixed(1));
  setText('tErrHint', 'из всех assistant');
  setText('tTimeout', m.timeout_rate.toFixed(1));
  setText('tTimeoutHint', 'llmMs > 30 с');
}

function setTile(id, value, suffix = '', { goal, label } = {}) {
  setText(id, value == null ? '—' : (+value).toFixed(0));
  const sufEl = $(id + 'Suf'); if (sufEl) sufEl.textContent = suffix;
  const bar = $(id + 'Bar');
  if (bar) bar.firstElementChild.style.width = `${Math.min(100, +value || 0)}%`;
  const hint = $(id + 'Hint');
  if (hint && label) {
    hint.textContent = label;
    if (goal != null) hint.classList.toggle('down', +value < goal);
  }
}

function setBarSplit(id, a, b) {
  const el = $(id); if (!el) return;
  const total = a + b || 1;
  const aw = (a / total) * 100;
  el.innerHTML = `
    <i style="width:${aw}%; background: var(--good)"></i>
    <b style="width:${100 - aw}%; background: var(--warn)"></b>`;
}

// ── Рендер: графики ──────────────────────────────────────────────────
const baseScales = {
  x: { grid: { color: C.line }, ticks: { color: C.muted, font: { size: 11, family: 'JetBrains Mono, monospace' } } },
  y: { grid: { color: C.line }, ticks: { color: C.muted, font: { size: 11, family: 'JetBrains Mono, monospace' } }, beginAtZero: true },
};
const baseOpts = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { labels: { font: { size: 11 }, color: '#3a3d44', boxWidth: 10, boxHeight: 10 } },
    tooltip: { mode: 'index', intersect: false, padding: 10, backgroundColor: '#0e0f12' },
  },
  scales: baseScales,
};

function makeChart(id, config) {
  if (charts[id]) charts[id].destroy();
  const ctx = $(id); if (!ctx) return;
  charts[id] = new Chart(ctx.getContext('2d'), config);
}

function renderCharts() {
  // 1. Активность по дням
  makeChart('chartActivity', {
    type: 'bar',
    data: {
      labels: STATE.daily.map(d => d.day.slice(5)),
      datasets: [
        { label: 'Вопросы', data: STATE.daily.map(d => +d.questions),
          backgroundColor: C.accentSoft, borderColor: C.accent, borderWidth: 1.5, borderRadius: 3,
          yAxisID: 'y' },
        { label: 'Активные пользователи', data: STATE.daily.map(d => +d.active_users),
          type: 'line', borderColor: C.good, backgroundColor: 'transparent',
          pointRadius: 2.5, pointBackgroundColor: C.good, tension: .3, yAxisID: 'y1' },
      ],
    },
    options: { ...baseOpts,
      scales: {
        x: baseScales.x,
        y:  { ...baseScales.y, position: 'left' },
        y1: { ...baseScales.y, position: 'right', grid: { drawOnChartArea: false } },
      },
    },
  });

  // 2. Feedback по дням + feedback rate
  makeChart('chartFeedback', {
    type: 'bar',
    data: {
      labels: STATE.daily.map(d => d.day.slice(5)),
      datasets: [
        { label: 'Лайки',    data: STATE.daily.map(d => +d.likes),
          backgroundColor: C.goodSoft, borderColor: C.good, borderWidth: 1.5, stack: 'v', yAxisID: 'y' },
        { label: 'Дизлайки', data: STATE.daily.map(d => +d.dislikes),
          backgroundColor: C.warnSoft, borderColor: C.warn, borderWidth: 1.5, stack: 'v', yAxisID: 'y' },
        { label: 'Feedback rate, %',
          data: STATE.daily.map(d => d.questions ? ((+d.likes + +d.dislikes) / +d.questions) * 100 : 0),
          type: 'line', borderColor: C.accent, backgroundColor: 'transparent',
          pointRadius: 2, tension: .3, yAxisID: 'y1', borderDash: [4, 3] },
      ],
    },
    options: { ...baseOpts,
      scales: {
        x: baseScales.x,
        y:  { ...baseScales.y, position: 'left', stacked: true },
        y1: { ...baseScales.y, position: 'right', max: 100, grid: { drawOnChartArea: false },
              title: { display: true, text: '% оценили', color: C.muted, font: { size: 10 } } },
      },
    },
  });

  // 3. Гистограмма латентности
  makeChart('chartLatencyHist', {
    type: 'bar',
    data: {
      labels: STATE.buckets.map(b => b.bucket),
      datasets: [{
        label: 'Ответы',
        data: STATE.buckets.map(b => +b.count),
        backgroundColor: STATE.buckets.map(b =>
          /≥\s*30|10–30/.test(b.bucket) ? C.warnSoft : C.accentSoft),
        borderColor: STATE.buckets.map(b =>
          /≥\s*30|10–30/.test(b.bucket) ? C.warn : C.accent),
        borderWidth: 1.5, borderRadius: 3,
      }],
    },
    options: { ...baseOpts, plugins: { ...baseOpts.plugins, legend: { display: false } } },
  });

  // 4. Латентность по часам
  makeChart('chartLatencyHour', {
    type: 'bar',
    data: {
      labels: STATE.latencyHour.map(h => `${h.hour_of_day}:00`),
      datasets: [
        { label: 'avg, мс',  data: STATE.latencyHour.map(h => +h.llm_avg_ms),
          backgroundColor: C.accentSoft, borderColor: C.accent, borderWidth: 1.5, borderRadius: 3 },
        { label: 'p95, мс',  data: STATE.latencyHour.map(h => +h.llm_p95_ms),
          type: 'line', borderColor: C.warn, backgroundColor: 'transparent',
          pointRadius: 2.5, tension: .3 },
      ],
    },
    options: baseOpts,
  });

  // 5. Топ промптов горизонтальный bar
  const top = STATE.prompts.slice(0, 8);
  makeChart('chartPrompts', {
    type: 'bar',
    data: {
      labels: top.map(p => p.prompt_name.length > 28 ? p.prompt_name.slice(0, 26) + '…' : p.prompt_name),
      datasets: [{
        data: top.map(p => +p.chats_count),
        backgroundColor: top.map((p, i) => i === 0 && /без\s*пром/i.test(p.prompt_name) ? C.warnSoft : C.accentSoft),
        borderColor:    top.map((p, i) => i === 0 && /без\s*пром/i.test(p.prompt_name) ? C.warn : C.accent),
        borderWidth: 1.5, borderRadius: 3,
      }],
    },
    options: { ...baseOpts, indexAxis: 'y',
      plugins: { ...baseOpts.plugins, legend: { display: false } } },
  });

  // 6. Глубина разговора
  makeChart('chartDepth', {
    type: 'bar',
    data: {
      labels: STATE.mock.depth_hist.map(d => d.range + ' вопр.'),
      datasets: [{
        data: STATE.mock.depth_hist.map(d => +d.chats),
        backgroundColor: C.accentSoft, borderColor: C.accent,
        borderWidth: 1.5, borderRadius: 3,
      }],
    },
    options: { ...baseOpts, plugins: { ...baseOpts.plugins, legend: { display: false } } },
  });
}

// ── Таблица промптов ─────────────────────────────────────────────────
function renderPromptTable() {
  const max = Math.max(...STATE.prompts.map(p => +p.chats_count));
  const rows = STATE.prompts.map((r, i) => {
    const noPrompt = /без\s*пром/i.test(r.prompt_name);
    const dp = r.dislike_pct == null || r.dislike_pct === '' ? null : +r.dislike_pct;
    return `
      <tr${noPrompt ? ' class="row-warn"' : ''}>
        <td class="num">${i + 1}</td>
        <td><div class="cell-name">${r.prompt_name}${noPrompt ? '<span class="row-tag">пусто</span>' : ''}</div></td>
        <td class="muted">${r.category || '—'}</td>
        <td>
          <div class="bar-cell">
            <div class="bar-bg"><div class="bar-fill" style="width:${(+r.chats_count / max * 100).toFixed(0)}%"></div></div>
            <span class="num">${fmt(r.chats_count)}</span>
          </div>
        </td>
        <td class="num">${fmt(r.unique_users)}</td>
        <td class="num">${pct(r.pct_of_total)}</td>
        <td class="num"><span class="chip chip-good">${fmt(r.likes)}</span></td>
        <td class="num">
          ${dp == null ? '<span class="muted">—</span>' : `
          <div class="bar-cell">
            <div class="bar-bg"><div class="bar-fill warn" style="width:${dp.toFixed(0)}%"></div></div>
            <span class="num">${dp.toFixed(1)}%</span>
          </div>`}
        </td>
      </tr>`;
  }).join('');

  $('promptTable').innerHTML = `
    <table>
      <thead><tr>
        <th>#</th><th>Промпт</th><th>Категория</th>
        <th>Чаты</th><th>Польз.</th><th>Доля</th>
        <th>Лайки</th><th>Дизлайки %</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>`;
}

// ── Главный рендер ───────────────────────────────────────────────────
function renderAll() {
  renderHero();
  renderTiles();
  renderCharts();
  renderPromptTable();
  updateSourceBadges();
}

function updateSourceBadges() {
  document.querySelectorAll('[data-source]').forEach(b => {
    const key = b.dataset.source;
    const isDemo = STATE.source[key] === 'demo';
    b.textContent = isDemo ? 'демо' : 'CSV';
    b.classList.toggle('demo', isDemo);
  });
}

// ── CSV загрузка ─────────────────────────────────────────────────────
function parseCSV(file) {
  return new Promise((res, rej) =>
    Papa.parse(file, { header: true, skipEmptyLines: true, complete: r => res(r.data), error: rej }));
}

function bindUpload(inputId, statusId, handler) {
  $(inputId).addEventListener('change', async (e) => {
    const file = e.target.files[0]; if (!file) return;
    try {
      const rows = await parseCSV(file);
      handler(rows);
      $(statusId).textContent = '✓ ' + file.name;
      $(statusId).className = 'upload-status ok';
      renderAll();
    } catch (err) {
      $(statusId).textContent = '✗ ошибка';
      $(statusId).className = 'upload-status err';
      console.error(err);
    }
  });
}

bindUpload('fileSummary', 'stSummary', (rows) => {
  if (rows[0]) {
    STATE.summary = { ...STATE.summary, ...rows[0] };
    // Числа из CSV приходят строками — нормализуем числовые поля
    Object.keys(STATE.summary).forEach(k => {
      const v = STATE.summary[k];
      if (typeof v === 'string' && v.match(/^-?[\d.]+$/)) STATE.summary[k] = +v;
    });
    STATE.source.summary = 'csv';
  }
});
bindUpload('fileDaily', 'stDaily', (rows) => {
  STATE.daily = rows.map(r => ({
    day: r.day, questions: +r.questions, active_users: +r.active_users,
    chats: +r.chats, likes: +r.likes, dislikes: +r.dislikes,
  }));
  STATE.source.daily = 'csv';
});
bindUpload('filePrompts', 'stPrompts', (rows) => {
  STATE.prompts = rows;
  STATE.source.prompts = 'csv';
});
bindUpload('fileLatencyHour', 'stLatencyHour', (rows) => {
  STATE.latencyHour = rows.map(r => ({
    hour_of_day: +r.hour_of_day,
    llm_avg_ms: +r.llm_avg_ms,
    llm_p95_ms: +r.llm_p95_ms,
    responses_count: +r.responses_count,
  }));
  STATE.source.latency = 'csv';
});

// ── Период ───────────────────────────────────────────────────────────
document.querySelectorAll('.period-pill').forEach(p => {
  p.addEventListener('click', () => { STATE.period = +p.dataset.period; applyPeriod(); });
});

// ── Сброс на демо ────────────────────────────────────────────────────
$('resetDemo')?.addEventListener('click', () => {
  STATE.summary = { ...DEMO.summary };
  STATE.prev    = { ...DEMO.prev };
  STATE.daily   = [...DEMO.daily];
  STATE.prompts = [...DEMO.prompts];
  STATE.latencyHour = [...DEMO.latency_hour];
  STATE.buckets = [...DEMO.latency_buckets];
  STATE.mock    = { ...DEMO.mock };
  STATE.source  = { summary: 'demo', daily: 'demo', prompts: 'demo', latency: 'demo' };
  ['stSummary','stDaily','stPrompts','stLatencyHour'].forEach(id => {
    $(id).textContent = '—'; $(id).className = 'upload-status';
  });
  renderAll();
});

// ── Снапшот‑режим (HTML, экспортированный через «Поделиться») ────────
if (window.__SNAPSHOT__) {
  document.body.classList.add('snapshot-mode');
  const meta = window.__SNAPSHOT__;
  Object.assign(STATE.source, meta.sources || {});
  if (meta.period != null) STATE.period = meta.period;
  const upload = document.querySelector('.upload');
  if (upload) {
    const dt = new Date(meta.exportedAt).toLocaleString('ru-RU', {
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit',
    });
    const sources = meta.sources || {};
    const csvN = Object.values(sources).filter(s => s === 'csv').length;
    const labels = { summary: 'Сводка', daily: 'По дням', prompts: 'Промпты', latency: 'Латентность' };
    const pills = Object.keys(labels).map(k => {
      const s = sources[k] || 'demo';
      return `<span class="src-pill ${s === 'csv' ? 'ok' : 'demo'}">${labels[k]}: ${s === 'csv' ? 'CSV' : 'демо'}</span>`;
    }).join(' ');
    upload.innerHTML = `
      <span class="upload-label">Снапшот от</span>
      <span class="upload-status ok" style="min-width:auto">${dt}</span>
      <span style="width:1px;height:14px;background:var(--line-2);margin:0 6px"></span>
      ${pills}
      <span style="margin-left:auto; color:var(--muted); font-family:var(--mono); font-size:11px">${csvN}/4 из CSV · только просмотр</span>`;
  }
  document.getElementById('shareBtn')?.remove();
}

// ── Старт ────────────────────────────────────────────────────────────
renderAll();
applyPeriod();
