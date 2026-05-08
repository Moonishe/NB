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



    const profileCache = new Map();



    const usernameCache = new Map();







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



        return d.innerHTML.replace(/"/g, '&quot;');



    }







    function cleanText(str, maxLen) {



        if (!str) return '';



        let s = str.replace(/[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]/g, '');



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



        html = html.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer" class="forum-link">$1</a>');



        // @mentions вЂ” link to profile if resolved



        html = html.replace(/@([A-Za-z0-9_]{2,32})/g, (match, username) => {



            const uid = usernameCache.get(username.toLowerCase());



            if (uid) return `<a href="profile.html?id=${uid}" class="forum-mention">@${username}</a>`;



            return `<span class="forum-mention">@${username}</span>`;



        });



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



        if (diff < 60) return 'С‚РѕР»СЊРєРѕ С‡С‚Рѕ';



        if (diff < 3600) return Math.floor(diff / 60) + ' РјРёРЅ. РЅР°Р·Р°Рґ';



        if (diff < 86400) return Math.floor(diff / 3600) + ' С‡. РЅР°Р·Р°Рґ';



        if (diff < 2592000) return Math.floor(diff / 86400) + ' РґРЅ. РЅР°Р·Р°Рґ';



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



        const name = parts.length > 0 ? parts.join(' ') : (cleanText(info.author_username, 50) || 'РђРЅРѕРЅРёРј');



        const photo = info.author_photo_url



            ? (info.author_photo_url.startsWith('/') ? 'https://t.me' + info.author_photo_url : info.author_photo_url)



            : null;



        const modBadge = info.is_author_moderator ? '<span class="forum-mod-badge">MOD</span>' : '';



        const roleBadge = info.author_role ? getRoleBadgeHtml(info.author_role) : '';



        const uidBadge = info.author_uid != null ? `<span class="forum-uid-badge">UID #${info.author_uid}</span>` : '';



        const href = info.author_id ? `profile.html?id=${info.author_id}` : '#';



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







    async function renderThreadList() {



        const main = document.getElementById('forum-main');



        if (!main) return;



        main.innerHTML = '<div class="forum-loading">Р—Р°РіСЂСѓР·РєР°...</div>';







        try {



            const [threads, total] = await Promise.all([



                Api.getForumThreads(currentCategory, THREADS_PER_PAGE, currentPage * THREADS_PER_PAGE),



                Api.getForumThreadsCount(currentCategory)



            ]);



            threadsTotal = total;







            const catSlug = currentCategory ? (categories.find(c => c.id === currentCategory)?.slug || '') : '';



            const catName = currentCategory ? (categories.find(c => c.id === currentCategory)?.name || '') : 'Р’СЃРµ РєР°С‚РµРіРѕСЂРёРё';







            let paginationHtml = '';



            const totalPages = Math.ceil(total / THREADS_PER_PAGE);



            if (totalPages > 1) {



                paginationHtml = '<div class="forum-pagination">';



                if (currentPage > 0) {



                    paginationHtml += `<button class="forum-page-btn" data-page="${currentPage - 1}">&larr; РќР°Р·Р°Рґ</button>`;



                }



                paginationHtml += `<span class="forum-page-info">РЎС‚СЂ. ${currentPage + 1} / ${totalPages}</span>`;



                if (currentPage < totalPages - 1) {



                    paginationHtml += `<button class="forum-page-btn" data-page="${currentPage + 1}">Р”Р°Р»РµРµ &rarr;</button>`;



                }



                paginationHtml += '</div>';



            }







            const newThreadBtn = canPost()
                ? `<a href="#new" class="forum-new-thread-btn">+ РќРѕРІС‹Р№ С‚СЂРµРґ</a>`
                : '';

            const pinnedThreads = threads.filter(t => t.is_pinned);
            const regularThreads = threads.filter(t => !t.is_pinned);
            const categoriesCount = categories.length || 0;
            const boardTitle = currentCategory ? catName : 'Р’СЃРµ РѕР±СЃСѓР¶РґРµРЅРёСЏ';
            const boardLabel = currentCategory ? 'РљР°С‚РµРіРѕСЂРёСЏ' : 'Р›РµРЅС‚Р° С„РѕСЂСѓРјР°';

            const renderThreadCard = (t) => {
                const author = getUserDisplay(t);
                const lastPostInfo = t.last_post_at
                    ? `<span class="forum-last-post">РџРѕСЃР»РµРґРЅРёР№: ${formatRelativeTime(t.last_post_at)}</span>`
                    : '<span class="forum-last-post">Р‘РµР· РѕС‚РІРµС‚РѕРІ</span>';
                const pinIcon = t.is_pinned ? '<span class="forum-pin-icon" title="Р—Р°РєСЂРµРїР»С‘РЅ">&#x1F4CC;</span>' : '';
                const lockIcon = t.is_locked ? '<span class="forum-lock-icon" title="Р—Р°РєСЂС‹С‚">&#x1F512;</span>' : '';
                const contentPreview = cleanText(t.content, t.is_pinned ? 220 : 150);
                const title = cleanText(t.title, 200);
                const safeTitle = escapeHtml(title);
                const postsCount = Number(t.posts_count || 0);
                const cardClass = t.is_pinned ? 'forum-thread-pinned' : 'forum-thread-regular';

                return `
                    <div class="forum-thread-card ${cardClass}" data-thread-id="${t.id}" role="link" tabindex="0" aria-label="РћС‚РєСЂС‹С‚СЊ С‚СЂРµРґ: ${safeTitle}">
                        <div class="forum-thread-card-top">
                            <div class="forum-thread-meta">
                                <span class="forum-thread-category">${escapeHtml(cleanText(t.category_name, 30) || 'Р‘РµР· РєР°С‚РµРіРѕСЂРёРё')}</span>
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
                                <span class="forum-thread-stat-chip">${postsCount} РѕС‚РІРµС‚РѕРІ</span>
                                ${lastPostInfo}
                            </div>
                        </div>
                    </div>
                `;
            };

            const pinnedHtml = pinnedThreads.length
                ? `
                    <div class="forum-section-head">
                        <span class="forum-board-label">Р—Р°РєСЂРµРїР»РµРЅРѕ</span>
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
                        <span class="forum-board-label">РЎРІРµР¶РёРµ С‚СЂРµРґС‹</span>
                        <span class="forum-board-count">${regularThreads.length}</span>
                    </div>
                    <div class="forum-regular-list">
                        ${regularThreads.map(renderThreadCard).join('')}
                    </div>
                `
                : '';

            main.innerHTML = `
                <div class="forum-shell">
                    <section class="forum-hero" aria-labelledby="forum-title">
                        <div class="forum-hero-copy">
                            <div class="forum-kicker">NeuroBench community</div>
                            <h1 id="forum-title" class="forum-hero-title">Р¤РѕСЂСѓРј</h1>
                            <p class="forum-subtitle">РћР±СЃСѓР¶РґРµРЅРёСЏ РјРѕРґРµР»РµР№, РіРµРЅРµСЂР°С†РёР№, Р±РµРЅС‡РјР°СЂРєРѕРІ Рё СЌРєСЃРїРµСЂРёРјРµРЅС‚РѕРІ СЃРѕРѕР±С‰РµСЃС‚РІР°.</p>
                        </div>
                        <div class="forum-hero-side">
                            <div class="forum-hero-stat"><span>${total}</span><small>С‚СЂРµРґРѕРІ</small></div>
                            <div class="forum-hero-stat"><span>${categoriesCount}</span><small>РєР°С‚РµРіРѕСЂРёР№</small></div>
                            ${newThreadBtn}
                        </div>
                    </section>

                    <div class="forum-category-rail" aria-label="РљР°С‚РµРіРѕСЂРёРё С„РѕСЂСѓРјР°">
                        <button class="forum-cat-btn ${!currentCategory ? 'active' : ''}" data-cat="">Р’СЃРµ</button>
                        ${categories.map(c => `<button class="forum-cat-btn ${currentCategory === c.id ? 'active' : ''}" data-cat="${c.id}">${escapeHtml(c.name)}</button>`).join('')}
                    </div>

                    ${userInfo && userInfo.is_banned ? '<div class="forum-restriction forum-ban-notice">Р’С‹ Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅС‹. РЎРѕР·РґР°РЅРёРµ С‚СЂРµРґРѕРІ Рё РїРѕСЃС‚РѕРІ РЅРµРґРѕСЃС‚СѓРїРЅРѕ.</div>' : ''}
                    ${userInfo && userInfo.is_muted && !userInfo.is_banned ? '<div class="forum-restriction forum-mute-notice">Р’С‹ Р·Р°РіР»СѓС€РµРЅС‹. РЎРѕР·РґР°РЅРёРµ С‚СЂРµРґРѕРІ Рё РїРѕСЃС‚РѕРІ РЅРµРґРѕСЃС‚СѓРїРЅРѕ.</div>' : ''}

                    <section class="forum-board" aria-label="${escapeHtml(boardTitle)}">
                        <div class="forum-board-head">
                            <div>
                                <div class="forum-board-label">${boardLabel}</div>
                                <div class="forum-board-title">${escapeHtml(boardTitle)}</div>
                            </div>
                            <div class="forum-board-count">${total} С‚СЂРµРґРѕРІ</div>
                        </div>
                        ${threads.length === 0 ? '<div class="forum-empty forum-empty-board">РџРѕРєР° РЅРµС‚ С‚СЂРµРґРѕРІ</div>' : `${pinnedHtml}${regularHtml}`}
                    </section>

                    ${paginationHtml}
                </div>
            `;







            attachThreadListHandlers();



        } catch (err) {



            main.innerHTML = `<div class="forum-error">РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё: ${escapeHtml(err.message)}</div>`;



        }



    }







    function attachThreadListHandlers() {



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



        document.querySelectorAll('.forum-cat-btn').forEach(btn => {



            btn.addEventListener('click', () => {



                const catId = btn.dataset.cat;



                currentCategory = catId ? parseInt(catId) : null;



                currentPage = 0;



                const slug = currentCategory ? (categories.find(c => c.id === currentCategory)?.slug || '') : '';



                window.location.hash = slug ? `category/${slug}` : '/';



            });



        });



        document.querySelectorAll('.forum-page-btn').forEach(btn => {



            btn.addEventListener('click', () => {



                currentPage = parseInt(btn.dataset.page);



                renderThreadList();



                window.scrollTo({ top: 0, behavior: 'smooth' });



            });



        });



        attachUserPopovers();



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



        main.innerHTML = '<div class="forum-loading">Р—Р°РіСЂСѓР·РєР°...</div>';







        try {



            const thread = await Api.getForumThread(currentThreadId);



            if (!thread) {



                main.innerHTML = '<div class="forum-empty">РўСЂРµРґ РЅРµ РЅР°Р№РґРµРЅ</div>';



                return;



            }







            const [posts, pTotal] = await Promise.all([



                Api.getForumThreadPosts(currentThreadId, POSTS_PER_PAGE, postPage * POSTS_PER_PAGE),



                Api.getForumThreadPostsCount(currentThreadId)



            ]);







            threadData = thread;



            postsData = posts;



            postsTotal = pTotal;







            // Resolve @usernames in all post content for mention linking



            await resolvePostMentions([thread, ...posts]);







            const isAuthor = userInfo && userInfo.user_id === thread.author_id;



            const isMod = isModerator();







            let authorInfo = null;



            if (thread.author_id) {



                try { authorInfo = await Api.getPublicProfile(thread.author_id); } catch { authorInfo = null; }



            }



            const authorPhoto = authorInfo && authorInfo.telegram_photo_url



                ? (authorInfo.telegram_photo_url.startsWith('/') ? 'https://t.me' + authorInfo.telegram_photo_url : authorInfo.telegram_photo_url)



                : null;



            const authorHref = thread.author_id ? `profile.html?id=${thread.author_id}` : '#';



            const authorDisplay = {



                name: authorInfo



                    ? cleanText([authorInfo.telegram_first_name, authorInfo.telegram_last_name].filter(Boolean).join(' ') || authorInfo.telegram_username, 50) || 'РђРЅРѕРЅРёРј'



                    : 'РЈРґР°Р»С‘РЅРЅС‹Р№ РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ',



                avatarHtml: authorPhoto



                    ? `<a href="${authorHref}"><img src="${escapeHtml(authorPhoto)}" class="forum-avatar" alt="" onerror="this.style.display='none'"></a>`



                    : `<a href="${authorHref}"><div class="forum-avatar-placeholder"></div></a>`,



                modBadge: authorInfo && authorInfo.is_moderator ? '<span class="forum-mod-badge">MOD</span>' : '',



                roleBadge: authorInfo && authorInfo.role ? getRoleBadgeHtml(authorInfo.role) : '',



                uidBadge: authorInfo && authorInfo.uid != null ? `<span class="forum-uid-badge">UID #${authorInfo.uid}</span>` : '',



                profileLink: thread.author_id



                    ? `<a href="${authorHref}" class="forum-username">${escapeHtml(authorInfo ? cleanText([authorInfo.telegram_first_name, authorInfo.telegram_last_name].filter(Boolean).join(' ') || authorInfo.telegram_username, 50) || 'РђРЅРѕРЅРёРј' : 'РЈРґР°Р»С‘РЅРЅС‹Р№ РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ')}</a>`



                    : '<span class="forum-username">РЈРґР°Р»С‘РЅРЅС‹Р№ РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ</span>'



            };







            const pinBtn = isMod



                ? `<button class="forum-mod-action" id="btn-pin">${thread.is_pinned ? 'РћС‚РєСЂРµРїРёС‚СЊ' : 'Р—Р°РєСЂРµРїРёС‚СЊ'}</button>`



                : '';



            const lockBtn = isMod



                ? `<button class="forum-mod-action" id="btn-lock">${thread.is_locked ? 'Р Р°Р·Р±Р»РѕРєРёСЂРѕРІР°С‚СЊ' : 'Р—Р°Р±Р»РѕРєРёСЂРѕРІР°С‚СЊ'}</button>`



                : '';



            const deleteThreadBtn = isMod



                ? `<button class="forum-mod-action forum-mod-delete" id="btn-delete-thread">РЈРґР°Р»РёС‚СЊ С‚СЂРµРґ</button>`



                : '';



            const editThreadBtn = isAuthor



                ? `<button class="forum-mod-action" id="btn-edit-thread">Р РµРґ.</button>`



                : '';







            const modBar = isMod ? `



                <div class="forum-mod-bar">



                    <span class="forum-mod-label">РњРѕРґРµСЂР°С†РёСЏ:</span>



                    ${pinBtn} ${lockBtn} ${deleteThreadBtn}



                </div>



            ` : '';







            const lockedNotice = thread.is_locked



                ? '<div class="forum-locked-notice">РўСЂРµРґ Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅ. РќРѕРІС‹Рµ РѕС‚РІРµС‚С‹ РЅРµРІРѕР·РјРѕР¶РЅС‹.</div>'



                : '';







            const replyForm = canPost() && !thread.is_locked



                ? `



                    <div class="forum-reply-form">



                        <textarea id="reply-content" placeholder="Р’Р°С€ РѕС‚РІРµС‚..." rows="4" maxlength="10000" class="forum-textarea"></textarea>



                        <div class="forum-reply-actions">



                            <span class="forum-char-count"><span id="reply-char-count">0</span>/10000</span>



                            <button id="btn-reply" class="forum-submit-btn">РћС‚РІРµС‚РёС‚СЊ</button>



                        </div>



                    </div>



                `



                : (!userInfo



                    ? '<div class="forum-login-prompt"><a href="register.html">Р’РѕР№РґРёС‚Рµ</a> С‡С‚РѕР±С‹ РѕС‚РІРµС‡Р°С‚СЊ РІ С‚СЂРµРґР°С…</div>'



                    : (userInfo.is_banned || userInfo.is_muted)



                        ? `<div class="forum-restriction">${userInfo.is_banned ? 'Р’С‹ Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅС‹' : 'Р’С‹ Р·Р°РіР»СѓС€РµРЅС‹'}. РћС‚РїСЂР°РІРєР° СЃРѕРѕР±С‰РµРЅРёР№ РЅРµРґРѕСЃС‚СѓРїРЅР°.</div>`



                        : ''



                );







            let paginationHtml = '';



            const totalPages = Math.ceil(pTotal / POSTS_PER_PAGE);



            if (totalPages > 1) {



                paginationHtml = '<div class="forum-pagination">';



                if (postPage > 0) {



                    paginationHtml += `<button class="forum-page-btn" data-post-page="${postPage - 1}">&larr; РќР°Р·Р°Рґ</button>`;



                }



                paginationHtml += `<span class="forum-page-info">РЎС‚СЂ. ${postPage + 1} / ${totalPages}</span>`;



                if (postPage < totalPages - 1) {



                    paginationHtml += `<button class="forum-page-btn" data-post-page="${postPage + 1}">Р”Р°Р»РµРµ &rarr;</button>`;



                }



                paginationHtml += '</div>';



            }







            main.innerHTML = `



                <div class="forum-breadcrumb">



                    <a href="#/">Р¤РѕСЂСѓРј</a>



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



                                ${thread.is_pinned ? '<span class="forum-pin-icon" title="Р—Р°РєСЂРµРїР»С‘РЅ">&#x1F4CC;</span>' : ''}



                                ${thread.is_locked ? '<span class="forum-lock-icon" title="Р—Р°РєСЂС‹С‚">&#x1F512;</span>' : ''}



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



            main.innerHTML = `<div class="forum-error">РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё: ${escapeHtml(err.message)}</div>`;



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



        const quoteBtn = userInfo ? `<button class="forum-quote-btn" data-post-id="${postId}" title="Р¦РёС‚РёСЂРѕРІР°С‚СЊ">&#10077;</button>` : '';



        html += quoteBtn + '</div>';



        return html;



    }







    function renderPostHtml(p) {



        const author = getUserDisplay(p);



        const isAuthor = userInfo && userInfo.user_id === p.author_id;



        const isMod = isModerator();



        const editedLabel = p.edited_at ? `<span class="forum-edited-label">(СЂРµРґ. ${formatRelativeTime(p.edited_at)})</span>` : '';



        const editBtn = isAuthor ? `<button class="forum-post-action-btn" data-action="edit" data-post-id="${p.id}">Р РµРґ.</button>` : '';



        const deleteBtn = isMod ? `<button class="forum-post-action-btn forum-mod-delete-sm" data-action="delete-post" data-post-id="${p.id}">РЈРґР°Р».</button>` : '';



        const modUserBtn = isMod && p.author_id && p.author_id !== userInfo?.user_id



            ? `<button class="forum-post-action-btn" data-action="mod-user" data-user-id="${p.author_id}">РњРѕРґ.</button>`



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



                replyBtn.textContent = 'РћС‚РїСЂР°РІРєР°...';



                try {



                    const newPostId = await Api.createForumPost(currentThreadId, content);



                    try { Api.checkAndGrantAchievements(); } catch (e) { /* fire-and-forget */ }



                    // Send mention notifications



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



                    replyTextarea.value = '';



                    if (charCount) charCount.textContent = '0';



                    await renderThreadDetail();



                    return;



                } catch (err) {



                    alert('РћС€РёР±РєР°: ' + (err.message || 'РќРµ СѓРґР°Р»РѕСЃСЊ РѕС‚РїСЂР°РІРёС‚СЊ'));



                    replyBtn.disabled = false;



                    replyBtn.textContent = 'РћС‚РІРµС‚РёС‚СЊ';



                }



            });



        }







        const pinBtn = document.getElementById('btn-pin');



        if (pinBtn) {



            pinBtn.addEventListener('click', async () => {



                try {



                    await Api.modPinThread(currentThreadId, !thread.is_pinned);



                    await renderThreadDetail();



                } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



            });



        }







        const lockBtn = document.getElementById('btn-lock');



        if (lockBtn) {



            lockBtn.addEventListener('click', async () => {



                try {



                    await Api.modLockThread(currentThreadId, !thread.is_locked);



                    await renderThreadDetail();



                } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



            });



        }







        const deleteThreadBtn = document.getElementById('btn-delete-thread');



        if (deleteThreadBtn) {



            deleteThreadBtn.addEventListener('click', async () => {



                if (!confirm('РЈРґР°Р»РёС‚СЊ С‚СЂРµРґ?')) return;



                try {



                    await Api.modDeleteThread(currentThreadId);



                    window.location.hash = '/';



                } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



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







        const name = [profile.telegram_first_name, profile.telegram_last_name].filter(Boolean).join(' ') || profile.telegram_username || 'РђРЅРѕРЅРёРј';



        const photo = profile.telegram_photo_url



            ? (profile.telegram_photo_url.startsWith('/') ? 'https://t.me' + profile.telegram_photo_url : profile.telegram_photo_url)



            : null;



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



                <span>${profile.threads_count || 0} С‚СЂРµРґРѕРІ</span>



                <span>${profile.posts_count || 0} РїРѕСЃС‚РѕРІ</span>



            </div>



            <a href="profile.html?id=${userId}" class="forum-popover-link">РћС‚РєСЂС‹С‚СЊ РїСЂРѕС„РёР»СЊ</a>



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



            <h3 class="font-title text-lg uppercase tracking-widest mb-4">Р РµРґР°РєС‚РёСЂРѕРІР°С‚СЊ РїРѕСЃС‚</h3>



            <textarea id="edit-post-content" rows="6" maxlength="10000" class="forum-textarea">${escapeHtml(post.content)}</textarea>



            <div class="forum-modal-actions">



                <button id="btn-save-edit-post" class="forum-submit-btn">РЎРѕС…СЂР°РЅРёС‚СЊ</button>



                <button id="btn-cancel-modal" class="forum-cancel-btn">РћС‚РјРµРЅР°</button>



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



            } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



        });



        document.getElementById('btn-cancel-modal').addEventListener('click', () => overlay.classList.add('hidden'));



    }







    // ========== EDIT THREAD MODAL ==========







    function showEditThreadModal(thread) {



        const overlay = document.getElementById('forum-modal-overlay');



        const modal = document.getElementById('forum-modal');



        if (!overlay || !modal) return;







        modal.innerHTML = `



            <h3 class="font-title text-lg uppercase tracking-widest mb-4">Р РµРґР°РєС‚РёСЂРѕРІР°С‚СЊ С‚СЂРµРґ</h3>



            <input id="edit-thread-title" value="${escapeHtml(thread.title)}" maxlength="200" placeholder="Р—Р°РіРѕР»РѕРІРѕРє" class="forum-input">



            <textarea id="edit-thread-content" rows="6" maxlength="10000" class="forum-textarea">${escapeHtml(thread.content)}</textarea>



            <div class="forum-modal-actions">



                <button id="btn-save-edit-thread" class="forum-submit-btn">РЎРѕС…СЂР°РЅРёС‚СЊ</button>



                <button id="btn-cancel-modal" class="forum-cancel-btn">РћС‚РјРµРЅР°</button>



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



            } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



        });



        document.getElementById('btn-cancel-modal').addEventListener('click', () => overlay.classList.add('hidden'));



    }







    // ========== DELETE POST ==========







    async function handleDeletePost(postId) {



        if (!confirm('РЈРґР°Р»РёС‚СЊ РїРѕСЃС‚?')) return;



        try {



            await Api.modDeletePost(postId);



            await renderThreadDetail();



        } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



    }







    // ========== MOD USER MODAL ==========







    function showModUserModal(userId) {



        const overlay = document.getElementById('forum-modal-overlay');



        const modal = document.getElementById('forum-modal');



        if (!overlay || !modal) return;







        modal.innerHTML = `



            <h3 class="font-title text-lg uppercase tracking-widest mb-4">РњРѕРґРµСЂР°С†РёСЏ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ</h3>



            <div class="forum-mod-user-section">



                <p class="forum-mod-user-label">Р—Р°РіР»СѓС€РёС‚СЊ (Р·Р°РїСЂРµС‚РёС‚СЊ РѕС‚РїСЂР°РІРєСѓ СЃРѕРѕР±С‰РµРЅРёР№)</p>



                <input id="mod-mute-reason" placeholder="РџСЂРёС‡РёРЅР° (РѕРїС†.)" class="forum-input">



                <div class="forum-duration-row">



                    <select id="mod-mute-duration" class="forum-select">



                        <option value="1h">1 С‡Р°СЃ</option>



                        <option value="6h">6 С‡Р°СЃРѕРІ</option>



                        <option value="1d" selected>1 РґРµРЅСЊ</option>



                        <option value="7d">7 РґРЅРµР№</option>



                        <option value="30d">30 РґРЅРµР№</option>



                        <option value="perm">РќР°РІСЃРµРіРґР°</option>



                    </select>



                    <button id="btn-mute-user" class="forum-mod-btn forum-mod-mute">Р—Р°РіР»СѓС€РёС‚СЊ</button>



                </div>



            </div>



            <div class="forum-mod-user-section">



                <p class="forum-mod-user-label">Р—Р°Р±Р»РѕРєРёСЂРѕРІР°С‚СЊ (РїРѕР»РЅС‹Р№ Р±Р°РЅ)</p>



                <input id="mod-ban-reason" placeholder="РџСЂРёС‡РёРЅР° (РѕРїС†.)" class="forum-input">



                <div class="forum-duration-row">



                    <select id="mod-ban-duration" class="forum-select">



                        <option value="1d">1 РґРµРЅСЊ</option>



                        <option value="7d" selected>7 РґРЅРµР№</option>



                        <option value="30d">30 РґРЅРµР№</option>



                        <option value="perm">РќР°РІСЃРµРіРґР°</option>



                    </select>



                    <button id="btn-ban-user" class="forum-mod-btn forum-mod-ban">Р—Р°Р±Р»РѕРєРёСЂРѕРІР°С‚СЊ</button>



                </div>



            </div>



            <div class="forum-mod-user-section">



                <p class="forum-mod-user-label">РЎРЅСЏС‚СЊ РѕРіСЂР°РЅРёС‡РµРЅРёСЏ</p>



                <div class="forum-duration-row">



                    <button id="btn-unmute-user" class="forum-mod-btn forum-mod-unmute">РЎРЅСЏС‚СЊ РјСѓС‚</button>



                    <button id="btn-unban-user" class="forum-mod-btn forum-mod-unban">РЎРЅСЏС‚СЊ Р±Р°РЅ</button>



                </div>



            </div>



            <div class="forum-modal-actions">



                <button id="btn-cancel-modal" class="forum-cancel-btn">Р—Р°РєСЂС‹С‚СЊ</button>



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



                if (!r) { alert('РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РіР»СѓС€РёС‚СЊ'); return; }



                alert('РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ Р·Р°РіР»СѓС€РµРЅ');



                overlay.classList.add('hidden');



            } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



        });







        document.getElementById('btn-ban-user').addEventListener('click', async () => {



            const reason = document.getElementById('mod-ban-reason').value.trim();



            const duration = document.getElementById('mod-ban-duration').value;



            if (!confirm('Р—Р°Р±Р»РѕРєРёСЂРѕРІР°С‚СЊ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ?')) return;



            try {



                const r = await Api.modBanUser(userId, reason, calcExpiry(duration));



                if (!r) { alert('РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°Р±Р»РѕРєРёСЂРѕРІР°С‚СЊ'); return; }



                alert('РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅ');



                overlay.classList.add('hidden');



            } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



        });







        document.getElementById('btn-unmute-user').addEventListener('click', async () => {



            try {



                await Api.modUnmuteUser(userId);



                alert('РњСѓС‚ СЃРЅСЏС‚');



                overlay.classList.add('hidden');



            } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



        });







        document.getElementById('btn-unban-user').addEventListener('click', async () => {



            try {



                await Api.modUnbanUser(userId);



                alert('Р‘Р°РЅ СЃРЅСЏС‚');



                overlay.classList.add('hidden');



            } catch (err) { alert('РћС€РёР±РєР°: ' + err.message); }



        });







        document.getElementById('btn-cancel-modal').addEventListener('click', () => overlay.classList.add('hidden'));



    }







    // ========== NEW THREAD FORM ==========







    function renderNewThreadForm() {



        const main = document.getElementById('forum-main');



        if (!main) return;







        if (!canPost()) {



            main.innerHTML = `



                <div class="forum-breadcrumb"><a href="#/">Р¤РѕСЂСѓРј</a> &rsaquo; РќРѕРІС‹Р№ С‚СЂРµРґ</div>



                <div class="forum-empty">${!userInfo ? '<a href="register.html">Р’РѕР№РґРёС‚Рµ</a> С‡С‚РѕР±С‹ СЃРѕР·РґР°РІР°С‚СЊ С‚СЂРµРґС‹' : 'РЈ РІР°СЃ РЅРµС‚ РїСЂР°РІ РґР»СЏ СЃРѕР·РґР°РЅРёСЏ С‚СЂРµРґРѕРІ'}</div>



            `;



            return;



        }







        main.innerHTML = `



            <div class="forum-breadcrumb"><a href="#/">Р¤РѕСЂСѓРј</a> &rsaquo; РќРѕРІС‹Р№ С‚СЂРµРґ</div>



            <div class="forum-new-thread-form">



                <h2 class="font-title text-xl uppercase tracking-widest text-shiny mb-6">РќРѕРІС‹Р№ С‚СЂРµРґ</h2>



                <label class="forum-form-label">



                    РљР°С‚РµРіРѕСЂРёСЏ



                    <select id="new-thread-category" class="forum-select">



                        ${categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('')}



                    </select>



                </label>



                <label class="forum-form-label">



                    Р—Р°РіРѕР»РѕРІРѕРє <span class="forum-char-hint"><span id="title-char-count">0</span>/200</span>



                    <input id="new-thread-title" maxlength="200" placeholder="РўРµРјР° РѕР±СЃСѓР¶РґРµРЅРёСЏ" class="forum-input">



                </label>



                <label class="forum-form-label">



                    РЎРѕРґРµСЂР¶Р°РЅРёРµ <span class="forum-char-hint"><span id="content-char-count">0</span>/10000</span>



                    <textarea id="new-thread-content" rows="8" maxlength="10000" placeholder="РћРїРёС€РёС‚Рµ С‚РµРјСѓ..." class="forum-textarea"></textarea>



                </label>



                <div class="forum-form-actions">



                    <button id="btn-create-thread" class="forum-submit-btn">РЎРѕР·РґР°С‚СЊ С‚СЂРµРґ</button>



                    <a href="#/" class="forum-cancel-btn">РћС‚РјРµРЅР°</a>



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



            if (!title || title.length < 3) { alert('Р—Р°РіРѕР»РѕРІРѕРє РјРёРЅРёРјСѓРј 3 СЃРёРјРІРѕР»Р°'); return; }



            if (!content) { alert('Р’РІРµРґРёС‚Рµ СЃРѕРґРµСЂР¶Р°РЅРёРµ'); return; }







            const btn = document.getElementById('btn-create-thread');



            btn.disabled = true;



            btn.textContent = 'РЎРѕР·РґР°РЅРёРµ...';



            try {



                const threadId = await Api.createForumThread(categoryId, title, content);



                try { Api.checkAndGrantAchievements(); } catch (e) { /* fire-and-forget */ }



                window.location.hash = `thread/${threadId}`;



            } catch (err) {



                alert('РћС€РёР±РєР°: ' + (err.message || 'РќРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ С‚СЂРµРґ'));



                btn.disabled = false;



                btn.textContent = 'РЎРѕР·РґР°С‚СЊ С‚СЂРµРґ';



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
