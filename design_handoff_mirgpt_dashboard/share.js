/* ──────────────────────────────────────────────────────────────────────
   share.js — экспорт текущего состояния дашборда в один offline HTML.
   Инлайнит: dashboard-v2.js, dashboard-v2-demo.js → снапшот STATE,
             Chart.js (CDN), Papa Parse (CDN), Google Fonts (CSS + woff2 base64).
   Внешних зависимостей у итогового файла нет — открывается без интернета.
   ──────────────────────────────────────────────────────────────────── */
(function () {
  // Кэш тяжёлых ресурсов между кликами
  const cache = {};

  async function fetchText(url) {
    if (cache[url]) return cache[url];
    // XHR работает на file:// в отличие от fetch()
    const t = await new Promise((res, rej) => {
      const xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      xhr.onload = () => xhr.status < 400 ? res(xhr.responseText) : rej(new Error('XHR ' + url + ': ' + xhr.status));
      xhr.onerror = () => rej(new Error('XHR failed: ' + url));
      xhr.send();
    });
    cache[url] = t;
    return t;
  }

  function blobToBase64(blob) {
    return new Promise((res, rej) => {
      const r = new FileReader();
      r.onerror = () => rej(r.error);
      r.onload = () => res(String(r.result).split(',')[1]);
      r.readAsDataURL(blob);
    });
  }

  // Скачиваем Google Fonts CSS, затем все woff2 → base64, подставляем data: URL
  async function inlineGoogleFontsCss(cssUrl) {
    const cacheKey = '__inlined__' + cssUrl;
    if (cache[cacheKey]) return cache[cacheKey];
    const css = await fetchText(cssUrl);
    const urls = [...new Set([...css.matchAll(/url\((https:\/\/fonts\.gstatic\.com\/[^)]+)\)/g)].map(m => m[1]))];
    const map = {};
    await Promise.all(urls.map(async u => {
      const blob = await fetch(u).then(r => r.blob());
      const b64 = await blobToBase64(blob);
      map[u] = 'data:' + (blob.type || 'font/woff2') + ';base64,' + b64;
    }));
    let out = css;
    for (const [from, to] of Object.entries(map)) {
      out = out.split(from).join(to);
    }
    cache[cacheKey] = out;
    return out;
  }

  async function exportSnapshot() {
    const btn = document.getElementById('shareBtn');
    if (!btn) return;
    const origText = btn.textContent;
    const setText = (s) => { btn.textContent = s; };
    btn.disabled = true;

    try {
      // 1) Собираем тексты ресурсов параллельно
      setText('Собираю ресурсы…');

      // Локальные JS читаем через абсолютный src тега — fetch('dashboard-v2.js') не работает на file://
      const getScriptSrc = (pattern) => {
        const el = [...document.querySelectorAll('script[src]')]
          .find(s => pattern.test(s.getAttribute('src') || ''));
        if (!el) throw new Error('script not found: ' + pattern);
        return fetchText(el.src);
      };

      const [jsText, chartJsText, papaText, fontCssJBM, fontCssInter] = await Promise.all([
        getScriptSrc(/dashboard-v2\.js$/),
        fetchText('https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js'),
        fetchText('https://cdn.jsdelivr.net/npm/papaparse@5.4.1/papaparse.min.js'),
        inlineGoogleFontsCss('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap'),
        inlineGoogleFontsCss('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap'),
      ]);

      // 2) Снимок STATE
      const snapshot = {
        summary: window.STATE?.summary ?? window.DEMO?.summary,
        prev: window.STATE?.prev ?? window.DEMO?.prev,
        daily: window.STATE?.daily ?? window.DEMO?.daily,
        prompts: window.STATE?.prompts ?? window.DEMO?.prompts,
        latency_hour: window.STATE?.latencyHour ?? window.DEMO?.latency_hour,
        latency_buckets: window.STATE?.buckets ?? window.DEMO?.latency_buckets,
        mock: window.STATE?.mock ?? window.DEMO?.mock,
      };
      const meta = {
        exportedAt: new Date().toISOString(),
        sources: { ...(window.STATE?.source || {}) },
        period: window.STATE?.period ?? 30,
        offline: true,
      };

      // 3) Клон DOM
      setText('Готовлю файл…');
      const docClone = document.documentElement.cloneNode(true);

      // Сбросим канвасы — Chart.js перерисует
      docClone.querySelectorAll('canvas').forEach(c => {
        c.removeAttribute('width');
        c.removeAttribute('height');
        c.style.removeProperty('width');
        c.style.removeProperty('height');
      });

      // Заменим внешние <script src=...> на инлайн
      docClone.querySelectorAll('script[src]').forEach(s => {
        const src = s.getAttribute('src') || '';
        let inlineCode = null;
        if (/dashboard-v2-demo\.js$/.test(src)) {
          inlineCode =
            'window.DEMO = ' + JSON.stringify(snapshot) + ';\n' +
            'window.__SNAPSHOT__ = ' + JSON.stringify(meta) + ';';
        } else if (/dashboard-v2\.js$/.test(src)) {
          inlineCode = jsText;
        } else if (/share\.js$/.test(src)) {
          s.remove();
          return;
        } else if (/chart\.umd\.min\.js/.test(src)) {
          inlineCode = chartJsText;
        } else if (/papaparse\.min\.js/.test(src)) {
          inlineCode = papaText;
        }
        if (inlineCode != null) {
          const inline = document.createElement('script');
          inline.textContent = inlineCode;
          s.replaceWith(inline);
        }
      });

      // Удалим preconnect и заменим Google Fonts <link> на <style>
      docClone.querySelectorAll('link[rel="preconnect"]').forEach(l => l.remove());
      docClone.querySelectorAll('link[rel="stylesheet"]').forEach(l => {
        const href = l.getAttribute('href') || '';
        if (href.includes('fonts.googleapis.com/css2')) {
          const style = document.createElement('style');
          if (href.includes('JetBrains+Mono')) style.textContent = fontCssJBM;
          else if (href.includes('Inter')) style.textContent = fontCssInter;
          else return;
          l.replaceWith(style);
        }
      });

      // Сбросим file input
      docClone.querySelectorAll('input[type="file"]').forEach(i => i.removeAttribute('value'));

      const html = '<!DOCTYPE html>\n' + docClone.outerHTML;
      const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
      const sizeKb = Math.round(blob.size / 1024);
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'mirgpt-dashboard-' + meta.exportedAt.slice(0, 10) + '.html';
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);

      setText('✓ ' + sizeKb + ' КБ');
      setTimeout(() => { setText(origText); btn.disabled = false; }, 2000);
    } catch (e) {
      console.error('export failed', e);
      setText('✗ Ошибка');
      setTimeout(() => { setText(origText); btn.disabled = false; }, 2400);
    }
  }

  window.exportSnapshot = exportSnapshot;
  document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('shareBtn')?.addEventListener('click', exportSnapshot);
  });
})();
