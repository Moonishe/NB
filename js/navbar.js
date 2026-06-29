(function() {

    // safeDisplayName provided by profile-utils.js


    // getProfileBasePath provided by profile-utils.js

    // getProfileHref provided by profile-utils.js

    // sanitizeTelegramPhotoUrl provided by profile-utils.js

    const page = location.pathname.split('/').pop() || 'index.html';
    const isIndex = page === 'index.html' || page === '' || page === '/';
    const isForum = page === 'forum.html' || page === 'forum';
    const aboutHref = isIndex ? '#about' : './#about';
    const forumHref = 'forum';
    const logoHref = isIndex ? '#' : './';
    const isLocal = window.isLocalhost ? window.isLocalhost() : false;

    function getSupabaseAuthStorageKey() {
        const url = window.SUPABASE_URL || '';
        if (!url) return null;
        try {
            const projectRef = new URL(url).hostname.split('.')[0];
            return projectRef ? `sb-${projectRef}-auth-token` : null;
        } catch (_) {
            return null;
        }
    }

    const lbItems = [
        { href: 'svg',    label: '&lt;/&gt; SVG' },
        { href: 'voxel',  label: '[▦] Voxel' },
        { href: 'shader', label: '{◈} Shader' },
    ];

    function lbLinkClass(href) {
        const active = page === href;
        return `nav-scramble block text-[10px] uppercase tracking-[0.15em] font-bold px-3 py-2 ${active ? 'opacity-100' : 'opacity-50 hover:opacity-100'} hover:bg-white/5 transition-all`;
    }

    function mobileLbClass(href) {
        const active = page === href;
        return `mobile-nav-link nav-scramble text-[10px] uppercase tracking-[0.15em] font-bold ${active ? 'opacity-100' : 'opacity-40 hover:opacity-100 transition-opacity'} block py-1`;
    }

    const supabaseAuthStorageKey = getSupabaseAuthStorageKey();
    const hasSession = !!((isLocal && localStorage.getItem('nb_dev_session')) || localStorage.getItem('neurobench-auth') || (supabaseAuthStorageKey && localStorage.getItem(supabaseAuthStorageKey)));

    const html = `
    <nav class="fixed top-8 w-full z-[100] px-4 md:px-6 font-sans" id="main-navbar">
        <div class="max-w-4xl mx-auto nav-pill flex justify-between items-center p-2">
            <a href="${logoHref}" class="flex items-center gap-3 pl-4" style="text-decoration:none;color:inherit;">
                <img src="logo.png" alt="NeuroBench" class="w-8 h-8 rounded-lg object-contain">
                <span class="font-bold tracking-tighter text-lg uppercase">NeuroBench</span>
            </a>
            <div class="hidden md:flex items-center gap-8 -ml-4">
                <a href="${aboutHref}" class="nav-link nav-scramble text-[10px] uppercase tracking-[0.2em] font-bold opacity-30 hover:opacity-100 transition-opacity">О проекте</a>
                <div class="relative" id="leaderboard-nav-wrap">
                    <button id="leaderboard-nav-btn" class="nav-link text-[10px] uppercase tracking-[0.2em] font-bold opacity-30 hover:opacity-100 transition-opacity flex items-center gap-1" type="button" aria-haspopup="true" aria-expanded="false">Лидерборд <span class="text-[8px]">▾</span></button>
                    <div id="leaderboard-nav-dropdown" class="hidden absolute left-0 top-full mt-2 nav-dropdown p-2 z-[200] min-w-[160px] flex-col gap-0.5">
                        ${lbItems.map(i => `<a href="${i.href}" class="${lbLinkClass(i.href)}">${i.label}</a>`).join('\n                        ')}
                    </div>
                </div>
                <a href="${forumHref}" class="nav-link nav-scramble text-[10px] uppercase tracking-[0.2em] font-bold ${isForum ? 'opacity-100' : 'opacity-30 hover:opacity-100'} transition-opacity">Форум</a>
                <a href="auth" id="nav-auth-link" class="nav-link nav-scramble text-[10px] uppercase tracking-[0.2em] font-bold opacity-30 hover:opacity-100 transition-opacity" style="${hasSession ? 'display:none' : ''}">Войти</a>
            </div>
            <div id="nav-actions" class="flex items-center gap-2">
                <a href="admin/index.html" id="nav-admin-shortcut" class="hidden nav-admin-shortcut" aria-label="Админка" title="Админка">A</a>
                <div id="nav-notif-wrap" class="${hasSession ? 'relative' : 'hidden relative'}">
                    <button id="nav-notif-btn" class="flex items-center justify-center w-10 h-10 opacity-40 hover:opacity-100 transition-opacity" aria-label="Уведомления">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
                        <span id="nav-notif-badge" class="notif-badge hidden">0</span>
                    </button>
                </div>
                <div id="nav-user-menu" class="${hasSession ? 'relative' : 'hidden relative'}">
                    <button id="nav-user-btn" class="flex items-center justify-center w-10 h-10 opacity-40 hover:opacity-100 transition-opacity" aria-label="Аккаунт">
                        <img id="nav-user-photo" src="" alt="" class="hidden w-6 h-6 rounded object-cover">
                        <svg id="nav-user-icon" class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                    </button>
                </div>
                <button id="mobile-menu-btn" class="md:hidden flex items-center justify-center w-10 h-10 opacity-40 hover:opacity-100 transition-opacity" aria-label="Меню" aria-controls="mobile-menu" aria-expanded="false" type="button">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path id="menu-icon-open" d="M4 6h16M4 12h16M4 18h16"/><path id="menu-icon-close" d="M6 6l12 12M6 18L18 6" class="hidden"/></svg>
                </button>
            </div>
        </div>
        <div id="mobile-menu" class="md:hidden max-w-4xl mx-auto mt-2 nav-pill p-4 hidden flex-col gap-4">
            <a href="${aboutHref}" class="mobile-nav-link nav-scramble text-[10px] uppercase tracking-[0.2em] font-bold opacity-30 hover:opacity-100 transition-opacity block py-2">О проекте</a>
            <div class="py-2">
                <p class="text-[10px] uppercase tracking-[0.2em] font-bold opacity-30 mb-2">Лидерборд</p>
                <div class="flex flex-col gap-1 pl-3">
                    ${lbItems.map(i => `<a href="${i.href}" class="${mobileLbClass(i.href)}">${i.label}</a>`).join('\n                    ')}
                </div>
            </div>
            <a href="${forumHref}" class="mobile-nav-link nav-scramble text-[10px] uppercase tracking-[0.2em] font-bold ${isForum ? 'opacity-100' : 'opacity-30 hover:opacity-100'} transition-opacity block py-2">Форум</a>
            <a href="auth" id="mobile-nav-auth-link" class="mobile-nav-link nav-scramble text-[10px] uppercase tracking-[0.2em] font-bold opacity-30 hover:opacity-100 transition-opacity block py-2" style="${hasSession ? 'display:none' : ''}">Войти</a>
        </div>
    </nav>`;

    const placeholder = document.getElementById('navbar-placeholder');
    if (placeholder) {
        placeholder.outerHTML = html;
    } else {
        document.body.insertAdjacentHTML('afterbegin', html);
    }

    // --- Nav link scramble animation ---
    document.querySelectorAll('.nav-scramble').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const href = this.getAttribute('href');
            const target = this.textContent.trim();
            const el = this;
            asciiDecode(el, target, 550);
            setTimeout(() => { window.location.href = href; }, 610);
        });
    });

    // --- Logo title click animation ---
    const logoLink = document.querySelector('#main-navbar a.flex.items-center.gap-3');
    const logoTitle = logoLink ? logoLink.querySelector('.font-bold.tracking-tighter') : null;
    if (logoLink && logoTitle) {
        const originalText = logoTitle.textContent;
        let logoAnimating = false;
        logoLink.addEventListener('click', function(e) {
            e.preventDefault();
            if (logoAnimating) return;
            logoAnimating = true;
            const href = this.getAttribute('href');
            const el = logoTitle;
            const len = originalText.length;
            const totalFrames = 14;
            let frame = 0;

            function glitchStep() {
                // intensity curve: peaks at middle, fades at edges
                const t = frame / totalFrames; // 0..1
                const intensity = Math.sin(t * Math.PI); // 0→1→0

                // scramble text — more chars scrambled at peak intensity
                let out = '';
                const revealCount = Math.floor((1 - intensity) * len);
                for (let i = 0; i < len; i++) {
                    if (i < revealCount) {
                        out += originalText[i];
                    } else {
                        out += asciiGlyphs[Math.floor(Math.random() * asciiGlyphs.length)];
                    }
                }
                el.textContent = out;

                // white glow on peak
                el.style.textShadow = `0 0 ${Math.round(intensity * 8)}px rgba(255,255,255,${intensity * 0.3})`;

                // horizontal shake
                const shakeX = Math.round((Math.random() - 0.5) * intensity * 6);
                el.style.transform = `translateX(${shakeX}px) scale(${1 + intensity * 0.08})`;

                frame++;
                if (frame < totalFrames) {
                    requestAnimationFrame(glitchStep);
                } else {
                    // clean up styles, then asciiDecode
                    el.style.textShadow = '';
                    el.style.transform = '';
                    asciiDecode(el, originalText, 450);
                    setTimeout(() => { logoAnimating = false; }, 500);
                }
            }
            requestAnimationFrame(glitchStep);
            // navigate after full animation
            if (href) setTimeout(() => { window.location.href = href; }, 1100);
        });
    }

    // --- Leaderboard dropdown toggle ---
    const lbBtn = document.getElementById('leaderboard-nav-btn');
    const lbDrop = document.getElementById('leaderboard-nav-dropdown');
    const lbWrap = document.getElementById('leaderboard-nav-wrap');
    if (lbBtn && lbDrop && lbWrap) {
        lbBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            var isHidden = lbDrop.classList.toggle('hidden');
            if (!isHidden) lbDrop.classList.add('flex');
            else lbDrop.classList.remove('flex');
            lbBtn.setAttribute('aria-expanded', isHidden ? 'false' : 'true');
        });
        document.addEventListener('click', function(e) {
            if (!lbWrap.contains(e.target)) {
                lbDrop.classList.add('hidden');
                lbDrop.classList.remove('flex');
                lbBtn.setAttribute('aria-expanded', 'false');
            }
        });
        document.addEventListener('keydown', function(e) {
            if (e.key !== 'Escape' || lbDrop.classList.contains('hidden')) return;
            lbDrop.classList.add('hidden');
            lbDrop.classList.remove('flex');
            lbBtn.setAttribute('aria-expanded', 'false');
            lbBtn.focus({ preventScroll: true });
        });
    }

    // --- Mobile menu toggle ---
    const mobileBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    const iconOpen = document.getElementById('menu-icon-open');
    const iconClose = document.getElementById('menu-icon-close');
    if (mobileBtn && mobileMenu) {
        mobileBtn.addEventListener('click', function() {
            toggleMobileMenu(mobileMenu.classList.contains('hidden'));
        });
        mobileMenu.querySelectorAll('a[href]').forEach(link => {
            link.addEventListener('click', function() {
                toggleMobileMenu(false);
            });
        });
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape' && !mobileMenu.classList.contains('hidden')) {
                toggleMobileMenu(false);
                mobileBtn.focus({ preventScroll: true });
            }
        });
        document.addEventListener('click', function(e) {
            if (mobileMenu.classList.contains('hidden')) return;
            if (mobileBtn.contains(e.target) || mobileMenu.contains(e.target)) return;
            toggleMobileMenu(false);
        });
    }

    function toggleMobileMenu(shouldOpen) {
        if (!mobileBtn || !mobileMenu) return;
        mobileMenu.classList.toggle('hidden', !shouldOpen);
        mobileMenu.classList.toggle('flex', shouldOpen);
        mobileBtn.setAttribute('aria-expanded', shouldOpen ? 'true' : 'false');
        if (iconOpen) iconOpen.classList.toggle('hidden', shouldOpen);
        if (iconClose) iconClose.classList.toggle('hidden', !shouldOpen);
    }

    // --- User dropdown (ASCII style) ---
    const userBtn = document.getElementById('nav-user-btn');
    const userMenuWrap = document.getElementById('nav-user-menu');
    let dropdownEl = null;
    let dropdownOpen = false;
    const asciiGlyphs = '░▒▓█▀▄▌▐│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬';

    function createDropdown() {
        // FIX: info не существует в этом scope — берём uid из dataset кнопки
        const uid = (userBtn && userBtn.dataset.uid) ? userBtn.dataset.uid : '';
        const profileHref = uid ? window.getProfileHref(uid) : 'auth';
        const el = document.createElement('div');
        el.id = 'nav-user-dropdown';
        el.className = 'nav-user-dropdown-float';
        el.innerHTML = `
            <div class="nav-user-menu-card">
                <div class="nav-user-menu-ascii-border"></div>
                <p id="nav-user-display" class="nav-user-menu-name"></p>
                <div class="nav-user-menu-divider"></div>
                <a href="${profileHref}" class="nav-user-menu-item" id="nav-dropdown-profile">
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                    <span class="nav-item-text" data-text="Аккаунт"></span>
                </a>
                <a href="admin/index.html" class="nav-user-menu-item" id="nav-dropdown-admin" style="display:none">
                    <span style="font-size:14px">👑</span>
                    <span class="nav-item-text" data-text="Admin"></span>
                </a>
                <button id="nav-user-logout" class="nav-user-menu-item nav-user-menu-logout">
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
                    <span class="nav-item-text" data-text="Выйти"></span>
                </button>
            </div>`;
        document.body.appendChild(el);
        return el;
    }

    function asciiDecode(el, target, duration) {
        const len = target.length;
        const t0 = performance.now();
        const dur = duration || 400;
        const frozen = new Uint8Array(len);
        function step(now) {
            const t = Math.min((now - t0) / dur, 1);
            const reveal = Math.floor(t * len);
            let out = '';
            for (let i = 0; i < len; i++) {
                if (i < reveal || frozen[i]) {
                    frozen[i] = 1;
                    out += target[i];
                } else {
                    out += asciiGlyphs[Math.floor(Math.random() * asciiGlyphs.length)];
                }
            }
            el.textContent = out;
            if (t < 1) requestAnimationFrame(step);
            else el.textContent = target;
        }
        requestAnimationFrame(step);
    }

    function openDropdown() {
        if (dropdownOpen) return;
        dropdownOpen = true;
        if (!dropdownEl) dropdownEl = createDropdown();

        // FIX: обновляем href ссылки на профиль при каждом открытии —
        // при первом создании uid мог ещё не быть загружен из API
        const profileLink = dropdownEl.querySelector('#nav-dropdown-profile');
        if (profileLink && userBtn && userBtn.dataset.uid) {
            profileLink.href = window.getProfileHref(userBtn.dataset.uid);
        }

        const anchor = document.getElementById('nav-actions') || userBtn;
        const rect = anchor.getBoundingClientRect();
        dropdownEl.style.top = (rect.bottom + 4) + 'px';
        dropdownEl.style.right = (window.innerWidth - rect.right) + 'px';
        dropdownEl.classList.remove('open');
        void dropdownEl.offsetWidth;
        requestAnimationFrame(() => dropdownEl.classList.add('open'));

        const displayEl = dropdownEl.querySelector('#nav-user-display');
        const name = userBtn.dataset.displayName || '';
        if (displayEl && name) {
            displayEl.textContent = '';
            asciiDecode(displayEl, name, 300);
        }

        dropdownEl.querySelectorAll('.nav-item-text').forEach((span, i) => {
            const target = span.dataset.text;
            span.textContent = '';
            setTimeout(() => asciiDecode(span, target, 250), 80 + i * 100);
        });

        setTimeout(() => {
            document.removeEventListener('click', outsideClick);
            document.addEventListener('click', outsideClick);
        }, 10);
    }

    function closeDropdown() {
        if (!dropdownOpen || !dropdownEl) return;
        dropdownOpen = false;
        dropdownEl.classList.remove('open');
        document.removeEventListener('click', outsideClick);
    }

    function outsideClick(e) {
        if (dropdownEl && !dropdownEl.contains(e.target) && !userBtn.contains(e.target)) {
            closeDropdown();
        }
    }

    if (userBtn) {
        userBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            userBtn.classList.remove('profile-anim');
            void userBtn.offsetWidth;
            userBtn.classList.add('profile-anim');
            userBtn.addEventListener('animationend', () => userBtn.classList.remove('profile-anim'), { once: true });
            dropdownOpen ? closeDropdown() : openDropdown();
        });
    }

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && dropdownOpen) closeDropdown();
    });

    // --- User menu init (works on all pages) ---
    const authLink = document.getElementById('nav-auth-link');
    const mobileAuthLink = document.getElementById('mobile-nav-auth-link');

    function setDisplayName(name) {
        if (userBtn) userBtn.dataset.displayName = name;
    }

    function showUserMenu(name, role, uid) {
        if (authLink) authLink.classList.add('hidden');
        if (mobileAuthLink) mobileAuthLink.classList.add('hidden');
        if (userMenuWrap) userMenuWrap.classList.remove('hidden');
        const notifWrap = document.getElementById('nav-notif-wrap');
        if (notifWrap) notifWrap.classList.remove('hidden');
        const adminShortcut = document.getElementById('nav-admin-shortcut');
        if (adminShortcut) adminShortcut.classList.toggle('hidden', role !== 'admin');
        setDisplayName(name);
        // FIX: сохраняем uid в dataset кнопки, чтобы createDropdown мог его использовать
        if (uid && userBtn) userBtn.dataset.uid = String(uid);
        if (userBtn) userBtn.dataset.role = role || '';
        if (role === 'admin') {
            const adminLink = document.getElementById('nav-dropdown-admin');
            if (adminLink) adminLink.style.display = '';
        }
        initNotifications();
    }

    function hideUserMenu() {
        if (userMenuWrap) userMenuWrap.classList.add('hidden');
        const notifWrap = document.getElementById('nav-notif-wrap');
        if (notifWrap) notifWrap.classList.add('hidden');
        if (authLink) { authLink.classList.remove('hidden'); authLink.style.display = ''; }
        if (mobileAuthLink) { mobileAuthLink.classList.remove('hidden'); mobileAuthLink.style.display = ''; }
        const adminShortcut = document.getElementById('nav-admin-shortcut');
        if (adminShortcut) adminShortcut.classList.add('hidden');
    }

    async function initUser() {
        if (isLocal) {
            const devRaw = localStorage.getItem('nb_dev_session');
            if (devRaw) {
                try {
                    const dev = JSON.parse(devRaw);
                    const name = window.safeDisplayName(dev) || 'Dev';
                    showUserMenu(name, dev.role, dev.uid);
                    return;
                } catch {}
            }
        }

        if (typeof Api === 'undefined' || !Api.getSession) return;
        try {
            const session = await Api.getSession();
            if (!session) { hideUserMenu(); return; }
            const info = await Api.getUserDisplayName();
            if (!info) return;
            const name = window.safeDisplayName(info) || 'User';
            // FIX: передаём uid чтобы createDropdown мог построить ссылку на профиль
            showUserMenu(name, info.role, info.uid);

            if (info.telegram_photo_url) {
                const photoEl = document.getElementById('nav-user-photo');
                const iconEl = document.getElementById('nav-user-icon');
                if (photoEl) {
                    const url = window.sanitizeTelegramPhotoUrl(info.telegram_photo_url);
                    if (url) {
                        photoEl.src = url;
                        photoEl.classList.remove('hidden');
                    }
                    photoEl.onerror = () => { photoEl.classList.add('hidden'); if (iconEl) iconEl.classList.remove('hidden'); };
                }
                if (iconEl && photoEl) iconEl.classList.add('hidden');
            }
        } catch {}
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initUser);
    } else {
        setTimeout(initUser, 0);
    }

    document.addEventListener('click', (e) => {
        const btn = e.target.closest('#nav-user-logout');
        if (!btn) return;
        localStorage.removeItem('nb_dev_session');
        if (typeof Api !== 'undefined' && Api.logout) {
            Api.logout().then(() => { location.href = './'; });
        } else {
            location.href = './';
        }
    });

    // ========== NOTIFICATIONS ==========

    let notifDropEl = null;
    let notifDropOpen = false;
    let notifPollTimer = null;
    let notifInitialized = false;

    function initNotifications() {
        if (typeof Api === 'undefined' || !Api.getUnreadCount) return;
        if (notifInitialized) {
            fetchUnreadCount();
            return;
        }
        notifInitialized = true;
        fetchUnreadCount();
        if (!notifPollTimer) notifPollTimer = setInterval(fetchUnreadCount, 60000);

        const notifBtn = document.getElementById('nav-notif-btn');
        if (notifBtn) {
            notifBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                notifBtn.classList.remove('bell-anim');
                void notifBtn.offsetWidth;
                notifBtn.classList.add('bell-anim');
                notifBtn.addEventListener('animationend', () => notifBtn.classList.remove('bell-anim'), { once: true });
                notifDropOpen ? closeNotifDrop() : openNotifDrop();
            });
        }
    }

    async function fetchUnreadCount() {
        if (typeof Api === 'undefined' || !Api.getUnreadCount) return;
        try {
            const count = await Api.getUnreadCount();
            const badge = document.getElementById('nav-notif-badge');
            if (!badge) return;
            if (count > 0) {
                badge.textContent = count > 99 ? '99+' : count;
                badge.classList.remove('hidden');
            } else {
                badge.classList.add('hidden');
            }
        } catch {}
    }

    function createNotifDrop() {
        const el = document.createElement('div');
        el.id = 'nav-notif-dropdown';
        el.className = 'notif-dropdown';
        document.body.appendChild(el);
        return el;
    }

    async function openNotifDrop() {
        if (notifDropOpen) return;
        notifDropOpen = true;
        if (!notifDropEl) notifDropEl = createNotifDrop();

        const notifBtn = document.getElementById('nav-notif-btn');
        if (notifBtn) {
            const anchor = document.getElementById('nav-actions') || notifBtn;
            const rect = anchor.getBoundingClientRect();
            notifDropEl.style.top = (rect.bottom + 4) + 'px';
            notifDropEl.style.right = (window.innerWidth - rect.right) + 'px';
        }
        notifDropEl.innerHTML = '<div class="nav-user-menu-card notif-menu-card"><div class="nav-user-menu-ascii-border"></div><p class="nav-user-menu-name">Уведомления</p><div class="nav-user-menu-divider"></div><div class="notif-loading">Загрузка...</div></div>';
        notifDropEl.classList.remove('open');
        void notifDropEl.offsetWidth;
        requestAnimationFrame(() => notifDropEl.classList.add('open'));

        const notifTitleEl = notifDropEl.querySelector('.nav-user-menu-name');
        if (notifTitleEl) {
            const titleText = notifTitleEl.textContent;
            notifTitleEl.textContent = '';
            asciiDecode(notifTitleEl, titleText, 300);
        }

        setTimeout(() => {
            document.removeEventListener('click', outsideNotifClick);
            document.addEventListener('click', outsideNotifClick);
        }, 10);

        if (typeof Api === 'undefined' || !Api.getMyNotifications) return;
        try {
            const notifs = await Api.getMyNotifications(15);
            renderNotifList(notifs);
        } catch {
            notifDropEl.innerHTML = '<div class="nav-user-menu-card notif-menu-card"><div class="nav-user-menu-ascii-border"></div><p class="nav-user-menu-name">Уведомления</p><div class="nav-user-menu-divider"></div><div class="notif-empty">Ошибка загрузки</div></div>';
            const t2 = notifDropEl.querySelector('.nav-user-menu-name');
            if (t2) { const t2t = t2.textContent; t2.textContent = ''; asciiDecode(t2, t2t, 300); }
            const e2 = notifDropEl.querySelector('.notif-empty');
            if (e2) { const e2t = e2.textContent; e2.textContent = ''; asciiDecode(e2, e2t, 250); }
        }
    }

    function closeNotifDrop() {
        if (!notifDropOpen || !notifDropEl) return;
        notifDropOpen = false;
        notifDropEl.classList.remove('open');
        document.removeEventListener('click', outsideNotifClick);
    }

    function outsideNotifClick(e) {
        if (notifDropEl && !notifDropEl.contains(e.target) && !document.getElementById('nav-notif-btn')?.contains(e.target)) {
            closeNotifDrop();
        }
    }

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && notifDropOpen) closeNotifDrop();
    });

    const NOTIF_EMOJI_MAP = {
        like: '\uD83D\uDC4D', dislike: '\uD83D\uDC4E', fire: '\uD83D\uDD25',
        puke: '\uD83E\uDD2E', brain: '\uD83E\uDDE0', emotion: '\uD83D\uDE02',
        admin_like: '\uD83D\uDC51'
    };

    function renderNotifList(notifs) {
        if (!notifDropEl) return;
        if (!notifs || notifs.length === 0) {
            notifDropEl.innerHTML = '<div class="nav-user-menu-card notif-menu-card"><div class="nav-user-menu-ascii-border"></div><p class="nav-user-menu-name">Уведомления</p><div class="nav-user-menu-divider"></div><div class="notif-empty">Нет уведомлений</div></div>';
            const t3 = notifDropEl.querySelector('.nav-user-menu-name');
            if (t3) { const t3t = t3.textContent; t3.textContent = ''; asciiDecode(t3, t3t, 300); }
            const e3 = notifDropEl.querySelector('.notif-empty');
            if (e3) { const e3t = e3.textContent; e3.textContent = ''; asciiDecode(e3, e3t, 250); }
            return;
        }
        let html = '<div class="notif-list">';
        notifs.forEach(n => {
            const unread = n.is_read ? '' : ' notif-unread';
            const name = n.from_first_name || n.from_username || 'Кто-то';
            const photo = n.from_photo_url
                ? (n.from_photo_url.startsWith('/') ? 'https://t.me' + n.from_photo_url : n.from_photo_url)
                : null;
            const safePhoto = photo ? escAttr(photo) : null;
            const avatarHtml = safePhoto
                ? `<img src="${safePhoto}" class="notif-avatar" alt="" onerror="this.style.display='none'">`
                : '<div class="notif-avatar-ph"></div>';
            let text = '';
            if (n.type === 'reaction') {
                const emojiIcon = NOTIF_EMOJI_MAP[n.emoji] || n.emoji || '';
                text = `<strong>${esc(name)}</strong> ${esc(emojiIcon)} на ваш пост`;
            } else if (n.type === 'mention') {
                text = `<strong>${esc(name)}</strong> упомянул вас`;
            } else if (n.type === 'reply') {
                text = `<strong>${esc(name)}</strong> ответил в треде`;
            }
            if (n.snippet) text += `<span class="notif-snippet">${esc(n.snippet.slice(0, 60))}</span>`;
            const time = formatNotifTime(n.created_at);
            const href = n.ref_thread_id ? `forum#thread/${encodeURIComponent(String(n.ref_thread_id))}` : '#';
            html += `<a href="${href}" class="notif-item${unread}">
                ${avatarHtml}
                <div class="notif-body">
                    <div class="notif-text">${text}</div>
                    <div class="notif-time">${time}</div>
                </div>
            </a>`;
        });
        html += '</div>';
        html += '<button id="notif-mark-all" class="notif-mark-all">Прочитать все</button>';
        notifDropEl.innerHTML = '<div class="nav-user-menu-card notif-menu-card"><div class="nav-user-menu-ascii-border"></div><p class="nav-user-menu-name">Уведомления</p><div class="nav-user-menu-divider"></div>' + html + '</div>';

        const notifTitle = notifDropEl.querySelector('.nav-user-menu-name');
        if (notifTitle) { const tt = notifTitle.textContent; notifTitle.textContent = ''; asciiDecode(notifTitle, tt, 300); }

        notifDropEl.querySelectorAll('.notif-text').forEach((el, i) => {
            const text = el.textContent;
            el.textContent = '';
            setTimeout(() => asciiDecode(el, text, 250), i * 40);
        });
        notifDropEl.querySelectorAll('.notif-time').forEach((el, i) => {
            const text = el.textContent;
            el.textContent = '';
            setTimeout(() => asciiDecode(el, text, 200), i * 40 + 60);
        });

        const markBtn = document.getElementById('notif-mark-all');
        if (markBtn) {
            const markText = markBtn.textContent;
            markBtn.textContent = '';
            setTimeout(() => asciiDecode(markBtn, markText, 200), notifs.length * 40 + 100);
            markBtn.addEventListener('click', async (e) => {
                e.stopPropagation();
                if (typeof Api !== 'undefined' && Api.markNotificationsRead) {
                    await Api.markNotificationsRead();
                    const badge = document.getElementById('nav-notif-badge');
                    if (badge) badge.classList.add('hidden');
                    notifDropEl.querySelectorAll('.notif-unread').forEach(el => el.classList.remove('notif-unread'));
                }
            });
        }
    }

    function esc(s) {
        if (!s) return '';
        const d = document.createElement('div');
        d.textContent = s;
        return d.innerHTML;
    }

    function escAttr(s) {
        return esc(s).replace(/"/g, '&quot;');
    }

    function formatNotifTime(dateVal) {
        if (!dateVal) return '';
        const d = new Date(dateVal);
        const now = new Date();
        const diff = Math.floor((now - d) / 1000);
        if (diff < 60) return 'только что';
        if (diff < 3600) return Math.floor(diff / 60) + ' мин';
        if (diff < 86400) return Math.floor(diff / 3600) + ' ч';
        return Math.floor(diff / 86400) + ' дн';
    }
})();
