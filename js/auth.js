const AuthApp = (() => {

    let inviteCode = '';


    // getProfileBasePath provided by profile-utils.js

    // getProfileHref provided by profile-utils.js


    let isProcessing = false;

    let authMode = 'login';
    let turnstileToken = '';
    let turnstileWidgetId = null;
    let telegramWidgetTimer = null;

    const _DANGEROUS_RE = /[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]/g;

    // safeDisplayName provided by profile-utils.js

    // sanitizeTelegramPhotoUrl provided by profile-utils.js

    // === Plane loop animation (мёртвая петля) ===
    let planeLoopTimer = null;

    function triggerPlaneLoop() {
        const plane = document.querySelector('.tg-plane-svg');
        if (!plane || plane.classList.contains('tg-looping') || plane.classList.contains('tg-fly-away')) return;

        // Respect reduced motion preference
        if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

        plane.classList.add('tg-looping');

        // Remove class after animation completes (3s)
        setTimeout(() => {
            plane.classList.remove('tg-looping');
        }, 3050);
    }

    function startPlaneLoopTimer() {
        if (planeLoopTimer) return;

        // Random interval between 15-20 seconds
        function scheduleNext() {
            const delay = 15000 + Math.random() * 5000; // 15-20 sec
            planeLoopTimer = setTimeout(() => {
                triggerPlaneLoop();
                scheduleNext();
            }, delay);
        }

        // First loop after 8-12 seconds (so user sees it sooner on first visit)
        planeLoopTimer = setTimeout(() => {
            triggerPlaneLoop();
            scheduleNext();
        }, 8000 + Math.random() * 4000);
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

    const _GLYPH = window.NB_GLYPH; // provided by glyph-data.js



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





    function decodeText(el, target) {

        if (!el || !el.isConnected) return;

        if (el.children && el.children.length > 0) return;

        target = String(target || '');

        if (!target.trim()) return;

        // FIX: если текст уже совпадает с target и не анимируется — не запускать повторно
        // Это предотвращает ситуацию когда resetAccountDecodeState вызывается 2-3 раза подряд
        // (из cache → из session), перебивая анимацию и оставляя шум
        if (el._decodeFinal === target && !el._decodeRunning && el.textContent === target) return;

        if (el._decodeFinal === target && el._decodeRunning) return;

        el._decodeFinal = target;

        const token = {};

        el._decodeToken = token;

        el._decodeRunning = true;

        // Маркерный класс — никаких display/min-width хаков (см. CSS).
        // Стабильность горизонтальной ширины строки обеспечивается узким charset'ом
        // ниже: широкие глифы (@#$%& и т.д.) исключены, и шум по ширине ≈ финальному тексту.
        el.classList.add('is-decoding');

        const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

        if (reduceMotion) { el.textContent = target; el._decodeRunning = false; el.classList.remove('is-decoding'); return; }

        // Don't lock dimensions — it causes layout jumps when chars change width

        // Hackerdecode: латиница + узкие символы. Широкие глифы (@ # $ % & M W m w ^ ~ №)
        // выкинуты — на пропорциональном Inter они дают разную ширину строки и карточка прыгает.
        // Остались только символы примерно равной ширины + цифры.
        const chars = 'abcdefghijklnopqrstuvxyzABCDEFGHIJKLNOPQRSTUVXYZ0123456789!;:?*()[]<>+=-_/\\|.,';

        // Сохраняем только пробелы и пунктуацию-разделители; буквы скремблятся
        const keep = /[\s.\-:,/@()]/;

        const t0 = performance.now();

        // Длиннее, плавнее — больше «дыхания» на коротких словах, не растягивается на длинных
        const duration = Math.min(1300, Math.max(720, target.length * 48));

        function rg() { return chars[Math.floor(Math.random() * chars.length)]; }

        // FIX: per-slot буфер — каждый символ-шум обновляется не чаще раз в ~SLOT_PERIOD мс,
        // а не каждый кадр (60fps). Это убирает мерцание/strob — символы становятся читаемыми
        // вместо мельтешения. Для разных слотов разный jitter, чтобы не было синхронного «дыхания».
        const SLOT_PERIOD = 110; // мс
        const slotChars = new Array(target.length);
        const slotNext = new Array(target.length);
        for (let i = 0; i < target.length; i++) {
            slotChars[i] = keep.test(target[i]) ? target[i] : rg();
            slotNext[i] = t0 + Math.random() * SLOT_PERIOD;
        }

        function frame(t, now) {

            // Ease-out с инерцией: символы быстро декодятся в начале, заметно замедляются к концу.
            // 1 - (1-t)^2.6 даёт сильный deceleration в финале.
            const eased = 1 - Math.pow(1 - t, 2.6);
            const sweep = eased * (target.length + 2);

            let out = '';

            for (let i = 0; i < target.length; i++) {

                const ch = target[i];

                if (keep.test(ch) || i < sweep - 1 || t >= 1) {
                    out += ch;
                    continue;
                }

                // Settle zone — у границы sweep символы залипают на финальном чаще,
                // дальше остаются скрамблеными
                if (i < sweep + 2 && Math.random() < eased * 0.3) {
                    slotChars[i] = ch;
                    out += ch;
                    continue;
                }

                // Перерисовываем шум только если истёк период этого слота
                if (now >= slotNext[i]) {
                    slotChars[i] = rg();
                    slotNext[i] = now + SLOT_PERIOD + Math.random() * 60;
                }
                out += slotChars[i];
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

                el.classList.remove('is-decoding');

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

                el.classList.remove('is-decoding');

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



    // Pre-scramble all decode targets synchronously BEFORE first paint —
    // иначе на reload пользователь успевает увидеть финальный текст до анимации.
    function prescrambleAll() {
        const noiseChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!";%:?*()[]{}<>+=-_/\\@#$&^~';
        const keep = /[\s.\-:,/@()]/;
        const rg = () => noiseChars[Math.floor(Math.random() * noiseChars.length)];
        const selectors = [
            '.register-shell > .text-center a span',
            '[data-view="auth"] .auth-terminal-header span',
            '#auth-title-main',
            '#auth-sub-pre',
            '#auth-sub-mid',
            '#auth-subtitle-telegram',
            '#auth-sub-post',
            '.auth-ascii-line span',
            '.invite-access-label span',
            '#invite-section p',
            '#dev-login-section p',
            '#dev-login-btn',
            '#tg-custom-btn-text',
            '.tg-btn-suffix'
        ];
        const seen = new Set();
        selectors.forEach(sel => {
            document.querySelectorAll(sel).forEach(el => {
                if (seen.has(el) || el.children.length) return;
                seen.add(el);
                const original = el.dataset.text != null ? el.dataset.text
                                : el.dataset.decodeText != null ? el.dataset.decodeText
                                : el.textContent;
                if (!original || !original.trim()) return;
                if (el.dataset.text == null && el.dataset.decodeText == null) {
                    el.dataset.decodeText = original;
                }
                el.classList.add('is-decoding');
                let out = '';
                for (let i = 0; i < original.length; i++) {
                    out += keep.test(original[i]) ? original[i] : rg();
                }
                el.textContent = out;
            });
        });
    }

    function runInitialDecode() {
        // FIX: добавлен stagger (60мс между элементами) чтобы не запускать 12+ RAF-анимаций одновременно
        const selectors = [
            '.register-shell > .text-center a span',
            '[data-view="auth"] .auth-terminal-header span',
            '#auth-title-main',
            '#auth-sub-pre',
            '#auth-sub-mid',
            '#auth-subtitle-telegram',
            '#auth-sub-post',
            '.auth-ascii-line span',
            '.invite-access-label span',
            '#invite-section p',
            '#dev-login-section p',
            '#dev-login-btn',
            '#tg-custom-btn-text',
            '.tg-btn-suffix'
        ];
        requestAnimationFrame(() => {
            selectors.forEach((sel, i) => {
                setTimeout(() => {
                    const scope = document;
                    scope.querySelectorAll(sel).forEach(el => {
                        if (el.closest('.hidden')) return;
                        // FIX: keep leading/trailing spaces intact when data-decode-text/data-text is set,
                        // only fallback uses .trim() to strip surrounding whitespace from textContent
                        const explicit = el.dataset.text != null ? el.dataset.text
                                        : el.dataset.decodeText != null ? el.dataset.decodeText
                                        : null;
                        const target = explicit !== null ? explicit : el.textContent.trim();
                        decodeText(el, target);
                    });
                }, i * 25);
            });
        });
    }



    function resetAccountDecodeState() {
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

        target = target.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 16);

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

        const chars = 'qwertyuiop[]asdfghjkl;zxcvbnm,./!@#$%^&*QWERTYUIOPASDFGHJKLZXCVBNM<>?+=';

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
        const prevMode = authMode;
        authMode = mode === 'register' ? 'register' : 'login';
        const isRegister = authMode === 'register';

        // Animate sliding border on mode switch
        const switchEl = document.getElementById('auth-mode-switch');
        if (switchEl) {
            switchEl.dataset.mode = authMode;
            requestAnimationFrame(() => {
                const activeBtn = switchEl.querySelector(`[data-auth-mode="${authMode}"]`);
                if (activeBtn) {
                    switchEl.style.setProperty('--switch-border-left', activeBtn.offsetLeft + 'px');
                    switchEl.style.setProperty('--switch-border-width', activeBtn.offsetWidth + 'px');
                }
            });
        }

        document.querySelectorAll('[data-auth-mode]').forEach(btn => {
            const active = btn.dataset.authMode === authMode;
            btn.classList.toggle('active', active);
            btn.setAttribute('aria-selected', active ? 'true' : 'false');
            if (animate) {
                btn.classList.add('decoding-active');
                setTimeout(() => btn.classList.remove('decoding-active'), 400);
            }
        });

        // Content slide transition
        const bodyEl = document.querySelector('.auth-mode-body');
        if (bodyEl && animate) {
            const reverse = prevMode === 'register' && authMode === 'login';
            bodyEl.classList.add(reverse ? 'auth-switching-reverse' : 'auth-switching');
            requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                    bodyEl.classList.remove('auth-switching', 'auth-switching-reverse');
                });
            });
        }

        const inviteSection = document.getElementById('invite-section');
        if (inviteSection) {
            inviteSection.classList.toggle('invite-visible', isRegister);
            inviteSection.setAttribute('aria-hidden', isRegister ? 'false' : 'true');
            // Trigger hackerdecode on invite section elements when switching to register
            if (isRegister && animate) {
                setTimeout(() => {
                    inviteSection.querySelectorAll('[data-decode-text], .invite-access-label span').forEach(el => {
                        decodeText(el, el.dataset.decodeText || el.textContent.trim());
                    });
                }, 150);
            }
        }

        // FIX: каждая часть подзаголовка/кнопки — отдельный slot с собственным data-decode-text.
        // Никаких innerHTML-перезаписей с trim() — пробелы сохраняются дословно.
        const slots = isRegister ? {
            '#auth-title-main':       'Регистрация',
            '#auth-sub-pre':          'Введите инвайт и подтвердите аккаунт',
            '#auth-sub-mid':          ' через ',
            '#auth-subtitle-telegram':'Telegram',
            '#auth-sub-post':         '',
            '#tg-custom-btn-text':    'Регистрация',
            '.tg-btn-suffix':         ' через Telegram'
        } : {
            '#auth-title-main':       'Вход',
            '#auth-sub-pre':          'Войдите',
            '#auth-sub-mid':          ' через ваш ',
            '#auth-subtitle-telegram':'Telegram',
            '#auth-sub-post':         ' аккаунт',
            '#tg-custom-btn-text':    'Войти',
            '.tg-btn-suffix':         ' через Telegram'
        };

        Object.entries(slots).forEach(([sel, txt]) => {
            const el = document.querySelector(sel);
            if (!el) return;
            if (sel === '#auth-title-main') el.dataset.text = txt;
            else el.dataset.decodeText = txt;
            if (animate && txt.trim()) {
                decodeText(el, txt);
            } else {
                // Снимаем устаревший width-lock от предыдущего режима, иначе пустой/короткий
                // текст сохранит ширину предыдущего слова → визуальный «призрак».
                el.classList.remove('is-decoding');
                el.style.minWidth = '';
                el.textContent = txt;
            }
        });

        const titleContainer = document.getElementById('auth-title');
        if (titleContainer && animate) {
            titleContainer.classList.add('decode-bounce');
            setTimeout(() => titleContainer.classList.remove('decode-bounce'), 360);
        }

        const tgContainer = document.getElementById('tg-widget-container');
        if (tgContainer) tgContainer.classList.remove('tg-auth-active');
        hideError('auth-error');

        if (!isRegister) {
            const inviteInput = document.getElementById('invite-code');
            if (inviteInput) inviteInput.value = '';
            if (inviteSection) inviteSection.classList.remove('ring-1', 'ring-red-400/50');
        }
    }





    function showView(view) {

        // Reset plane / fly classes so re-entering auth view restores card overflow
        if (view === 'auth') {
            const authCard = document.querySelector('[data-view="auth"]');
            if (authCard) authCard.classList.remove('tg-flying');
            document.querySelectorAll('#tg-widget-container .tg-plane-wrap, #tg-widget-container .tg-custom-btn')
                .forEach(el => el.classList.remove('tg-fly-away', 'tg-flying', 'tg-crash'));
        }

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
        clearTurnstileTimeout();
    }

    function onTurnstileExpired() {
        turnstileToken = '';
    }

    function resetTurnstile() {
        turnstileToken = '';
        try {
            if (window.turnstile && turnstileWidgetId !== null) {
                window.turnstile.reset(turnstileWidgetId);
            }
        } catch (e) {
            console.warn('Turnstile reset error:', e.message);
        }
    }

    function showTurnstile() {
        const wrap = document.getElementById('turnstile-wrap');
        if (!wrap) return;
        wrap.classList.remove('hidden');
        if (window._renderTurnstile) window._renderTurnstile(true);
        initTurnstileWithTimeout();
    }

    function triggerPlaneCrash() {
        // Reusable crash animation — used on invite validation errors and auth errors.
        const wrap = document.querySelector('#tg-widget-container .tg-plane-wrap');
        if (!wrap) return;
        wrap.classList.remove('tg-crash');
        // force reflow so re-adding the class restarts the animation
        // eslint-disable-next-line no-unused-expressions
        void wrap.offsetWidth;
        wrap.classList.add('tg-crash');
        setTimeout(() => wrap.classList.remove('tg-crash'), 1300);
    }

    async function handleTelegramAuth(user) {
        if (isProcessing) return;
        clearTimeout(_tgActiveTimer);

        if (authMode === 'register') {
            const code = document.getElementById('invite-code').value.trim().toUpperCase();
            if (!code) {
                showError('auth-error', 'Введите инвайт-код для регистрации');
                const inviteSection = document.getElementById('invite-section');
                if (inviteSection) inviteSection.classList.add('ring-1', 'ring-red-400/50');
                triggerPlaneCrash();
                return;
            }
            if (code.length < 8) {
                showError('auth-error', 'Инвайт-код должен содержать 8 символов');
                const inviteSection = document.getElementById('invite-section');
                if (inviteSection) inviteSection.classList.add('ring-1', 'ring-red-400/50');
                triggerPlaneCrash();
                return;
            }
        }

        if (!turnstileToken && window.TURNSTILE_SITE_KEY) {
            const wrap = document.getElementById('turnstile-wrap');
            if (wrap && !wrap.classList.contains('hidden')) {
                showError('auth-error', 'Пройдите проверку капчи');
                return;
            }
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

            clearTurnstileTimeout();
            const controller = new AbortController();
            const authTimeout = setTimeout(() => controller.abort(), 30000);
            let result;
            try {
                result = await Api.telegramAuth(user, code || null, turnstileToken, controller.signal);
            } finally {
                clearTimeout(authTimeout);
            }
            const containerAfter = document.getElementById('tg-widget-container');
            if (containerAfter) containerAfter.classList.remove('tg-auth-active');
            await Api.setSession(result.access_token, result.refresh_token);

            const tgWrap = tgBtn ? tgBtn.querySelector('.tg-plane-wrap') : null;
            const customBtnEl = tgBtn ? tgBtn.querySelector('.tg-custom-btn') : null;
            const authCard = document.querySelector('[data-view="auth"]');
            // FIX: enable overflow:visible on ancestors so plane can fly past button/card edges
            if (authCard) authCard.classList.add('tg-flying');
            if (customBtnEl) customBtnEl.classList.add('tg-flying');
            if (tgWrap) tgWrap.classList.add('tg-fly-away');

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
            const container = document.getElementById('tg-widget-container');
            if (container) container.classList.remove('tg-auth-active');
            resetTurnstile();

            const tgWrapErr = tgBtn ? tgBtn.querySelector('.tg-plane-wrap') : null;

            if (tgWrapErr) {

                tgWrapErr.classList.add('tg-crash');

                setTimeout(() => tgWrapErr.classList.remove('tg-crash'), 1300);

            }

            if (err.name === 'AbortError') {
                showError('auth-error', 'Превышено время ожидания. Попробуйте снова.');
                showTelegramRefreshButton();
            } else if (/captcha|капч/i.test(err.message || '')) {
                showTurnstile();
                showError('auth-error', err.message);
                showTelegramRefreshButton();
            } else if (err.needsInvite) {

                showError('auth-error', err.message || 'Для регистрации нужен инвайт-код. Введите код выше и попробуйте снова');

                const inviteSection = document.getElementById('invite-section');

                if (inviteSection) inviteSection.classList.add('ring-1', 'ring-red-400/50');

            } else {

                showError('auth-error', err.message || 'Ошибка аутентификации');

                if (err.status === 401 || err.status >= 500 || !err.status) {
                    showTelegramRefreshButton();
                }

            }

        } finally {

            isProcessing = false;

            if (btn) btn.classList.add('hidden');

            if (tgBtn) tgBtn.classList.remove('opacity-30', 'pointer-events-none');

        }

    }

    const telegramIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M21.9 4.6 18.7 19.7c-.2 1-.8 1.2-1.6.8l-4.8-3.5-2.3 2.2c-.3.3-.5.5-1 .5l.4-4.9 8.9-8c.4-.4-.1-.6-.6-.2l-11 6.9-4.7-1.5c-1-.3-1-1 .2-1.5L20.7 3.4c.9-.3 1.6.2 1.2 1.2Z"/></svg>';

    function showTelegramWidgetFallback(container, message, className = 'tg-widget-state') {
        if (!container) return;
        container.classList.remove('tg-widget-ready');
        container.querySelectorAll('.tg-widget-state, .tg-local-fallback').forEach(el => el.remove());
        const fb = document.createElement('div');
        const icon = document.createElement('span');
        const label = document.createElement('span');
        fb.className = className;
        icon.innerHTML = telegramIcon;
        label.textContent = message;
        fb.append(icon, label);
        container.appendChild(fb);
    }

    function wireTelegramReset(container) {
        const resetBtn = container ? container.querySelector('[data-tg-reset]') : null;
        if (!resetBtn) return;
        resetBtn.addEventListener('click', (e) => {
            // Reset-box is inside .tg-custom-btn — stop propagation so clicking it
            // does not also trigger the main Telegram-auth click handler.
            e.stopPropagation();
            e.preventDefault();
            resetBtn.classList.remove('tg-resetting');
            // force reflow so animation restarts on repeated clicks
            // eslint-disable-next-line no-unused-expressions
            void resetBtn.offsetWidth;
            resetBtn.classList.add('tg-resetting');
            setTimeout(() => resetBtn.classList.remove('tg-resetting'), 1000);
            hideError('auth-error');
            resetTurnstile();
            reloadTelegramWidget();
        });
    }

    let _tgActiveTimer = 0;

    function wireCustomButtonClick(container) {
        const customBtn = container ? container.querySelector('.tg-custom-btn') : null;
        if (!customBtn) return;
        customBtn.addEventListener('click', () => {
            if (authMode === 'register') {
                const code = document.getElementById('invite-code').value.trim().toUpperCase();
                if (!code) {
                    showError('auth-error', 'Введите инвайт-код для регистрации');
                    const inviteSection = document.getElementById('invite-section');
                    if (inviteSection) inviteSection.classList.add('ring-1', 'ring-red-400/50');
                    return;
                }
                if (code.length < 8) {
                    showError('auth-error', 'Инвайт-код должен содержать 8 символов');
                    const inviteSection = document.getElementById('invite-section');
                    if (inviteSection) inviteSection.classList.add('ring-1', 'ring-red-400/50');
                    return;
                }
            }
            hideError('auth-error');
            container.classList.add('tg-auth-active');
            clearTimeout(_tgActiveTimer);
            _tgActiveTimer = setTimeout(() => {
                if (container.classList.contains('tg-auth-active')) {
                    container.classList.remove('tg-auth-active');
                }
            }, 15000);
        });
    }

    function createTelegramScript(container) {
        const botUsername = window.TELEGRAM_BOT_USERNAME;
        if (!botUsername) return false;
        container.classList.remove('tg-widget-ready');
        container.querySelectorAll('.tg-widget-state, .tg-local-fallback').forEach(el => el.remove());
        const customBtn = container.querySelector('.tg-custom-btn');
        if (customBtn) {
            customBtn.style.display = '';
            customBtn.classList.add('tg-btn-loading');
        }
        const s = document.createElement('script');
        s.async = true;
        s.src = 'https://telegram.org/js/telegram-widget.js?22&t=' + Date.now();
        s.setAttribute('data-telegram-login', botUsername);
        s.setAttribute('data-size', 'large');
        s.setAttribute('data-radius', '8');
        s.setAttribute('data-userpic', 'false');
        s.setAttribute('data-onauth', 'onTelegramAuth(user)');
        s.onerror = () => {
            if (customBtn) customBtn.classList.remove('tg-btn-loading');
            showTelegramWidgetFallback(container, 'Telegram widget не загружен');
        };
        container.appendChild(s);

        if (telegramWidgetTimer) window.clearInterval(telegramWidgetTimer);
        let checksLeft = 40;
        telegramWidgetTimer = window.setInterval(() => {
            const iframe = container.querySelector('iframe');
            const iframeReady = iframe && (iframe._ready || iframe.contentDocument !== null || iframe.offsetHeight > 10);
            if (iframe && iframeReady) {
                if (customBtn) {
                    customBtn.classList.remove('tg-btn-loading');
                }
                container.classList.add('tg-widget-ready');
                window.clearInterval(telegramWidgetTimer);
                telegramWidgetTimer = null;
            } else if (iframe) {
                if (customBtn) customBtn.classList.remove('tg-btn-loading');
                container.classList.add('tg-widget-ready');
                window.clearInterval(telegramWidgetTimer);
                telegramWidgetTimer = null;
            } else if (--checksLeft <= 0) {
                if (customBtn) customBtn.classList.remove('tg-btn-loading');
                showTelegramWidgetFallback(container, 'Telegram widget не отображается');
                window.clearInterval(telegramWidgetTimer);
                telegramWidgetTimer = null;
            }
        }, 300);

        return true;
    }

    function resetTelegramWidgetContainer() {
        const container = document.getElementById('tg-widget-container');
        if (!container) return null;
        if (telegramWidgetTimer) {
            window.clearInterval(telegramWidgetTimer);
            telegramWidgetTimer = null;
        }
        container.classList.remove('tg-widget-ready', 'tg-auth-active');
        container.innerHTML = `
            <div class="tg-custom-btn" aria-hidden="true">
                <span class="tg-plane-wrap">
                    <span class="tg-plane-trail" aria-hidden="true"></span>
                    <svg class="tg-plane-svg" viewBox="0 0 24 24" fill="none"><path d="M20.66 3.72c-.45-.18-1.07-.1-1.88.18L3.72 9.37c-.9.31-1.4.7-1.49 1.15-.1.46.2.86.88 1.18l4.5 1.76 1.65 5.28c.18.56.42.87.72.93.3.06.63-.1.97-.47l2.28-2.28 4.47 3.38c.82.62 1.42.55 1.78-.22l3.38-14.05c.24-.97.07-1.62-.5-1.94a1.5 1.5 0 0 0-.7-.17z" fill="currentColor"/><path d="M8.98 13.64l-.62 3.37.2-3.56 9.2-8.34c.18-.16.2-.22.04-.18L8.98 13.64z" fill="rgba(0,0,0,0.25)"/></svg>
                </span>
                <span class="tg-btn-label"><span id="tg-custom-btn-text">${authMode === 'register' ? 'Регистрация' : 'Войти'}</span><span class="tg-btn-suffix"> через Telegram</span></span>
                <button type="button" class="tg-reset-box" data-tg-reset title="Сбросить Telegram" aria-label="Сбросить Telegram">
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                        <path d="M3 12a9 9 0 0 1 15.5-6.3L21 8" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M21 3v5h-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M21 12a9 9 0 0 1-15.5 6.3L3 16" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M3 21v-5h5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                    </svg>
                </button>
            </div>
        `;
        wireTelegramReset(container);
        wireCustomButtonClick(container);
        return container;
    }

    function reloadTelegramWidget() {
        const container = resetTelegramWidgetContainer();
        if (!container) return;
        createTelegramScript(container);
    }

    function showTelegramRefreshButton() {
        const container = document.getElementById('tg-widget-container');
        if (!container) return;
        container.innerHTML = `
            <div class="tg-custom-btn" aria-hidden="true" id="tg-refresh-auth-btn">
                <span class="tg-plane-wrap">
                    <span class="tg-plane-trail" aria-hidden="true"></span>
                    <svg class="tg-plane-svg" viewBox="0 0 24 24" fill="none"><path d="M20.66 3.72c-.45-.18-1.07-.1-1.88.18L3.72 9.37c-.9.31-1.4.7-1.49 1.15-.1.46.2.86.88 1.18l4.5 1.76 1.65 5.28c.18.56.42.87.72.93.3.06.63-.1.97-.47l2.28-2.28 4.47 3.38c.82.62 1.42.55 1.78-.22l3.38-14.05c.24-.97.07-1.62-.5-1.94a1.5 1.5 0 0 0-.7-.17z" fill="currentColor"/><path d="M8.98 13.64l-.62 3.37.2-3.56 9.2-8.34c.18-.16.2-.22.04-.18L8.98 13.64z" fill="rgba(0,0,0,0.25)"/></svg>
                </span>
                <span class="tg-btn-label"><span id="tg-custom-btn-text">Попробовать снова</span></span>
                <button type="button" class="tg-reset-box" data-tg-reset title="Сбросить Telegram" aria-label="Сбросить Telegram">
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                        <path d="M3 12a9 9 0 0 1 15.5-6.3L21 8" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M21 3v5h-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M21 12a9 9 0 0 1-15.5 6.3L3 16" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M3 21v-5h5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                    </svg>
                </button>
            </div>
        `;
        const refreshBtn = document.getElementById('tg-refresh-auth-btn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => {
                hideError('auth-error');
                resetTurnstile();
                reloadTelegramWidget();
            });
        }
        wireTelegramReset(container);
    }

    function initTelegramWidget() {
        const container = document.getElementById('tg-widget-container');
        if (!container) return;
        const host = window.location.hostname;
        const isLocal = !host || host === 'localhost' || host === '127.0.0.1' || host === '::1';
        if (isLocal) {
            showTelegramWidgetFallback(container, 'Telegram доступен только на домене бота', 'tg-local-fallback');
            return;
        }
        if (!window.TELEGRAM_BOT_USERNAME) {
            showTelegramWidgetFallback(container, 'Telegram bot не настроен');
            return;
        }
        wireTelegramReset(container);
        wireCustomButtonClick(container);
        createTelegramScript(container);
    }

    let _turnstileTimeout = 0;
    let _turnstileScriptLoading = false;
    function ensureTurnstileScript() {
        if (!window.TURNSTILE_SITE_KEY) return false;
        if (window.turnstile) return true;
        if (_turnstileScriptLoading || document.querySelector('script[data-turnstile-api]')) return false;
        _turnstileScriptLoading = true;
        const script = document.createElement('script');
        script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=onTurnstileLoad';
        script.async = true;
        script.defer = true;
        script.dataset.turnstileApi = 'true';
        script.onerror = () => {
            _turnstileScriptLoading = false;
            console.warn('[auth] Turnstile script failed to load');
        };
        document.head.appendChild(script);
        return false;
    }

    function initTurnstileWithTimeout() {
        _turnstileTimeout = setTimeout(() => {
            if (!turnstileToken && window.TURNSTILE_SITE_KEY) {
                console.warn('[auth] Turnstile timed out — proceeding without captcha');
                const wrap = document.getElementById('turnstile-wrap');
                if (wrap) wrap.classList.add('hidden');
            }
        }, 15000);
    }
    function clearTurnstileTimeout() {
        if (_turnstileTimeout) { clearTimeout(_turnstileTimeout); _turnstileTimeout = 0; }
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

                    nameEl.textContent = window.safeDisplayName(info);

                }

                if (usernameEl && info.telegram_username) {

                    usernameEl.textContent = '@' + info.telegram_username;

                    usernameEl.classList.remove('hidden');

                }

                if (photoEl && info.telegram_photo_url) {

                    const url = window.sanitizeTelegramPhotoUrl(info.telegram_photo_url);

                    if (!url) {
                        photoEl.classList.add('hidden');
                    } else {

                        photoEl.src = url;

                        photoEl.classList.remove('hidden');

                        const placeholder = document.getElementById('account-photo-placeholder');

                        if (placeholder) placeholder.classList.add('hidden');

                    }

                }



                if (info.is_verified) {

                    setStatusLabel(true);

                } else {

                    showEl('account-unverified');

                    setStatusLabel(false);

                }

                const profileLink = document.getElementById('account-profile-link');
                if (profileLink && info.uid) profileLink.href = window.getProfileHref(info.uid);

                resetAccountDecodeState();

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

                    if (nameEl) nameEl.textContent = window.safeDisplayName(devInfo);

                    const usernameEl = document.getElementById('account-username');

                    if (usernameEl && devInfo.telegram_username) { usernameEl.textContent = '@' + devInfo.telegram_username; usernameEl.classList.remove('hidden'); }

                    setStatusLabel(true);

                    resetAccountDecodeState();

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

        }

    }



    function isLocalhost() {

        const h = window.location.hostname;

        return h === 'localhost' || h === '127.0.0.1' || h === '::1';

    }



    function fillAccountFromCache(info) {

        hideEl('account-unverified');
        hideEl('account-username');
        hideEl('account-photo');
        showEl('account-photo-placeholder');
        hideEl('new-user-badge');

        const nameEl = document.getElementById('account-name');

        if (nameEl) {

            nameEl.textContent = window.safeDisplayName(info);

        }

        const usernameEl = document.getElementById('account-username');

        if (usernameEl && info.telegram_username) {

            usernameEl.textContent = '@' + info.telegram_username;

            usernameEl.classList.remove('hidden');

        }

        if (info.telegram_photo_url) {
            const url = window.sanitizeTelegramPhotoUrl(info.telegram_photo_url);
            if (url) {
                const photoEl = document.getElementById('account-photo');
                if (photoEl) {
                    photoEl.src = url;
                    photoEl.classList.remove('hidden');
                }
                hideEl('account-photo-placeholder');
            }
        }

        if (info.is_verified) {

            setStatusLabel(true);

        } else {

            showEl('account-unverified');

            setStatusLabel(false);

        }

        const profileLink = document.getElementById('account-profile-link');
        if (profileLink && info.uid) profileLink.href = window.getProfileHref(info.uid);

        resetAccountDecodeState();
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

        if (nameEl) nameEl.textContent = window.safeDisplayName(devInfo);

        const usernameEl = document.getElementById('account-username');

        if (usernameEl) { usernameEl.textContent = '@' + devInfo.telegram_username; usernameEl.classList.remove('hidden'); }

        setStatusLabel(true);

        showSuccessBadge();

        resetAccountDecodeState();

        // Delay success-glow so card-entrance animation plays first

        setTimeout(() => {

            const accountCard = document.querySelector('[data-view="account"]');

            if (accountCard) {

                accountCard.classList.add('success-glow');

                setTimeout(() => accountCard.classList.remove('success-glow'), 1800);

            }

        }, 500);

    }

    function renderTurnstile(keepVisible = false) {
        try {
            const wrap = document.getElementById('turnstile-wrap');
            if (wrap && ensureTurnstileScript()) {
                const container = wrap.querySelector('.cf-turnstile');
                if (container && !container.hasChildNodes()) {
                    turnstileWidgetId = turnstile.render(container, {
                        sitekey: window.TURNSTILE_SITE_KEY,
                        callback: onTurnstile,
                        'expired-callback': onTurnstileExpired,
                        theme: 'dark',
                        size: 'compact',
                    });
                }
                if (!turnstileToken && !keepVisible) wrap.classList.add('hidden');
            }
        } catch (e) { console.warn('Turnstile render error:', e.message); }
    }
    window._renderTurnstile = renderTurnstile;

    function init() {

        // CRITICAL: scramble all decode targets BEFORE first paint so user sees
        // the hackerdecode animation play, not plain text first.
        prescrambleAll();

        window.SUPABASE_URL = window.SUPABASE_URL || '';

        window.SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || '';

        Api.reinit();


window.onTelegramAuth = handleTelegramAuth;
initTelegramWidget();

const devBtn = document.getElementById('dev-login-btn');

if (devBtn) {

if (isLocalhost()) {

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

        // Keep sliding border aligned on resize
        window.addEventListener('resize', () => {
            const switchEl = document.getElementById('auth-mode-switch');
            if (switchEl) {
                const activeBtn = switchEl.querySelector('.auth-mode-btn.active');
                if (activeBtn) {
                    switchEl.style.setProperty('--switch-border-left', activeBtn.offsetLeft + 'px');
                    switchEl.style.setProperty('--switch-border-width', activeBtn.offsetWidth + 'px');
                }
            }
        });

        runInitialDecode();

        // Start plane loop animation timer
        startPlaneLoopTimer();

        const logoutBtn = document.getElementById('account-logout');

        if (logoutBtn) logoutBtn.addEventListener('click', async () => {

            localStorage.removeItem('nb_dev_session');

            localStorage.removeItem('nb_auth_cache');

            const tgContainer = document.getElementById('tg-widget-container');
            if (tgContainer) tgContainer.classList.remove('tg-auth-active');

            await Api.logout();

            // Reset decode flags so re-login re-triggers hackerDecode

            document.querySelectorAll('[data-view] *').forEach(el => {

                el._decodeFinal = undefined;

                el._decodeRunning = false;

                el._decoded = false;

            });

            showView('auth');

            hideEl('account-unverified');

            hideEl('account-username');

            hideEl('account-photo');

            showEl('account-photo-placeholder');

            hideEl('new-user-badge');

            const nameEl = document.getElementById('account-name');

            if (nameEl) nameEl.textContent = '';

            const usernameEl = document.getElementById('account-username');

            if (usernameEl) usernameEl.textContent = '';

            runInitialDecode();

        });



        checkExistingSession();

    }



    return { init, onTurnstile, onTurnstileExpired };

})();

document.addEventListener('DOMContentLoaded', AuthApp.init);
