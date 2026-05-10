const ProfileModule = (() => {



    let userInfo = null;



    let profileData = null;



    let profileUserId = null;



    let profileUserUid = null;



    let isOwnProfile = false;



    let editingBio = false;
    let editingUsername = false;



    let inviteInfo = null;



    let animationsRan = false;



    let userAchievements = [];



    let achievementsCatalog = [];



    const lockedAchievementTitleCache = new Map();



    let activityOffset = 0;



    const activityLimit = 15;



    let activityLoading = false;



    let activityHasMore = true;








    function getProfileHref(uid, userId) {
        if (uid !== undefined && uid !== null && String(uid) !== '') return getBasePath() + '/profile/uid-' + encodeURIComponent(uid);
        if (userId) return getBasePath() + '/profile.html?id=' + encodeURIComponent(userId);
        return '#';
    }

    function getBasePath() {
        const parts = window.location.pathname.split('/').filter(Boolean);
        if (window.location.hostname.endsWith('github.io') && parts.length > 0) return '/' + parts[0];
        return '';
    }

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

        'R':['████ ','█   █','████ ','█  █ ','█   █'],

        'S':[' ████','█    ',' ███ ','    █','████ '],

        'T':['█████','  █  ','  █  ','  █  ','  █  '],

        'U':['█   █','█   █','█   █','█   █',' ███ '],

        'V':['█   █','█   █','█   █',' █ █ ',' █ █ '],

        'X':['█   █',' █ █ ','  █  ',' █ █ ','█   █'],

        'Y':['█   █',' █ █ ','  █  ','  █  ','  █  '],

        'Z':['█████','   █ ','  █  ',' █   ','█████'],

        '0':[' ███ ','█  ██','█ █ █','██  █',' ███ '],

        '1':['  █  ',' ██  ','  █  ','  █  ','█████'],

        '2':[' ███ ','█   █','  ██ ',' █   ','█████'],

        '3':[' ███ ','█   █',' ████','    █',' ███ '],

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

        let html = '';

        let copyIndex = 0;

        for (const row of rows) {

            let line = '';

            for (const ch of row) {

                if (ch === '█') line += `<span class="ascii-bright" style="--copy-i:${copyIndex++}">█</span>`;

                else if (ch === ' ') line += `<span class="ascii-dim" style="--copy-i:${copyIndex++}">·</span>`;

                else line += ch;

            }

            html += line + '\n';

        }

        return `<pre class="invite-ascii-text">${html}</pre>`;

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
    let _inviteDecodeSeq = 0;

    let _copyAnimRafId = 0;
    let _copyAnimSeq = 0;

    let _inviteGen = 0;

    let _hoverTimer = null;

    let _inviteTimerId = null;

    let _inviteTimerFinalizeId = null;



    const INVITE_INFINITE_TTL_SECONDS = 35996400;

    const INVITE_INFINITE_LABEL = 'бесконечность';



    function isInviteInfiniteTTL(totalSeconds) {

        return Number(totalSeconds || 0) >= INVITE_INFINITE_TTL_SECONDS;

    }



    function formatTTL(totalSeconds) {

        const totalSec = Math.max(0, Math.round(totalSeconds));

        const h = Math.floor(totalSec / 3600);

        if (isInviteInfiniteTTL(totalSec)) return INVITE_INFINITE_LABEL;

        const m = Math.floor((totalSec % 3600) / 60);

        const sec = totalSec % 60;

        return `${h} ч ${m} мин ${sec} сек`;

    }



    function formatInviteExpiry(totalSeconds) {

        return isInviteInfiniteTTL(totalSeconds) ? INVITE_INFINITE_LABEL : 'истекает через ' + formatTTL(totalSeconds);

    }



    function hackerDecodeStable(el, target, duration) {

        if (el._hackerDecodeRaf) { cancelAnimationFrame(el._hackerDecodeRaf); el._hackerDecodeRaf = 0; }

        const glyphs = '░▒▓█▀▄▌▐│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬';

        const len = target.length;

        const t0 = performance.now();

        const dur = duration || 180;

        const step = (now) => {

            if (!el.isConnected) { el._hackerDecodeRaf = 0; return; }

            const t = Math.min((now - t0) / dur, 1);

            const reveal = Math.floor(t * len);

            let out = '';

            for (let i = 0; i < len; i++) {

                if (i < reveal) {

                    out += target[i];

                } else if (target[i] === ' ') {

                    out += ' ';

                } else {

                    out += glyphs[Math.floor(Math.random() * glyphs.length)];

                }

            }

            el.textContent = t < 1 ? out : target;

            if (t < 1) {

                el._hackerDecodeRaf = requestAnimationFrame(step);

            } else {

                el._hackerDecodeRaf = 0;

            }

        };

        el._hackerDecodeRaf = requestAnimationFrame(step);

    }



    function startInviteExpiryTimer(totalSeconds, root) {

        if (_inviteTimerId) { clearInterval(_inviteTimerId); _inviteTimerId = null; }

        if (_inviteTimerFinalizeId) { clearTimeout(_inviteTimerFinalizeId); _inviteTimerFinalizeId = null; }

        const scope = root || document;

        const el = scope.querySelector ? scope.querySelector('.profile-account-invite-expiry') : document.querySelector('.profile-account-invite-expiry');

        if (!el) return;

        if (isInviteInfiniteTTL(totalSeconds)) { el.textContent = INVITE_INFINITE_LABEL; return; }

        const deadline = Date.now() + Math.max(0, Number(totalSeconds || 0)) * 1000;

        let prevH = null, prevM = null, prevS = null;

        const tick = (animate) => {

            if (!el.isConnected) {

                if (_inviteTimerId) { clearInterval(_inviteTimerId); _inviteTimerId = null; }

                return;

            }

            const remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));

            const h = Math.floor(remaining / 3600);

            const m = Math.floor((remaining % 3600) / 60);

            const sec = remaining % 60;

            const hText = `${h} ч`;

            const mText = `${m} мин`;

            const sText = `${sec} сек`;

            const prefix = 'истекает через ';

            let html = prefix;

            const buildSpan = (text, changed, key) => {

                if (animate && changed) {

                    return `<span class="profile-account-invite-expiry-part" data-expiry-part="${key}">${text}</span>`;

                }

                return text;

            };

            html += buildSpan(hText, animate && prevH !== null && prevH !== h, 'h') + ' ';

            html += buildSpan(mText, animate && prevM !== null && prevM !== m, 'm') + ' ';

            html += buildSpan(sText, animate && prevS !== null && prevS !== sec, 's');

            if (animate) {

                if (_inviteTimerFinalizeId) { clearTimeout(_inviteTimerFinalizeId); _inviteTimerFinalizeId = null; }

                el.innerHTML = html;

                el.querySelectorAll('[data-expiry-part]').forEach(part => {

                    const target = part.textContent;

                    part.textContent = '';

                    hackerDecodeStable(part, target, 140);

                });

                _inviteTimerFinalizeId = setTimeout(() => {

                    if (!el.isConnected) return;

                    el.textContent = prefix + hText + ' ' + mText + ' ' + sText;

                    _inviteTimerFinalizeId = null;

                }, 220);

            } else {

                el.textContent = prefix + hText + ' ' + mText + ' ' + sText;

            }

            prevH = h; prevM = m; prevS = sec;

            if (remaining <= 0 && _inviteTimerId) { clearInterval(_inviteTimerId); _inviteTimerId = null; }

        };

        tick(false);

        _inviteTimerId = setInterval(() => tick(true), 1000);

    }



