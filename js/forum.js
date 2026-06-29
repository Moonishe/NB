const ForumModule = (() => {



    const THREADS_PER_PAGE = 20;



    const POSTS_PER_PAGE = 25;







    let currentView = 'list';



    let currentThreadId = null;



    let currentCategory = null;



    let currentPage = 0;



    let postPage = 0;



    let categories = [];



    let userInfo = null;



    let threadData = null;



    let postsData = [];



    let postsTotal = 0;



    let threadsTotal = 0;



    let pendingTimeouts = [];



    let abortControllers = [];



    let renderSeq = 0;

    let resizeHandler = null;



    const profileCache = new Map();



    const usernameCache = new Map();


    // getProfileBasePath provided by profile-utils.js

    // getProfileHref provided by profile-utils.js

    let pollIntervalId = null;
    let lastThreadsCount = 0;
    let lastMessagesCount = 0;
    let pillState = { left: 0, width: 0 };






    function hackerDecodeNumber(el, target, duration) {
        if (!el || !el.isConnected) return;
        target = String(target || '');
        const digits = '0123456789';
        const len = target.length;
        const rg = () => digits[Math.floor(Math.random() * digits.length)];
        const dur = duration || 800;
        const t0 = performance.now();
        const frozen = new Uint8Array(len);
        function step(now) {
            if (!el.isConnected) return;
            const dt = now - t0;
            const t = Math.min(dt / dur, 1);
            let out = '';
            for (let i = 0; i < len; i++) {
                const ch = target[i];
                if (ch === ' ' || ch === '.' || ch === ',') {
                    out += ch; frozen[i] = 1;
                } else if (t >= 1 || frozen[i]) {
                    out += ch; frozen[i] = 1;
                } else {
                    const sweep = Math.max(0, (t - i / len * 0.4) / 0.6);
                    if (sweep > 0.5 + Math.random() * 0.4) { out += ch; frozen[i] = 1; }
                    else out += rg();
                }
            }
            el.textContent = out;
            if (t < 1) requestAnimationFrame(step);
            else el.textContent = target;
        }
        requestAnimationFrame(step);
    }


    const EMOJI_MAP = {
        like:    { icon: '\uD83D\uDC4D', label: '\u041D\u0440\u0430\u0432\u0438\u0442\u0441\u044F' },
        dislike: { icon: '\uD83D\uDC4E', label: '\u041D\u0435 \u043D\u0440\u0430\u0432\u0438\u0442\u0441\u044F' },
        fire:    { icon: '\uD83D\uDD25', label: '\u041E\u0433\u043E\u043D\u044C' },
        puke:    { icon: '\uD83E\uDD2E', label: '\u0424\u0443' },
        brain:   { icon: '\uD83E\uDDE0', label: '\u0423\u043C\u043D\u043E' },
        emotion: { icon: '\uD83D\uDE02', label: '\u0421\u043C\u0435\u0448\u043D\u043E' },
        admin_like: { icon: '\uD83D\uDC51', label: '\u041E\u0434\u043E\u0431\u0440\u0435\u043D\u0438\u0435 \u0430\u0434\u043C\u0438\u043D\u0430', adminOnly: true },
    };







    function escapeHtml(str) {



        if (!str) return '';



        const d = document.createElement('div');



        d.textContent = str;



        return d.innerHTML.replace(/"/g, '&quot;').replace(/'/g, '&#39;');



    }

    // sanitizeTelegramPhotoUrl provided by profile-utils.js







    function cleanText(str, maxLen) {



        if (!str) return '';



        let s = str.replace(/[\u0000-\u001F\u007F-\u009F\u00AD\u061C\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]/g, '');



        s = s.replace(/\s+/g, ' ').trim();



        if (maxLen && s.length > maxLen) s = s.slice(0, maxLen);



        return s;



    }







    function renderMarkdown(text) {



        if (!text) return '';



        let html = escapeHtml(text);



        html = html.replace(/&gt;\s(.+)/g, '<span class="forum-quote">$1</span>');



        html = html.replace(/```([\s\S]*?)```/g, '<pre class="forum-code-block"><code>$1</code></pre>');



        html = html.replace(/`([^`]+)`/g, '<code class="forum-inline-code">$1</code>');



        html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');



        html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');



        // @mentions — link to profile if resolved (skip inside <a>, <code>, <pre>)
        html = html.replace(/@([A-Za-z0-9_]{2,32})/g, (match, username) => {
            if (match.includes('</a>') || match.includes('<code') || match.includes('<pre')) return match;
            const uid = usernameCache.get(username.toLowerCase());
            if (uid) return `<a href="${escapeHtml(window.getProfileHref(uid))}" class="forum-mention">@${username}</a>`;
            return `<span class="forum-mention">@${username}</span>`;
        });

        // Links — match URLs but stop at @ mentions already wrapped in spans/anchors
        html = html.replace(/(https?:\/\/[^\s<@]+(?:@[^\s<]+)?)/g, '<a href="$1" target="_blank" rel="noopener noreferrer" class="forum-link">$1</a>');



        html = html.replace(/\n/g, '<br>');



        if (typeof DOMPurify !== 'undefined') {



            return DOMPurify.sanitize(html, { ADD_ATTR: ['target', 'rel', 'class'] });



        }



        return html;



    }







    function formatRelativeTime(dateVal) {



        if (!dateVal) return '';



        const d = new Date(dateVal);



        const now = new Date();



        const diff = Math.floor((now - d) / 1000);



        if (diff < 60) return 'только что';



        if (diff < 3600) return Math.floor(diff / 60) + ' мин. назад';



        if (diff < 86400) return Math.floor(diff / 3600) + ' ч. назад';



        if (diff < 2592000) return Math.floor(diff / 86400) + ' дн. назад';



        const day = String(d.getDate()).padStart(2, '0');



        const month = String(d.getMonth() + 1).padStart(2, '0');



        return `${day}.${month}.${d.getFullYear()}`;



    }







    function formatDate(dateVal) {



        if (!dateVal) return '';



        const d = new Date(dateVal);



        const day = String(d.getDate()).padStart(2, '0');



        const month = String(d.getMonth() + 1).padStart(2, '0');



        const h = String(d.getHours()).padStart(2, '0');



        const m = String(d.getMinutes()).padStart(2, '0');



        return `${day}.${month}.${d.getFullYear()} ${h}:${m}`;



    }







    function getRoleBadgeHtml(role) {



        if (!role || role === 'member') return '';



        const meta = { admin: 'ADMIN', stmoderator: 'ST.MOD', moderator: 'MOD', beta: 'BETA', alpha: 'ALPHA' };



        const label = meta[role];



        if (!label) return '';



        return `<span class="forum-role-badge forum-role-${role}">${label}</span>`;



    }







    function getUserDisplay(info) {



        const parts = [cleanText(info.author_first_name, 50), cleanText(info.author_last_name, 50)].filter(Boolean);



        const name = parts.length > 0 ? parts.join(' ') : (cleanText(info.author_username, 50) || 'Аноним');



        const photo = window.sanitizeTelegramPhotoUrl(info.author_photo_url);



        const modBadge = info.is_author_moderator ? '<span class="forum-mod-badge">MOD</span>' : '';



        const roleBadge = info.author_role ? getRoleBadgeHtml(info.author_role) : '';



        const uidBadge = info.author_uid != null ? `<span class="forum-uid-badge">UID #${info.author_uid}</span>` : '';



        const href = window.getProfileHref(info.author_uid, info.author_id);



        const safePhoto = photo ? escapeHtml(photo) : '';

        const avatarHtml = safePhoto



            ? `<a href="${href}"><img src="${safePhoto}" class="forum-avatar-sm" alt="" onerror="this.style.display='none'"></a>`



            : `<a href="${href}"><div class="forum-avatar-placeholder"></div></a>`;



        const profileLink = info.author_id



            ? `<a href="${href}" class="forum-username">${escapeHtml(name)}</a>`



            : `<span class="forum-username">${escapeHtml(name)}</span>`;



        return { name, photo: null, avatarHtml, modBadge, roleBadge, uidBadge, profileLink };



    }







    function canPost() {



        return userInfo && userInfo.is_verified && !userInfo.is_banned && !userInfo.is_muted;



    }







    let isModServerVerified = false;







    function isModerator() {



        return userInfo && isModServerVerified;



    }







    function cleanup() {



        pendingTimeouts.forEach(t => clearTimeout(t));



        pendingTimeouts = [];



        abortControllers.forEach(c => { try { c.abort(); } catch {} });



        abortControllers = [];

        stopStatsPoll();

        if (resizeHandler) { window.removeEventListener('resize', resizeHandler); resizeHandler = null; }
        clearTimeout(popoverTimeout);
        if (popoverEl) { popoverEl.remove(); popoverEl = null; }
        const overlay = document.getElementById('forum-modal-overlay');



        if (overlay) overlay.classList.add('hidden');



    }







    function setTimeoutSafe(fn, ms) {



        const id = setTimeout(fn, ms);



        pendingTimeouts.push(id);



        return id;



    }







    // ========== ROUTING ==========







    function route() {



        cleanup();



        const hash = window.location.hash.slice(1) || '/';



        const parts = hash.split('/');







        if (hash === '/' || hash === '') {



            currentView = 'list';



            currentThreadId = null;



            currentCategory = null;



            currentPage = 0;



            renderThreadList();



        } else if (hash === 'new') {



            currentView = 'new';



            renderNewThreadForm();



        } else if (parts[0] === 'thread' && parts[1]) {



            currentView = 'thread';



            currentThreadId = parseInt(parts[1]);



            postPage = 0;



            renderThreadDetail();



        } else if (parts[0] === 'category' && parts[1]) {



            currentView = 'list';



            const slug = parts[1];



            const cat = categories.find(c => c.slug === slug);



            currentCategory = cat ? cat.id : null;



            currentPage = 0;



            renderThreadList();



        } else {



            currentView = 'list';



            currentCategory = null;



            currentPage = 0;



            renderThreadList();



        }



    }







    // ========== THREAD LIST ==========







    // ===== PILL LOGIC =====

    function initCategoryPill() {
        const rail = document.querySelector('.forum-category-rail');
        if (!rail) return;
        let pill = rail.querySelector('.forum-cat-pill');
        if (!pill) {
            pill = document.createElement('div');
            pill.className = 'forum-cat-pill';
            rail.appendChild(pill);
        }
        const activeBtn = rail.querySelector('.forum-cat-btn.active');
        if (activeBtn) {
            movePillTo(activeBtn, false);
        }
        rail.addEventListener('scroll', () => {
            const active = rail.querySelector('.forum-cat-btn.active');
            if (active) movePillTo(active, false);
        });
        if (resizeHandler) window.removeEventListener('resize', resizeHandler);
        let resizeTimer = null;
        resizeHandler = () => {
            clearTimeout(resizeTimer);
            resizeTimer = setTimeout(() => {
                const active = rail.querySelector('.forum-cat-btn.active');
                if (active) movePillTo(active, false);
            }, 150);
        };
        window.addEventListener('resize', resizeHandler);
    }

    function movePillTo(targetBtn, animate) {
        const rail = document.querySelector('.forum-category-rail');
        if (!rail) return;
        let pill = rail.querySelector('.forum-cat-pill');
        if (!pill) return;
        const railRect = rail.getBoundingClientRect();
        const btnRect = targetBtn.getBoundingClientRect();
        const left = btnRect.left - railRect.left + rail.scrollLeft;
        const width = btnRect.width;
        if (animate === false) {
            pill.style.transition = 'none';
            pill.style.left = left + 'px';
            pill.style.width = width + 'px';
            pill.offsetHeight; // force reflow
            pill.style.transition = '';
        } else {
            pill.style.left = left + 'px';
            pill.style.width = width + 'px';
        }
        pillState = { left, width };
    }

    // ===== STATS POLLING =====

    function startStatsPoll() {
        stopStatsPoll();
        pollIntervalId = setInterval(async () => {
            try {
                const [tc, mc] = await Promise.all([
                    Api.getForumThreadsCount(null),
                    Api.getForumTotalPostsCount()
                ]);
                const threadEl = document.getElementById('forum-stat-threads');
                const msgEl = document.getElementById('forum-stat-messages');
                if (threadEl && tc !== lastThreadsCount) {
                    lastThreadsCount = tc;
                    hackerDecodeNumber(threadEl, String(tc), 800);
                }
                if (msgEl && mc !== lastMessagesCount) {
                    lastMessagesCount = mc;
                    hackerDecodeNumber(msgEl, String(mc), 800);
                }
            } catch {}
        }, 15000);
    }

    function stopStatsPoll() {
        if (pollIntervalId) { clearInterval(pollIntervalId); pollIntervalId = null; }
    }

    // ===== BOARD CONTENT (partial re-render) =====

    function renderThreadCard(t) {
        const author = getUserDisplay(t);
        const lastPostInfo = t.last_post_at
            ? `<span class="forum-last-post">Последний: ${formatRelativeTime(t.last_post_at)}</span>`
            : '<span class="forum-last-post">Без ответов</span>';
        const pinIcon = t.is_pinned ? '<span class="forum-pin-icon" title="Закреплён">&#x1F4CC;</span>' : '';
        const lockIcon = t.is_locked ? '<span class="forum-lock-icon" title="Закрыт">&#x1F512;</span>' : '';
        const contentPreview = cleanText(t.content, t.is_pinned ? 220 : 150);
        const title = cleanText(t.title, 200);
        const safeTitle = escapeHtml(title);
        const postsCount = Number(t.posts_count || 0);
        const cardClass = t.is_pinned ? 'forum-thread-pinned' : 'forum-thread-regular';

        return `
            <div class="forum-thread-card ${cardClass}" data-thread-id="${t.id}" role="link" tabindex="0" aria-label="Открыть тред: ${safeTitle}">
                <div class="forum-thread-card-top">
                    <div class="forum-thread-meta">
                        <span class="forum-thread-category">${escapeHtml(cleanText(t.category_name, 30) || 'Без категории')}</span>
                        <span class="forum-thread-time">${formatRelativeTime(t.created_at)}</span>
                    </div>
                    <div class="forum-thread-status">${pinIcon}${lockIcon}</div>
                </div>
                <div class="forum-thread-body">
                    <h3 class="forum-thread-title">${safeTitle}</h3>
                    <p class="forum-thread-preview">${escapeHtml(contentPreview)}</p>
                </div>
                <div class="forum-thread-card-bottom">
                    <div class="forum-thread-author" data-user-id="${t.author_id || ''}">
                        ${author.avatarHtml}
                        <div class="forum-thread-author-meta">${author.profileLink} ${author.roleBadge} ${author.modBadge} ${author.uidBadge}</div>
                    </div>
                    <div class="forum-thread-stats">
                        <span class="forum-thread-stat-chip">${postsCount} ответов</span>
                        ${lastPostInfo}
                    </div>
                </div>
            </div>
        `;
    }

    function buildBoardHtml(threads, total) {
        const catName = currentCategory ? (categories.find(c => c.id === currentCategory)?.name || '') : 'Все категории';
        const boardTitle = currentCategory ? catName : 'Все обсуждения';
        const boardLabel = currentCategory ? 'Категория' : 'Лента форума';
        const pinnedThreads = threads.filter(t => t.is_pinned);
        const regularThreads = threads.filter(t => !t.is_pinned);

        let paginationHtml = '';
        const totalPages = Math.ceil(total / THREADS_PER_PAGE);
        if (totalPages > 1) {
            paginationHtml = '<div class="forum-pagination">';
            if (currentPage > 0) {
                paginationHtml += `<button class="forum-page-btn" data-page="${currentPage - 1}">&larr; Назад</button>`;
            }
            paginationHtml += `<span class="forum-page-info">Стр. ${currentPage + 1} / ${totalPages}</span>`;
            if (currentPage < totalPages - 1) {
                paginationHtml += `<button class="forum-page-btn" data-page="${currentPage + 1}">Далее &rarr;</button>`;
            }
            paginationHtml += '</div>';
        }

        const pinnedHtml = pinnedThreads.length
            ? `
                <div class="forum-section-head">
                    <span class="forum-board-label">Закреплено</span>
                    <span class="forum-board-count">${pinnedThreads.length}</span>
                </div>
                <div class="forum-pinned-grid">
                    ${pinnedThreads.map(renderThreadCard).join('')}
                </div>
            `
            : '';

        const regularHtml = regularThreads.length
            ? `
                <div class="forum-section-head">
                    <span class="forum-board-label">Свежие треды</span>
                    <span class="forum-board-count">${regularThreads.length}</span>
                </div>
                <div class="forum-regular-list">
                    ${regularThreads.map(renderThreadCard).join('')}
                </div>
            `
            : '';

        return `
            <section class="forum-board" aria-label="${escapeHtml(boardTitle)}">
                <div class="forum-board-head">
                    <div>
                        <div class="forum-board-label">${boardLabel}</div>
                        <div class="forum-board-title">${escapeHtml(boardTitle)}</div>
                    </div>
                    <div class="forum-board-count">${total} тредов</div>
                </div>
                ${threads.length === 0 ? '<div class="forum-empty forum-empty-board">Пока нет тредов</div>' : `${pinnedHtml}${regularHtml}`}
            </section>
            ${paginationHtml}
        `;
    }

    async function updateBoardContent() {
        const boardContainer = document.getElementById('forum-board-container');
        if (!boardContainer) return;
        boardContainer.innerHTML = '<div class="forum-loading">Загрузка...</div>';
        const seq = ++renderSeq;
        try {
            const [threads, total] = await Promise.all([
                Api.getForumThreads(currentCategory, THREADS_PER_PAGE, currentPage * THREADS_PER_PAGE),
                Api.getForumThreadsCount(currentCategory)
            ]);
            if (seq !== renderSeq) return;
            const totalPages = Math.ceil(total / THREADS_PER_PAGE);
            if (totalPages > 0 && currentPage >= totalPages) {
                currentPage = totalPages - 1;
                return updateBoardContent();
            }
            threadsTotal = total;
            boardContainer.innerHTML = buildBoardHtml(threads, total);
            attachBoardHandlers();
        } catch (err) {
            if (seq !== renderSeq) return;
            boardContainer.innerHTML = `<div class="forum-error">Ошибка загрузки: ${escapeHtml(err.message)}</div>`;
        }
    }

    // ===== FULL PAGE RENDER =====

    async function renderThreadList() {



        const main = document.getElementById('forum-main');



        if (!main) return;



        main.innerHTML = '<div class="forum-loading">Загрузка...</div>';







        const seq = ++renderSeq;
        try {

            const [threads, total, totalThreads, totalMessages] = await Promise.all([
                Api.getForumThreads(currentCategory, THREADS_PER_PAGE, currentPage * THREADS_PER_PAGE),
                Api.getForumThreadsCount(currentCategory),
                Api.getForumThreadsCount(null),
                Api.getForumTotalPostsCount()
            ]);
            if (seq !== renderSeq) return;
            const totalPages = Math.ceil(total / THREADS_PER_PAGE);
            if (totalPages > 0 && currentPage >= totalPages) {
                currentPage = totalPages - 1;
                return renderThreadList();
            }
            threadsTotal = total;
            lastThreadsCount = totalThreads;
            lastMessagesCount = totalMessages;








            const newThreadBtn = canPost()
                ? `<a href="#new" class="forum-new-thread-btn">+ Новый тред</a>`
                : '';

            main.innerHTML = `
                <div class="forum-shell">
                    <section class="forum-hero" aria-labelledby="forum-title">
                        <div class="forum-hero-copy">
                            <div class="forum-kicker">NeuroBench community</div>
                            <h1 id="forum-title" class="forum-hero-title">Форум</h1>
                            <p class="forum-subtitle">Обсуждения моделей, генераций, бенчмарков и экспериментов сообщества.</p>
                        </div>
                        <div class="forum-hero-side">
                            <div class="forum-hero-stat"><span id="forum-stat-threads">${totalThreads}</span><small>тредов</small></div>
                            <div class="forum-hero-stat"><span id="forum-stat-messages">${totalMessages}</span><small>сообщений</small></div>
                            ${newThreadBtn}
                        </div>
                    </section>

                    <div class="forum-category-rail" aria-label="Категории форума">
                        <button class="forum-cat-btn ${!currentCategory ? 'active' : ''}" data-cat="">Все</button>
                        ${categories.map(c => `<button class="forum-cat-btn ${currentCategory === c.id ? 'active' : ''}" data-cat="${c.id}">${escapeHtml(c.name)}</button>`).join('')}
                    </div>

                    ${userInfo && userInfo.is_banned ? '<div class="forum-restriction forum-ban-notice">Вы заблокированы. Создание тредов и постов недоступно.</div>' : ''}
                    ${userInfo && userInfo.is_muted && !userInfo.is_banned ? '<div class="forum-restriction forum-mute-notice">Вы заглушены. Создание тредов и постов недоступно.</div>' : ''}

                    <div id="forum-board-container">
                        ${buildBoardHtml(threads, total)}
                    </div>
                </div>
            `;





            attachThreadListHandlers();
            initCategoryPill();
            startStatsPoll();

            // Initial hackerdecode animation on stat numbers
            const threadEl = document.getElementById('forum-stat-threads');
            const msgEl = document.getElementById('forum-stat-messages');
            if (threadEl) hackerDecodeNumber(threadEl, String(totalThreads), 1000);
            if (msgEl) hackerDecodeNumber(msgEl, String(totalMessages), 1000);

        } catch (err) {
            if (seq !== renderSeq) return;

            main.innerHTML = `<div class="forum-error">Ошибка загрузки: ${escapeHtml(err.message)}</div>`;

        }

    }


    function attachBoardHandlers() {
        document.querySelectorAll('.forum-thread-card').forEach(card => {
            card.addEventListener('click', (e) => {
                if (e.target.closest('a')) return;
                const id = card.dataset.threadId;
                if (id) window.location.hash = `thread/${id}`;
            });
            card.addEventListener('keydown', (e) => {
                if (e.target.closest('a, button, input, textarea, select')) return;
                if (e.key !== 'Enter' && e.key !== ' ') return;
                e.preventDefault();
                const id = card.dataset.threadId;
                if (id) window.location.hash = `thread/${id}`;
            });
        });
        document.querySelectorAll('.forum-page-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                currentPage = parseInt(btn.dataset.page);
                updateBoardContent();
                window.scrollTo({ top: 0, behavior: 'smooth' });
            });
        });
        attachUserPopovers();
    }

    function attachThreadListHandlers() {
        // Category rail buttons — animate pill + partial re-render
        document.querySelectorAll('.forum-cat-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const catId = btn.dataset.cat;
                const newCategory = catId ? parseInt(catId) : null;
                if (newCategory === currentCategory) return;

                // Update active state
                document.querySelectorAll('.forum-cat-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');

                // Animate pill
                movePillTo(btn, true);

                // Update state + hash silently
                currentCategory = newCategory;
                currentPage = 0;
                const slug = currentCategory ? (categories.find(c => c.id === currentCategory)?.slug || '') : '';
                const newHash = slug ? `category/${slug}` : '/';
                history.replaceState(null, '', '#' + newHash);

                // Partial re-render of board only
                updateBoardContent();
            });
        });
        // Board handlers (thread cards, pagination)
        attachBoardHandlers();
    }







    // ========== @MENTION RESOLUTION ==========







    async function resolvePostMentions(items) {



        const mentionRegex = /@([A-Za-z0-9_]{2,32})/g;



        const usernames = new Set();



        items.forEach(item => {



            if (!item.content) return;



            let m;



            while ((m = mentionRegex.exec(item.content)) !== null) {



                const u = m[1].toLowerCase();



                if (!usernameCache.has(u)) usernames.add(u);



            }



        });



        if (usernames.size === 0) return;



        try {



            const resolved = await Api.resolveUsernames([...usernames]);



            if (resolved && resolved.length) {



                resolved.forEach(r => {



                    if (r.username && r.user_id) usernameCache.set(r.username.toLowerCase(), r.user_id);



                });



            }



        } catch { /* ignore */ }



    }







    // ========== THREAD DETAIL ==========







    async function renderThreadDetail() {



        const main = document.getElementById('forum-main');



        if (!main) return;



        main.innerHTML = '<div class="forum-loading">Загрузка...</div>';







        const seq = ++renderSeq;
        try {



            const thread = await Api.getForumThread(currentThreadId);



            if (seq !== renderSeq) return;

            if (!thread) {



                main.innerHTML = '<div class="forum-empty">Тред не найден</div>';



                return;



            }







            const [posts, pTotal] = await Promise.all([



                Api.getForumThreadPosts(currentThreadId, POSTS_PER_PAGE, postPage * POSTS_PER_PAGE),



                Api.getForumThreadPostsCount(currentThreadId)



            ]);







            if (seq !== renderSeq) return;

            const postTotalPages = Math.ceil(pTotal / POSTS_PER_PAGE);
            if (postTotalPages > 0 && postPage >= postTotalPages) {
                postPage = postTotalPages - 1;
                return renderThreadDetail();
            }

            threadData = thread;



            postsData = posts;



            postsTotal = pTotal;







            // Resolve @usernames in all post content for mention linking



            await resolvePostMentions([thread, ...posts]);

            if (seq !== renderSeq) return;





            const isAuthor = userInfo && userInfo.user_id === thread.author_id;



            const isMod = isModerator();

            // FIX: убран лишний getPublicProfile запрос — данные автора уже есть в объекте thread
            // (author_username, author_first_name, author_photo_url возвращаются из get_forum_threads RPC)
            const authorHref = thread.author_id
                ? window.getProfileHref(thread.author_uid, thread.author_id)
                : '#';
            const authorPhoto = window.sanitizeTelegramPhotoUrl(thread.author_photo_url);
            const authorName = cleanText(
                [thread.author_first_name, thread.author_last_name].filter(Boolean).join(' ') || thread.author_username || '',
                50
            ) || 'Аноним';
            const authorDisplay = {
                name: authorName,
                avatarHtml: authorPhoto
                    ? `<a href="${authorHref}"><img src="${escapeHtml(authorPhoto)}" class="forum-avatar" alt="" onerror="this.style.display='none'"></a>`
                    : `<a href="${authorHref}"><div class="forum-avatar-placeholder"></div></a>`,
                modBadge: thread.is_author_moderator ? '<span class="forum-mod-badge">MOD</span>' : '',
                roleBadge: thread.author_role ? getRoleBadgeHtml(thread.author_role) : '',
                uidBadge: thread.author_uid != null ? `<span class="forum-uid-badge">UID #${thread.author_uid}</span>` : '',
                profileLink: thread.author_id
                    ? `<a href="${authorHref}" class="forum-username">${escapeHtml(authorName)}</a>`
                    : '<span class="forum-username">Удалённый пользователь</span>'
            };







            const pinBtn = isMod



                ? `<button class="forum-mod-action" id="btn-pin">${thread.is_pinned ? 'Открепить' : 'Закрепить'}</button>`



                : '';



            const lockBtn = isMod



                ? `<button class="forum-mod-action" id="btn-lock">${thread.is_locked ? 'Разблокировать' : 'Заблокировать'}</button>`



                : '';



            const deleteThreadBtn = isMod



                ? `<button class="forum-mod-action forum-mod-delete" id="btn-delete-thread">Удалить тред</button>`



                : '';



            const editThreadBtn = isAuthor



                ? `<button class="forum-mod-action" id="btn-edit-thread">Ред.</button>`



                : '';







            const modBar = isMod ? `



                <div class="forum-mod-bar">



                    <span class="forum-mod-label">Модерация:</span>



                    ${pinBtn} ${lockBtn} ${deleteThreadBtn}



                </div>



            ` : '';







            const lockedNotice = thread.is_locked



                ? '<div class="forum-locked-notice">Тред заблокирован. Новые ответы невозможны.</div>'



                : '';







            const replyForm = canPost() && !thread.is_locked



                ? `



                    <div class="forum-reply-form">



                        <textarea id="reply-content" placeholder="Ваш ответ..." rows="4" maxlength="10000" class="forum-textarea"></textarea>



                        <div class="forum-reply-actions">



                            <span class="forum-char-count"><span id="reply-char-count">0</span>/10000</span>



                            <button id="btn-reply" class="forum-submit-btn">Ответить</button>



                        </div>



                    </div>



                `



                : (!userInfo



                    ? '<div class="forum-login-prompt"><a href="auth">Войдите</a> чтобы отвечать в тредах</div>'



                    : (userInfo.is_banned || userInfo.is_muted)



                        ? `<div class="forum-restriction">${userInfo.is_banned ? 'Вы заблокированы' : 'Вы заглушены'}. Отправка сообщений недоступна.</div>`



                        : ''



                );







            let paginationHtml = '';



            const totalPages = Math.ceil(pTotal / POSTS_PER_PAGE);



            if (totalPages > 1) {



                paginationHtml = '<div class="forum-pagination">';



                if (postPage > 0) {



                    paginationHtml += `<button class="forum-page-btn" data-post-page="${postPage - 1}">&larr; Назад</button>`;



                }



                paginationHtml += `<span class="forum-page-info">Стр. ${postPage + 1} / ${totalPages}</span>`;



                if (postPage < totalPages - 1) {



                    paginationHtml += `<button class="forum-page-btn" data-post-page="${postPage + 1}">Далее &rarr;</button>`;



                }



                paginationHtml += '</div>';



            }







            main.innerHTML = `



                <div class="forum-breadcrumb">



                    <a href="#/">Форум</a>



                    ${thread.category_id ? ` &rsaquo; <a href="#/category/${categories.find(c => c.id === thread.category_id)?.slug || ''}">${escapeHtml(categories.find(c => c.id === thread.category_id)?.name || '')}</a>` : ''}



                    &rsaquo; <span>${escapeHtml(thread.title)}</span>



                </div>



                <div class="forum-thread-detail">



                    <div class="forum-thread-op">



                        <div class="forum-post-header">



                            <div class="forum-post-author" data-user-id="${thread.author_id || ''}">



                                ${authorDisplay.avatarHtml}



                                <div>



                                    ${authorDisplay.profileLink} ${authorDisplay.roleBadge} ${authorDisplay.modBadge} ${authorDisplay.uidBadge}



                                    <span class="forum-post-time">${formatDate(thread.created_at)}</span>



                                </div>



                            </div>



                            <div class="forum-post-actions">



                                ${thread.is_pinned ? '<span class="forum-pin-icon" title="Закреплён">&#x1F4CC;</span>' : ''}



                                ${thread.is_locked ? '<span class="forum-lock-icon" title="Закрыт">&#x1F512;</span>' : ''}



                                ${editThreadBtn}



                            </div>



                        </div>



                        <h1 class="forum-thread-detail-title">${escapeHtml(cleanText(thread.title, 200))}</h1>



                        <div class="forum-post-content">${renderMarkdown(cleanText(thread.content, 10000))}</div>



                    </div>



                    ${modBar}



                    ${lockedNotice}



                </div>



                <div class="forum-posts-list">



                    ${posts.map(p => renderPostHtml(p)).join('')}



                </div>



                ${paginationHtml}



                ${replyForm}



            `;







            attachThreadDetailHandlers(thread);



        } catch (err) {
            if (seq !== renderSeq) return;



            main.innerHTML = `<div class="forum-error">Ошибка загрузки: ${escapeHtml(err.message)}</div>`;



        }



    }







    function renderReactionsRow(postId, reactions) {
        const isAdmin = userInfo && (userInfo.role === 'admin' || userInfo.role === 'stmoderator');
        const emojis = ['like','dislike','fire','puke','brain','emotion'];
        // admin_like: show button only for admins, or if reactions already exist
        if (isAdmin || (reactions && reactions.admin_like && reactions.admin_like.count > 0)) {
            emojis.push('admin_like');
        }
        let html = '<div class="forum-reactions-row">';
        emojis.forEach(key => {
            const info = EMOJI_MAP[key];
            const data = reactions && reactions[key] ? reactions[key] : { count: 0, me: false };
            const activeClass = data.me ? ' forum-reaction-btn--active' : '';
            const isDisabled = info.adminOnly && !isAdmin ? ' disabled' : (userInfo ? '' : ' disabled');
            const adminClass = info.adminOnly ? ' forum-reaction-btn--admin' : '';
            html += `<button class="forum-reaction-btn${activeClass}${adminClass}" data-post-id="${postId}" data-emoji="${key}" title="${escapeHtml(info.label)}"${isDisabled}>`
                + `<span class="forum-reaction-icon">${info.icon}</span>`
                + `<span class="forum-reaction-count">${data.count || ''}</span></button>`;
        });



        const quoteBtn = userInfo ? `<button class="forum-quote-btn" data-post-id="${postId}" title="Цитировать">&#10077;</button>` : '';



        html += quoteBtn + '</div>';



        return html;



    }







    function renderPostHtml(p) {



        const author = getUserDisplay(p);



        const isAuthor = userInfo && userInfo.user_id === p.author_id;



        const isMod = isModerator();



        const editedLabel = p.edited_at ? `<span class="forum-edited-label">(ред. ${formatRelativeTime(p.edited_at)})</span>` : '';



        const editBtn = isAuthor ? `<button class="forum-post-action-btn" data-action="edit" data-post-id="${p.id}">Ред.</button>` : '';



        const deleteBtn = isMod ? `<button class="forum-post-action-btn forum-mod-delete-sm" data-action="delete-post" data-post-id="${p.id}">Удал.</button>` : '';



        const modUserBtn = isMod && p.author_id && p.author_id !== userInfo?.user_id



            ? `<button class="forum-post-action-btn" data-action="mod-user" data-user-id="${p.author_id}">Мод.</button>`



            : '';







        return `



            <div class="forum-post" data-post-id="${p.id}">



                <div class="forum-post-header">



                    <div class="forum-post-author" data-user-id="${p.author_id || ''}">



                        ${author.avatarHtml}



                        <div>



                            ${author.profileLink} ${author.roleBadge} ${author.modBadge} ${author.uidBadge}



                            <span class="forum-post-time">${formatDate(p.created_at)} ${editedLabel}</span>



                        </div>



                    </div>



                    <div class="forum-post-actions">



                        ${editBtn} ${deleteBtn} ${modUserBtn}



                    </div>



                </div>



                <div class="forum-post-content" id="post-content-${p.id}">${renderMarkdown(cleanText(p.content, 10000))}</div>



                ${renderReactionsRow(p.id, p.reactions)}



            </div>



        `;



    }







    function attachThreadDetailHandlers(thread) {



        const replyTextarea = document.getElementById('reply-content');



        const charCount = document.getElementById('reply-char-count');



        if (replyTextarea && charCount) {



            replyTextarea.addEventListener('input', () => {



                charCount.textContent = replyTextarea.value.length;



            });



        }







        const replyBtn = document.getElementById('btn-reply');



        if (replyBtn) {



            replyBtn.addEventListener('click', async () => {



                if (!replyTextarea) return;



                const content = replyTextarea.value.trim();



                if (!content) return;



                replyBtn.disabled = true;



                replyBtn.textContent = 'Отправка...';



                try {



                    const newPostId = await Api.createForumPost(currentThreadId, content);



                    try { Api.checkAndGrantAchievements(); } catch (e) { /* fire-and-forget */ }



                    replyTextarea.value = '';



                    if (charCount) charCount.textContent = '0';



                    // Send mention notifications



                    try {



                        const mentionRegex = /@([A-Za-z0-9_]{2,32})/g;



                        const mentions = [];



                        let mm;



                        while ((mm = mentionRegex.exec(content)) !== null) mentions.push(mm[1].toLowerCase());



                        if (mentions.length > 0) {



                            const resolved = await Api.resolveUsernames([...new Set(mentions)]);



                            if (resolved && resolved.length) {



                                const ids = resolved.map(r => r.user_id).filter(Boolean);



                                if (ids.length) await Api.createMentionNotifications(newPostId, currentThreadId, ids);



                            }



                        }



                    } catch (mentionErr) {



                        console.error('Mention notification failed:', mentionErr);



                    }



                    await renderThreadDetail();



                    return;



                } catch (err) {



                    alert('Ошибка: ' + (err.message || 'Не удалось отправить'));



                    replyBtn.disabled = false;



                    replyBtn.textContent = 'Ответить';



                }



            });



        }







        const pinBtn = document.getElementById('btn-pin');



        if (pinBtn) {



            pinBtn.addEventListener('click', async () => {



                try {



                    await Api.modPinThread(currentThreadId, !thread.is_pinned);



                    await renderThreadDetail();



                } catch (err) { alert('Ошибка: ' + err.message); }



            });



        }







        const lockBtn = document.getElementById('btn-lock');



        if (lockBtn) {



            lockBtn.addEventListener('click', async () => {



                try {



                    await Api.modLockThread(currentThreadId, !thread.is_locked);



                    await renderThreadDetail();



                } catch (err) { alert('Ошибка: ' + err.message); }



            });



        }







        const deleteThreadBtn = document.getElementById('btn-delete-thread');



        if (deleteThreadBtn) {



            deleteThreadBtn.addEventListener('click', async () => {



                if (!confirm('Удалить тред?')) return;



                try {



                    await Api.modDeleteThread(currentThreadId);



                    window.location.hash = '/';



                } catch (err) { alert('Ошибка: ' + err.message); }



            });



        }







        const editThreadBtn = document.getElementById('btn-edit-thread');



        if (editThreadBtn) {



            editThreadBtn.addEventListener('click', () => showEditThreadModal(thread));



        }







        document.querySelectorAll('.forum-page-btn[data-post-page]').forEach(btn => {



            btn.addEventListener('click', () => {



                postPage = parseInt(btn.dataset.postPage);



                renderThreadDetail();



                window.scrollTo({ top: 0, behavior: 'smooth' });



            });



        });







        document.querySelectorAll('.forum-post-action-btn').forEach(btn => {



            btn.addEventListener('click', () => {



                const action = btn.dataset.action;



                const postId = btn.dataset.postId ? parseInt(btn.dataset.postId) : null;



                const userId = btn.dataset.userId;







                if (action === 'edit' && postId) showEditPostModal(postId);



                else if (action === 'delete-post' && postId) handleDeletePost(postId);



                else if (action === 'mod-user' && userId) showModUserModal(userId);



            });



        });







        // Reaction handlers



        document.querySelectorAll('.forum-reaction-btn:not([disabled])').forEach(btn => {



            btn.addEventListener('click', async () => {



                const postId = parseInt(btn.dataset.postId);



                const emoji = btn.dataset.emoji;



                if (!postId || !emoji) return;



                // Optimistic UI



                const countEl = btn.querySelector('.forum-reaction-count');



                const wasActive = btn.classList.contains('forum-reaction-btn--active');



                const curCount = parseInt(countEl.textContent) || 0;



                if (wasActive) {



                    btn.classList.remove('forum-reaction-btn--active');



                    countEl.textContent = curCount > 1 ? curCount - 1 : '';



                } else {



                    btn.classList.add('forum-reaction-btn--active');



                    countEl.textContent = curCount + 1;



                }



                btn.disabled = true;
                try {



                    await Api.togglePostReaction(postId, emoji);



                } catch (err) {



                    // Revert on error



                    if (wasActive) {



                        btn.classList.add('forum-reaction-btn--active');



                        countEl.textContent = curCount || '';



                    } else {



                        btn.classList.remove('forum-reaction-btn--active');



                        countEl.textContent = curCount || '';



                    }



                } finally {

                    btn.disabled = false;

                }



            });



        });







        // Quote handlers



        document.querySelectorAll('.forum-quote-btn').forEach(btn => {



            btn.addEventListener('click', () => {



                const postId = parseInt(btn.dataset.postId);



                const post = postsData.find(p => p.id === postId);



                if (!post) return;



                const textarea = document.getElementById('reply-content');



                if (!textarea) return;



                const authorName = [post.author_first_name, post.author_last_name].filter(Boolean).join(' ') || post.author_username || '';



                const quoteText = cleanText(post.content, 300);



                const lines = quoteText.split('\n').map(l => '> ' + l).join('\n');



                const mention = post.author_username ? `@${post.author_username}` : authorName;



                textarea.value += (textarea.value ? '\n' : '') + lines + '\n' + mention + '\n\n';



                textarea.focus();



                textarea.scrollIntoView({ behavior: 'smooth', block: 'center' });



                const charCount = document.getElementById('reply-char-count');



                if (charCount) charCount.textContent = textarea.value.length;



            });



        });







        // Hover popover on author names



        attachUserPopovers();



    }







    // ========== USER POPOVER ==========







    let popoverEl = null;



    let popoverTimeout = null;







    function attachUserPopovers() {



        document.querySelectorAll('.forum-post-author[data-user-id], .forum-thread-author[data-user-id]').forEach(el => {



            const userId = el.dataset.userId;



            if (!userId) return;



            el.addEventListener('mouseenter', (e) => showUserPopover(userId, el));



            el.addEventListener('mouseleave', () => scheduleHidePopover());



        });



    }







    function scheduleHidePopover() {



        popoverTimeout = setTimeout(() => {



            if (popoverEl) { popoverEl.remove(); popoverEl = null; }



        }, 250);



    }







    async function showUserPopover(userId, anchor) {



        clearTimeout(popoverTimeout);



        if (popoverEl) { popoverEl.remove(); popoverEl = null; }







        let profile = profileCache.get(userId);



        if (!profile) {



            try {



                profile = await Api.getPublicProfile(userId);



                if (profile) profileCache.set(userId, profile);



            } catch { return; }



        }



        if (!profile) return;







        const name = (typeof safeDisplayName === 'function') ? window.safeDisplayName(profile) : ([profile.telegram_first_name, profile.telegram_last_name].filter(Boolean).join(' ') || profile.telegram_username || 'Аноним');



        const photo = window.sanitizeTelegramPhotoUrl(profile.telegram_photo_url);



        const roleMeta = { admin: 'ADMIN', stmoderator: 'ST.MOD', moderator: 'MOD', beta: 'BETA', alpha: 'ALPHA', member: 'MEMBER' };



        const roleLabel = roleMeta[profile.role] || 'MEMBER';



        const uid = profile.uid != null ? `UID #${profile.uid}` : '';







        const div = document.createElement('div');



        div.className = 'forum-user-popover';



        div.innerHTML = `



            <div class="forum-popover-header">



                ${photo ? `<img src="${escapeHtml(photo)}" class="forum-popover-avatar" alt="" onerror="this.style.display='none'">` : '<div class="forum-popover-avatar-ph"></div>'}



                <div>



                    <div class="forum-popover-name">${escapeHtml(name)}</div>



                    <div class="forum-popover-meta"><span class="forum-popover-role forum-popover-role-${profile.role || 'member'}">${roleLabel}</span> ${uid ? `<span class="forum-popover-uid">${uid}</span>` : ''}</div>



                </div>



            </div>



            <div class="forum-popover-stats">



                <span>${profile.threads_count || 0} тредов</span>



                <span>${profile.posts_count || 0} постов</span>



            </div>



            <a href="${escapeHtml(window.getProfileHref(profile.uid, userId))}" class="forum-popover-link">Открыть профиль</a>



        `;



        div.addEventListener('mouseenter', () => clearTimeout(popoverTimeout));



        div.addEventListener('mouseleave', () => scheduleHidePopover());







        document.body.appendChild(div);



        popoverEl = div;







        const rect = anchor.getBoundingClientRect();



        div.style.position = 'fixed';



        div.style.left = rect.left + 'px';



        div.style.top = (rect.bottom + 6) + 'px';



        div.style.zIndex = '9999';







        // Keep within viewport



        requestAnimationFrame(() => {



            const dr = div.getBoundingClientRect();



            if (dr.right > window.innerWidth - 8) div.style.left = (window.innerWidth - dr.width - 8) + 'px';



            if (dr.bottom > window.innerHeight - 8) div.style.top = (rect.top - dr.height - 6) + 'px';



        });



    }







    // ========== EDIT POST MODAL ==========







    function showEditPostModal(postId) {



        const post = postsData.find(p => p.id === postId);



        if (!post) return;



        const overlay = document.getElementById('forum-modal-overlay');



        const modal = document.getElementById('forum-modal');



        if (!overlay || !modal) return;







        modal.innerHTML = `



            <h3 class="font-title text-lg uppercase tracking-widest mb-4">Редактировать пост</h3>



            <textarea id="edit-post-content" rows="6" maxlength="10000" class="forum-textarea">${escapeHtml(post.content)}</textarea>



            <div class="forum-modal-actions">



                <button id="btn-save-edit-post" class="forum-submit-btn">Сохранить</button>



                <button id="btn-cancel-modal" class="forum-cancel-btn">Отмена</button>



            </div>



        `;



        overlay.classList.remove('hidden');







        document.getElementById('btn-save-edit-post').addEventListener('click', async () => {



            const content = document.getElementById('edit-post-content').value.trim();



            if (!content) return;



            try {



                await Api.updateForumPost(postId, content);



                overlay.classList.add('hidden');



                await renderThreadDetail();



            } catch (err) { alert('Ошибка: ' + err.message); }



        });



        document.getElementById('btn-cancel-modal').addEventListener('click', () => overlay.classList.add('hidden'));



    }







    // ========== EDIT THREAD MODAL ==========







    function showEditThreadModal(thread) {



        const overlay = document.getElementById('forum-modal-overlay');



        const modal = document.getElementById('forum-modal');



        if (!overlay || !modal) return;







        modal.innerHTML = `



            <h3 class="font-title text-lg uppercase tracking-widest mb-4">Редактировать тред</h3>



            <input id="edit-thread-title" value="${escapeHtml(thread.title)}" maxlength="200" placeholder="Заголовок" class="forum-input">



            <textarea id="edit-thread-content" rows="6" maxlength="10000" class="forum-textarea">${escapeHtml(thread.content)}</textarea>



            <div class="forum-modal-actions">



                <button id="btn-save-edit-thread" class="forum-submit-btn">Сохранить</button>



                <button id="btn-cancel-modal" class="forum-cancel-btn">Отмена</button>



            </div>



        `;



        overlay.classList.remove('hidden');







        document.getElementById('btn-save-edit-thread').addEventListener('click', async () => {



            const title = document.getElementById('edit-thread-title').value.trim();



            const content = document.getElementById('edit-thread-content').value.trim();



            if (!title || !content) return;



            try {



                await Api.updateForumThread(currentThreadId, title, content);



                overlay.classList.add('hidden');



                await renderThreadDetail();



            } catch (err) { alert('Ошибка: ' + err.message); }



        });



        document.getElementById('btn-cancel-modal').addEventListener('click', () => overlay.classList.add('hidden'));



    }







    // ========== DELETE POST ==========







    async function handleDeletePost(postId) {



        if (!confirm('Удалить пост?')) return;



        try {



            await Api.modDeletePost(postId);



            await renderThreadDetail();



        } catch (err) { alert('Ошибка: ' + err.message); }



    }







    // ========== MOD USER MODAL ==========







    function showModUserModal(userId) {



        const overlay = document.getElementById('forum-modal-overlay');



        const modal = document.getElementById('forum-modal');



        if (!overlay || !modal) return;







        modal.innerHTML = `



            <h3 class="font-title text-lg uppercase tracking-widest mb-4">Модерация пользователя</h3>



            <div class="forum-mod-user-section">



                <p class="forum-mod-user-label">Заглушить (запретить отправку сообщений)</p>



                <input id="mod-mute-reason" placeholder="Причина (опц.)" class="forum-input">



                <div class="forum-duration-row">



                    <select id="mod-mute-duration" class="forum-select">



                        <option value="1h">1 час</option>



                        <option value="6h">6 часов</option>



                        <option value="1d" selected>1 день</option>



                        <option value="7d">7 дней</option>



                        <option value="30d">30 дней</option>



                        <option value="perm">Навсегда</option>



                    </select>



                    <button id="btn-mute-user" class="forum-mod-btn forum-mod-mute">Заглушить</button>



                </div>



            </div>



            <div class="forum-mod-user-section">



                <p class="forum-mod-user-label">Заблокировать (полный бан)</p>



                <input id="mod-ban-reason" placeholder="Причина (опц.)" class="forum-input">



                <div class="forum-duration-row">



                    <select id="mod-ban-duration" class="forum-select">



                        <option value="1d">1 день</option>



                        <option value="7d" selected>7 дней</option>



                        <option value="30d">30 дней</option>



                        <option value="perm">Навсегда</option>



                    </select>



                    <button id="btn-ban-user" class="forum-mod-btn forum-mod-ban">Заблокировать</button>



                </div>



            </div>



            <div class="forum-mod-user-section">



                <p class="forum-mod-user-label">Снять ограничения</p>



                <div class="forum-duration-row">



                    <button id="btn-unmute-user" class="forum-mod-btn forum-mod-unmute">Снять мут</button>



                    <button id="btn-unban-user" class="forum-mod-btn forum-mod-unban">Снять бан</button>



                </div>



            </div>



            <div class="forum-modal-actions">



                <button id="btn-cancel-modal" class="forum-cancel-btn">Закрыть</button>



            </div>



        `;



        overlay.classList.remove('hidden');







        function calcExpiry(val) {



            if (val === 'perm') return null;



            const now = new Date();



            const map = { '1h': 3600000, '6h': 21600000, '1d': 86400000, '7d': 604800000, '30d': 2592000000 };



            return new Date(now.getTime() + (map[val] || 86400000)).toISOString();



        }







        document.getElementById('btn-mute-user').addEventListener('click', async () => {



            const reason = document.getElementById('mod-mute-reason').value.trim();



            const duration = document.getElementById('mod-mute-duration').value;



            try {



                const r = await Api.modMuteUser(userId, reason, calcExpiry(duration));



                if (!r) { alert('Не удалось заглушить'); return; }



                alert('Пользователь заглушен');



                overlay.classList.add('hidden');



            } catch (err) { alert('Ошибка: ' + err.message); }



        });







        document.getElementById('btn-ban-user').addEventListener('click', async () => {



            const reason = document.getElementById('mod-ban-reason').value.trim();



            const duration = document.getElementById('mod-ban-duration').value;



            if (!confirm('Заблокировать пользователя?')) return;



            try {



                const r = await Api.modBanUser(userId, reason, calcExpiry(duration));



                if (!r) { alert('Не удалось заблокировать'); return; }



                alert('Пользователь заблокирован');



                overlay.classList.add('hidden');



            } catch (err) { alert('Ошибка: ' + err.message); }



        });







        document.getElementById('btn-unmute-user').addEventListener('click', async () => {



            try {



                await Api.modUnmuteUser(userId);



                alert('Мут снят');



                overlay.classList.add('hidden');



            } catch (err) { alert('Ошибка: ' + err.message); }



        });







        document.getElementById('btn-unban-user').addEventListener('click', async () => {



            try {



                await Api.modUnbanUser(userId);



                alert('Бан снят');



                overlay.classList.add('hidden');



            } catch (err) { alert('Ошибка: ' + err.message); }



        });







        document.getElementById('btn-cancel-modal').addEventListener('click', () => overlay.classList.add('hidden'));



    }







    // ========== NEW THREAD FORM ==========







    function renderNewThreadForm() {



        const main = document.getElementById('forum-main');



        if (!main) return;







        if (!canPost()) {



            main.innerHTML = `



                <div class="forum-breadcrumb"><a href="#/">Форум</a> &rsaquo; Новый тред</div>



                <div class="forum-empty">${!userInfo ? '<a href="auth">Войдите</a> чтобы создавать треды' : 'У вас нет прав для создания тредов'}</div>



            `;



            return;



        }







        main.innerHTML = `



            <div class="forum-breadcrumb"><a href="#/">Форум</a> &rsaquo; Новый тред</div>



            <div class="forum-new-thread-form">



                <h2 class="font-title text-xl uppercase tracking-widest text-shiny mb-6">Новый тред</h2>



                <label class="forum-form-label">



                    Категория



                    <select id="new-thread-category" class="forum-select">



                        ${categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('')}



                    </select>



                </label>



                <label class="forum-form-label">



                    Заголовок <span class="forum-char-hint"><span id="title-char-count">0</span>/200</span>



                    <input id="new-thread-title" maxlength="200" placeholder="Тема обсуждения" class="forum-input">



                </label>



                <label class="forum-form-label">



                    Содержание <span class="forum-char-hint"><span id="content-char-count">0</span>/10000</span>



                    <textarea id="new-thread-content" rows="8" maxlength="10000" placeholder="Опишите тему..." class="forum-textarea"></textarea>



                </label>



                <div class="forum-form-actions">



                    <button id="btn-create-thread" class="forum-submit-btn">Создать тред</button>



                    <a href="#/" class="forum-cancel-btn">Отмена</a>



                </div>



            </div>



        `;







        const titleInput = document.getElementById('new-thread-title');



        const contentInput = document.getElementById('new-thread-content');



        const titleCount = document.getElementById('title-char-count');



        const contentCount = document.getElementById('content-char-count');







        if (titleInput && titleCount) {



            titleInput.addEventListener('input', () => { titleCount.textContent = titleInput.value.length; });



        }



        if (contentInput && contentCount) {



            contentInput.addEventListener('input', () => { contentCount.textContent = contentInput.value.length; });



        }







        document.getElementById('btn-create-thread').addEventListener('click', async () => {



            const categoryId = parseInt(document.getElementById('new-thread-category').value);



            const title = titleInput.value.trim();



            const content = contentInput.value.trim();



            if (!title || title.length < 3) { alert('Заголовок минимум 3 символа'); return; }



            if (!content) { alert('Введите содержание'); return; }







            const btn = document.getElementById('btn-create-thread');



            btn.disabled = true;



            btn.textContent = 'Создание...';



            try {



                const threadId = await Api.createForumThread(categoryId, title, content);



                try { Api.checkAndGrantAchievements(); } catch (e) { /* fire-and-forget */ }



                window.location.hash = `thread/${threadId}`;



            } catch (err) {



                alert('Ошибка: ' + (err.message || 'Не удалось создать тред'));



                btn.disabled = false;



                btn.textContent = 'Создать тред';



            }



        });



    }







    // ========== INIT ==========







    async function init() {



        Api.reinit();







        try {



            categories = await Api.getForumCategories();



        } catch { categories = []; }







        try {



            const isLocal = ['localhost', '127.0.0.1', '::1'].includes(window.location.hostname);



            const devRaw = isLocal ? localStorage.getItem('nb_dev_session') : null;



            if (devRaw) {



                userInfo = JSON.parse(devRaw);



            } else {



                const session = await Api.getSession();



                if (session) {



                    userInfo = await Api.getUserDisplayName();



                    if (userInfo) {



                        userInfo.user_id = session.user.id;



                    }



                }



            }



            if (userInfo) {



                if (devRaw && ['admin', 'stmoderator', 'moderator'].includes(userInfo.role)) {



                    isModServerVerified = true;



                } else {



                    try { isModServerVerified = await Api.isModeratorCheck(); } catch { isModServerVerified = false; }



                }



            }



        } catch (e) { console.warn('[forum] user init error:', e); userInfo = null; }







        window.addEventListener('hashchange', route);



        route();







        const overlay = document.getElementById('forum-modal-overlay');



        if (overlay) {



            overlay.addEventListener('click', (e) => {



                if (e.target.id === 'forum-modal-overlay') overlay.classList.add('hidden');



            });



        }



    }







    return { init };



})();







document.addEventListener('DOMContentLoaded', ForumModule.init);
