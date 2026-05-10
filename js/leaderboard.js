const CRITERIA = ["Визуал", "Анимация", "Креатив", "Код", "Детали"];
const MAX_PER = 10;
const MAX_TOTAL = 90;

const LeaderboardModule = (() => {
    let promptsCache = { easy: [], medium: [], hard: [] };
    let currentDifficulty = 'easy';
    let currentPromptId = null;
    let currentTop = 'all';
    let currentSort = 'score';
    let resultsData = [];
    let allModelsCount = 0;
    let searchQuery = '';
    let barObserver = null;
    let decodeObserver = null;
    let svgPreviewObserver = null;
    let svgPreviewQueue = [];
    let svgPreviewQueueRunning = false;
    let pendingTimeouts = [];


    function getProfileBasePath() {
        const parts = window.location.pathname.split('/').filter(Boolean);
        if (window.location.hostname.endsWith('github.io') && parts.length > 0) return '/' + parts[0];
        return '';
    }

    function getProfileHref(uid, userId) {
        if (uid !== undefined && uid !== null && String(uid) !== '') return getProfileBasePath() + '/profile/uid-' + encodeURIComponent(uid);
        if (userId) return getProfileBasePath() + '/profile.html?id=' + encodeURIComponent(userId);
        return '#';
    }

    let ratingStats = new Map();
    let ratingEntries = new Map();

    const glyphPoolCache = new Map();
    const glyphMetricsCanvas = document.createElement('canvas');
    const glyphMetricsCtx = glyphMetricsCanvas.getContext('2d');
    const SVG_SANITIZE_CACHE_LIMIT = 80;
    const svgSanitizeCache = new Map();

    function scrambleText(el, target, duration = 600) {
        if (!el || !el.isConnected) return;
        target = String(target || '');
        const chars = 'ABCDEFGHKNOPRSTUVXYZ023456789#@%&';
        const len = target.length;
        const rg = () => chars[Math.floor(Math.random() * chars.length)];
        const keep = /[\s.\-:,\/]/;
        const t0 = performance.now();
        const frozen = new Uint8Array(len);
        function step(now) {
            if (!el.isConnected) return;
            const t = Math.min((now - t0) / duration, 1);
            const sweepPos = t * (len + 3);
            let out = '';
            for (let i = 0; i < len; i++) {
                if (keep.test(target[i])) { out += target[i]; continue; }
                if (frozen[i]) { out += target[i]; continue; }
                if (i < sweepPos - 1) { frozen[i] = 1; out += target[i]; }
                else out += rg();
            }
            el.textContent = out;
            if (t < 1) requestAnimationFrame(step);
            else el.textContent = target;
        }
        el.textContent = Array.from(target).map(c => keep.test(c) ? c : rg()).join('');
        requestAnimationFrame(step);
    }

    async function load() {
        showLoading();
        hideError();
        try {
            promptsCache.easy = await Api.getPromptsByDifficulty('easy');
            promptsCache.medium = await Api.getPromptsByDifficulty('medium');
            promptsCache.hard = await Api.getPromptsByDifficulty('hard');
        } catch (e) {
            promptsCache = { easy: [], medium: [], hard: [] };
            hideLoading();
            showError('Не удалось загрузить промпты. Проверьте подключение.');
            renderDifficultyFilters();
            return;
        }
        try {
            const allModels = await Api.getAllModels();
            allModelsCount = allModels.length;
        } catch { allModelsCount = 0; }
        hideLoading();
        renderDifficultyFilters();
        selectDifficulty('easy');
    }

    function renderDifficultyFilters() {
        const container = document.getElementById('difficulty-filters');
        container.innerHTML = '';
        const diffs = [
            { key: 'easy', label: 'Лёгкие' },
            { key: 'medium', label: 'Средние' },
            { key: 'hard', label: 'Сложные' }
        ];
        diffs.forEach((d, i) => {
            const btn = document.createElement('button');
            btn.className = 'difficulty-tab' + (d.key === currentDifficulty ? ' active' : '');
            btn.setAttribute('data-difficulty', d.key);
            btn.setAttribute('aria-pressed', d.key === currentDifficulty ? 'true' : 'false');
            btn.textContent = d.label;
            btn.addEventListener('click', () => selectDifficulty(d.key));
            container.appendChild(btn);
            setTimeout(() => scrambleText(btn, d.label, 400), i * 60);
        });
    }

    async function selectDifficulty(diff) {
        currentDifficulty = diff;
        currentPromptId = null;
        document.querySelectorAll('#difficulty-filters .difficulty-tab').forEach(b => {
            const active = b.getAttribute('data-difficulty') === diff;
            b.classList.toggle('active', active);
            b.setAttribute('aria-pressed', active ? 'true' : 'false');
        });
        renderPromptFilters();
        renderTopFilters();
        const prompts = promptsCache[currentDifficulty] || [];
        if (prompts.length > 0) {
            await selectPrompt(prompts[0].id);
        } else {
            hidePromptDisplay();
            clearBenchmarkList();
            showEmptyState();
        }
    }

    function renderPromptFilters() {
        const container = document.getElementById('prompt-filters');
        container.innerHTML = '';
        const prompts = promptsCache[currentDifficulty] || [];
        if (prompts.length === 0) {
            container.innerHTML = '<span class="text-xs text-gray-500 uppercase tracking-widest">Нет промптов</span>';
            return;
        }
        prompts.forEach((p, i) => {
            const btn = document.createElement('button');
            btn.className = 'top-filter-btn' + (p.id === currentPromptId ? ' active' : '');
            btn.setAttribute('data-prompt-id', p.id);
            btn.setAttribute('aria-pressed', p.id === currentPromptId ? 'true' : 'false');
            const label = p.name || ('Промпт #' + (i + 1));
            btn.textContent = label;
            btn.addEventListener('click', () => selectPrompt(p.id));
            container.appendChild(btn);
            setTimeout(() => scrambleText(btn, label, 500), i * 50);
        });
    }

    function renderTopFilters() {
        const container = document.getElementById('top-filters');
        container.innerHTML = '';
        const tops = [
            { key: 'all', label: 'Все' },
            { key: '3', label: 'Топ 3' },
            { key: '5', label: 'Топ 5' },
            { key: '10', label: 'Топ 10' }
        ];
        tops.forEach((t, i) => {
            const btn = document.createElement('button');
            btn.className = 'top-filter-btn' + (t.key === currentTop ? ' active' : '');
            btn.setAttribute('data-count', t.key);
            btn.setAttribute('aria-pressed', t.key === currentTop ? 'true' : 'false');
            btn.textContent = t.label;
            btn.addEventListener('click', () => selectTop(t.key));
            container.appendChild(btn);
            setTimeout(() => scrambleText(btn, t.label, 400), i * 50);
        });
        if (currentTop === 'all') {
            const sortBtn = document.createElement('button');
            sortBtn.className = 'top-filter-btn sort-btn' + (currentSort === 'date' ? ' active' : '');
            sortBtn.setAttribute('data-sort', 'date');
            sortBtn.setAttribute('aria-pressed', currentSort === 'date' ? 'true' : 'false');
            sortBtn.textContent = 'По дате';
            sortBtn.addEventListener('click', () => { currentSort = currentSort === 'date' ? 'score' : 'date'; renderTopFilters(); renderBenchmarkList(); });
            container.appendChild(sortBtn);
            setTimeout(() => scrambleText(sortBtn, 'По дате', 400), tops.length * 50);
        } else {
            currentSort = 'score';
        }
    }

    async function selectPrompt(promptId) {
        currentPromptId = promptId;
        document.querySelectorAll('#prompt-filters .top-filter-btn').forEach(b => {
            const bid = isNaN(b.getAttribute('data-prompt-id')) ? b.getAttribute('data-prompt-id') : parseInt(b.getAttribute('data-prompt-id'));
            const active = bid === promptId;
            b.classList.toggle('active', active);
            b.setAttribute('aria-pressed', active ? 'true' : 'false');
        });
        const prompts = promptsCache[currentDifficulty] || [];
        const prompt = prompts.find(p => p.id === promptId);
        if (prompt) showPromptDisplay(prompt.text);
        await loadResults();
    }

    let _autoRefreshTimer = null;
    function startAutoRefresh() {
        // FIX: сбрасываем старый таймер при каждом вызове чтобы он всегда обновлял актуальный currentPromptId
        if (_autoRefreshTimer) {
            clearInterval(_autoRefreshTimer);
            _autoRefreshTimer = null;
        }
        _autoRefreshTimer = setInterval(async () => {
            if (document.hidden || !currentPromptId) return;
            try {
                const fresh = await Api.getResultsByPrompt(currentPromptId);
                const prevIds = new Set(resultsData.map(r => r.id));
                const hasNew = fresh.some(r => !prevIds.has(r.id));
                const hasChanges = hasNew || fresh.some(r => {
                    const prev = resultsData.find(p => p.id === r.id);
                    return prev && JSON.stringify(prev) !== JSON.stringify(r);
                });
                if (hasChanges) {
                    resultsData = fresh;
                    renderBenchmarkList(resultsData);
                }
            } catch (_) {}
        }, 180000);
    }

    async function loadResults() {
        if (!currentPromptId) { clearBenchmarkList(); showEmptyState(); return; }
        showLoading();
        hideError();
        try {
            resultsData = await Api.getResultsByPrompt(currentPromptId);
            const resultIds = resultsData.map(r => r.id);
            const [stats, entries] = await Promise.all([
                Api.getResultRatingStats(resultIds),
                Api.getResultRatingEntries ? Api.getResultRatingEntries(resultIds, 8) : []
            ]);
            ratingStats = new Map((stats || []).map(s => [Number(s.result_id), s]));
            ratingEntries = new Map();
            (entries || []).forEach(entry => {
                const id = Number(entry.result_id);
                if (!ratingEntries.has(id)) ratingEntries.set(id, []);
                ratingEntries.get(id).push(entry);
            });
            if (Api.isDevSession()) {
                const devRatings = JSON.parse(localStorage.getItem('nb_dev_ratings') || '{}');
                Object.entries(devRatings).forEach(([rid, rv]) => {
                    const id = Number(rid);
                    const existing = ratingStats.get(id);
                    const myTotal = (rv.s_visual + rv.s_animation + rv.s_creative + rv.s_code + rv.s_detail) * 1.8;
                    if (existing) {
                        existing.my_score = myTotal;
                        existing.my_s_visual = rv.s_visual;
                        existing.my_s_animation = rv.s_animation;
                        existing.my_s_creative = rv.s_creative;
                        existing.my_s_code = rv.s_code;
                        existing.my_s_detail = rv.s_detail;
                        existing.my_update_count = Number(rv.update_count || 0);
                    } else {
                        ratingStats.set(id, {
                            result_id: id, avg_score: null, rating_count: 0,
                            my_score: myTotal,
                            my_s_visual: rv.s_visual, my_s_animation: rv.s_animation,
                            my_s_creative: rv.s_creative, my_s_code: rv.s_code, my_s_detail: rv.s_detail,
                            my_update_count: Number(rv.update_count || 0)
                        });
                    }
                });
            }
        } catch (e) {
            resultsData = [];
            ratingStats = new Map();
            ratingEntries = new Map();
            hideLoading();
            showError('Не удалось загрузить результаты. Попробуйте позже.');
            return;
        }
        hideLoading();
        renderBenchmarkList();
        hideEmptyState();
    }

    function selectTop(count) {
        currentTop = count;
        currentSort = 'score';
        renderTopFilters();
        renderBenchmarkList();
    }

    const PROMPT_MAX_LINES = 5;

    function showPromptDisplay(text) {
        const el = document.getElementById('prompt-text');
        const fade = document.getElementById('prompt-text-fade');
        const btn = document.getElementById('prompt-expand-btn');
        document.getElementById('prompt-display').classList.remove('hidden');
        el.textContent = text;
        scrambleText(el, text, Math.min(1200, 300 + text.length * 4));
        el.style.maxHeight = '';
        el.style.overflow = '';
        fade.classList.add('hidden');
        btn.classList.add('hidden');
        btn.textContent = 'Открыть полностью';
        requestAnimationFrame(() => {
            const cs = getComputedStyle(el);
            const lh = parseFloat(cs.lineHeight);
            const fontSize = parseFloat(cs.fontSize);
            const effectiveLH = isNaN(lh) ? fontSize * 1.5 : lh;
            const maxH = effectiveLH * PROMPT_MAX_LINES;
            if (el.scrollHeight > maxH + 4) {
                el.style.maxHeight = maxH + 'px';
                el.style.overflow = 'hidden';
                fade.classList.remove('hidden');
                btn.classList.remove('hidden');
                let expanded = false;
                btn.onclick = () => {
                    expanded = !expanded;
                    if (expanded) { el.style.maxHeight = ''; el.style.overflow = ''; fade.classList.add('hidden'); btn.textContent = 'Свернуть'; }
                    else { el.style.maxHeight = maxH + 'px'; el.style.overflow = 'hidden'; fade.classList.remove('hidden'); btn.textContent = 'Открыть полностью'; }
                };
            }
        });
    }

    function hidePromptDisplay() { document.getElementById('prompt-display').classList.add('hidden'); document.getElementById('prompt-text').textContent = ''; document.getElementById('prompt-text-fade').classList.add('hidden'); document.getElementById('prompt-expand-btn').classList.add('hidden'); }
    function showEmptyState() { document.getElementById('empty-state').classList.remove('hidden'); }
    function hideEmptyState() { document.getElementById('empty-state').classList.add('hidden'); }
    function clearBenchmarkList() { document.getElementById('benchmark-list').innerHTML = ''; }
    function showLoading() { document.getElementById('loading-state').classList.remove('hidden'); }
    function hideLoading() { document.getElementById('loading-state').classList.add('hidden'); }
    function showError(msg) { const el = document.getElementById('error-state'); el.classList.remove('hidden'); if (msg) document.getElementById('error-state-text').textContent = msg; }
    function hideError() { document.getElementById('error-state').classList.add('hidden'); }
    function showNoResults() { document.getElementById('no-results-state').classList.remove('hidden'); }
    function hideNoResults() { document.getElementById('no-results-state').classList.add('hidden'); }

    function renderBars(result) {
        let scoresHtml = '';
        const keys = ['s_visual', 's_animation', 's_creative', 's_code', 's_detail'];
        CRITERIA.forEach((c, ci) => {
            const score = parseFloat(result[keys[ci]]) || 0;
            const scoreText = Number.isInteger(score) ? String(score) : score.toFixed(1);
            const pct = (score / MAX_PER) * 100;
            scoresHtml += `
                <div class="w-full">
                    <div class="flex justify-between text-xs mb-2.5 uppercase tracking-widest text-gray-400">
                        <span class="criteria-decode" data-name="${c}">${c}</span>
                        <span class="text-white font-bold score-decode" data-name="${scoreText} / 10">${scoreText} / 10</span>
                    </div>
                    <div class="h-[18px] w-full bg-black/40 relative overflow-hidden">
                        <div class="hatching-fill absolute top-0 left-0 h-full w-0 transition-all duration-[1.8s] cubic-bezier(0.19, 1, 0.22, 1) score-bar" data-ci="${ci}" data-target="${pct}%"></div>
                    </div>
                </div>
            `;
        });
        return scoresHtml;
    }

    function escapeHtml(str) {
        const d = document.createElement('div');
        d.textContent = str;
        return d.innerHTML.replace(/"/g, '&quot;');
    }

    function formatScore(score) {
        const n = parseFloat(score);
        if (!Number.isFinite(n)) return '—';
        return Number.isInteger(n) ? String(n) : n.toFixed(1);
    }

    function parseFiniteScore(value, fallback = null) {
        const n = parseFloat(value);
        return Number.isFinite(n) ? n : fallback;
    }

    function getScoreMeta(result) {
        const adminScore = parseFiniteScore(result.overall, 0);
        const stat = ratingStats.get(Number(result.id));
        const userScore = stat && stat.avg_score != null ? parseFiniteScore(stat.avg_score, null) : null;
        const userCount = stat && stat.rating_count != null ? Number(stat.rating_count) : 0;
        const myScore = stat && stat.my_score != null ? parseFiniteScore(stat.my_score, null) : null;
        const myCriteria = {
            s_visual: stat && stat.my_s_visual != null ? parseFiniteScore(stat.my_s_visual, null) : null,
            s_animation: stat && stat.my_s_animation != null ? parseFiniteScore(stat.my_s_animation, null) : null,
            s_creative: stat && stat.my_s_creative != null ? parseFiniteScore(stat.my_s_creative, null) : null,
            s_code: stat && stat.my_s_code != null ? parseFiniteScore(stat.my_s_code, null) : null,
            s_detail: stat && stat.my_s_detail != null ? parseFiniteScore(stat.my_s_detail, null) : null
        };
        const myUpdateCount = stat && stat.my_update_count != null ? Number(stat.my_update_count) : 0;
        const combined = userScore == null ? adminScore : (adminScore + userScore) / 2;
        return {
            adminScore,
            userScore,
            userCount,
            myScore,
            myCriteria,
            myUpdateCount,
            combined: Math.max(0, Math.round((Number.isFinite(combined) ? combined : 0) * 10) / 10)
        };
    }

    function renderScoreSplit(result, meta) {
        const isLoggedIn = Api.isDevSession()
            || (Api.hasStoredSupabaseSession && Api.hasStoredSupabaseSession())
            || (Api.getUserId && Api.getUserId());
        const userLabel = meta.userScore == null ? '—' : formatScore(meta.userScore);
        const mineLabel = meta.myScore == null ? '—' : formatScore(meta.myScore);
        const mineRaw = meta.myScore == null ? '' : meta.myScore;
        const minePillHtml = isLoggedIn ? `
                <div class="benchmark-score-pill benchmark-score-mine">
                    <span class="score-pill-value" data-raw="${mineRaw}">${mineLabel}</span>
                    <small>твоя</small>
                </div>` : '';
        return `
            <div class="benchmark-score-split" data-result-id="${result.id}">
                <div class="benchmark-score-pill benchmark-score-admin">
                    <span class="score-pill-value" data-raw="${meta.adminScore}">0</span>
                    <small>admin</small>
                </div>
                <div class="benchmark-score-pill benchmark-score-user">
                    <span class="score-pill-value" data-raw="${meta.userScore ?? ''}">${userLabel}</span>
                    <small>общая</small>
                </div>${minePillHtml}
            </div>
        `;
    }


    function renderRateCta(resultId, requiresAuth) {
        const label = requiresAuth ? 'Войдите, чтобы оценить' : 'Оценить';
        const authClass = requiresAuth ? ' benchmark-rate-cta-auth' : '';
        return `
            <div class="benchmark-left-rating">
                <button class="benchmark-rate-cta${authClass}" type="button" data-result-id="${resultId}" data-requires-auth="${requiresAuth ? 'true' : 'false'}">
                    <span class="rate-cta-label" aria-label="${label}">
                        ${label.split('').map((ch, idx) => `<span class="rate-cta-char" data-char="${ch}" style="--i:${idx}">${ch}</span>`).join('')}
                    </span>
                </button>
            </div>`;
    }

    function renderRatingForm(result, meta, forceOpen) {
        const isLoggedIn = Api.isDevSession()
            || (Api.hasStoredSupabaseSession && Api.hasStoredSupabaseSession())
            || (Api.getUserId && Api.getUserId());
        const updateCount = Math.max(0, Number(meta.myUpdateCount) || 0);
        const updatesLeft = Math.max(0, 2 - updateCount);
        const isExisting = meta.myScore != null;
        const isLocked = isExisting && updatesLeft <= 0;
        if (!isLoggedIn) return renderRateCta(result.id, true);
        if (!isExisting && !forceOpen) {
            return renderRateCta(result.id, false);
        }
        const keys = ['s_visual', 's_animation', 's_creative', 's_code', 's_detail'];
        const ratingRows = keys.map((key, idx) => {
            const numeric = meta.myCriteria?.[key] == null ? 1 : parseFloat(meta.myCriteria[key]);
            const selected = formatScore(numeric);
            const pct = Math.max(0, Math.min(100, (numeric / MAX_PER) * 100));
            return `
                <label class="benchmark-rating-field benchmark-rating-mini-field" style="--rating-pct:${pct}%">
                    <div class="benchmark-rating-mini-head">
                        <span class="criteria-decode" data-name="${CRITERIA[idx]}">${CRITERIA[idx]}</span>
                        <input type="number" name="${key}" aria-label="${CRITERIA[idx]}" min="1" max="10" step="0.1" inputmode="decimal" value="${selected}" ${isLocked ? 'disabled' : ''}>
                    </div>
                    <div class="benchmark-rating-mini-track" aria-hidden="true">
                        <div class="benchmark-rating-mini-fill"></div>
                    </div>
                </label>
            `;
        }).join('');
        const headLabel = isExisting ? (isLocked ? 'Твоя окончательная оценка' : `Переоценка (${updatesLeft})`) : 'Оценить';
        const attemptsHtml = '';
        const submitText = isExisting ? `Обновить (${updatesLeft})` : 'Оценить';
        const submitHtml = isLocked ? '' : `<button class="benchmark-rate-submit" type="submit">${submitText}</button>`;
        return `
            <div class="benchmark-left-rating">
                <div class="benchmark-left-rating-head">
                    <span class="rating-head-decode criteria-decode" data-name="${headLabel}">${headLabel}</span>
                    ${attemptsHtml}
                </div>
                <form class="benchmark-rate-form" data-result-id="${result.id}" data-update-count="${updateCount}" data-locked="${isLocked ? 'true' : 'false'}">
                    <div class="benchmark-rate-row">${ratingRows}</div>
                    ${submitHtml}
                </form>
            </div>
        `;
    }

    function formatRatingDate(dateVal) {
        if (!dateVal) return '—';
        const d = new Date(dateVal);
        if (isNaN(d.getTime())) return '—';
        const day = String(d.getDate()).padStart(2, '0');
        const month = String(d.getMonth() + 1).padStart(2, '0');
        return `${day}.${month} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    }

    function formatRatingDelay(seconds) {
        const n = Number(seconds);
        if (!Number.isFinite(n) || n <= 0) return '+0с';
        const days = Math.floor(n / 86400);
        if (days > 0) return `+${days}д`;
        const hours = Math.floor(n / 3600);
        if (hours > 0) return `+${hours}ч`;
        const minutes = Math.floor(n / 60);
        if (minutes > 0) return `+${minutes}м`;
        return `+${Math.floor(n)}с`;
    }

    function normalizeRole(role) {
        const allowed = ['admin', 'stmoderator', 'moderator', 'beta', 'alpha', 'member'];
        return allowed.includes(role) ? role : 'member';
    }

    function getRoleLabel(role) {
        const labels = { admin: 'ADMIN', stmoderator: 'ST.MOD', moderator: 'MOD', beta: 'BETA', alpha: 'ALPHA', member: 'MEMBER' };
        return labels[role] || labels.member;
    }

    function renderRatingEntriesPanel(result) {
        const entries = ratingEntries.get(Number(result.id)) || [];
        const stats = ratingStats.get(Number(result.id));
        const visibleCount = Number(stats?.rating_count ?? entries.length) || 0;
        const panelId = `rating-entries-${result.id}`;
        const rows = entries.map((entry, idx) => {
            const role = normalizeRole(entry.rater_role);
            const nickname = entry.rater_nickname || entry.rater_uid || 'user';
            const uid = entry.rater_uid ? String(entry.rater_uid) : '';
            const href = uid ? getProfileHref(uid) : '#';
            const rank = Number(entry.rating_rank) || idx + 1;
            const score = Number(entry.total_score);
            const scoreText = Number.isFinite(score) ? formatScore(score) : '—';
            const nickHtml = uid
                ? `<a class="rating-entry-user" href="${href}">@${escapeHtml(nickname)}</a>`
                : `<span class="rating-entry-user">@${escapeHtml(nickname)}</span>`;
            return `
                <tr>
                    <td>
                        <div class="rating-entry-person">
                            ${nickHtml}
                            <span class="rating-entry-role rating-role-${role}">${getRoleLabel(role)}</span>
                        </div>
                        <div class="rating-entry-speed">#${String(rank).padStart(2, '0')} ${formatRatingDelay(entry.rating_delay_seconds)}</div>
                    </td>
                    <td class="rating-entry-date">${formatRatingDate(entry.rated_at)}</td>
                    <td class="rating-entry-score">${scoreText}</td>
                </tr>
            `;
        }).join('');

        return `
            <div class="rating-entries-panel">
                <button class="rating-entries-toggle" type="button" aria-expanded="false" aria-controls="${panelId}">
                    <span>Оценившие</span>
                    <strong>${visibleCount}</strong>
                    <svg class="rating-entries-chevron" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 4.5L6 7.5L9 4.5"/></svg>
                </button>
                <div id="${panelId}" class="rating-entries-body" aria-hidden="true">
                    <div class="rating-entries-inner">
                        ${entries.length ? `
                            <div class="rating-entries-scroll">
                                <table class="rating-entries-table">
                                    <tbody>${rows}</tbody>
                                </table>
                            </div>
                        ` : '<div class="rating-entries-empty">Пока нет оценок</div>'}
                    </div>
                </div>
            </div>
        `;
    }

    function renderSvgBlock(result, isFirst) {
        if (!result.svg_content) return '';
        const modelSlug = (result.models ? result.models.name : 'model').replace(/[^a-zA-Z0-9]/g, '_');
        const entriesPanel = renderRatingEntriesPanel(result);
        const firstClass = isFirst ? ' svg-viewer-box--first' : '';
        return `
            <div class="svg-score-preview">
                <div class="svg-viewer-box border border-border overflow-hidden${firstClass}"></div>
                <div class="svg-tools-row">
                    <button class="svg-download-btn text-[9px] uppercase tracking-widest border border-white/15 px-2 py-1.5 bg-white/5 hover:bg-white/10 transition-colors flex items-center gap-1.5 cursor-pointer"
                        data-model-slug="${escapeHtml(modelSlug)}">
                        <svg class="w-2.5 h-2.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/></svg>
                        SVG
                    </button>
                    ${entriesPanel}
                </div>
            </div>
        `;
    }

    function parseDate(dateVal) {
        if (!dateVal) return 0;
        if (typeof dateVal === 'string') {
            const iso = dateVal.match(/^(\d{4})-(\d{2})-(\d{2})/);
            if (iso) return new Date(parseInt(iso[1]), parseInt(iso[2]) - 1, parseInt(iso[3])).getTime();
        }
        const d = new Date(dateVal);
        return isNaN(d.getTime()) ? 0 : d.getTime();
    }

    function formatDateDisplay(dateVal) {
        if (!dateVal) return '—';
        if (typeof dateVal === 'string') {
            const parts = dateVal.split('-');
            if (parts.length === 3) return `${parts[2]}.${parts[1]}.${parts[0]}`;
        }
        const d = new Date(dateVal);
        const day = String(d.getDate()).padStart(2, '0');
        const month = String(d.getMonth() + 1).padStart(2, '0');
        return `${day}.${month}.${d.getFullYear()}`;
    }

    function sanitizeSvg(svgStr) {
        const safeEmptySvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1" aria-hidden="true"></svg>';
        let clean = String(svgStr || '')
            .replace(/<\?xml[^?]*\?>/gi, '')
            .replace(/<!DOCTYPE[^>]*>/gi, '')
            .replace(/\s+xmlns\s*=\s*["']/g, ' xmlns="')
            .replace(/<svg(?![^>]*xmlns)/, '<svg xmlns="http://www.w3.org/2000/svg"');
        if (typeof DOMPurify !== 'undefined') {
            const sanitized = DOMPurify.sanitize(clean, {
                USE_PROFILES: { svg: true },
                FORBID_TAGS: ['script', 'style', 'foreignObject', 'iframe', 'object', 'embed', 'link', 'meta']
            });
            return stripUnsafeSvgReferences(sanitized) || safeEmptySvg;
        }
        return safeEmptySvg;
    }

    function getCachedSanitizedSvg(result) {
        const source = String(result?.svg_content || '');
        const key = result?.id == null ? source : String(result.id);
        const cached = svgSanitizeCache.get(key);
        if (cached && cached.source === source) {
            svgSanitizeCache.delete(key);
            svgSanitizeCache.set(key, cached);
            return cached.safeSvg;
        }
        const safeSvg = sanitizeSvg(source);
        svgSanitizeCache.set(key, { source, safeSvg });
        while (svgSanitizeCache.size > SVG_SANITIZE_CACHE_LIMIT) {
            svgSanitizeCache.delete(svgSanitizeCache.keys().next().value);
        }
        return safeSvg;
    }

    function stripUnsafeSvgReferences(svgStr) {
        try {
            const doc = new DOMParser().parseFromString(svgStr, 'image/svg+xml');
            if (doc.querySelector('parsererror') || !doc.documentElement || doc.documentElement.tagName.toLowerCase() !== 'svg') {
                return '';
            }

            doc.querySelectorAll('script, style, foreignObject, iframe, object, embed, link, meta').forEach(el => el.remove());
            doc.querySelectorAll('*').forEach(el => {
                Array.from(el.attributes).forEach(attr => {
                    const name = attr.name.toLowerCase();
                    const value = attr.value.trim();
                    if (name.startsWith('on')) {
                        el.removeAttribute(attr.name);
                        return;
                    }
                    if ((name === 'href' || name === 'xlink:href' || name.endsWith(':href') || name === 'src') && value && !value.startsWith('#')) {
                        el.removeAttribute(attr.name);
                        return;
                    }
                    if (name === 'style') {
                        el.removeAttribute(attr.name);
                        return;
                    }
                    if (/url\s*\(|@import/i.test(value)) {
                        el.removeAttribute(attr.name);
                    }
                });
            });

            return new XMLSerializer().serializeToString(doc.documentElement);
        } catch (e) {
            return '';
        }
    }

    function svgNeedsLightPreview(svgStr, previewHost) {
        let probe = null;
        try {
            probe = document.createElement('div');
            probe.style.cssText = 'position:fixed;left:-9999px;top:-9999px;width:1px;height:1px;visibility:hidden;pointer-events:none;';
            if (previewHost) probe.style.color = getComputedStyle(previewHost).color;
            document.body.appendChild(probe);

            const shadow = probe.attachShadow({ mode: 'closed' });
            const root = document.createElement('div');
            root.innerHTML = svgStr;
            shadow.appendChild(root);

            const paintedElements = root.querySelectorAll('path, circle, ellipse, rect, polygon, polyline, line, text');
            const needsLight = Array.from(paintedElements).some(el => {
                const tagName = el.tagName.toLowerCase();
                const styles = getComputedStyle(el);
                const fillCanPaint = tagName !== 'line' && tagName !== 'polyline';
                return (fillCanPaint && isDarkSvgPaint(styles.fill, styles.fillOpacity)) ||
                    isDarkSvgPaint(styles.stroke, styles.strokeOpacity);
            });
            return needsLight;
        } catch (e) {
            return false;
        } finally {
            if (probe) probe.remove();
        }
    }

    function scheduleIdleTask(fn) {
        if ('requestIdleCallback' in window) {
            window.requestIdleCallback(fn, { timeout: 1800 });
        } else {
            setTimeout(fn, 0);
        }
    }

    function enqueueSvgPreviewTask(task) {
        svgPreviewQueue.push(task);
        processSvgPreviewQueue();
    }

    function processSvgPreviewQueue() {
        if (svgPreviewQueueRunning || svgPreviewQueue.length === 0) return;
        svgPreviewQueueRunning = true;
        const task = svgPreviewQueue.shift();
        scheduleIdleTask(() => {
            task();
            svgPreviewQueueRunning = false;
            processSvgPreviewQueue();
        });
    }

    function queueSvgPreviewMount(svgBox, mount) {
        svgBox._mountSvgPreview = mount;
        if ('IntersectionObserver' in window) {
            if (!svgPreviewObserver) {
                svgPreviewObserver = new IntersectionObserver((entries) => {
                    entries.forEach(entry => {
                        if (!entry.isIntersecting) return;
                        const target = entry.target;
                        svgPreviewObserver.unobserve(target);
                        const mountPreview = target._mountSvgPreview;
                        if (mountPreview) enqueueSvgPreviewTask(mountPreview);
                    });
                }, { rootMargin: '1200px 0px', threshold: 0.01 });
            }
            svgPreviewObserver.observe(svgBox);
        } else {
            enqueueSvgPreviewTask(mount);
        }
    }

    function isDarkSvgPaint(value, opacityValue) {
        if (!value || value === 'none' || value === 'transparent') return false;
        const paintOpacity = opacityValue === undefined ? 1 : parseFloat(opacityValue);
        if (Number.isFinite(paintOpacity) && paintOpacity <= 0.05) return false;

        const match = value.match(/rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)/i);
        if (!match) return /^(?:black|#000|#000000|#111|#111111|#222|#222222|#333|#333333)$/i.test(value.trim());

        const alpha = match[4] === undefined ? 1 : parseFloat(match[4]);
        if (alpha <= 0.05) return false;
        const r = parseFloat(match[1]);
        const g = parseFloat(match[2]);
        const b = parseFloat(match[3]);
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 80;
    }

    function getParamLabel(result) {
        const rpvs = result.result_param_values || [];
        if (rpvs.length === 0) return '';
        return rpvs.map(rpv => {
            const mpv = rpv.model_param_values;
            if (!mpv) return '';
            const mp = mpv.model_params;
            return mp ? `${mp.name}: ${mpv.value}` : mpv.value;
        }).filter(Boolean).join(' + ');
    }

    function updateTitleCounter() {
        const titleEl = document.getElementById('leaderboard-title');
        if (titleEl) titleEl.textContent = 'Лидерборд';
        document.querySelectorAll('#prompt-filters .top-filter-btn').forEach(btn => {
            const base = btn.getAttribute('data-base-label') || btn.textContent.replace(/\s*\d+\/\d+$/, '');
            btn.setAttribute('data-base-label', base);
            btn.textContent = base;
        });
    }

    function runCardDecode(card) {
        if (!card || !card.isConnected || card._decoded) return;
        card._decoded = true;
        const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        const nameEl = card.querySelector('.model-name-decode');
        if (nameEl && !nameEl._decoded) {
            nameEl._decoded = true;
            if (reduceMotion) nameEl.textContent = nameEl.dataset.name || nameEl.textContent;
            else requestAnimationFrame(() => hackerDecode(nameEl, nameEl.dataset.name));
        }
        card.querySelectorAll('.criteria-decode').forEach(el => {
            if (el._decoded) return;
            el._decoded = true;
            if (reduceMotion) el.textContent = el.dataset.name || el.textContent;
            else requestAnimationFrame(() => hackerDecodeShort(el, el.dataset.name));
        });
        card.querySelectorAll('.score-decode').forEach(el => {
            if (el._decoded) return;
            el._decoded = true;
            if (reduceMotion) el.textContent = el.dataset.name || el.textContent;
            else requestAnimationFrame(() => hackerDecodeScore(el, el.dataset.name));
        });
    }

    function queueCardDecode(card) {
        if ('IntersectionObserver' in window) {
            if (!decodeObserver) {
                decodeObserver = new IntersectionObserver((entries) => {
                    entries.forEach(entry => {
                        if (!entry.isIntersecting) return;
                        decodeObserver.unobserve(entry.target);
                        runCardDecode(entry.target);
                    });
                }, { rootMargin: '320px 0px', threshold: 0.01 });
            }
            decodeObserver.observe(card);
        } else {
            requestAnimationFrame(() => runCardDecode(card));
        }
    }

    function renderBenchmarkList() {
        const listContainer = document.getElementById('benchmark-list');
        pendingTimeouts.forEach(t => { if (t && t._raf) cancelAnimationFrame(t.id); else clearTimeout(t); });
        pendingTimeouts = [];
        if (decodeObserver) decodeObserver.disconnect();
        if (svgPreviewObserver) svgPreviewObserver.disconnect();
        svgPreviewQueue = [];
        svgPreviewQueueRunning = false;
        if (scoreAnimRaf) {
            cancelAnimationFrame(scoreAnimRaf);
            scoreAnimRaf = 0;
        }
        scoreAnimQueue.length = 0;
        listContainer.innerHTML = '';

        updateTitleCounter();

        let displayResults = [...resultsData];

        if (currentSort === 'date') {
            displayResults.sort((a, b) => parseDate(b.test_date) - parseDate(a.test_date));
        } else {
            displayResults.sort((a, b) => getScoreMeta(b).combined - getScoreMeta(a).combined);
        }

        if (searchQuery) {
            const q = searchQuery.toLowerCase();
            displayResults = displayResults.filter(r => {
                const modelName = r.models ? r.models.name : '';
                return modelName.toLowerCase().includes(q) ||
                    (r.author && r.author.toLowerCase().includes(q));
            });
        }

        if (currentTop !== 'all') displayResults = displayResults.slice(0, parseInt(currentTop));

        hideNoResults();
        if (displayResults.length === 0 && resultsData.length > 0) { showNoResults(); return; }

        displayResults.forEach((result, idx) => {
            const modelName = result.models ? result.models.name : '—';
            const spaceName = result.model_spaces ? result.model_spaces.name : '';
            const paramLabel = getParamLabel(result);
            const authorLine = result.author ? `<span class="text-[10px] text-gray-500 font-mono">by ${escapeHtml(result.author)}</span>` : '';
            const rank = idx + 1;
            const rankDisplay = String(rank).padStart(2, '0');
            const isTopRank = rank === 1;
            const isSecondRank = rank === 2;
            const podiumTone = isTopRank ? 'gold' : isSecondRank ? 'silver' : '';
            const podiumCardClass = podiumTone ? ` podium-card podium-${podiumTone}-card` : '';
            const rankClass = podiumTone ? `podium-rank podium-${podiumTone}-text` : 'text-white/30 group-hover:text-white/50';
            const rankPrefix = isTopRank ? '<span class="top-rank-crown">♛</span>' : '';
            const nameClass = podiumTone ? ` podium-name podium-${podiumTone}-text` : '';
            const spaceLabelClass = podiumTone ? `podium-meta podium-${podiumTone}-meta` : 'text-gray-300';
            const paramLabelClass = podiumTone ? `podium-param podium-${podiumTone}-param` : 'text-purple-400/60';

            let labelsHtml = '';
            if (spaceName) {
                labelsHtml += `<span class="text-[12px] font-bold tracking-[0.15em] ${spaceLabelClass} uppercase">${escapeHtml(spaceName)}</span>`;
            }
            if (paramLabel) {
                labelsHtml += ` <span class="text-[10px] ${paramLabelClass} font-mono">${escapeHtml(paramLabel)}</span>`;
            }

            const scoresHtml = renderBars(result);
            const svgBlock = renderSvgBlock(result, isTopRank);
            const dateStr = formatDateDisplay(result.test_date);
            const scoreMeta = getScoreMeta(result);
            const scoreSplitHtml = renderScoreSplit(result, scoreMeta);
            const ratingFormHtml = renderRatingForm(result, scoreMeta);
            const formulaId = `formula-popover-${result.id}`;

            const card = document.createElement('div');
            card.className = `matte-card p-4 sm:p-8 border border-border hover:border-white/50 transition-colors duration-300 flex flex-col bg-surface benchmark-card group${podiumCardClass}`;
            card.dataset.animDelay = String(Math.min(idx, 4) * 90);

            card.innerHTML = `
                <div class="flex flex-col lg:flex-row gap-0 items-stretch lg:items-start">
                    <div class="benchmark-card-side w-full lg:w-[34%] flex flex-col justify-center lg:justify-start text-center lg:text-left border-b lg:border-b-0 pb-4 sm:pb-6 lg:pb-0 pr-0 lg:pr-6 lg:pt-2 relative lg:self-start">
                        <span class="text-[10px] font-mono ${rankClass} transition-colors tracking-widest mb-1">${rankPrefix}#${rankDisplay}</span>
                        <h3 class="font-title text-xl sm:text-2xl lg:text-3xl uppercase tracking-wider text-[#F2F2F2] mb-2 group-hover:text-white transition-colors model-name-decode${nameClass}" data-name="${escapeHtml(modelName)}">${escapeHtml(modelName)}</h3>
                        <span class="text-[10px] uppercase font-mono text-gray-400 tracking-widest">${dateStr}</span>
                        <div class="mt-2">${labelsHtml} ${authorLine}</div>
                        ${ratingFormHtml || renderRateCta(result.id, true)}
                    </div>
                    <div class="w-full lg:flex-1 flex flex-col md:flex-row items-center md:items-start justify-between mt-4 sm:mt-6 lg:mt-0 lg:pl-10 group/bracket">
                        <div class="benchmark-scores-bracket-wrap">
                            <div class="flex-grow flex flex-col gap-y-4 sm:gap-y-5 w-full scores-container justify-center">
                                ${scoresHtml}
                            </div>
                            <svg preserveAspectRatio="none" viewBox="0 0 36 100" class="score-bracket hidden md:block text-white/40 stroke-current transition-colors duration-500 group-hover/bracket:text-white/80" fill="none">
                                <path d="M 2 1 C 18 1 18 8 18 20 L 18 42 C 18 48 18 49 34 50 C 18 51 18 52 18 58 L 18 80 C 18 92 18 99 2 99" stroke-width="1" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round"/>
                            </svg>
                        </div>
                        <div class="score-panel w-full md:w-80 lg:w-80 xl:w-80 flex-shrink-0 relative z-30 group/score text-center md:text-left mt-6 sm:mt-8 md:mt-0 md:pl-2 pr-0 md:pr-0 xl:pr-0">
                            <span class="text-[10px] sm:text-[12px] font-bold uppercase tracking-[0.2em] text-gray-400 block mb-2">Общий балл</span>
                            <div class="score-formula-wrap relative inline-flex items-center gap-3">
                                <span class="font-title text-[48px] sm:text-[64px] lg:text-[76px] leading-none text-[#F2F2F2] font-bold overall-score" data-raw="${scoreMeta.combined}">0</span>
                                <button class="formula-toggle opacity-0 group-hover/score:opacity-100" type="button" aria-label="Показать формулу" aria-expanded="false" aria-controls="${formulaId}">
                                    <svg class="formula-toggle-icon" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="1" width="12" height="12" rx="3"/><path d="M4.5 7h5M7 4.5v5" class="formula-toggle-plus"/><path d="M4.5 7h5" class="formula-toggle-minus" style="display:none"/></svg>
                                </button>
                                <div id="${formulaId}" class="formula-popover" aria-hidden="true">
                                    <div class="formula-popover-title" data-scramble="Формулы">Формулы</div>
                                    <div class="formula-popover-row"><span class="formula-popover-label" data-scramble="Overall">Overall</span><span class="formula-popover-val" data-scramble="(admin + user avg) / 2">(admin + user avg) / 2</span></div>
                                    <div class="formula-popover-row"><span class="formula-popover-label" data-scramble="Score">Score</span><span class="formula-popover-val" data-scramble="5 критериев × (1–10), сумма × 1.8">5 критериев × (1–10), сумма × 1.8</span></div>
                                </div>
                            </div>
                            ${scoreSplitHtml}
                            ${svgBlock}
                        </div>
                    </div>
                </div>
            `;

            if (result.svg_content) {
                const svgBox = card.querySelector('.svg-viewer-box');
                let sanitized = null;
                const getSanitizedSvg = () => {
                    if (sanitized == null) sanitized = getCachedSanitizedSvg(result);
                    return sanitized;
                };
                if (svgBox) {
                    svgBox.classList.remove('svg-light-preview');
                    svgBox.classList.add('is-svg-pending');
                    svgBox.style.display = 'flex';
                    svgBox.style.alignItems = 'center';
                    svgBox.style.justifyContent = 'center';
                    svgBox.style.cursor = 'pointer';
                    svgBox.setAttribute('role', 'button');
                    svgBox.setAttribute('tabindex', '0');
                    svgBox.setAttribute('aria-label', 'Открыть SVG preview');
                    const openPreview = () => {
                        const safeSvg = getSanitizedSvg();
                        const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>SVG Preview</title><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#0a0a0a;display:flex;align-items:center;justify-content:center;min-height:100vh}svg{max-width:95vw;max-height:95vh;width:auto;height:auto}</style></head><body>${safeSvg}</body></html>`;
                        const blob = new Blob([html], { type: 'text/html' });
                        const url = URL.createObjectURL(blob);
                        const previewWindow = window.open(url, '_blank', 'noopener,noreferrer');
                        if (previewWindow) previewWindow.opener = null;
                        setTimeout(() => URL.revokeObjectURL(url), 1000);
                    };
                    const mountSvgPreview = () => {
                        if (svgBox._svgMounted || !svgBox.isConnected) return;
                        const safeSvg = getSanitizedSvg();
                        const shadow = svgBox.attachShadow({ mode: 'open' });
                        const style = document.createElement('style');
                        style.textContent = ':host{display:flex;align-items:center;justify-content:center;width:100%;height:100%;font-family:initial;background:transparent}.svg-preview-root{display:flex;align-items:center;justify-content:center;width:100%;height:100%;padding:12px;filter:drop-shadow(0 0 1px rgba(255,255,255,.55)) drop-shadow(0 0 8px rgba(255,255,255,.08))}.svg-preview-root svg{max-width:100%;max-height:100%;width:auto;height:auto;background:transparent}';
                        const root = document.createElement('div');
                        root.className = 'svg-preview-root';
                        root.innerHTML = safeSvg;
                        shadow.appendChild(style);
                        shadow.appendChild(root);
                        svgBox.classList.remove('is-svg-pending');
                        svgBox._svgMounted = true;
                    };
                    svgBox.addEventListener('click', openPreview);
                    svgBox.addEventListener('keydown', (e) => {
                        if (e.key !== 'Enter' && e.key !== ' ') return;
                        e.preventDefault();
                        openPreview();
                    });
                    queueSvgPreviewMount(svgBox, mountSvgPreview);
                }
                const downloadBtn = card.querySelector('.svg-download-btn');
                if (downloadBtn) {
                    downloadBtn.addEventListener('click', (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        const slug = downloadBtn.getAttribute('data-model-slug');
                        const blob = new Blob([getSanitizedSvg()], { type: 'image/svg+xml' });
                        const url = URL.createObjectURL(blob);
                        const a = document.createElement('a');
                        a.href = url; a.download = slug + '.svg';
                        document.body.appendChild(a); a.click(); document.body.removeChild(a);
                        URL.revokeObjectURL(url);
                    });
                }
            }

            listContainer.appendChild(card);

            queueCardDecode(card);
        });

        if (barObserver) barObserver.disconnect();
        barObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.querySelectorAll('.hatching-fill').forEach(bar => { bar.style.width = bar.getAttribute('data-target'); });
                    const scoreEl = entry.target.querySelector('.overall-score');
                    if (scoreEl && !scoreEl._counted) {
                        scoreEl._counted = true;
                        countUpScore(scoreEl, parseFloat(scoreEl.dataset.raw) || 0);
                    }
                    entry.target.querySelectorAll('.score-pill-value').forEach(pill => {
                        if (pill._counted) return;
                        const raw = pill.dataset.raw;
                        if (raw === '' || raw === undefined) { pill.textContent = '—'; return; }
                        pill._counted = true;
                        countUpScore(pill, parseFloat(raw) || 0);
                    });
                    barObserver.unobserve(entry.target);
                }
            });
        }, { rootMargin: '200px 0px', threshold: 0.01 });
        document.querySelectorAll('.benchmark-card').forEach(card => barObserver.observe(card));
        attachRatingHandlers();
        startAutoRefresh();
        document.querySelectorAll('.rating-entries-toggle').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const panel = btn.closest('.rating-entries-panel');
                const body = panel?.querySelector('.rating-entries-body');
                if (!panel || !body) return;
                document.querySelectorAll('.rating-entries-panel.open').forEach(other => {
                    if (other === panel) return;
                    closeRatingEntriesPanel(other);
                });
                document.querySelectorAll('.formula-popover.open').forEach(p => closeFormulaPanel(p));
                const isOpen = panel.classList.toggle('open');
                btn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
                body.setAttribute('aria-hidden', isOpen ? 'false' : 'true');
            });
        });
        document.querySelectorAll('.formula-toggle').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const popover = btn.parentElement.querySelector('.formula-popover');
                if (!popover) return;
                const wrap = btn.closest('.score-formula-wrap');
                const scorePanel = btn.closest('.score-panel');
                const plus = btn.querySelector('.formula-toggle-plus');
                const minus = btn.querySelector('.formula-toggle-minus');
                document.querySelectorAll('.formula-popover.open').forEach(p => {
                    if (p === popover) return;
                    closeFormulaPanel(p);
                });
                document.querySelectorAll('.rating-entries-panel.open').forEach(panel => closeRatingEntriesPanel(panel));
                const isOpen = popover.classList.toggle('open');
                popover.setAttribute('aria-hidden', isOpen ? 'false' : 'true');
                wrap?.classList.toggle('formula-open', isOpen);
                scorePanel?.classList.toggle('formula-open', isOpen);
                if (plus) plus.style.display = isOpen ? 'none' : '';
                if (minus) minus.style.display = isOpen ? '' : 'none';
                btn.classList.toggle('active', isOpen);
                btn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
                const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
                if (isOpen && !reduceMotion) {
                    popover.querySelectorAll('[data-scramble]').forEach((el, i) => {
                        const target = el.dataset.scramble;
                        setTimeout(() => scrambleText(el, target, 350), i * 60);
                    });
                }
            });
        });
        if (!document._nbFormulaCloseBound) {
            document._nbFormulaCloseBound = true;
            document.addEventListener('click', (e) => {
                if (!e.target.closest('.formula-popover') && !e.target.closest('.formula-toggle')) {
                    document.querySelectorAll('.formula-popover.open').forEach(p => {
                        closeFormulaPanel(p);
                    });
                }
                if (!e.target.closest('.rating-entries-panel')) {
                    document.querySelectorAll('.rating-entries-panel.open').forEach(panel => {
                        closeRatingEntriesPanel(panel);
                    });
                }
            });
            document.addEventListener('keydown', (e) => {
                if (e.key !== 'Escape') return;
                document.querySelectorAll('.formula-popover.open').forEach(p => {
                    closeFormulaPanel(p, true);
                });
                document.querySelectorAll('.rating-entries-panel.open').forEach(panel => {
                    closeRatingEntriesPanel(panel, true);
                });
            });
        }
    }

    function closeRatingEntriesPanel(panel, returnFocus = false) {
        panel.classList.remove('open');
        const btn = panel.querySelector('.rating-entries-toggle');
        const body = panel.querySelector('.rating-entries-body');
        btn?.setAttribute('aria-expanded', 'false');
        body?.setAttribute('aria-hidden', 'true');
        if (returnFocus) btn?.focus({ preventScroll: true });
    }

    function closeFormulaPanel(popover, returnFocus = false) {
        popover.classList.remove('open');
        popover.setAttribute('aria-hidden', 'true');
        popover.closest('.score-formula-wrap')?.classList.remove('formula-open');
        popover.closest('.score-panel')?.classList.remove('formula-open');
        const btn = popover.parentElement.querySelector('.formula-toggle');
        if (!btn) return;
        btn.classList.remove('active');
        btn.setAttribute('aria-expanded', 'false');
        const plus = btn.querySelector('.formula-toggle-plus');
        const minus = btn.querySelector('.formula-toggle-minus');
        if (plus) plus.style.display = '';
        if (minus) minus.style.display = 'none';
        if (returnFocus) btn.focus({ preventScroll: true });
    }

    function parseRatingValue(value) {
        const normalized = String(value || '').trim().replace(',', '.');
        if (!/^(?:10(?:\.0)?|[1-9](?:\.\d)?)$/.test(normalized)) return null;
        const parsed = Number(normalized);
        if (!Number.isFinite(parsed) || parsed < 1 || parsed > 10) return null;
        return Math.round(parsed * 10) / 10;
    }

    function showToast(msg) {
        let t = document.getElementById('nb-toast');
        if (!t) {
            t = document.createElement('div');
            t.id = 'nb-toast';
            t.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);padding:10px 20px;border-radius:8px;background:rgba(68,144,255,0.18);border:1px solid rgba(68,144,255,0.4);color:rgba(255,255,255,0.85);font:8px/1.4 "Geist Mono",monospace;letter-spacing:0.1em;text-transform:uppercase;z-index:9999;opacity:0;transition:opacity .3s;pointer-events:none;';
            document.body.appendChild(t);
        }
        t.textContent = msg;
        t.style.opacity = '1';
        clearTimeout(t._tid);
        t._tid = setTimeout(() => { t.style.opacity = '0'; }, 2400);
    }

    function attachRatingHandlers() {
        document.querySelectorAll('.benchmark-rate-form').forEach(bindRatingForm);
        document.querySelectorAll('.benchmark-rate-cta').forEach(cta => {
            if (cta._bound) return;
            cta._bound = true;
            bindRateCtaHover(cta);
            cta.addEventListener('click', () => {
                if (cta.dataset.requiresAuth === 'true') {
                    showToast('Войдите, чтобы оценить');
                    return;
                }
                const resultId = Number(cta.dataset.resultId);
                const result = resultsData.find(r => Number(r.id) === resultId);
                if (!result) return;
                const meta = getScoreMeta(result);
                const wrap = cta.closest('.benchmark-left-rating');
                if (!wrap) return;
                const tempMeta = { ...meta, myScore: null, myUpdateCount: 0 };
                wrap.outerHTML = renderRatingForm(result, tempMeta, true);
                const nextForm = document.querySelector(`.benchmark-rate-form[data-result-id="${resultId}"]`);
                if (nextForm) bindRatingForm(nextForm);
                const card = nextForm?.closest('.benchmark-card');
                if (card) {
                    card.querySelectorAll('.criteria-decode').forEach(el => {
                        if (el._decoded) return;
                        el._decoded = true;
                        hackerDecodeShort(el, el.dataset.name);
                    });
                }
            });
        });
    }

    function bindRateCtaHover(cta) {
        const glyphs = 'АВГДЕЖЗИКЛМНОПРСТУХЦ0123456789';
        cta.querySelectorAll('.rate-cta-char').forEach(charEl => {
            if (charEl._hoverBound) return;
            charEl._hoverBound = true;
            charEl.addEventListener('mouseenter', () => {
                clearInterval(charEl._scrambleTid);
                charEl.classList.add('is-scrambling');
                charEl._scrambleTid = setInterval(() => {
                    charEl.textContent = glyphs[Math.floor(Math.random() * glyphs.length)];
                }, 48);
            });
            charEl.addEventListener('mouseleave', () => {
                clearInterval(charEl._scrambleTid);
                charEl._scrambleTid = null;
                charEl.classList.remove('is-scrambling');
                charEl.textContent = charEl.dataset.char || '';
            });
        });
    }

    function bindRatingForm(form) {
        if (form._bound) return;
        form._bound = true;
        form.querySelectorAll('.benchmark-rating-mini-field input').forEach(input => {
            input.addEventListener('input', () => {
                const field = input.closest('.benchmark-rating-mini-field');
                const val = Math.max(1, Math.min(10, parseFloat(String(input.value).replace(',', '.')) || 0));
                if (field) field.style.setProperty('--rating-pct', `${(val / MAX_PER) * 100}%`);
            });
        });
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            e.stopPropagation();
            const btn = form.querySelector('.benchmark-rate-submit');
            if (!btn) return;
            btn.disabled = true;
            try {
                const fd = new FormData(form);
                const values = {
                    s_visual: parseRatingValue(fd.get('s_visual')),
                    s_animation: parseRatingValue(fd.get('s_animation')),
                    s_creative: parseRatingValue(fd.get('s_creative')),
                    s_code: parseRatingValue(fd.get('s_code')),
                    s_detail: parseRatingValue(fd.get('s_detail'))
                };
                if (Object.values(values).some(v => v == null)) {
                    showToast('Оценка: 1-10, шаг 0.1');
                    btn.disabled = false;
                    return;
                }
                const resultId = Number(form.dataset.resultId);
                const data = await Api.rateResult(resultId, values);
                const updatedStat = Array.isArray(data) ? data[0] : data;
                const existing = ratingStats.get(resultId) || {};
                const myScore = Math.round((values.s_visual + values.s_animation + values.s_creative + values.s_code + values.s_detail) * 18) / 10;
                const fallbackUpdateCount = existing.my_score == null ? 0 : Math.min(2, Number(existing.my_update_count || 0) + 1);
                ratingStats.set(resultId, {
                    ...existing,
                    ...(updatedStat || {}),
                    avg_score: updatedStat?.avg_score ?? existing.avg_score ?? myScore,
                    rating_count: updatedStat?.rating_count ?? existing.rating_count ?? 1,
                    my_score: updatedStat?.my_score ?? myScore,
                    my_s_visual: updatedStat?.my_s_visual ?? values.s_visual,
                    my_s_animation: updatedStat?.my_s_animation ?? values.s_animation,
                    my_s_creative: updatedStat?.my_s_creative ?? values.s_creative,
                    my_s_code: updatedStat?.my_s_code ?? values.s_code,
                    my_s_detail: updatedStat?.my_s_detail ?? values.s_detail,
                    my_update_count: updatedStat?.my_update_count ?? fallbackUpdateCount
                });
                const result = resultsData.find(r => Number(r.id) === resultId);
                const card = form.closest('.benchmark-card');
                if (result && card) updateRatingUi(card, result);
                else btn.disabled = false;
            } catch (err) {
                if (Api.isDevSession && Api.isDevSession()) {
                    showToast(err && /limit/i.test(err.message || '') ? 'Лимит обновлений исчерпан' : 'Оценка сохранена локально (dev-режим)');
                } else {
                    alert(err?.message || 'Войдите, чтобы оценивать результаты');
                }
                btn.disabled = false;
            }
        });
    }

    function updateRatingUi(card, result) {
        const meta = getScoreMeta(result);

        // 1. Replace score split HTML first (so new DOM is ready)
        const splitWrap = card.querySelector('.benchmark-score-split');
        if (splitWrap) {
            splitWrap.outerHTML = renderScoreSplit(result, meta);
        }

        // 2. Animate overall score
        const scoreEl = card.querySelector('.overall-score');
        if (scoreEl) {
            scoreEl.dataset.raw = String(meta.combined);
            scoreEl.classList.remove('score-refresh');
            void scoreEl.offsetWidth;
            scoreEl.classList.add('score-refresh');
            countUpScore(scoreEl, meta.combined);
            setTimeout(() => scoreEl.classList.remove('score-refresh'), 700);
        }

        // 3. Animate admin pill (starts at "0" in new HTML)
        const adminPill = card.querySelector('.benchmark-score-admin .score-pill-value');
        if (adminPill) {
            countUpScore(adminPill, meta.adminScore);
        }

        // 4. Animate user pill
        const userPill = card.querySelector('.benchmark-score-user .score-pill-value');
        if (userPill) {
            if (meta.userScore == null) userPill.textContent = '—';
            else countUpScore(userPill, meta.userScore);
        }

        // 5. Animate mine pill
        const minePill = card.querySelector('.benchmark-score-mine .score-pill-value');
        if (minePill) {
            if (meta.myScore == null) minePill.textContent = '—';
            else countUpScore(minePill, meta.myScore);
        }

        // 6. Replace rating form
        const ratingWrap = card.querySelector('.benchmark-left-rating');
        if (ratingWrap) {
            ratingWrap.outerHTML = renderRatingForm(result, meta);
            const nextForm = card.querySelector('.benchmark-rate-form');
            if (nextForm) bindRatingForm(nextForm);
        }
    }

    // hackerDecodeClassic removed — dead code, was never called

    function hackerDecodeShort(el, target) {
        if (!el || !el.isConnected) return;
        target = String(target || '');
        const glyphs = 'АВГДЕЖЗИКЛМНОПРСТУХЦ0123456789';
        const len = target.length;
        el.textContent = target;
        const h = el.offsetHeight;
        el.style.height = h + 'px';
        el.style.overflow = 'hidden';
        el.classList.add('decoding');
        const rg = () => glyphs[Math.floor(Math.random() * glyphs.length)];
        const dur = 600;
        const t0 = performance.now();
        const frozen = new Uint8Array(len);
        function step(now) {
            if (!el.isConnected) return;
            const dt = now - t0;
            const t = Math.min(dt / dur, 1);
            let out = '';
            for (let i = 0; i < len; i++) {
                if (t >= 1 || frozen[i]) { out += target[i]; frozen[i] = 1; }
                else if (Math.random() < t * t) { out += target[i]; frozen[i] = 1; }
                else out += rg();
            }
            el.textContent = out;
            if (t < 1) requestAnimationFrame(step);
            else { el.textContent = target; el.style.height = ''; el.style.overflow = ''; }
        }
        requestAnimationFrame(step);
    }

    function hackerDecodeScore(el, target) {
        if (!el || !el.isConnected) return;
        target = String(target || '');
        const digits = '0123456789';
        const len = target.length;
        el.textContent = target;
        const h = el.offsetHeight;
        el.style.height = h + 'px';
        el.style.overflow = 'hidden';
        el.classList.add('decoding');
        const rg = () => digits[Math.floor(Math.random() * digits.length)];
        const dur = 1800;
        const t0 = performance.now();
        const frozen = new Uint8Array(len);
        function step(now) {
            if (!el.isConnected) return;
            const dt = now - t0;
            const t = Math.min(dt / dur, 1);
            let out = '';
            for (let i = 0; i < len; i++) {
                const ch = target[i];
                if (ch === ' ' || ch === '/' || ch === '.') {
                    out += ch;
                    frozen[i] = 1;
                } else if (t >= 1 || frozen[i]) {
                    out += ch;
                    frozen[i] = 1;
                } else {
                    const sweep = Math.max(0, (t - i / len * 0.5) / 0.5);
                    if (sweep > 0.6 + Math.random() * 0.3) { out += ch; frozen[i] = 1; }
                    else out += rg();
                }
            }
            el.textContent = out;
            if (t < 1) requestAnimationFrame(step);
            else { el.textContent = target; el.style.height = ''; el.style.overflow = ''; }
        }
        requestAnimationFrame(step);
    }

    function hackerDecode(el, target) {
        if (!el || !el.isConnected) return;
        target = String(target || '');
        const glyphs = 'ABCDEFGHKNOPRSTUVXYZ023456789';
        const len = target.length;
        el.textContent = target;
        const h = el.offsetHeight;
        el.style.height = h + 'px';
        el.style.overflow = 'hidden';
        el.classList.add('decoding');
        const rg = () => glyphs[Math.floor(Math.random() * glyphs.length)];
        const keep = /[\s.\-]/;
        const dur = 2500;
        const t0 = performance.now();
        const frozen = new Uint8Array(len);
        const glyphState = Array.from({ length: len }, (_, i) => keep.test(target[i]) ? target[i] : rg());
        const glyphNext = Array.from({ length: len }, () => t0 + 90 + Math.random() * 120);
        const cs = getComputedStyle(el);
        glyphMetricsCtx.font = `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
        const glyphPools = Array.from({ length: len }, (_, i) => {
            if (keep.test(target[i])) return [target[i]];
            const cacheKey = `${glyphMetricsCtx.font}|${target[i]}`;
            if (glyphPoolCache.has(cacheKey)) return glyphPoolCache.get(cacheKey);
            const targetW = glyphMetricsCtx.measureText(target[i]).width;
            const pool = glyphs.split('')
                .map(g => ({ g, d: Math.abs(glyphMetricsCtx.measureText(g).width - targetW) }))
                .sort((a, b) => a.d - b.d)
                .slice(0, 5)
                .map(x => x.g);
            glyphPoolCache.set(cacheKey, pool);
            return pool;
        });
        glyphState.forEach((_, i) => {
            if (keep.test(target[i])) return;
            const pool = glyphPools[i];
            glyphState[i] = pool[Math.floor(Math.random() * pool.length)];
        });
        function noise(i, now) {
            if (now >= glyphNext[i]) {
                const pool = glyphPools[i];
                glyphState[i] = pool[Math.floor(Math.random() * pool.length)];
                glyphNext[i] = now + 100 + Math.random() * 120;
            }
            return glyphState[i];
        }
        function step(now) {
            if (!el.isConnected) return;
            const dt = now - t0;
            const t = Math.min(dt / dur, 1);
            let out = '';
            // Phase weights (smooth crossfade via wide overlapping ranges)
            const wHint = t < 0.15 ? 0 : t < 0.35 ? (t - 0.15) / 0.2 : t < 0.55 ? 1 : Math.max(0, 1 - (t - 0.55) / 0.2);
            const sweepT = Math.max(0, (t - 0.3) / 0.7);
            const sweepEased = 1 - Math.pow(1 - sweepT, 5);
            const sweepPos = sweepEased * (len + 5);
            for (let i = 0; i < len; i++) {
                if (keep.test(target[i])) { out += target[i]; continue; }
                if (frozen[i]) { out += target[i]; continue; }
                if (sweepT > 0 && i < sweepPos - 2) {
                    frozen[i] = 1;
                    out += target[i];
                } else if (sweepT > 0 && i < sweepPos + 6) {
                    const d = i - (sweepPos - 2);
                    const chance = Math.max(0, 1 - d / 8) * 0.35;
                    if (Math.random() < chance) { frozen[i] = 1; out += target[i]; }
                    else out += noise(i, now);
                } else {
                    out += noise(i, now);
                }
            }
            if (t >= 1) {
                el.textContent = target;
                el.style.height = '';
                el.style.overflow = '';
                return;
            }
            el.textContent = out;
            requestAnimationFrame(step);
        }
        requestAnimationFrame(step);
    }

    function countUpScore(el, target) {
        target = parseFiniteScore(target, null);
        if (target == null) {
            el.textContent = el.classList.contains('overall-score') ? '0' : '—';
            return;
        }
        target = Math.max(0, target);
        scoreAnimQueue.push({ el, target, start: 0, lastText: '' });
        scheduleScoreAnimTick();
    }

    const scoreAnimQueue = [];
    let scoreAnimRaf = 0;
    const SCORE_ANIM_DURATION = 1400;

    function scheduleScoreAnimTick() {
        if (scoreAnimRaf) return;
        scoreAnimRaf = requestAnimationFrame(tickScoreAnims);
    }

    function tickScoreAnims(now) {
        scoreAnimRaf = 0;
        if (scoreAnimQueue.length === 0) return;
        let alive = 0;
        for (let i = 0; i < scoreAnimQueue.length; i++) {
            const a = scoreAnimQueue[i];
            if (!a.start) { a.start = now; a.lastText = '0'; }
            const t = Math.min((now - a.start) / SCORE_ANIM_DURATION, 1);
            const eased = 1 - Math.pow(1 - t, 3);
            const current = eased * a.target;
            const hasDecimal = a.target % 1 !== 0;
            const text = t >= 1
                ? (hasDecimal ? a.target.toFixed(1) : String(Math.floor(a.target)))
                : (hasDecimal ? current.toFixed(1) : String(Math.floor(current)));
            if (text !== a.lastText) {
                a.el.textContent = text;
                a.lastText = text;
            }
            if (t < 1) { scoreAnimQueue[alive++] = a; }
        }
        scoreAnimQueue.length = alive;
        if (alive) scheduleScoreAnimTick();
    }

    return { load, setSearch(q) { searchQuery = q; renderBenchmarkList(); }, retry() { load(); } };
})();
