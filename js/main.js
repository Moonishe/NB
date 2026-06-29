async function trackVisit() {
    try {
        const TTL = 60 * 60 * 1000; // 1 час
        const cached = localStorage.getItem('nb_visit_tracked');
        if (cached) {
            try {
                const parsed = JSON.parse(cached);
                if (parsed && parsed.ts && (Date.now() - parsed.ts < TTL)) return;
            } catch {}
        }
        const ua = navigator.userAgent || '';
        const screenInfo = screen.width + 'x' + screen.height;
        const raw = ua + screenInfo + navigator.language;
        const hashBuffer = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(raw));
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        const visitorHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 32);
        await Api.trackPageView(visitorHash, window.location.pathname, document.referrer || null);
        localStorage.setItem('nb_visit_tracked', JSON.stringify({ ts: Date.now() }));
    } catch {}
}

document.addEventListener('DOMContentLoaded', async () => {
    trackVisit();

    const searchInput = document.getElementById('model-search');
    const searchClear = document.getElementById('model-search-clear');
    if (searchInput) {
        let debounceTimer;
        searchInput.addEventListener('input', () => {
            clearTimeout(debounceTimer);
            const val = searchInput.value.trim();
            if (searchClear) searchClear.classList.toggle('hidden', !val);
            debounceTimer = setTimeout(() => { if (typeof LeaderboardModule !== 'undefined') LeaderboardModule.setSearch(val); }, 250);
        });
    }
    if (searchClear) {
        searchClear.addEventListener('click', () => {
            searchInput.value = '';
            searchClear.classList.add('hidden');
            if (typeof LeaderboardModule !== 'undefined') LeaderboardModule.setSearch('');
        });
    }

    const retryBtn = document.getElementById('error-retry-btn');
    if (retryBtn) {
        retryBtn.addEventListener('click', () => { if (typeof LeaderboardModule !== 'undefined') LeaderboardModule.retry(); });
    }

    try {
        const TTL = 60 * 60 * 1000; // 1 час
        let cachedSha = null;
        const cachedRaw = localStorage.getItem('nb_github_sha');
        if (cachedRaw) {
            try {
                const parsed = JSON.parse(cachedRaw);
                if (parsed && parsed.sha && parsed.ts && (Date.now() - parsed.ts < TTL)) cachedSha = parsed.sha;
            } catch {}
        }
        if (cachedSha) {
            const shaEl = document.getElementById('commit-sha');
            if (shaEl) shaEl.textContent = cachedSha;
        } else {
            const resp = await fetch('https://api.github.com/repos/Moonishe/NB/commits?per_page=1');
            if (!resp.ok) throw new Error('GitHub API ' + resp.status);
            const data = await resp.json();
            if (data && data[0] && data[0].sha) {
                const sha = data[0].sha.slice(0, 7);
                localStorage.setItem('nb_github_sha', JSON.stringify({ sha, ts: Date.now() }));
                const shaEl = document.getElementById('commit-sha');
                if (shaEl) shaEl.textContent = sha;
            }
        }
    } catch {}

    document.addEventListener('click', (e) => {
        if (!e.target.closest('.date-dropdown-container')) {
            document.querySelectorAll('.date-dropdown-menu.visible').forEach(m => {
                m.classList.remove('opacity-100', 'visible', 'translate-y-0');
                m.classList.add('opacity-0', 'invisible', 'translate-y-[-10px]');
            });
            document.querySelectorAll('.date-chevron.rotate-180').forEach(c => c.classList.remove('rotate-180'));
        }
    });

    if (typeof LeaderboardModule !== 'undefined') {
        LeaderboardModule.load();
    }
});
