(() => {
    const script = document.currentScript || document.querySelector('script[data-title]');
    const titles = (script?.getAttribute('data-titles') || window.__NB_TITLES__ || '')
        .split('|')
        .map(title => title.trim())
        .filter(Boolean);
    let target = window.__NB_TITLE__ || script?.getAttribute('data-title') || document.title;
    let titleIndex = Math.max(0, titles.indexOf(target));
    let decodeToken = 0;
    const glyphs = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_|/\\[]{}<>#@$%&*+=?';
    const keep = /[\s|—-]/;

    function randomTitle() {
        return Array.from(target, ch => keep.test(ch) ? ch : glyphs[Math.floor(Math.random() * glyphs.length)]);
    }

    function easeOutCubic(t) {
        return 1 - Math.pow(1 - t, 3);
    }

    function decode(nextTitle = target) {
        target = nextTitle;
        window.__NB_TITLE__ = target;
        const token = ++decodeToken;
        const duration = 1650;
        const start = performance.now();
        const state = randomTitle();
        const next = state.map(() => start + 35 + Math.random() * 90);

        function step(now) {
            if (token !== decodeToken) return;
            const progress = Math.min(1, (now - start) / duration);
            const reveal = easeOutCubic(progress) * target.length;

            for (let i = 0; i < target.length; i++) {
                if (i <= reveal || keep.test(target[i])) {
                    state[i] = target[i];
                } else if (now >= next[i]) {
                    state[i] = glyphs[Math.floor(Math.random() * glyphs.length)];
                    next[i] = now + 65 + Math.random() * 125;
                }
            }

            document.title = state.join('');
            if (progress < 1) {
                requestAnimationFrame(step);
            } else {
                document.title = target;
            }
        }

        requestAnimationFrame(step);
    }

    function start() {
        document.title = target;
        decode();
        window.addEventListener('focus', () => decode(target));
        window.__NB_DECODE_TITLE__ = (t) => decode(t);
        let intervalId = setInterval(() => {
            if (titles.length > 1) {
                titleIndex = (titleIndex + 1) % titles.length;
                decode(titles[titleIndex]);
            } else {
                decode(window.__NB_TITLE__ || target);
            }
        }, 7000);
        // bfcache-safe cleanup
        window.addEventListener('pagehide', () => { if (intervalId) { clearInterval(intervalId); intervalId = null; } });
        window.addEventListener('pageshow', (e) => {
            if (e.persisted && !intervalId) {
                intervalId = setInterval(() => {
                    if (titles.length > 1) {
                        titleIndex = (titleIndex + 1) % titles.length;
                        decode(titles[titleIndex]);
                    } else {
                        decode(window.__NB_TITLE__ || target);
                    }
                }, 7000);
            }
        });
        window.addEventListener('beforeunload', () => { if (intervalId) { clearInterval(intervalId); intervalId = null; } });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