function decodeInviteAscii(code) {

    const ascii = document.getElementById('account-invite-ascii');

    const plain = document.getElementById('account-invite-plain');

    const raw = document.getElementById('account-invite-code');

    if (raw) raw.textContent = code;

    if (plain) plain.textContent = code;

    if (!ascii) return;

    if (_decodeRafId) { cancelAnimationFrame(_decodeRafId); _decodeRafId = 0; }
    const decodeSeq = ++_inviteDecodeSeq;

    const hadContent = ascii.querySelector('.invite-ascii-text');
    if (hadContent) {
        ascii.classList.add('invite-code-fading');
    }

    _decodeRafId = requestAnimationFrame(() => {

    _decodeRafId = 0;
    if (decodeSeq !== _inviteDecodeSeq || !ascii.isConnected) return;

    ascii.innerHTML = renderInviteAscii(code);

    if (hadContent) {
        void ascii.offsetWidth;
        ascii.classList.remove('invite-code-fading');
    }

    void ascii.offsetWidth;

    const tokenBox = ascii.closest('.profile-invite-token-box');

    if (tokenBox) {

        if (tokenBox._inviteGenFadeTimer) {
            clearTimeout(tokenBox._inviteGenFadeTimer);
            tokenBox._inviteGenFadeTimer = null;
        }

        tokenBox.classList.remove('invite-generating');
        tokenBox.classList.remove('invite-gen-fading');
        tokenBox.classList.remove('invite-border-reappearing');
        if (tokenBox._inviteBorderTimer) { clearTimeout(tokenBox._inviteBorderTimer); tokenBox._inviteBorderTimer = null; }

        void tokenBox.offsetWidth;

        tokenBox.classList.add('invite-generating');

    }

        const spans = ascii.querySelectorAll('.invite-ascii-text span');

        if (!spans.length) return;

        const total = spans.length;

        const brightPool = '\u2588\u2593\u2592\u2591\u2502\u2524\u251c\u2563\u2554\u255a';
        const dimPool   = '\u00b7\u2219\u02d9\'\"';
        const brightReduced = '\u2588\u2593\u2592\u2591';
        const dimReduced    = '\u00b7\u2219';
        const fs = parseFloat(getComputedStyle(spans[0]).fontSize) || 8;
        const offsetScale = fs < 7 ? 0.55 : 1;
        const cols = Math.round(total / 5);
        const centerCol = (cols - 1) / 2;
        const CONVERGE_DUR = 300;
        const CHAOS_DUR    = 200;
        const STAGGER_SPAN = 380;

        const targets   = new Array(total);
        const isBright  = new Uint8Array(total);
        const offX      = new Float32Array(total);
        const offY      = new Float32Array(total);
        const convStart = new Float32Array(total);
        const glyphNext = new Float32Array(total);
        const lockedAt  = new Float32Array(total);
        const frozen    = new Uint8Array(total);

        for (let i = 0; i < total; i++) {
            const s = spans[i];
            targets[i]  = s.textContent;
            isBright[i] = s.classList.contains('ascii-bright') ? 1 : 0;
            const row = Math.floor(i / cols);
            const col = i % cols;
            const dc = col - centerCol;
            const dr = row - 2;
            const maxD = Math.sqrt(centerCol * centerCol + 4) || 1;
            const norm = Math.sqrt(dc*dc + dr*dr) / maxD + (Math.random()-0.5)*0.3;
            const angle = Math.random() * Math.PI * 2;
            const dist  = (22 + Math.random() * 40) * offsetScale;
            offX[i] = Math.cos(angle) * dist;
            offY[i] = Math.sin(angle) * dist;
            convStart[i] = CHAOS_DUR + Math.max(0, Math.min(1, norm)) * STAGGER_SPAN;
            glyphNext[i] = 0;
            lockedAt[i]  = 0;
            const pool = isBright[i] ? brightPool : dimPool;
            s.textContent = pool[Math.floor(Math.random() * pool.length)];
            s.style.opacity = '0';
            s.style.transform = 'translate(' + offX[i].toFixed(1) + 'px,' + offY[i].toFixed(1) + 'px) translateZ(0)';
            s.style.filter = 'blur(0.8px)';
        }

        const t0 = performance.now();

        const step = (now) => {

            if (decodeSeq !== _inviteDecodeSeq || !ascii.isConnected) {
                _decodeRafId = 0;
                if (tokenBox) {
                    tokenBox.classList.remove('invite-generating', 'invite-gen-fading');
                    if (tokenBox._inviteBorderTimer) { clearTimeout(tokenBox._inviteBorderTimer); tokenBox._inviteBorderTimer = null; }
                    void tokenBox.offsetWidth;
                    tokenBox.classList.add('invite-border-reappearing');
                    tokenBox._inviteBorderTimer = setTimeout(() => {
                        tokenBox.classList.remove('invite-border-reappearing');
                        tokenBox._inviteBorderTimer = null;
                    }, 300);
                }
                for (let i = 0; i < total; i++) {
                    const el = spans[i];
                    if (el && el.isConnected) {
                        el.textContent = targets[i];
                        el.style.transform = '';
                        el.style.opacity = '';
                        el.style.filter = '';
                    }
                }
                return;
            }

            const elapsed = now - t0;
            let allDone = true;

            for (let i = 0; i < total; i++) {
                const el = spans[i];
                if (!el || !el.isConnected) continue;

                if (frozen[i]) {
                    const sinceLock = now - lockedAt[i];
                    if (sinceLock < 100) {
                        const f = 1 + 1.0 * (1 - sinceLock / 100);
                        el.style.filter = 'brightness(' + f.toFixed(2) + ')';
                        const sc = 1 + 0.12 * (1 - sinceLock / 100);
                        el.style.transform = 'scale(' + sc.toFixed(3) + ') translateZ(0)';
                    } else {
                        el.style.filter = '';
                        el.style.transform = '';
                    }
                    continue;
                }

                const cs = convStart[i];

                if (elapsed < CHAOS_DUR) {
                    allDone = false;
                    const appearT = Math.min(elapsed / 80, 1);
                    const drift = Math.sin(now * 0.009 + i * 2.1) * 3 * offsetScale;
                    el.style.transform = 'translate(' + (offX[i] + drift).toFixed(1) + 'px,' + offY[i].toFixed(1) + 'px) translateZ(0)';
                    el.style.opacity = (0.35 * appearT + Math.random() * 0.1).toFixed(2);
                    el.style.filter = 'blur(0.6px)';
                    if (now >= glyphNext[i]) {
                        const pool = isBright[i] ? brightPool : dimPool;
                        el.textContent = pool[Math.floor(Math.random() * pool.length)];
                        glyphNext[i] = now + 70 + Math.random() * 50;
                    }
                } else if (elapsed < cs) {
                    allDone = false;
                    const drift = Math.sin(now * 0.008 + i * 1.7) * 3 * offsetScale;
                    el.style.transform = 'translate(' + (offX[i] + drift).toFixed(1) + 'px,' + offY[i].toFixed(1) + 'px) translateZ(0)';
                    el.style.opacity = (0.38 + Math.random() * 0.12).toFixed(2);
                    el.style.filter = 'blur(0.5px)';
                    if (now >= glyphNext[i]) {
                        const pool = isBright[i] ? brightPool : dimPool;
                        el.textContent = pool[Math.floor(Math.random() * pool.length)];
                        glyphNext[i] = now + 80 + Math.random() * 60;
                    }
                } else {
                    const localT = Math.min((elapsed - cs) / CONVERGE_DUR, 1);
                    const easedT = 1 - Math.pow(1 - localT, 3);
                    if (localT < 1) {
                        allDone = false;
                        const tx = offX[i] * (1 - easedT);
                        const ty = offY[i] * (1 - easedT);
                        el.style.transform = 'translate(' + tx.toFixed(1) + 'px,' + ty.toFixed(1) + 'px) translateZ(0)';
                        el.style.opacity = (0.38 + 0.62 * easedT).toFixed(2);
                        const blur = 0.5 * (1 - easedT);
                        el.style.filter = blur > 0.05 ? 'blur(' + blur.toFixed(1) + 'px)' : '';
                        if (localT < 0.25) {
                            if (now >= glyphNext[i]) {
                                const pool = isBright[i] ? brightPool : dimPool;
                                el.textContent = pool[Math.floor(Math.random() * pool.length)];
                                glyphNext[i] = now + 65 + Math.random() * 45;
                            }
                        } else if (localT < 0.6) {
                            if (now >= glyphNext[i]) {
                                const pool = isBright[i] ? brightReduced : dimReduced;
                                el.textContent = pool[Math.floor(Math.random() * pool.length)];
                                glyphNext[i] = now + 85 + Math.random() * 55;
                            }
                        } else {
                            if (Math.random() < 0.18 && now >= glyphNext[i]) {
                                const pool = isBright[i] ? brightReduced : dimReduced;
                                el.textContent = pool[Math.floor(Math.random() * pool.length)];
                                glyphNext[i] = now + 60;
                            } else {
                                el.textContent = targets[i];
                            }
                        }
                    } else {
                        frozen[i] = 1;
                        el.textContent = targets[i];
                        el.style.opacity = '';
                        el.style.filter = 'brightness(2.0)';
                        el.style.transform = 'scale(1.12) translateZ(0)';
                        lockedAt[i] = now;
                    }
                }
            }

            if (!allDone) {
                _decodeRafId = requestAnimationFrame(step);
            } else {
                _decodeRafId = 0;
                if (tokenBox) {
                    tokenBox.classList.remove('invite-generating');
                    void tokenBox.offsetWidth;
                    tokenBox.classList.add('invite-border-reappearing');
                    if (tokenBox._inviteBorderTimer) clearTimeout(tokenBox._inviteBorderTimer);
                    tokenBox._inviteBorderTimer = setTimeout(() => {
                        tokenBox.classList.remove('invite-border-reappearing');
                        tokenBox._inviteBorderTimer = null;
                    }, 300);
                }
                for (let i = 0; i < total; i++) {
                    const el = spans[i];
                    if (el && el.isConnected) {
                        el.textContent = targets[i];
                        el.style.transform = '';
                        el.style.opacity = '';
                        el.style.filter = '';
                    }
                }
            }
        };

        _decodeRafId = requestAnimationFrame(step);

    });

    }



    function finishDecodeAnimation() {

        if (_decodeRafId) { cancelAnimationFrame(_decodeRafId); _decodeRafId = 0; }
        _inviteDecodeSeq++;

        const ascii = document.getElementById('account-invite-ascii');

        const raw = document.getElementById('account-invite-code');

        if (ascii && raw && raw.textContent) {

            ascii.innerHTML = renderInviteAscii(raw.textContent.trim());

        }

        const tokenBox = ascii ? ascii.closest('.profile-invite-token-box') : null;
        if (tokenBox) {
            tokenBox.classList.remove('invite-generating', 'invite-gen-fading', 'invite-border-reappearing');
            if (tokenBox._inviteBorderTimer) { clearTimeout(tokenBox._inviteBorderTimer); tokenBox._inviteBorderTimer = null; }
            void tokenBox.offsetWidth;
            tokenBox.classList.add('invite-border-reappearing');
            tokenBox._inviteBorderTimer = setTimeout(() => {
                tokenBox.classList.remove('invite-border-reappearing');
                tokenBox._inviteBorderTimer = null;
            }, 300);
        }

    }


    function triggerInviteCopyAnimation(asciiEl) {
        if (!asciiEl) return 460;
        finishDecodeAnimation();
        if (_copyAnimRafId) { cancelAnimationFrame(_copyAnimRafId); _copyAnimRafId = 0; }
        const copySeq = ++_copyAnimSeq;
        const tokenBox = asciiEl.closest('.profile-invite-token-box');
        const spans = asciiEl.querySelectorAll('.invite-ascii-text span');
        if (!spans.length) return 460;

        /* reduced-motion: skip animation entirely */
        if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return 460;

        if (tokenBox) {
            if (tokenBox._inviteCopyTimer) clearTimeout(tokenBox._inviteCopyTimer);
            if (tokenBox._inviteBoxTimer) { clearTimeout(tokenBox._inviteBoxTimer); tokenBox._inviteBoxTimer = null; }
            if (tokenBox._inviteSettleTimer) { clearTimeout(tokenBox._inviteSettleTimer); tokenBox._inviteSettleTimer = null; }
            if (tokenBox._inviteRestoreTimer) { clearTimeout(tokenBox._inviteRestoreTimer); tokenBox._inviteRestoreTimer = null; }
            if (tokenBox._inviteGenFadeTimer) { clearTimeout(tokenBox._inviteGenFadeTimer); tokenBox._inviteGenFadeTimer = null; }
            const wasGenerating = tokenBox.classList.contains('invite-generating');
            if (wasGenerating) tokenBox.classList.add('invite-gen-fading');
            tokenBox.classList.remove('invite-copy-burst', 'invite-copy-box-burst', 'invite-copy-settling', 'invite-copy-restoring', 'invite-copy-assembling', 'invite-border-reappearing', 'invite-copy-wave');
            if (tokenBox._inviteBorderTimer) { clearTimeout(tokenBox._inviteBorderTimer); tokenBox._inviteBorderTimer = null; }
            void tokenBox.offsetWidth;
            tokenBox.classList.add('invite-copy-wave');
            if (wasGenerating) {
                tokenBox._inviteGenFadeTimer = setTimeout(() => {
                    tokenBox.classList.remove('invite-generating', 'invite-gen-fading');
                    tokenBox._inviteGenFadeTimer = null;
                }, 150);
            } else {
                tokenBox.classList.remove('invite-generating');
            }
        }

        const total = spans.length;
        const fs = parseFloat(getComputedStyle(spans[0]).fontSize) || 8;
        const isMobile = fs < 7;
        const STAGGER = isMobile ? 14 : 20;
        const FLASH_DUR = 70;
        const totalDuration = total * STAGGER + FLASH_DUR + 160;

        /* Get role accent color from CSS variable */
        let roleColor = '';
        if (tokenBox) {
            const cs = getComputedStyle(tokenBox);
            const rgb = cs.getPropertyValue('--profile-account-rgb').trim();
            if (rgb) roleColor = 'rgba(' + rgb + ',0.95)';
        }

        const t0 = performance.now();
        const highlighted = new Uint8Array(total);

        const step = (now) => {
            if (copySeq !== _copyAnimSeq || !asciiEl.isConnected) {
                _copyAnimRafId = 0;
                if (tokenBox) tokenBox.classList.remove('invite-copy-wave');
                for (let i = 0; i < total; i++) {
                    const el = spans[i];
                    if (el && el.isConnected) {
                        el.style.color = '';
                        el.style.filter = '';
                        el.style.textShadow = '';
                    }
                }
                return;
            }
            const elapsed = now - t0;
            let allDone = true;

            for (let i = 0; i < total; i++) {
                const el = spans[i];
                if (!el || !el.isConnected) continue;

                const hitAt = i * STAGGER;
                if (elapsed < hitAt) {
                    allDone = false;
                    continue;
                }

                if (!highlighted[i]) {
                    highlighted[i] = 1;
                    if (roleColor) el.style.color = roleColor;
                    el.style.filter = 'brightness(2.4)';
                    el.style.textShadow = '0 0 10px ' + (roleColor || 'rgba(255,255,255,0.5)') + ', 0 0 22px ' + (roleColor || 'rgba(255,255,255,0.25)');
                }

                const sinceHit = elapsed - hitAt;
                if (sinceHit < FLASH_DUR) {
                    allDone = false;
                } else {
                    /* CSS transition handles the fade-back */
                    el.style.color = '';
                    el.style.filter = '';
                    el.style.textShadow = '';
                }
            }

            if (!allDone) {
                _copyAnimRafId = requestAnimationFrame(step);
            } else {
                _copyAnimRafId = 0;
                if (tokenBox) {
                    tokenBox.classList.remove('invite-copy-wave');
                }
                for (let i = 0; i < total; i++) {
                    const el = spans[i];
                    if (el && el.isConnected) {
                        el.style.color = '';
                        el.style.filter = '';
                        el.style.textShadow = '';
                    }
                }
            }
        };
        _copyAnimRafId = requestAnimationFrame(step);
        return totalDuration;
    }


    const glyphPoolCache = new Map();



    const glyphMetricsCanvas = document.createElement('canvas');



    const glyphMetricsCtx = glyphMetricsCanvas.getContext('2d');



    const achievementIconAssets = Object.freeze({



        welcome: 'assets/achievements/welcome.png',



        // first_post removed — achievement deleted from DB in 04-achievements.sql



        first_referral: 'assets/achievements/first_referral.png',



        first_thread: 'assets/achievements/first_thread.png',



        first_reaction: 'assets/achievements/first_reaction.png',



        profile_tuned: 'assets/achievements/profile_tuned.png',



        daily_login: 'assets/achievements/daily_login.png',



        first_comment: 'assets/achievements/first_comment.png',



        first_model_rate: 'assets/achievements/first_model_rate.png',



        first_mention: 'assets/achievements/first_mention.png',



        first_edit: 'assets/achievements/first_edit.png',



        silent_wave: 'assets/achievements/silent_wave.png',



        puke_gradient: 'assets/achievements/puke_gradient.png',



        binding_layer: 'assets/achievements/binding_layer.png',



        models_remember: 'assets/achievements/models_remember.png',



        before_public_launch: 'assets/achievements/before_public_launch.png',



        beta_user: 'assets/achievements/beta_user.png',



        silent_observer: 'assets/achievements/silent_observer.png',



        overfitting: 'assets/achievements/overfitting.png',



        seven_day_streak: 'assets/achievements/seven_day_streak.png',



        night_shift: 'assets/achievements/night_shift.png',



        archaeologist: 'assets/achievements/archaeologist.png',



        cluster_formed: 'assets/achievements/cluster_formed.png',



        benchmark_oracle: 'assets/achievements/benchmark_oracle.png',



        first_among_equals: 'assets/achievements/first_among_equals.png',



        alpha_user: 'assets/achievements/alpha_user.png',



        moderator_power: 'assets/achievements/moderator_power.png',



        the_first_hundred: 'assets/achievements/the_first_hundred.png'



    });



    const achievementIconVersion = '20260502g';







    function escapeHtml(str) {



        if (!str) return '';



        const d = document.createElement('div');



        d.textContent = str;



        return d.innerHTML.replace(/"/g, '&quot;');



    }







    function renderAchievementIcon(id, iconEmoji, variant) {



        const assetPath = achievementIconAssets[id];



        if (assetPath) {



            const mediaClass = variant === 'showcase' ? 'showcase-icon-media' : 'ach-icon-media';



            const fallbackClass = variant === 'showcase' ? 'showcase-icon-emoji' : 'ach-icon';



            const fallbackEmoji = escapeHtml(iconEmoji || '🏅');



            return `<img class="${mediaClass}" src="${assetPath}?v=${achievementIconVersion}" alt="" aria-hidden="true" decoding="async" data-fallback="${fallbackEmoji}" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'${fallbackClass}',textContent:this.dataset.fallback||'🏅'}))">`;



        }







        if (variant === 'showcase') {



            return `<span class="showcase-icon-emoji">${escapeHtml(iconEmoji || '🏅')}</span>`;



        }







        return `<span class="ach-icon">${escapeHtml(iconEmoji || '🏅')}</span>`;



    }







    function cleanText(str, maxLen) {



        if (!str) return '';



        let s = str.replace(/[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]/g, '');



        s = s.replace(/\s+/g, ' ').trim();



        if (maxLen && s.length > maxLen) s = s.slice(0, maxLen);



        return s;



    }







    function hackerDecode(el, target, duration) {



        const glyphs = '░▒▓█▀▄▌▐│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬';



        const len = target.length;



        el.textContent = target;



        const h = el.offsetHeight;



        el.style.height = h + 'px';



        el.style.overflow = 'hidden';



        el.textContent = '';



        const t0 = performance.now();



        const dur = duration || 550;



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



                    out += glyphs[Math.floor(Math.random() * glyphs.length)];



                }



            }



            el.textContent = out;



            if (t < 1) {



                requestAnimationFrame(step);



            } else {



                el.textContent = target;



                el.style.height = '';



                el.style.overflow = '';



            }



        }



        requestAnimationFrame(step);



    }







    function runDecodeAnimations() {



        if (animationsRan) return;



        animationsRan = true;



        const targets = [



            { sel: '.profile-name', delay: 0 },



            { sel: '.profile-username', delay: 0 },



            { sel: '.profile-uid', delay: 0 },



            { sel: '.profile-joined', delay: 0 },



            { sel: '.profile-role-badge', delay: 0 },



            { sel: '.profile-banner-copy strong', delay: 0 },



            { sel: '.profile-account-invite-quota-value', delay: 0 },



            { sel: '.profile-section-title', delay: 0 },



            { sel: '.profile-level-name', delay: 0 },



            { sel: '.profile-tab', delay: 0 },



            { sel: '.profile-mini-label', delay: 0 },



            { sel: '.profile-bio-edit-btn', delay: 0 },



            { sel: '#btn-save-bio', delay: 0 },



            { sel: '#btn-cancel-bio', delay: 0 },



        ];



        targets.forEach(({ sel, delay }) => {



            document.querySelectorAll(sel).forEach(el => {



                if (!el || el._decoded) return;



                const text = el.textContent.trim();



                if (!text) return;



                el._decoded = true;



                setTimeout(() => hackerDecode(el, text), delay);



            });



        });







        document.querySelectorAll('[data-decode]').forEach(el => {



            if (el._decoded) return;



            const text = el.textContent.trim();



            if (!text) return;



            el._decoded = true;



            hackerDecode(el, text);



        });



    }







    function runAccountDecodeAnimations(root) {



        const scope = root || document;



        const elements = scope === document

            ? scope.querySelectorAll('.profile-account-card [data-decode]')

            : scope.querySelectorAll('[data-decode]');



        elements.forEach(el => {



            if (el._decoded) return;



            const text = el.textContent.trim();



            if (!text) return;



            el._decoded = true;



            hackerDecode(el, text);



        });



    }







    function formatDate(dateVal) {



        if (!dateVal) return '';



        const d = new Date(dateVal);



        const day = String(d.getDate()).padStart(2, '0');



        const month = String(d.getMonth() + 1).padStart(2, '0');



        return `${day}.${month}.${d.getFullYear()}`;



    }







    function formatActivityTime(dateVal) {



        if (!dateVal) return '';



        const d = new Date(dateVal);



        const now = new Date();



        const diffMs = now - d;



        const diffMins = Math.floor(diffMs / 60000);



        const diffHours = Math.floor(diffMs / 3600000);



        const diffDays = Math.floor(diffMs / 86400000);



        if (diffMins < 1) return 'только что';



        if (diffMins < 60) return `${diffMins} мин назад`;



        if (diffHours < 24) return `${diffHours} ч назад`;



        if (diffDays === 1) return 'вчера';



        if (diffDays < 7) return `${diffDays} дн назад`;



        return formatDate(dateVal);



    }







    function isLocalhost() {



        return ['localhost', '127.0.0.1', '::1'].includes(window.location.hostname);



    }







    function makeDevInviteCode() {



        return Math.random().toString(36).replace(/[^a-z0-9]/gi, '').slice(2, 10).toUpperCase().padEnd(8, 'X');



    }







    async function init() {



        Api.reinit();







        const devRaw = localStorage.getItem('nb_dev_session');



        if (devRaw) {



            try {



                const dev = JSON.parse(devRaw);



                userInfo = dev;



                if (userInfo.invite_max === undefined) {



                    userInfo.invite_max = userInfo.role === 'admin' ? 999999 : 1;



                    userInfo.invite_active_count = 0;



                    userInfo.has_generated_invite = false;



                    userInfo.generated_code = null;



                    userInfo.invite_use_count = 0;



                    localStorage.setItem('nb_dev_session', JSON.stringify(userInfo));



                }



                initNavUser();



            } catch (e) { console.warn('[profile] dev session parse error:', e); }



        }







        const query = new URLSearchParams(window.location.search);
        const queryUid = query.get('uid');
        const queryId = query.get('id');

        const pathParts = window.location.pathname.split('/').filter(Boolean);
        const lastPart = pathParts[pathParts.length - 1];
        const isProfilePage = lastPart === 'profile' || pathParts[pathParts.length - 2] === 'profile';
        const pathUidMatch = window.location.pathname.match(/\/profile\/uid-(\d+)$/);
        let requestedId = null;
        let requestedUid = null;
        if (pathUidMatch) {
            requestedUid = parseInt(pathUidMatch[1], 10);
        } else if (queryUid && /^\d+$/.test(queryUid)) {
            requestedUid = parseInt(queryUid, 10);
        } else if (queryId) {
            requestedId = queryId;
        } else if (isProfilePage && lastPart !== 'profile') {
            if (/^\d+$/.test(lastPart)) {
                requestedUid = parseInt(lastPart, 10);
            } else {
                requestedId = lastPart;
            }
        }







        if (requestedUid) {



            profileUserId = null;
            profileUserUid = requestedUid;



            isOwnProfile = userInfo && userInfo.uid === requestedUid;



        } else if (requestedId) {



            profileUserId = requestedId;



            isOwnProfile = userInfo && requestedId === userInfo.user_id;



        } else if (userInfo) {



            profileUserId = userInfo.user_id;



            isOwnProfile = true;



        }







        if (isOwnProfile && devRaw) {



            try {



                const dev = JSON.parse(devRaw);



                profileData = {



                    telegram_first_name: dev.telegram_first_name || '',



                    telegram_last_name: dev.telegram_last_name || '',



                    telegram_username: dev.telegram_username || 'devuser',



                    telegram_photo_url: dev.telegram_photo_url || '',



                    bio: dev.bio || 'Dev-аккаунт для локальной разработки',



                    is_moderator: dev.is_moderator || false,



                    role: dev.role || 'admin',



                    is_verified: true,



                    created_at: '2026-02-19T10:30:00Z',



                    threads_count: 4,



                    posts_count: 30,



                    achievement_points: 295,



                    achievements_count: 6,



                    showcased_achievements: [



                        { id: 'benchmark_oracle', title: 'Получение признание', icon_emoji: '🔮', rarity: 'unique', points: 40 },



                        { id: 'the_first_hundred', title: 'Первые 100 пользователей', icon_emoji: '💎', rarity: 'limited', points: 150 },



                        { id: 'first_among_equals', title: 'Первые 10 пользователей', icon_emoji: '👑', rarity: 'unique', points: 75 }



                    ]



                };



                userAchievements = [



                    { achievement_id: 'welcome', title: 'Добро пожаловать', description: 'Зарегистрироваться на сайте', category: 'starter', rarity: 'common', points: 5, icon_emoji: '👋', is_secret: false, unlocked_at: '2026-02-19T10:30:00Z', is_showcased: false },



                    { achievement_id: 'first_referral', title: 'Первый приглашённый', description: 'Пригласить 1 пользователя', category: 'starter', rarity: 'common', points: 10, icon_emoji: '🤝', is_secret: false, unlocked_at: '2026-03-05T14:20:00Z', is_showcased: false },



                    { achievement_id: 'benchmark_oracle', title: 'Получение признание', description: 'Получить закреп треда от администратора', category: 'unique', rarity: 'unique', points: 40, icon_emoji: '🔮', is_secret: false, unlocked_at: '2026-03-12T09:15:00Z', is_showcased: true },



                    { achievement_id: 'models_remember', title: 'Реакция модератора', description: 'Получить реакцию от модератора или админа', category: 'rare', rarity: 'rare', points: 35, icon_emoji: '🤖', is_secret: false, unlocked_at: '2026-04-01T18:40:00Z', is_showcased: false },



                    { achievement_id: 'first_among_equals', title: 'Первые 10 пользователей', description: 'Войти в первые 10 зарегистрированных', category: 'unique', rarity: 'unique', points: 75, icon_emoji: '👑', is_secret: false, unlocked_at: '2026-02-19T10:30:00Z', is_showcased: true },



                    { achievement_id: 'the_first_hundred', title: 'Первые 100 пользователей', description: 'Войти в первые 100 зарегистрированных аккаунтов', category: 'secret_limited', rarity: 'limited', points: 150, icon_emoji: '💎', is_secret: true, unlocked_at: '2026-02-19T10:30:00Z', is_showcased: true },



                    { achievement_id: 'alpha_user', title: 'Альфа-пользователь', description: 'Получить alpha-роль', category: 'unique', rarity: 'unique', points: 60, icon_emoji: '⚡', is_secret: false, unlocked_at: '2026-02-20T12:00:00Z', is_showcased: false },



                    { achievement_id: 'moderator_power', title: 'Модератор', description: 'Получить роль модератора', category: 'unique', rarity: 'unique', points: 80, icon_emoji: '🗡️', is_secret: false, unlocked_at: '2026-03-01T08:00:00Z', is_showcased: false }



                ];



                achievementsCatalog = [



                    ...userAchievements.map(a => ({ ...a, id: a.achievement_id, max_supply: a.achievement_id === 'the_first_hundred' ? 100 : null, total_unlocked: a.achievement_id === 'the_first_hundred' ? 47 : 0, sort_order: 0 })),



                    { id: 'silent_wave', title: 'Без негатива', description: 'Получить 20 реакций на посте без dislike', category: 'rare', rarity: 'rare', points: 25, icon_emoji: '🌊', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 11 },



                    { id: 'puke_gradient', title: 'Несварение желудка', description: 'Получить 20 puke-реакций на одном посте', category: 'rare', rarity: 'rare', points: 30, icon_emoji: '🤮', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 12 },



                    { id: 'binding_layer', title: 'Три приглашения', description: 'Пригласить 3 пользователей', category: 'rare', rarity: 'rare', points: 20, icon_emoji: '🔗', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 13 },



                    { id: 'cluster_formed', title: 'Десять приглашений', description: 'Пригласить 10 пользователей', category: 'unique', rarity: 'unique', points: 50, icon_emoji: '🧬', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 22 },



                    { id: 'silent_observer', title: '30 дней тишины', description: 'Не писать посты 30 дней после регистрации', category: 'rare', rarity: 'rare', points: 20, icon_emoji: '👁️', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 17 },



                    { id: 'overfitting', title: '100 постов', description: 'Написать 100 постов на форуме', category: 'rare', rarity: 'rare', points: 45, icon_emoji: '🧠', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 18 },



                    { id: 'before_public_launch', title: 'До запуска', description: 'Создать аккаунт до публичного запуска', category: 'rare', rarity: 'rare', points: 25, icon_emoji: '🕰️', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 15 },



                    { id: 'beta_user', title: 'Бета-пользователь', description: 'Получить beta-роль', category: 'rare', rarity: 'rare', points: 30, icon_emoji: '🧪', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 16 },



                    { id: 'seven_day_streak', title: 'Семидневка', description: 'Зайти на сайт 7 дней подряд', category: 'rare', rarity: 'rare', points: 25, icon_emoji: '🔥', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 19 },



                    { id: 'night_shift', title: 'Ночная смена', description: 'Опубликовать пост между 02:00 и 05:00', category: 'rare', rarity: 'rare', points: 20, icon_emoji: '🌙', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 20 },



                    { id: 'archaeologist', title: 'Археолог', description: 'Ответить в тред старше 90 дней', category: 'rare', rarity: 'rare', points: 25, icon_emoji: '🦴', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 21 },



                    { id: 'first_mention', title: 'Упоминание', description: 'Упомянуть пользователя через @', category: 'starter', rarity: 'common', points: 5, icon_emoji: '📣', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 9 },



                    { id: 'first_edit', title: 'Редактор', description: 'Отредактировать свой пост или комментарий', category: 'starter', rarity: 'common', points: 5, icon_emoji: '✏️', is_secret: false, max_supply: null, total_unlocked: 0, sort_order: 10 }



                ];



                renderProfile();



                return;



            } catch (e) { console.warn('[profile] dev profile error:', e); }



        }







        if (!userInfo && typeof Api !== 'undefined' && Api.getSession) {



            try {



                const session = await Api.getSession();



                if (session) {



                    userInfo = await Api.getUserDisplayName();



                    if (userInfo) userInfo.user_id = session.user.id;



                    initNavUser();



                    if (!requestedId && userInfo) {



                        profileUserId = userInfo.user_id;



                        isOwnProfile = true;



                    }



                }



            } catch (e) { console.warn('[profile] session init error:', e); }



        }







        if (!profileUserId && !profileUserUid) {



            renderNoProfile();



            return;



        }







        await loadProfile();



    }







    function initNavUser() {



        const authLink = document.getElementById('nav-auth-link');



        const userMenu = document.getElementById('nav-user-menu');



        if (!userInfo) return;



        if (authLink) authLink.classList.add('hidden');



        if (userMenu) userMenu.classList.remove('hidden');







        const displayName = (typeof safeDisplayName === 'function') ? safeDisplayName(userInfo) : ([userInfo.telegram_first_name, userInfo.telegram_last_name].filter(Boolean).join(' ') || userInfo.telegram_username || userInfo.display_name);



        const userBtn = document.getElementById('nav-user-btn');



        if (userBtn) userBtn.dataset.displayName = displayName;



        const displayEl = document.getElementById('nav-user-display');



        if (displayEl) displayEl.textContent = displayName;







        if (userInfo.telegram_photo_url) {



            const photoEl = document.getElementById('nav-user-photo');



            if (photoEl) {



                const url = userInfo.telegram_photo_url.startsWith('/')



                    ? 'https://t.me' + userInfo.telegram_photo_url



                    : userInfo.telegram_photo_url;



                photoEl.src = url;



                photoEl.classList.remove('hidden');



                photoEl.onerror = () => photoEl.classList.add('hidden');



            }



        }







    }







    async function loadProfile() {



        const main = document.getElementById('profile-main');



        if (!main) return;



        main.innerHTML = '<div class="forum-loading">Загрузка профиля...</div>';







        try {



            profileData = await (profileUserUid
                ? Api.getPublicProfileByUid(profileUserUid)
                : Api.getPublicProfile(profileUserId));



            if (!profileData) {



                renderNoProfile();



                return;



            }



            if (profileUserUid && profileData.user_id) profileUserId = profileData.user_id;



            if (profileUserUid && !window.location.pathname.match(/\/profile\/uid-\d+$/)) {
                const base = window.location.pathname.replace(/\/profile.*$/, '') || '';
                const cleanPath = base + '/profile/uid-' + profileUserUid + window.location.hash;
                history.replaceState(null, '', cleanPath);
            }



            if (!profileData.achievement_points) profileData.achievement_points = 0;



            if (!profileData.achievements_count) profileData.achievements_count = 0;



            if (!profileData.showcased_achievements) profileData.showcased_achievements = [];







            try {



                const [ach, cat] = await Promise.all([



                    Api.getUserAchievements(profileUserId),



                    Api.getAchievementsCatalog()



                ]);



                userAchievements = ach || [];



                achievementsCatalog = cat || [];



            } catch (e) {



                userAchievements = [];



                achievementsCatalog = [];



            }



            renderProfile();



        } catch (err) {



            main.innerHTML = `<div class="forum-error">Ошибка загрузки профиля</div>`;



        }



    }







    function resolveRole(data) {



        if (data.role) return data.role;



        if (data.is_admin) return 'admin';



        if (data.is_st_moderator) return 'stmoderator';



        if (data.is_moderator) return 'moderator';



        if (data.is_beta) return 'beta';



        if (data.is_alpha) return 'alpha';



        return 'member';



    }







    function getRoleMeta(role) {



        const roles = {



            admin: { label: 'ADMIN', className: 'admin' },



            stmoderator: { label: 'ST. MODERATOR', className: 'stmoderator' },



            moderator: { label: 'MODERATOR', className: 'moderator' },



            beta: { label: 'BETA', className: 'beta' },



            alpha: { label: 'ALPHA', className: 'alpha' },



            member: { label: 'MEMBER', className: 'member' },



        };



        return roles[role] || roles.member;



    }







    function getRoleBadge(role) {



        const meta = getRoleMeta(role);



        return `<span class="profile-role-badge profile-role-${meta.className}" title="${escapeHtml(meta.label)}"><span class="profile-role-orb"></span>${escapeHtml(meta.label)}</span>`;



    }







    function formatNumber(value) {



        return Number(value || 0).toLocaleString('ru-RU');



    }







    function getLockedAchievementTitle(id) {



        if (lockedAchievementTitleCache.has(id)) return lockedAchievementTitleCache.get(id);



        const glyphs = '?¿⁇⁈⁉◇◆□■△▲';



        const len = 5 + Math.floor(Math.random() * 4);



        let title = '';



        for (let i = 0; i < len; i++) title += glyphs[Math.floor(Math.random() * glyphs.length)];



        lockedAchievementTitleCache.set(id, title);



        return title;



    }







    function animateLockedAchievements(container) {



        const els = Array.from(container.querySelectorAll('.ach-locked-title'));



        if (els.length === 0) return;



        const glyphs = '?¿⁇⁈⁉◇◆□■△▲';



        const tick = () => {



            els.forEach(el => {



                const len = Number(el.dataset.lockedLen || 6);



                let next = '';



                for (let i = 0; i < len; i++) next += glyphs[Math.floor(Math.random() * glyphs.length)];



                el.textContent = next;



            });



        };



        tick();



        setInterval(tick, 140);



    }







    function getProfileScore(data) {



        const threads = Number(data.threads_count || 0);



        const posts = Number(data.posts_count || 0);



        const verifiedBonus = data.is_verified ? 120 : 0;



        const roleBonus = {



            admin: 1500,



            stmoderator: 1100,



            moderator: 800,



            beta: 500,



            alpha: 260,



            member: 0,



        }[resolveRole(data)] || 0;



        return threads * 90 + posts * 18 + verifiedBonus + roleBonus;



    }







    function getLevelInfo(score) {



        const level = Math.max(1, Math.floor(score / 350) + 1);



        const current = (level - 1) * 350;



        const next = level * 350;



        const progress = Math.min(100, Math.max(0, ((score - current) / (next - current)) * 100));



        return { level, next, progress };



    }







    function getInitials(name) {



        return name



            .split(' ')



            .filter(Boolean)



            .slice(0, 2)



            .map(part => part[0])



            .join('')



            .toUpperCase() || 'NB';



    }







    function renderProfileAvatar(photo, name) {



        const fallback = `<div class="profile-avatar-fallback">${escapeHtml(getInitials(name))}</div>`;



        const safePhoto = photo ? escapeHtml(photo) : '';



        return safePhoto



            ? `<img src="${safePhoto}" class="profile-avatar-xl" alt="" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'"><div class="profile-avatar-fallback" style="display:none">${escapeHtml(getInitials(name))}</div>`



            : fallback;



    }







    function renderProfile() {

        // FIX: сбрасываем флаг чтобы decode-анимации запускались при каждом ре-рендере (например при редактировании bio)
        animationsRan = false;

        const main = document.getElementById('profile-main');



        if (!main) return;







        const rawName = (typeof safeDisplayName === 'function') ? safeDisplayName(profileData) : [cleanText(profileData.telegram_first_name, 50), cleanText(profileData.telegram_last_name, 50)].filter(Boolean).join(' ')



            || cleanText(profileData.telegram_username, 50) || 'Аноним';



        const name = rawName;



        const photo = profileData.telegram_photo_url



            ? (profileData.telegram_photo_url.startsWith('/') ? 'https://t.me' + profileData.telegram_photo_url : profileData.telegram_photo_url)



            : null;



        const role = resolveRole(profileData);



        const roleBadge = getRoleBadge(role);



        const displayUid = Number.isFinite(Number(profileData.uid)) ? Number(profileData.uid) : 0;



        const displayUsername = profileData.username || profileData.telegram_username || '';
        const username = displayUsername ? `@${escapeHtml(cleanText(displayUsername, 32))}` : '';
        const hasPendingUsername = !!profileData.pending_username;
        const pendingUsernameText = hasPendingUsername ? `@${escapeHtml(cleanText(profileData.pending_username, 32))}` : '';

        const telegramUrl = profileData.telegram_username ? `https://t.me/${encodeURIComponent(profileData.telegram_username)}` : '';

        const bioText = profileData.bio ? escapeHtml(cleanText(profileData.bio, 400)) : (isOwnProfile ? 'Расскажите о себе...' : '');

        const usernameDisplay = isOwnProfile && !editingUsername
            ? `<div class="profile-username-display" id="username-display">
                ${username ? `<span class="profile-username-text">${username}</span>` : '<span class="profile-username-placeholder text-gray-500">Без ника</span>'}
                ${hasPendingUsername ? `<span class="profile-pending-badge text-yellow-400 text-xs ml-2">(${pendingUsernameText} на рассмотрении)</span>` : ''}
                <button class="profile-bio-edit-btn ml-2" id="btn-edit-username">Ред.</button>
               </div>`
            : editingUsername
                ? `<div class="profile-username-edit">
                    <input id="username-input" type="text" maxlength="32" class="forum-textarea" style="min-height:auto;height:auto;padding:8px 12px;resize:none;" value="${escapeHtml(profileData.pending_username || profileData.username || profileData.telegram_username || '')}" placeholder="Введите ник...">
                    <div class="profile-bio-edit-actions mt-2">
                        <button id="btn-save-username" class="forum-submit-btn">Сохранить</button>
                        <button id="btn-cancel-username" class="forum-cancel-btn">Отмена</button>
                    </div>
                   </div>`
                : (username ? `<p class="profile-username">${username}</p>` : '');



        const reactionsGiven = Number(profileData.reactions_given_count || 0);



        const score = getProfileScore(profileData);



        const levelInfo = getLevelInfo(score);



        const inviteUses = userInfo && userInfo.invite_use_count !== undefined && userInfo.invite_use_count !== null ? userInfo.invite_use_count : 0;







        const bioDisplay = isOwnProfile && !editingBio



            ? `<div class="profile-bio-display" id="bio-display"><span class="profile-bio-text" data-decode>${bioText}</span><button class="profile-bio-edit-btn" id="btn-edit-bio">Ред.</button></div>`



            : editingBio



                ? `<div class="profile-bio-edit"><textarea id="bio-textarea" maxlength="400" rows="3" class="forum-textarea">${escapeHtml(profileData.bio || '')}</textarea><div class="profile-bio-edit-actions"><button id="btn-save-bio" class="forum-submit-btn">Сохранить</button><button id="btn-cancel-bio" class="forum-cancel-btn">Отмена</button></div></div>`



                : `<div class="profile-bio-display"><span class="profile-bio-text" data-decode>${bioText}</span></div>`;







        const restrictionNotice = isOwnProfile && userInfo



            ? (userInfo.is_banned



                ? '<div class="forum-restriction forum-ban-notice">Ваш аккаунт заблокирован</div>'



                : userInfo.is_muted



                    ? '<div class="forum-restriction forum-mute-notice">Ваш аккаунт заглушен</div>'



                    : '')



            : '';







        let accountSection = '';



        if (isOwnProfile && userInfo) {



            accountSection = renderAccountSection();



        }







        const showcased = (profileData.showcased_achievements || []);



        const achievementPoints = Number(profileData.achievement_points || 0);



        const achievementsCount = Number(profileData.achievements_count || 0);







        const accountStatusHtml = profileData.is_verified
            ? '<div class="profile-account-status profile-account-status-verified"><span>Статус аккаунта</span><strong>VERIFIED</strong></div>'
            : '<div class="profile-account-status profile-account-status-unverified"><span>Статус аккаунта</span><strong>NOT VERIFIED</strong></div>';

        const invitedUsers = Array.isArray(profileData.invited_users) ? profileData.invited_users : [];
        const invitedUsersCount = Number(profileData.invited_users_count || invitedUsers.length || 0);
        const invitedUsersHtml = invitedUsersCount > 0
            ? `<div class="profile-invited-users"><div class="profile-invited-users-head"><span>Приглашённые</span><strong>${invitedUsersCount}</strong></div><div class="profile-invited-users-list">${invitedUsers.map(invited => {
                const invitedNameRaw = [invited.telegram_first_name, invited.telegram_last_name].filter(Boolean).join(' ') || invited.username || invited.telegram_username || `UID ${invited.uid}`;
                const invitedName = escapeHtml(cleanText(invitedNameRaw, 40));
                const invitedDisplayUname = invited.username || invited.telegram_username || '';
                const invitedUsername = invitedDisplayUname ? `@${escapeHtml(cleanText(invitedDisplayUname, 32))}` : `#${escapeHtml(invited.uid || '')}`;
                const invitedPhoto = invited.telegram_photo_url ? (invited.telegram_photo_url.startsWith('/') ? 'https://t.me' + invited.telegram_photo_url : invited.telegram_photo_url) : '';
                return `<a class="profile-invited-user" href="${getProfileHref(invited.uid, invited.user_id)}">${invitedPhoto ? `<img src="${escapeHtml(invitedPhoto)}" alt="" onerror="this.style.display='none'">` : '<span class="profile-invited-user-avatar"></span>'}<span><strong>${invitedName}</strong><em>${invitedUsername}</em></span></a>`;
            }).join('')}</div></div>`
            : '<div class="profile-invited-users profile-invited-users-empty"><div class="profile-invited-users-head"><span>Приглашённые</span><strong>0</strong></div><p>Пока никого не пригласил</p></div>';

        const showcaseRowHtml = showcased.length > 0



            ? `<div class="profile-showcase-row">${showcased.map(a => {



                const rarityClass = `profile-showcase-item-${a.rarity}`;



                return `<div class="profile-showcase-item ${rarityClass}" data-title="${escapeHtml(a.title)}" data-rarity="${a.rarity}">



                    <span class="profile-showcase-label">${escapeHtml(a.title)}</span>



                    ${renderAchievementIcon(a.id, a.icon_emoji, 'showcase')}



                </div>`;



            }).join('')}</div>` : '';







        main.innerHTML = `



            <div class="profile-layout">



                <aside class="profile-sidebar profile-sidebar-stagger">



                    <section class="profile-card profile-identity-card role-${role}">



                        <div class="profile-avatar-frame role-${role}">



                            ${renderProfileAvatar(photo, name)}



                        </div>



                        <div class="profile-name-stack">



                            <div class="profile-name-row">



                                <h1 class="profile-name">${escapeHtml(name)}<span class="profile-name-uid">#${escapeHtml(displayUid)}</span></h1>



                                ${roleBadge}



                            </div>



                            ${showcaseRowHtml}



                            ${usernameDisplay}



                            <p class="profile-joined">Дата регистрации: ${formatDate(profileData.created_at)}</p>

                            ${accountStatusHtml}



                        </div>







                        ${restrictionNotice}







                        <div class="profile-bio-section">



                            <h3 class="profile-section-title">О себе</h3>



                            ${bioDisplay}



                        </div>







                        <div class="profile-social-row">



                            ${telegramUrl ? `<a href="${telegramUrl}" target="_blank" rel="noopener" class="profile-social-btn">Telegram</a>` : ''}



                        </div>



                    </section>







                    <section class="profile-card profile-level-card role-${role}">



                        <div class="profile-level-head">



                            <h3 class="profile-section-title">Уровень профиля</h3>



                            <span class="profile-level-chip" data-decode>LVL ${levelInfo.level}</span>



                        </div>



                        <div class="profile-level-medal">



                            <div class="profile-medal-core">${levelInfo.level}</div>



                            <div>



                                <p class="profile-level-name">Neuro Rank</p>



                                <p class="profile-level-score" data-decode>${formatNumber(score + achievementPoints)} баллов активности</p>



                            </div>



                        </div>



                        <div class="profile-progress">



                            <span style="width:${levelInfo.progress}%"></span>



                        </div>



                        <p class="profile-progress-note" data-decode>До следующего уровня: ${formatNumber(Math.max(0, levelInfo.next - (score + achievementPoints)))}</p>



                    </section>







                    ${accountSection}

                    ${invitedUsersHtml}



                </aside>







                <section class="profile-content">



                    <div class="profile-banner">



                        <div class="profile-banner-grid"></div>



                        <div class="profile-banner-orbit profile-banner-orbit-a"></div>



                        <div class="profile-banner-orbit profile-banner-orbit-b"></div>



                        <div class="profile-banner-copy">



                            <span>UID</span>



                            <strong>#${displayUid}</strong>



                        </div>



                    </div>







                    <div class="profile-tabs">



                        <button class="profile-tab profile-tab-active" data-tab="activity" type="button">Активность</button>



                        <button class="profile-tab" data-tab="threads" type="button">Треды</button>



                        <button class="profile-tab" data-tab="achievements" type="button">Достижения</button>



                    </div>







                    <div class="profile-dashboard-grid">



                        <div class="profile-mini-card">



                            <span class="profile-mini-label">Тредов</span>



                            <strong data-decode>${formatNumber(profileData.threads_count)}</strong>



                        </div>



                        <div class="profile-mini-card">



                            <span class="profile-mini-label">Постов</span>



                            <strong data-decode>${formatNumber(profileData.posts_count)}</strong>



                        </div>



                        <div class="profile-mini-card">



                            <span class="profile-mini-label">Реакций</span>



                            <strong data-decode>${formatNumber(reactionsGiven)}</strong>



                        </div>



                        <div class="profile-mini-card profile-mini-card-ach">



                            <span class="profile-mini-label">Достижений</span>



                            <strong data-decode>${achievementsCount}</strong>



                        </div>



                    </div>







                    <div id="profile-tab-content">



                        <div class="forum-loading">Загрузка...</div>



                    </div>



                </section>



            </div>



        `;







        attachProfileHandlers();



        if (isOwnProfile && userInfo) {



            attachAccountHandlers();



        }



        runDecodeAnimations();



        runAccountDecodeAnimations();



        // Trigger sidebar stagger animation

        requestAnimationFrame(() => {

            const sidebar = document.querySelector('.profile-sidebar-stagger');

            if (sidebar) sidebar.classList.add('is-visible');

        });







        activityOffset = 0;



        activityHasMore = true;



        loadTabContent('activity');







        const titleName = cleanText(profileData.telegram_first_name, 30) || cleanText(profileData.username || profileData.telegram_username, 30) || 'Профиль';



        const newTitle = `NeuroBench | ${titleName}`;



        document.title = newTitle;



        if (window.__NB_TITLE__) window.__NB_TITLE__ = newTitle;



        if (window.__NB_DECODE_TITLE__) window.__NB_DECODE_TITLE__(newTitle);



    }







    function renderAccountSection() {



        if (!userInfo) return '';







        let inviteHtml = '';

        const role = resolveRole(profileData || userInfo);

        const isAdminRole = role === 'admin';

        const canGenerateInvites = userInfo.is_verified;



        if (canGenerateInvites) {



            const max = isAdminRole ? (userInfo.invite_max || 999999) : 1;

            const active = userInfo.invite_active_count || 0;

            const remaining = Math.max(0, max - active);

            const quotaLabel = max >= 999999 ? 'Безлимитно' : `${active} / ${max}`;

            const selectedMaxUses = isAdminRole ? Math.max(1, Math.min(9999, Number(userInfo.selected_invite_max_uses || 1))) : 1;

            const selectedTtlSeconds = isAdminRole ? Math.max(1, Math.min(INVITE_INFINITE_TTL_SECONDS, Number(userInfo.selected_invite_ttl_seconds || ((userInfo.selected_invite_ttl_minutes || 5) * 60)))) : 300;

            const inviteControlsHtml = isAdminRole ? `

                <div class="profile-account-invite-controls profile-account-invite-controls-compact">

                    <label class="profile-account-invite-control profile-invite-uses-control">

                        <span data-decode>uses</span>

                        <input id="account-invite-max-uses" class="profile-invite-input" type="number" min="1" max="9999" value="${selectedMaxUses}" inputmode="numeric">

                    </label>

                    <fieldset class="profile-account-invite-control profile-invite-ttl-control">

                        <legend data-decode>Time</legend>

                        <label>

                            <input id="account-invite-ttl-hours" class="profile-invite-input" type="number" min="0" max="9999" value="${Math.floor(selectedTtlSeconds / 3600)}" inputmode="numeric">

                            <span>h</span>

                        </label>

                        <label>

                            <input id="account-invite-ttl-minutes" class="profile-invite-input" type="number" min="0" max="59" value="${Math.floor((selectedTtlSeconds % 3600) / 60)}" inputmode="numeric">

                            <span>m</span>

                        </label>

                        <label>

                            <input id="account-invite-ttl-seconds" class="profile-invite-input" type="number" min="0" max="59" value="${selectedTtlSeconds % 60}" inputmode="numeric">

                            <span>s</span>

                        </label>

                    </fieldset>

                </div>` : '';

            let activeCodeHtml = '';



            if (userInfo.has_generated_invite && userInfo.generated_code) {

                const inviteUsed = Number(userInfo.invite_use_count || 0) > 0;



                activeCodeHtml = `

                    <div class="profile-account-invite-card profile-account-invite-has">


                        <div class="profile-account-invite-token profile-invite-token-box">

                            <span id="account-invite-code" class="hidden">${escapeHtml(userInfo.generated_code)}</span>

                            <p id="account-invite-plain" class="invite-code-plain">${escapeHtml(userInfo.generated_code)}</p>

                            <div class="profile-invite-ascii-wrap" aria-hidden="true">

                                <div id="account-invite-ascii" class="invite-code-ascii">${renderInviteAscii(userInfo.generated_code)}</div>

                            </div>

                        </div>

                        <div class="profile-account-invite-foot">

                            <span class="profile-account-invite-expiry" data-invite-ttl="${selectedTtlSeconds}">${formatInviteExpiry(selectedTtlSeconds)}</span>

                            ${userInfo.invite_use_count !== undefined && userInfo.invite_use_count !== null

                                ? `<span class="profile-account-invite-uses" data-decode>used ${userInfo.invite_use_count}</span>` : ''}

                        </div>

                        <div class="profile-account-invite-actions">

                            <button id="account-copy-code" class="forum-cancel-btn profile-invite-copy-btn">copy</button>

                            ${isAdminRole || !inviteUsed ? `<button id="account-gen-invite" class="forum-cancel-btn profile-invite-primary-btn">new token</button>` : ''}

                        </div>

                    </div>`;



            } else if (remaining > 0 || max >= 999999) {



                activeCodeHtml = `

                    <div class="profile-account-invite-card profile-account-invite-none">


                        <p class="profile-account-invite-empty" data-decode>Generate a short-lived invite token.</p>

                        <button id="account-gen-invite" class="forum-cancel-btn">generate token</button>

                    </div>`;



            }







            inviteHtml = `

                <div class="profile-account-invite-quota">

                    <span class="profile-account-invite-quota-label" data-decode>Инвайты</span>

                    <span class="profile-account-invite-quota-value" data-decode>${quotaLabel}</span>

                </div>

                ${inviteControlsHtml}

                ${activeCodeHtml}`;



        }







        return `

            <div class="profile-account-card role-${role}">

                ${inviteHtml}

            </div>

        `;



    }







    function attachAccountHandlers() {



        const genBtn = document.getElementById('account-gen-invite');



        if (genBtn) {



            genBtn.addEventListener('click', () => doGenerateInvite('account-gen-invite'));



        }



        const expiryEl = document.querySelector('.profile-account-invite-expiry');

        if (expiryEl) startInviteExpiryTimer(Number(expiryEl.dataset.inviteTtl || 300));







        const copyBtn = document.getElementById('account-copy-code');



        if (copyBtn) {



            let copyAnimating = false;



            copyBtn.addEventListener('click', async () => {



                if (copyAnimating) return;



                copyAnimating = true;



                finishDecodeAnimation();



                const codeEl = document.getElementById('account-invite-code');



                if (!codeEl) { copyAnimating = false; return; }



                const code = codeEl.textContent.trim();

                if (!code) { copyAnimating = false; return; }



                const asciiEl = document.getElementById('account-invite-ascii');



                const waveDuration = triggerInviteCopyAnimation(asciiEl);



                copyBtn.classList.remove('invite-press-tap');

                void copyBtn.offsetWidth;

                copyBtn.classList.add('invite-press-tap');

                setTimeout(() => copyBtn.classList.remove('invite-press-tap'), 200);



                copyBtn.classList.add('is-copying');

                copyBtn.classList.remove('is-copy-error');

                const copyStart = performance.now();

                let copySucceeded = true;

                try {

                    await copyTextToClipboard(code);

                } catch {

                    copySucceeded = false;

                }

                if (!copySucceeded) copyBtn.classList.add('is-copy-error');

                hackerDecodeStable(copyBtn, copySucceeded ? 'copied' : 'failed', 220);

                const minCopyDuration = Math.max(waveDuration, copySucceeded ? 520 : 720);

                const resetDelay = Math.max(520, minCopyDuration - (performance.now() - copyStart));

                setTimeout(() => {

                    copyBtn.classList.remove('is-copying');

                    copyBtn.classList.remove('is-copy-error');



                    hackerDecodeStable(copyBtn, 'copy', 180);



                    setTimeout(() => { copyAnimating = false; }, 220);



                }, resetDelay);



            });



        }







        const asciiWrap = document.querySelector('.profile-invite-ascii-wrap');

        const plainEl = document.getElementById('account-invite-plain');

        if (asciiWrap && plainEl) {

            const inviteCard = asciiWrap.closest('.profile-account-invite-card');

            const revealTarget = asciiWrap.closest('.profile-invite-token-box') || asciiWrap;

            // hover reveal disabled: plain code stays hidden, ASCII stays at default opacity

            void revealTarget;

            void inviteCard;

        }



    }

    async function copyTextToClipboard(text) {



        if (navigator.clipboard && navigator.clipboard.writeText) {



            try {



                await navigator.clipboard.writeText(text);



                return;



            } catch {}



        }







        const ta = document.createElement('textarea');



        ta.value = text;



        ta.style.position = 'fixed';



        ta.style.left = '-9999px';



        ta.style.top = '0';



        document.body.appendChild(ta);



        ta.focus();



        ta.select();



        const copied = document.execCommand('copy');



        document.body.removeChild(ta);



        if (!copied) throw new Error('copy failed');



    }







    async function doGenerateInvite(btnId) {



        const btn = document.getElementById(btnId);



        if (!btn) return;



        btn.disabled = true;



        const originalText = btn.textContent;



        btn.textContent = 'Генерация...';



        try {



            const gen = ++_inviteGen;

            finishDecodeAnimation();



            const devRaw = isLocalhost() ? localStorage.getItem('nb_dev_session') : null;

            const isAdminRole = resolveRole(profileData || userInfo) === 'admin';

            const maxUsesEl = document.getElementById('account-invite-max-uses');

            const ttlHoursEl = document.getElementById('account-invite-ttl-hours');

            const ttlMinutesEl = document.getElementById('account-invite-ttl-minutes');

            const ttlSecondsEl = document.getElementById('account-invite-ttl-seconds');

            const maxUses = isAdminRole && maxUsesEl ? Math.max(1, Math.min(9999, Number(maxUsesEl.value || 1))) : 1;

            const ttlHoursRaw = isAdminRole && ttlHoursEl ? Math.max(0, Number(ttlHoursEl.value || 0)) : 0;

            const ttlHours = Math.min(9999, ttlHoursRaw);

            const ttlMinPart = isAdminRole && ttlMinutesEl ? Math.max(0, Math.min(59, Number(ttlMinutesEl.value || 0))) : 5;

            const ttlSecPart = isAdminRole && ttlSecondsEl ? Math.max(0, Math.min(59, Number(ttlSecondsEl.value || 0))) : 0;

            const ttlSeconds = isAdminRole ? (ttlHoursRaw >= 9999 ? INVITE_INFINITE_TTL_SECONDS : Math.max(1, Math.min(INVITE_INFINITE_TTL_SECONDS, ttlHours * 3600 + ttlMinPart * 60 + ttlSecPart))) : 300;



            if (!userInfo || !userInfo.is_verified) throw new Error('Недостаточно прав');

            if (!isAdminRole && userInfo.invite_use_count > 0) throw new Error('Старый инвайт уже использован — перегенерация запрещена');



            const code = devRaw

                ? makeDevInviteCode()

                : (isAdminRole ? await Api.adminGenerateInviteCode(maxUses, ttlSeconds) : await Api.generateInviteCode());



            if (!code) throw new Error('Не удалось сгенерировать код');



            if (gen !== _inviteGen) return;



            if (userInfo) {



                userInfo.has_generated_invite = true;



                userInfo.generated_code = code;



                userInfo.invite_use_count = 0;

                userInfo.selected_invite_max_uses = maxUses;

                userInfo.selected_invite_ttl_seconds = ttlSeconds;

                userInfo.selected_invite_ttl_minutes = Math.ceil(ttlSeconds / 60);



                if (userInfo.invite_active_count !== undefined) {



                    userInfo.invite_active_count = (userInfo.invite_active_count || 0) + 1;



                }



                if (localStorage.getItem('nb_dev_session')) {



                    localStorage.setItem('nb_dev_session', JSON.stringify(userInfo));



                }



            }



            const inviteHas = document.querySelector('.profile-account-invite-has');

            if (inviteHas) {

                decodeInviteAscii(code);

                if (_hoverTimer) { clearTimeout(_hoverTimer); _hoverTimer = null; }

                const plainReset = inviteHas.querySelector('.invite-code-plain');

                if (plainReset) { plainReset.style.opacity = ''; plainReset.style.transform = ''; }

                const asciiReset = inviteHas.querySelector('.profile-invite-ascii-wrap');

                if (asciiReset) { asciiReset.style.opacity = ''; asciiReset.dataset.revealed = ''; }

                inviteHas.classList.remove('invite-revealed');

                const expiryEl = inviteHas.querySelector('.profile-account-invite-expiry');

                if (expiryEl) {

                    expiryEl.dataset.inviteTtl = ttlSeconds;

                    expiryEl.textContent = formatInviteExpiry(ttlSeconds);

                    hackerDecodeStable(expiryEl, expiryEl.textContent, 300);

                }

                const usesEl = inviteHas.querySelector('.profile-account-invite-uses');

                if (usesEl) usesEl.textContent = 'used 0';

                inviteHas.querySelectorAll('[data-decode]').forEach(el => { el._decoded = false; });

                runAccountDecodeAnimations(inviteHas);

                startInviteExpiryTimer(ttlSeconds, inviteHas);

            } else {

                const inviteNone = document.querySelector('.profile-account-invite-none');

                if (inviteNone) {

                    inviteNone.outerHTML = `

                    <div class="profile-account-invite-card profile-account-invite-has">


                        <div class="profile-account-invite-token profile-invite-token-box">

                            <span id="account-invite-code" class="hidden">${escapeHtml(code)}</span>

                            <p id="account-invite-plain" class="invite-code-plain">${escapeHtml(code)}</p>

                            <div class="profile-invite-ascii-wrap" aria-hidden="true">

                                <div id="account-invite-ascii" class="invite-code-ascii"></div>

                            </div>

                        </div>

                        <div class="profile-account-invite-foot">

                            <span class="profile-account-invite-expiry" data-invite-ttl="${ttlSeconds}">${formatInviteExpiry(ttlSeconds)}</span>

                            <span class="profile-account-invite-uses" data-decode>used 0</span>

                        </div>

                        <div class="profile-account-invite-actions">

                            <button id="account-copy-code" class="forum-cancel-btn profile-invite-copy-btn">copy</button>

                            ${isAdminRole || Number(userInfo.invite_use_count || 0) === 0 ? `<button id="account-gen-invite" class="forum-cancel-btn profile-invite-primary-btn">new token</button>` : ''}

                        </div>

                    </div>`;

                    decodeInviteAscii(code);

                    attachAccountHandlers();

                    const newInviteHas = document.querySelector('.profile-account-invite-has');

                    if (newInviteHas) {

                        runAccountDecodeAnimations(newInviteHas);

                        startInviteExpiryTimer(ttlSeconds, newInviteHas);

                    }

                }

            }



            return;



        } catch (err) {



            alert(err.message || 'Ошибка генерации');



        } finally {



            btn.disabled = false;



            btn.textContent = originalText;



        }



    }







    function attachProfileHandlers() {



        const editBtn = document.getElementById('btn-edit-bio');



        if (editBtn) {



            editBtn.addEventListener('click', () => {



                editingBio = true;



                renderProfile();



            });



        }







        const saveBtn = document.getElementById('btn-save-bio');



        if (saveBtn) {



            saveBtn.addEventListener('click', async () => {



                const bio = document.getElementById('bio-textarea').value.trim();



                try {



                    await Api.updateProfileBio(bio);



                    profileData.bio = bio;



                    editingBio = false;



                    renderProfile();



                } catch (err) { alert('Ошибка: ' + err.message); }



            });



        }







        const cancelBtn = document.getElementById('btn-cancel-bio');



        if (cancelBtn) {



            cancelBtn.addEventListener('click', () => {



                editingBio = false;



                renderProfile();



            });



        }



        // Username editing
        const editUsernameBtn = document.getElementById('btn-edit-username');
        if (editUsernameBtn) {
            editUsernameBtn.addEventListener('click', () => {
                editingUsername = true;
                renderProfile();
            });
        }

        const saveUsernameBtn = document.getElementById('btn-save-username');
        if (saveUsernameBtn) {
            saveUsernameBtn.addEventListener('click', async () => {
                const val = document.getElementById('username-input').value.trim();
                if (!val) { alert('Введите ник'); return; }
                try {
                    const result = await Api.requestUsernameChange(val);
                    if (result && result.ok) {
                        profileData.pending_username = result.pending_username || val;
                        editingUsername = false;
                        renderProfile();
                        alert('Запрос на смену ника отправлен. Ожидайте подтверждения администратора.');
                    } else {
                        alert('Не удалось: ' + (result && result.reason ? result.reason : 'ошибка'));
                    }
                } catch (err) { alert('Ошибка: ' + err.message); }
            });
        }

        const cancelUsernameBtn = document.getElementById('btn-cancel-username');
        if (cancelUsernameBtn) {
            cancelUsernameBtn.addEventListener('click', () => {
                editingUsername = false;
                renderProfile();
            });
        }

        // Tab switching



        document.querySelectorAll('.profile-tab[data-tab]').forEach(tab => {



            tab.addEventListener('click', () => {



                document.querySelectorAll('.profile-tab[data-tab]').forEach(t => t.classList.remove('profile-tab-active'));



                tab.classList.add('profile-tab-active');



                loadTabContent(tab.dataset.tab);



            });



        });







        // Showcase item animated tooltips



        document.querySelectorAll('.profile-showcase-item').forEach(item => {



            const label = item.querySelector('.profile-showcase-label');



            if (!label) return;



            const originalText = label.textContent;







            item.addEventListener('mouseenter', () => {



                hackerDecode(label, originalText);



            });







            item.addEventListener('mouseleave', () => {



                label.textContent = originalText;



                label.style.height = '';



                label.style.overflow = '';



            });



        });



    }







    async function loadTabContent(tabName) {



        const container = document.getElementById('profile-tab-content');



        if (!container) return;



        container.classList.remove('profile-tab-content-animated');







        if (tabName === 'achievements') {



            renderAchievementsTab(container);



            animateTabContent(container);



            return;



        }







        if (tabName === 'activity') {



            activityOffset = 0;



            activityHasMore = true;



            await renderActivityFeed(container, 0);



            animateTabContent(container);



            return;



        }







        if (tabName === 'threads') {



            container.innerHTML = '<div class="forum-loading">Загрузка тредов...</div>';



            try {



                const threads = await Api.getUserThreads(profileUserId, 20, 0);



                if (!threads || threads.length === 0) {



                    container.innerHTML = '<div class="profile-card"><p class="profile-empty-tab">Нет созданных тредов</p></div>';



                    animateTabContent(container);



                    return;



                }



                let html = '<section class="profile-card profile-activity-card"><h3 class="profile-section-title">Созданные треды</h3><div class="profile-activity-list">';



                threads.forEach(t => {



                    const href = `forum#thread/${t.id}`;



                    const title = escapeHtml(cleanText(t.title || '', 100));



                    const cat = t.category_name ? escapeHtml(t.category_name) : '';



                    const date = formatDate(t.created_at);



                    html += `<a href="${href}" class="profile-activity-item">



                        <span class="profile-activity-mark">📝</span>



                        <div>



                            <strong>${title}</strong>



                            <p>${cat} · ${t.posts_count || 0} ответов</p>



                            <span class="profile-activity-time">${date}</span>



                        </div>



                    </a>`;



                });



                html += '</div></section>';



                container.innerHTML = html;



            } catch {



                container.innerHTML = '<div class="profile-card"><p class="profile-empty-tab">Ошибка загрузки</p></div>';



            }



            animateTabContent(container);



            return;



        }



    }







    function animateTabContent(container) {



        requestAnimationFrame(() => {



            container.classList.add('profile-tab-content-animated');



        });



    }







    const lockSvg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>';







    function renderAchievementsTab(container) {



        const ownedMap = new Map();



        userAchievements.forEach(ua => ownedMap.set(ua.achievement_id, ua));







        const categories = {



            starter: { label: 'Стартовые', order: 0 },



            rare: { label: 'Редкие', order: 1 },



            unique: { label: 'Уникальные', order: 2 },



            secret_limited: { label: 'Лимитированные', order: 3 }



        };







        const grouped = {};



        achievementsCatalog.forEach(a => {



            if (!grouped[a.category]) grouped[a.category] = [];



            grouped[a.category].push(a);



        });







        const showcaseIds = new Set(



            userAchievements.filter(a => a.is_showcased).map(a => a.achievement_id)



        );







        let html = `<section class="profile-card ach-card">



            <div class="ach-header">



                <h3 class="profile-section-title">Достижения</h3>



                <span class="ach-total-xp">${formatNumber(userAchievements.reduce((s, a) => s + (a.points || 0), 0))} XP</span>



            </div>`;







        if (isOwnProfile) {



            html += `<div class="ach-showcase-hint">Нажмите в† чтобы показать достижение у аватарки</div>`;



        }







        Object.entries(categories).forEach(([catKey, catMeta]) => {



            const items = grouped[catKey];



            if (!items || items.length === 0) return;







            html += `<div class="ach-category">



                <h4 class="ach-category-title">${escapeHtml(catMeta.label)}</h4>



                <div class="ach-grid">`;







            items.forEach(a => {



                const owned = ownedMap.get(a.id);



                const isOwned = !!owned;



                const isShowcased = showcaseIds.has(a.id);



                const isLocked = !isOwned;



                const isSecret = isLocked;



                const displayTitle = isLocked ? getLockedAchievementTitle(a.id) : escapeHtml(a.title);



                const displayDescription = isLocked ? '' : escapeHtml(a.description);



                const displayRarity = isLocked ? '' : `<span class="ach-rarity-badge ach-rarity-${a.rarity}">${a.rarity}</span>`;



                const displayMeta = isLocked ? '' : `<div class="ach-meta">



                            <span class="ach-points">+${a.points} XP</span>



                            ${a.max_supply ? `<span class="ach-supply">${a.total_unlocked || 0}/${a.max_supply}</span>` : ''}



                            ${isOwned ? `<span class="ach-date">${formatDate(owned.unlocked_at)}</span>` : ''}



                        </div>`;



                const rarityClass = `ach-rarity-${a.rarity}`;



                const ownedClass = isOwned ? 'ach-owned' : 'ach-locked';



                const secretClass = isSecret ? 'ach-secret' : '';



                const showcaseClass = isShowcased ? 'ach-showcased' : '';







                const iconContent = isLocked



                    ? `<div class="ach-lock-icon">${lockSvg}</div>`



                    : renderAchievementIcon(a.id, a.icon_emoji, 'card');







                html += `<div class="ach-item ${rarityClass} ${ownedClass} ${secretClass} ${showcaseClass}" data-ach-id="${escapeHtml(a.id)}">



                    ${isOwnProfile && isOwned ? `<button class="ach-showcase-btn ${isShowcased ? 'ach-showcase-active' : ''}" data-ach-id="${escapeHtml(a.id)}" title="${isShowcased ? 'Убрать из профиля' : 'Показать в профиле'}">${isShowcased ? 'в…' : 'в†'}</button>` : ''}



                    <div class="ach-icon-wrap">



                        ${iconContent}



                    </div>



                    <div class="ach-info">



                        <div class="ach-title-row">



                            <span class="ach-title ${isLocked ? 'ach-locked-title' : ''}" ${isLocked ? `data-locked-len="${displayTitle.length}"` : ''}>${displayTitle}</span>



                        </div>



                        ${displayRarity}



                        ${displayDescription ? `<p class="ach-desc">${displayDescription}</p>` : ''}



                        ${displayMeta}



                    </div>



                </div>`;



            });







            html += '</div></div>';



        });







        html += '</section>';



        container.innerHTML = html;



        animateLockedAchievements(container);







        if (isOwnProfile) {



            container.querySelectorAll('.ach-showcase-btn').forEach(btn => {



                btn.addEventListener('click', (e) => {



                    e.stopPropagation();



                    toggleShowcase(btn.dataset.achId);



                });



            });



        }



    }







    async function toggleShowcase(achievementId) {



        const currentShowcased = userAchievements.filter(a => a.is_showcased).map(a => a.achievement_id);



        let newShowcased;







        if (currentShowcased.includes(achievementId)) {



            newShowcased = currentShowcased.filter(id => id !== achievementId);



        } else {



            if (currentShowcased.length >= 3) {



                newShowcased = [...currentShowcased.slice(1), achievementId];



            } else {



                newShowcased = [...currentShowcased, achievementId];



            }



        }







        try {



            await Api.setShowcasedAchievements(newShowcased);



            userAchievements.forEach(a => {



                a.is_showcased = newShowcased.includes(a.achievement_id);



            });



            profileData.showcased_achievements = userAchievements



                .filter(a => a.is_showcased)



                .map(a => ({



                    id: a.achievement_id,



                    title: a.title,



                    icon_emoji: a.icon_emoji,



                    rarity: a.rarity,



                    points: a.points



                }));



            renderProfile();



        } catch (err) {



            alert('Ошибка: ' + (err.message || 'Не удалось обновить'));



        }



    }







    async function renderActivityFeed(container, offset) {



        if (activityLoading) return;



        activityLoading = true;



        if (offset === 0) {



            container.innerHTML = '<div class="forum-loading">Загрузка активности...</div>';



            activityHasMore = true;



        }



        try {



            const items = await Api.getUserRecentActivity(profileUserId, activityLimit, offset);



            if (!items || items.length < activityLimit) activityHasMore = false;



            if (offset === 0 && (!items || items.length === 0)) {



                container.innerHTML = '<div class="profile-card"><p class="profile-empty-tab">Нет активности на форуме</p></div>';



                activityLoading = false;



                return;



            }



            let html = '';



            if (offset === 0) html = '<section class="profile-card profile-activity-card"><h3 class="profile-section-title">Активность</h3><div class="profile-activity-list" id="activity-feed-list">';



            items.forEach(item => {



                const type = item.activity_type;



                let icon = '💬', actionText = '', href = '';



                const title = escapeHtml(cleanText(item.thread_title || '', 80));



                if (type === 'thread') { icon = '📝'; actionText = 'Создал тред'; href = `forum#thread/${item.thread_id}`; }



                else if (type === 'post') { icon = '💬'; actionText = 'Ответил в треде'; href = `forum#thread/${item.thread_id}`; }



                else if (type === 'reaction') { icon = item.emoji || '👍'; actionText = 'Поставил реакцию'; href = `forum#thread/${item.thread_id}`; }



                const preview = escapeHtml(cleanText(item.preview || '', 100));



                const time = formatActivityTime(item.created_at);



                html += `<a href="${href}" class="profile-activity-item"><span class="profile-activity-mark">${icon}</span><div><strong>${actionText}${title ? ' · ' + title : ''}</strong>${preview ? `<p>${preview}</p>` : ''}<span class="profile-activity-time">${time}</span></div></a>`;



            });



            if (offset === 0) {



                html += '</div>';



                if (activityHasMore) html += '<button class="forum-cancel-btn" id="activity-load-more" style="margin-top:12px;width:100%">Загрузить ещё</button>';



                html += '</section>';



                container.innerHTML = html;



                const loadMoreBtn = document.getElementById('activity-load-more');



                if (loadMoreBtn) loadMoreBtn.addEventListener('click', async () => {



                    activityOffset += activityLimit;



                    loadMoreBtn.textContent = 'Загрузка...';



                    loadMoreBtn.disabled = true;



                    await renderActivityFeed(container, activityOffset);



                    loadMoreBtn.remove();



                });



            } else {



                const list = document.getElementById('activity-feed-list');



                if (list) list.insertAdjacentHTML('beforeend', html);



                if (activityHasMore) {



                    const btn = document.createElement('button');



                    btn.className = 'forum-cancel-btn';



                    btn.id = 'activity-load-more';



                    btn.style.cssText = 'margin-top:12px;width:100%';



                    btn.textContent = 'Загрузить ещё';



                    btn.addEventListener('click', async () => {



                        activityOffset += activityLimit;



                        btn.textContent = 'Загрузка...';



                        btn.disabled = true;



                        await renderActivityFeed(container, activityOffset);



                        btn.remove();



                    });



                    container.querySelector('.profile-activity-card').appendChild(btn);



                }



            }



        } catch (e) {



            if (offset === 0) container.innerHTML = '<div class="profile-card"><p class="profile-empty-tab">Ошибка загрузки</p></div>';



        } finally {



            activityLoading = false;



        }



    }







    function renderNoProfile() {



        const main = document.getElementById('profile-main');



        if (!main) return;



        main.innerHTML = `



            <div class="forum-empty">



                ${!userInfo ? '<a href="register">Войдите</a> чтобы просмотреть профиль' : 'Профиль не найден'}



            </div>



            <div class="profile-back">



                <a href="forum" class="forum-cancel-btn">&larr; На форум</a>



            </div>



        `;



    }







    return { init };



})();







document.addEventListener('DOMContentLoaded', ProfileModule.init);
