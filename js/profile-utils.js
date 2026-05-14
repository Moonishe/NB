// Shared profile utility functions
// Used by auth.js, navbar.js, forum.js, leaderboard.js, profile.js
(function() {
    const _DANGEROUS_RE = /[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]/g;

    window.getProfileBasePath = function() {
        var parts = window.location.pathname.split('/').filter(Boolean);
        if (window.location.hostname.endsWith('github.io') && parts.length > 0) return '/' + parts[0];
        return '';
    };

    window.getProfileHref = function(uid, userId) {
        var base = window.getProfileBasePath();
        if (uid !== undefined && uid !== null && String(uid) !== '') return base + '/profile/uid-' + encodeURIComponent(uid);
        if (userId) return base + '/profile.html?id=' + encodeURIComponent(userId);
        return '#';
    };

    window.safeDisplayName = function(info) {
        if (!info) return 'User';
        var raw = [info.telegram_first_name, info.telegram_last_name].filter(Boolean).join(' ').trim();
        if (raw) {
            var clean = raw.replace(_DANGEROUS_RE, '').replace(/\s+/g, ' ').trim();
            if (clean.length > 0) return clean;
        }
        if (info.telegram_username) return info.telegram_username;
        if (info.display_name) {
            var cleanDn = info.display_name.replace(_DANGEROUS_RE, '').replace(/\s+/g, ' ').trim();
            if (cleanDn.length > 0) return cleanDn;
        }
        return 'User';
    };

    window.sanitizeTelegramPhotoUrl = function(value) {
        if (!value) return '';
        if (value.startsWith('/')) return value.startsWith('/i/userpic/') ? 'https://t.me' + value : '';
        try {
            var url = new URL(value);
            var hostname = url.hostname.toLowerCase();
            if (url.protocol !== 'https:') return '';
            if (hostname === 't.me' || hostname.endsWith('.t.me') || hostname === 'telegram.org' || hostname.endsWith('.telegram.org')) {
                return url.toString();
            }
        } catch (_) {}
        return '';
    };

    window.isLocalhost = function() {
        return ['localhost', '127.0.0.1', '::1'].includes(window.location.hostname);
    };
})();
