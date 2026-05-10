const AuthApp = (() => {

    let inviteCode = '';


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


    let isProcessing = false;

    let authMode = 'login';
    let turnstileToken = '';

    const _DANGEROUS_RE = /[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]/g;

    function safeDisplayName(info) {

        if (!info) return 'User';

        const raw = [info.telegram_first_name, info.telegram_last_name].filter(Boolean).join(' ').trim();

        if (raw) {

            const clean = raw.replace(_DANGEROUS_RE, '').replace(/\s+/g, ' ').trim();

            if (clean.length > 0) return clean;

        }

        if (info.telegram_username) return info.telegram_username;

        if (info.display_name) {

            const cleanDn = info.display_name.replace(_DANGEROUS_RE, '').replace(/\s+/g, ' ').trim();

            if (cleanDn.length > 0) return cleanDn;

        }

        return 'User';

    }



    function showError(id, msg) {

        const el = document.getElementById(id);

        if (el) {
            el.textContent = msg;
            el.classList.remove('hidden');
            el.classList.toggle('auth-error-card', id === 'auth-error');
        }

    }



    function hideError(id) {

        const el = document.getElementById(id);

        if (el) {
            el.classList.add('hidden');
            el.classList.remove('auth-error-card');
        }

    }



    function showEl(id) {

        const el = document.getElementById(id);

        if (el) el.classList.remove('hidden');

    }



    function hideEl(id) {

        const el = document.getElementById(id);

        if (el) el.classList.add('hidden');

    }



    function setText(id, text) {

        const el = document.getElementById(id);

        if (el) el.textContent = text;

    }



    const SUCCESS_BADGE_HTML = '<svg class="success-checkmark-svg" viewBox="0 0 16 16" fill="none"><path d="M3 8.5l3.5 3.5 6.5-7" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg><span data-decode-text="Регистрация завершена">Регистрация завершена</span>';



    function showSuccessBadge() {

        const badge = document.getElementById('new-user-badge');

        if (!badge) return;

        badge.innerHTML = SUCCESS_BADGE_HTML;

        badge.classList.remove('hidden');

        const text = badge.querySelector('[data-decode-text]');

        if (text) requestAnimationFrame(() => decodeText(text, text.dataset.decodeText));

    }



    // ASCII block font for invite codes (5 rows, 5 cols per char)

    const _GLYPH = {

        'A':[' ███ ','█   █','█████','█   █','█   █'],

        'B':['████ ','█   █','████ ','█   █','████ '],

        'C':[' ████','█    ','█    ','█    ',' ████'],

        'D':['████ ','█   █','█   █','█   █','████ '],

        'E':['█████','█    ','████ ','█    ','█████'],

        'F':['█████','█    ','████ ','█    ','█    '],

        'G':[' ████','█    ','█  ██','█   █',' ████'],

        'H':['█   █','█   █','█████','█   █','█   █'],

        'I':['█████','  █  ','  █  ','  █  ','█████'],

        'J':['█████','    █','    █','█   █',' ███ '],

        'K':['█   █','█  █ ','███  ','█  █ ','█   █'],

        'L':['█    ','█    ','█    ','█    ','█████'],

        'M':['█   █','██ ██','█ █ █','█   █','█   █'],

        'N':['█   █','██  █','█ █ █','█  ██','█   █'],

        'O':[' ███ ','█   █','█   █','█   █',' ███ '],

        'P':['████ ','█   █','████ ','█    ','█    '],

        'Q':[' ███ ','█   █','█ █ █','█  ██',' ████'],

        'R':['████ ','█   █','████ ','█  █ ','█   █'],

        'S':[' ████','█    ',' ███ ','    █','████ '],

        'T':['█████','  █  ','  █  ','  █  ','  █  '],

        'U':['█   █','█   █','█   █','█   █',' ███ '],

        'V':['█   █','█   █','█   █',' █ █ ','  █  '],

        'W':['█   █','█   █','█ █ █','██ ██','█   █'],

        'X':['█   █',' █ █ ','  █  ',' █ █ ','█   █'],

        'Y':['█   █',' █ █ ','  █  ','  █  ','  █  '],

        'Z':['█████','   █ ','  █  ',' █   ','█████'],

        '0':[' ███ ','█  ██','█ █ █','██  █',' ███ '],

        '1':['  █  ',' ██  ','  █  ','  █  ','█████'],

        '2':[' ███ ','█   █','  ██ ',' █   ','█████'],

        '3':['████ ','    █',' ███ ','    █','████ '],

        '4':['█   █','█   █','█████','    █','    █'],

        '5':['█████','█    ','████ ','    █','████ '],

        '6':[' ███ ','█    ','████ ','█   █',' ███ '],

        '7':['█████','    █','   █ ','  █  ','  █  '],

        '8':[' ███ ','█   █',' ███ ','█   █',' ███ '],

        '9':[' ███ ','█   █',' ████','    █',' ███ '],

    };



    function renderInviteAscii(code) {

        const chars = code.toUpperCase().split('');

        const rows = ['','','','',''];

        for (const ch of chars) {

            const g = _GLYPH[ch];

            if (!g) continue;

            for (let r = 0; r < 5; r++) {

                rows[r] += (rows[r] ? ' ' : '') + g[r];

            }

        }

        // Build HTML: replace per character to avoid corrupting HTML tags

        let html = '';

        for (const row of rows) {

            let line = '';

            for (const ch of row) {

                if (ch === '█') line += '<span class="ascii-bright">█</span>';

                else if (ch === ' ') line += '<span class="ascii-dim">·</span>';

                else line += ch;

            }

            html += line + '\n';

        }

        return html;

    }



    function setStatusLabel(verified) {

        const el = document.getElementById('account-status-label');

        if (!el) return;

        el.textContent = verified ? 'verified' : 'not verified';

        el.style.color = verified ? 'rgba(100,200,100,0.7)' : 'rgba(255,100,100,0.6)';

    }



    function setInviteCode(code) {

        const raw = document.getElementById('account-invite-code');

        if (raw) raw.textContent = code;

        const ascii = document.getElementById('account-invite-ascii');

        if (ascii) ascii.innerHTML = renderInviteAscii(code);

        const plain = document.getElementById('account-invite-plain');

        if (plain) plain.textContent = code;

    }



    let _decodeRafId = 0;



    function decodeInviteAscii(code) {

        const ascii = document.getElementById('account-invite-ascii');

        const plain = document.getElementById('account-invite-plain');

        const raw = document.getElementById('account-invite-code');

        if (raw) raw.textContent = code;

        if (plain) plain.textContent = code;

        if (!ascii) return;

        // Build the final HTML first

        const finalHtml = renderInviteAscii(code);

        // Cancel any previous decode animation

        if (_decodeRafId) { cancelAnimationFrame(_decodeRafId); _decodeRafId = 0; }

        // Parse into rows of characters

        const targetRows = code.toUpperCase().split('').map(ch => _GLYPH[ch]).filter(Boolean);

        const scrambleChars = '░▒▓█▀▄▌▐│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬';

        const t0 = performance.now();

        const duration = 600;

        function step(now) {

            if (!ascii.isConnected) { _decodeRafId = 0; return; }

            const t = Math.min((now - t0) / duration, 1);

            let html = '';

            for (let r = 0; r < 5; r++) {

                for (let c = 0; c < targetRows.length; c++) {

                    const row = targetRows[c][r];

                    if (c > 0) html += ' ';

                    for (let ci = 0; ci < row.length; ci++) {

                        const ch = row[ci];

                        // Sweep reveals left-to-right across all columns

                        const globalPos = c * row.length + ci;

                        const sweep = t * (targetRows.length * 5 + 10);

                        if (ch === '█') {

                            if (globalPos < sweep || t >= 1) {

                                html += '<span class="ascii-bright">█</span>';

                            } else {

                                html += '<span class="ascii-dim">' + scrambleChars[Math.floor(Math.random() * scrambleChars.length)] + '</span>';

                            }

                        } else if (ch === ' ') {

                            if (globalPos < sweep || t >= 1) {

                                html += '<span class="ascii-dim">·</span>';

                            } else {

                                html += '<span class="ascii-dim">' + scrambleChars[Math.floor(Math.random() * scrambleChars.length)] + '</span>';

                            }

                        } else {

                            html += ch;

                        }

                    }

                }

                html += '\n';

            }

            ascii.innerHTML = html;

            if (t < 1) { _decodeRafId = requestAnimationFrame(step); }

            else { _decodeRafId = 0; }

        }

        _decodeRafId = requestAnimationFrame(step);

    }



    function finishDecodeAnimation() {

        if (_decodeRafId) { cancelAnimationFrame(_decodeRafId); _decodeRafId = 0; }

        const ascii = document.getElementById('account-invite-ascii');

        const raw = document.getElementById('account-invite-code');

        if (ascii && raw && raw.textContent) {

            ascii.innerHTML = renderInviteAscii(raw.textContent.trim());

        }

    }



    function decodeText(el, target) {

        if (!el || !el.isConnected) return;

        if (el.children && el.children.length > 0) return;

        target = String(target || '');

        if (!target.trim()) return;

        // FIX: если текст уже совпадает с target и не анимируется — не запускать повторно
        // Это предотвращает ситуацию когда runAccountDecode вызывается 2-3 раза подряд
        // (из cache → из session), перебивая анимацию и оставляя шум
        if (el._decodeFinal === target && !el._decodeRunning && el.textContent === target) return;

        if (el._decodeFinal === target && el._decodeRunning) return;

        el._decodeFinal = target;

        const token = {};

        el._decodeToken = token;

        el._decodeRunning = true;

        const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

        if (reduceMotion) { el.textContent = target; el._decodeRunning = false; return; }

        // Don't lock dimensions — it causes layout jumps when chars change width

        // FIX: только визуальный шум (блоки) для скрамбла — если анимация оборвётся на полпути,
        // не останется артефактов типа "ПРОФИЛ4", "ТЯ", "ВЫЙFU" (замены букв на буквы/цифры)
        const chars = '░▒▓█▀▄▌▐';

        // FIX: добавлена кириллица в keep — иначе кирилл. буквы скрамблились в случайные символы
        const keep = /[\s.\-:,/@()\u0400-\u04FF]/;

        const t0 = performance.now();

        const duration = Math.min(520, Math.max(320, target.length * 18)); // FIX: было 808-1108мс — слишком долго, вызывало лаг при одновременном запуске 12+ анимаций

        function rg() { return chars[Math.floor(Math.random() * chars.length)]; }

        function frame(t, now) {

            const sweep = Math.pow(t, 1.35) * (target.length + 2);

            let out = '';

            for (let i = 0; i < target.length; i++) {

                const ch = target[i];

                if (keep.test(ch) || i < sweep - 1 || t >= 1) out += ch;

                else if (i < sweep + 2 && Math.random() < t * 0.25) out += ch;

                else out += rg(now);

            }

            el.textContent = out;

        }

        frame(0, t0);

        function step(now) {

            if (!el.isConnected) return;

            // FIX: если токен перебит — принудительно завершаем старую анимацию финальным текстом
            // раньше просто выходили без финализации, оставляя шум (█▌▐)
            if (el._decodeToken !== token) {
                // Не трогаем текст — новая анимация уже управляет элементом
                return;
            }

            const t = Math.min((now - t0) / duration, 1);

            frame(t, now);

            if (t < 1) requestAnimationFrame(step);

            else {

                el.textContent = target;

                el._decodeRunning = false;

            }

        }

        requestAnimationFrame(step);

        // FIX: БЕЗУСЛОВНЫЙ fallback — ставим финальный текст если _decodeFinal всё ещё target
        // (новая анимация не стартовала с другим target). Даже если токен перебит — значит
        // запустилась новая анимация с тем же target, и она своим setTimeout'ом тоже финализирует
        setTimeout(() => {

            if (el.isConnected && el._decodeFinal === target) {

                el.textContent = target;

                el._decodeRunning = false;

            }

        }, duration + 200);

    }



    function decodeTextGroup(selectors, root) {

        const scope = root || document;

        selectors.forEach(sel => {

            scope.querySelectorAll(sel).forEach(el => {

                if (el.closest('.hidden')) return;

                decodeText(el, el.dataset.text || el.dataset.decodeText || el.textContent.trim());

            });

        });

    }



    function runInitialDecode() {
        // FIX: добавлен stagger (60мс между элементами) чтобы не запускать 12+ RAF-анимаций одновременно
        const selectors = [
            '.register-shell > .text-center a span',
            '[data-view="auth"] .auth-terminal-header span',
            '#auth-title',
            '#auth-subtitle',
            '[data-auth-mode]',
            '.auth-ascii-line span',
            '.invite-access-label span',
            '#invite-section p',
            '#dev-login-section p',
            '#dev-login-btn',
            '#tg-custom-btn-text',
            '.tg-custom-btn span:last-child'
        ];
        requestAnimationFrame(() => {
            selectors.forEach((sel, i) => {
                setTimeout(() => {
                    const scope = document;
                    scope.querySelectorAll(sel).forEach(el => {
                        if (el.closest('.hidden')) return;
                        decodeText(el, el.dataset.text || el.dataset.decodeText || el.textContent.trim());
                    });
                }, i * 60);
            });
        });
    }



    function runAccountDecode() {
        // FIX: анимация скрамблит текст только визуальным шумом (блоки),
        // cyrillic в keep-regex не трогает, fallback в decodeText гарантирует финальный текст
        requestAnimationFrame(() => {
            document.querySelectorAll([
                '[data-view="account"] .auth-terminal-header span',
                '#account-name',
                '#account-username',
                '#account-logout',
                '#account-profile-link'
            ].join(',')).forEach(el => {
                el.textContent = el.dataset.text || el.dataset.decodeText || el.textContent.trim();
                el._decodeRunning = false;
                el._decodeFinal = el.textContent;
            });
        });
    }

    let _inviteDecodeRaf = 0;

    function decodeInviteInput(input, target) {

        target = target.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8);

        if (!target) return;

        if (_inviteDecodeRaf) { cancelAnimationFrame(_inviteDecodeRaf); _inviteDecodeRaf = 0; }

        input.value = '';

        input.classList.add('decoding');

        input.classList.remove('decoded');

        const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

        if (reduceMotion) {

            input.value = target;

            input.classList.remove('decoding');

            input.classList.add('decoded');

            setTimeout(() => input.classList.remove('decoded'), 600);

            return;

        }

        const chars = 'ABCDEFGHKNOPRSTUVXYZ023456789░▒▓█';

        const t0 = performance.now();

        const duration = Math.min(900, Math.max(500, target.length * 80));

        function rg() { return chars[Math.floor(Math.random() * chars.length)]; }

        function step(now) {

            const t = Math.min((now - t0) / duration, 1);

            const sweep = Math.pow(t, 1.4) * (target.length + 2);

            let out = '';

            for (let i = 0; i < target.length; i++) {

                if (i < sweep - 1 || t >= 1) out += target[i];

                else if (i < sweep + 1 && Math.random() < t * 0.4) out += target[i];

                else out += rg();

            }

            input.value = out;

            if (t < 1) _inviteDecodeRaf = requestAnimationFrame(step);

            else {

                input.value = target;

                input.classList.remove('decoding');

                input.classList.add('decoded');

                _inviteDecodeRaf = 0;

                setTimeout(() => input.classList.remove('decoded'), 600);

            }

        }

        _inviteDecodeRaf = requestAnimationFrame(step);

    }



    function setAuthMode(mode, animate = true) {

        authMode = mode === 'register' ? 'register' : 'login';

        const isRegister = authMode === 'register';

        const switchEl = document.getElementById('auth-mode-switch');

        if (switchEl) switchEl.dataset.mode = authMode;

        document.querySelectorAll('[data-auth-mode]').forEach(btn => {

            const active = btn.dataset.authMode === authMode;

            btn.classList.toggle('active', active);

            btn.setAttribute('aria-selected', active ? 'true' : 'false');

        });

        const inviteSection = document.getElementById('invite-section');

        if (inviteSection) {

            inviteSection.classList.toggle('invite-visible', isRegister);

            inviteSection.setAttribute('aria-hidden', isRegister ? 'false' : 'true');

        }

        const title = isRegister ? 'Регистрация через Telegram' : 'Вход через Telegram';

        const subtitle = isRegister

            ? 'Введите инвайт и подтвердите аккаунт через Telegram'

            : 'Войдите через ваш Telegram аккаунт';

        const titleEl = document.getElementById('auth-title');

        const subtitleEl = document.getElementById('auth-subtitle');

        if (titleEl) {

            titleEl.dataset.text = title;

            if (animate) decodeText(titleEl, title);

            else titleEl.textContent = title;

        }

        if (subtitleEl) {

            subtitleEl.dataset.decodeText = subtitle;

            if (animate) decodeText(subtitleEl, subtitle);

            else subtitleEl.textContent = subtitle;

        }

        const btnTextEl = document.getElementById('tg-custom-btn-text');

        if (btnTextEl) {

            const btnLabel = isRegister ? 'Регистрация' : 'Войти';

            if (animate) decodeText(btnTextEl, btnLabel);

            else btnTextEl.textContent = btnLabel;

        }

        hideError('auth-error');

        if (!isRegister) {

            const inviteInput = document.getElementById('invite-code');

            if (inviteInput) inviteInput.value = '';

            const inviteSection = document.getElementById('invite-section');

            if (inviteSection) inviteSection.classList.remove('ring-1', 'ring-red-400/50');

        }

    }



    function makeDevInviteCode() {

        return Math.random().toString(36).replace(/[^a-z0-9]/gi, '').slice(2, 10).toUpperCase().padEnd(8, 'X');

    }



    function showView(view) {

        const views = document.querySelectorAll('[data-view]');

        const target = document.querySelector(`[data-view="${view}"]`);

        if (!target) return;



        const currentVisible = Array.from(views).find(v => !v.classList.contains('hidden'));

        if (currentVisible === target) return;



        // Switch views

        views.forEach(v => v.classList.toggle('hidden', v !== target));



        // Card entrance animation (re-trigger)

        target.classList.remove('card-entrance');

        void target.offsetHeight;

        target.classList.add('card-entrance');



        // Reset decode flags on the new view so hackerDecode re-triggers

        target.querySelectorAll('*').forEach(el => {

            el._decodeFinal = undefined;

            el._decodeRunning = false;

            el._decoded = false;

        });

    }



    function resetInviteState() {

        const noInvite = document.getElementById('account-no-invite');

        const deletedInvite = document.getElementById('account-invite-deleted');

        const hasInvite = document.getElementById('account-has-invite');

        if (noInvite) noInvite.classList.add('hidden');

        if (deletedInvite) deletedInvite.classList.add('hidden');

        if (hasInvite) hasInvite.classList.add('hidden');

    }



    function cacheSession(info) {

        try {

            localStorage.setItem('nb_auth_cache', JSON.stringify({ ts: Date.now(), info: info }));

        } catch (e) { /* quota */ }

    }



    function getCachedSession() {

        try {

            const raw = localStorage.getItem('nb_auth_cache');

            if (!raw) return null;

            const cache = JSON.parse(raw);

            if (Date.now() - cache.ts > 3600000) { localStorage.removeItem('nb_auth_cache'); return null; }

            return cache.info;

        } catch (e) { return null; }

    }



    function onTurnstile(token) {
        turnstileToken = token;
    }

    function onTurnstileExpired() {
        turnstileToken = '';
    }

    async function handleTelegramAuth(user) {
        if (isProcessing) return;

        if (user && user.auth_date) {
            const authAge = Math.floor(Date.now() / 1000) - Number(user.auth_date);
            if (isNaN(authAge) || authAge > 300) {
                showError('auth-error', 'Telegram-подтверждение устарело. Нажмите кнопку обновления ниже ↻');
                showTelegramRefreshButton();
                return;
            }
        }

        if (authMode === 'register') {
            const code = document.getElementById('invite-code').value.trim().toUpperCase();
            if (!code) {
                showError('auth-error', 'Введите инвайт-код для регистрации');
                const inviteSection = document.getElementById('invite-section');
                if (inviteSection) inviteSection.classList.add('ring-1', 'ring-red-400/50');
                return;
            }
        }

        if (!turnstileToken) {
            showError('auth-error', 'Пройдите проверку капчи');
            return;
        }
        isProcessing = true;

        hideError('auth-error');


        const code = authMode === 'register' ? document.getElementById('invite-code').value.trim().toUpperCase() : '';

        inviteCode = code;



        const btn = document.getElementById('auth-loading');

        if (btn) btn.classList.remove('hidden');

        const tgBtn = document.getElementById('tg-widget-container');

        if (tgBtn) tgBtn.classList.add('opacity-30', 'pointer-events-none');



        try {

            const result = await Api.telegramAuth(user, code || null, turnstileToken);

            await Api.setSession(result.access_token, result.refresh_token);

            const tgSvg = tgBtn ? tgBtn.querySelector('.tg-custom-btn svg') : null;

            if (tgSvg) tgSvg.classList.add('tg-fly-away');

            const info = await showAccountView();

            cacheSession(info);



            if (result.is_new) {

                showSuccessBadge();

                // Delay success-glow so card-entrance animation plays first

                setTimeout(() => {

                    const accountCard = document.querySelector('[data-view="account"]');

                    if (accountCard) {

                        accountCard.classList.add('success-glow');

                        setTimeout(() => accountCard.classList.remove('success-glow'), 1800);

                    }

                }, 1250);

                try { await Api.checkAndGrantAchievements(); } catch (e) { /* silent */ }

            }

        } catch (err) {

            const tgSvgErr = tgBtn ? tgBtn.querySelector('.tg-custom-btn svg') : null;

            if (tgSvgErr) {

                tgSvgErr.classList.add('tg-crash');

                setTimeout(() => tgSvgErr.classList.remove('tg-crash'), 1000);

            }

            if (err.needsInvite) {

                showError('auth-error', err.message || 'Для регистрации нужен инвайт-код. Введите код выше и попробуйте снова 🤨');

                const inviteSection = document.getElementById('invite-section');

                if (inviteSection) inviteSection.classList.add('ring-1', 'ring-red-400/50');

            } else {

                showError('auth-error', err.message || 'Ошибка аутентификации');

                if (err.status === 401) {
                    showTelegramRefreshButton();
                }

            }

        } finally {

            isProcessing = false;

            if (btn) btn.classList.add('hidden');

            if (tgBtn) tgBtn.classList.remove('opacity-30', 'pointer-events-none');

        }

    }

    function createTelegramScript(container) {
        const botUsername = window.TELEGRAM_BOT_USERNAME;
        if (!botUsername) return false;
        const s = document.createElement('script');
        s.async = true;
        s.src = 'https://telegram.org/js/telegram-widget.js?22&t=' + Date.now();
        s.setAttribute('data-telegram-login', botUsername);
        s.setAttribute('data-size', 'large');
        s.setAttribute('data-radius', '8');
        s.setAttribute('data-userpic', 'false');
        s.setAttribute('data-onauth', 'onTelegramAuth(user)');
        container.appendChild(s);
        return true;
    }

    function resetTelegramWidgetContainer() {
        const container = document.getElementById('tg-widget-container');
        if (!container) return null;
        container.innerHTML = `
            <div class="tg-custom-btn" aria-hidden="true">
                <svg viewBox="0 0 24 24" fill="none"><path d="M20.66 3.72c-.45-.18-1.07-.1-1.88.18L3.72 9.37c-.9.31-1.4.7-1.49 1.15-.1.46.2.86.88 1.18l4.5 1.76 1.65 5.28c.18.56.42.87.72.93.3.06.63-.1.97-.47l2.28-2.28 4.47 3.38c.82.62 1.42.55 1.78-.22l3.38-14.05c.24-.97.07-1.62-.5-1.94a1.5 1.5 0 0 0-.7-.17z" fill="currentColor"/><path d="M8.98 13.64l-.62 3.37.2-3.56 9.2-8.34c.18-.16.2-.22.04-.18L8.98 13.64z" fill="rgba(0,0,0,0.25)"/></svg>
                <span id="tg-custom-btn-text">${authMode === 'register' ? 'Регистрация' : 'Войти'}</span><span> через Telegram</span>
            </div>
        `;
        return container;
    }

    function reloadTelegramWidget() {
        const container = resetTelegramWidgetContainer();
        if (!container) return;
        setTimeout(() => createTelegramScript(container), 400);
    }

    function showTelegramRefreshButton() {
        const container = document.getElementById('tg-widget-container');
        if (!container) return;
        container.innerHTML = `
            <button type="button" class="tg-custom-btn" id="tg-refresh-auth-btn">
                <span>↻</span><span>Обновить Telegram-подтверждение</span>
            </button>
        `;
        const refreshBtn = document.getElementById('tg-refresh-auth-btn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => {
                hideError('auth-error');
                const inner = container.querySelector('.tg-custom-btn');
                if (inner) {
                    inner.innerHTML = '<span class="animate-pulse">Загрузка виджета…</span>';
                    inner.style.pointerEvents = 'none';
                }
                reloadTelegramWidget();
            }, { once: true });
        }
    }



    async function showAccountView() {

        showView('account');

        let info = null; // FIX: объявляем снаружи try, иначе return info кидает ReferenceError

        try {

            info = await Api.getUserDisplayName();

            if (info) {

                cacheSession(info);

                const nameEl = document.getElementById('account-name');

                const usernameEl = document.getElementById('account-username');

                const photoEl = document.getElementById('account-photo');



                if (nameEl) {

                    nameEl.textContent = safeDisplayName(info);

                }

                if (usernameEl && info.telegram_username) {

                    usernameEl.textContent = '@' + info.telegram_username;

                    usernameEl.classList.remove('hidden');

                }

                if (photoEl && info.telegram_photo_url) {

                    const url = info.telegram_photo_url.startsWith('/')

                        ? 'https://t.me' + info.telegram_photo_url

                        : info.telegram_photo_url;

                    photoEl.src = url;

                    photoEl.classList.remove('hidden');

                    const placeholder = document.getElementById('account-photo-placeholder');

                    if (placeholder) placeholder.classList.add('hidden');

                }



                if (info.is_verified) {

                    setStatusLabel(true);

                } else {

                    showEl('account-unverified');

                    setStatusLabel(false);

                }

                const profileLink = document.getElementById('account-profile-link');
                if (profileLink && info.uid) profileLink.href = getProfileHref(info.uid);

                runAccountDecode();

            }

        } catch (e) { console.warn('[auth] account view error:', e); }

        return info;

    }



    async function checkExistingSession() {

        if (isLocalhost()) {

            const devRaw = localStorage.getItem('nb_dev_session');

            if (devRaw) {

                try {

                    const devInfo = JSON.parse(devRaw);

                    if (devInfo.invite_max === undefined) {

                        devInfo.invite_max = devInfo.role === 'admin' ? 999999 : 1;

                        devInfo.invite_active_count = 0;

                        devInfo.has_generated_invite = false;

                        devInfo.generated_code = null;

                        devInfo.invite_use_count = 0;

                        localStorage.setItem('nb_dev_session', JSON.stringify(devInfo));

                    }

                    showView('account');

                    const nameEl = document.getElementById('account-name');

                    if (nameEl) nameEl.textContent = safeDisplayName(devInfo);

                    const usernameEl = document.getElementById('account-username');

                    if (usernameEl && devInfo.telegram_username) { usernameEl.textContent = '@' + devInfo.telegram_username; usernameEl.classList.remove('hidden'); }

                    setStatusLabel(true);

                    runAccountDecode();

                    return;

                } catch (e) { console.warn('[auth] dev session parse error:', e); }

            }

        }

        const cached = getCachedSession();

        if (cached) {

            showView('account');

            fillAccountFromCache(cached);

        }

        const session = await Api.getSession();

        if (session) {

            await showAccountView();

        } else if (cached) {

            showView('auth');

            localStorage.removeItem('nb_auth_cache');

            sessionStorage.removeItem('nb_auth_cache');

        }

    }



    function isLocalhost() {

        const h = window.location.hostname;

        return h === 'localhost' || h === '127.0.0.1' || h === '::1';

    }



    function fillAccountFromCache(info) {

        const nameEl = document.getElementById('account-name');

        if (nameEl) {

            nameEl.textContent = safeDisplayName(info);

        }

        const usernameEl = document.getElementById('account-username');

        if (usernameEl && info.telegram_username) {

            usernameEl.textContent = '@' + info.telegram_username;

            usernameEl.classList.remove('hidden');

        }

        if (info.is_verified) {

            setStatusLabel(true);

        } else {

            showEl('account-unverified');

            setStatusLabel(false);

        }

        const profileLink = document.getElementById('account-profile-link');
        if (profileLink && info.uid) profileLink.href = getProfileHref(info.uid);

        runAccountDecode();
    }

    function activateDevLogin() {

        if (!isLocalhost()) return;

        const devInfo = {

            user_id: 'dev-user-' + Date.now(),

            telegram_first_name: 'Dev',

            telegram_last_name: 'User',

            telegram_username: 'devuser',

            telegram_photo_url: '',

            display_name: 'Dev User',

            is_verified: true,

            is_banned: false,

            is_muted: false,

            is_moderator: false,

            role: 'admin',

            has_generated_invite: false,

            generated_code: null,

            invite_use_count: 0,

            invite_max: 999999,

            invite_active_count: 0

        };

        localStorage.setItem('nb_dev_session', JSON.stringify(devInfo));

        showView('account');

        const nameEl = document.getElementById('account-name');

        if (nameEl) nameEl.textContent = safeDisplayName(devInfo);

        const usernameEl = document.getElementById('account-username');

        if (usernameEl) { usernameEl.textContent = '@' + devInfo.telegram_username; usernameEl.classList.remove('hidden'); }

        setStatusLabel(true);

        showSuccessBadge();

        runAccountDecode();

        // Delay success-glow so card-entrance animation plays first

        setTimeout(() => {

            const accountCard = document.querySelector('[data-view="account"]');

            if (accountCard) {

                accountCard.classList.add('success-glow');

                setTimeout(() => accountCard.classList.remove('success-glow'), 1800);

            }

        }, 500);

    }



    function init() {

        window.SUPABASE_URL = window.SUPABASE_URL || '';

        window.SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || '';

        Api.reinit();


window.onTelegramAuth = handleTelegramAuth;

function renderTurnstile() {
    try {
        const wrap = document.getElementById('turnstile-wrap');
        if (wrap && window.TURNSTILE_SITE_KEY && window.turnstile) {
            wrap.classList.remove('hidden');
            const container = wrap.querySelector('.cf-turnstile');
            if (container && !container.hasChildNodes()) {
                turnstile.render(container, {
                    sitekey: window.TURNSTILE_SITE_KEY,
                    callback: onTurnstile,
                    'expired-callback': onTurnstileExpired,
                    theme: 'dark',
                    size: 'compact',
                });
            }
        }
    } catch (e) { console.warn('Turnstile render error:', e.message); }
}
window._renderTurnstile = renderTurnstile;
if (window._turnstileReady) renderTurnstile();

const devBtn = document.getElementById('dev-login-btn');

if (devBtn) {

if (isLocalhost()) {

showEl('dev-login-section');

devBtn.addEventListener('click', activateDevLogin);

                showEl('dev-login-section');

                devBtn.addEventListener('click', activateDevLogin);

            }

        }



        const inviteInput = document.getElementById('invite-code');

        if (inviteInput) {

            inviteInput.addEventListener('input', () => {

                inviteInput.value = inviteInput.value.toUpperCase().replace(/[^A-Z0-9]/g, '');

                hideError('auth-error');

                const inviteSection = document.getElementById('invite-section');

                if (inviteSection) inviteSection.classList.remove('ring-1', 'ring-red-400/50');

            });

            inviteInput.addEventListener('paste', (e) => {

                e.preventDefault();

                const pasted = (e.clipboardData || window.clipboardData).getData('text');

                if (pasted) decodeInviteInput(inviteInput, pasted);

            });

        }



        document.querySelectorAll('[data-auth-mode]').forEach(btn => {

            btn.addEventListener('click', () => setAuthMode(btn.dataset.authMode));

        });

        setAuthMode('login', false);

        runInitialDecode();



        const logoutBtn = document.getElementById('account-logout');

        if (logoutBtn) logoutBtn.addEventListener('click', async () => {

            localStorage.removeItem('nb_dev_session');

            localStorage.removeItem('nb_auth_cache');

            await Api.logout();

            // Reset decode flags so re-login re-triggers hackerDecode

            document.querySelectorAll('[data-view] *').forEach(el => {

                el._decodeFinal = undefined;

                el._decodeRunning = false;

                el._decoded = false;

            });

            showView('auth');

            hideEl('account-verified');

            hideEl('account-unverified');

            hideEl('account-username');

            hideEl('account-photo');

            showEl('account-photo-placeholder');

            hideEl('new-user-badge');

            resetInviteState();

            const nameEl = document.getElementById('account-name');

            if (nameEl) nameEl.textContent = '';

            const usernameEl = document.getElementById('account-username');

            if (usernameEl) usernameEl.textContent = '';

            runInitialDecode();

        });



        checkExistingSession();

    }



    return { init, safeDisplayName, onTurnstile, onTurnstileExpired };

})();

window.safeDisplayName = AuthApp.safeDisplayName;



document.addEventListener('DOMContentLoaded', AuthApp.init);
