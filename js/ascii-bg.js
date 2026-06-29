(() => {
    const canvas = document.getElementById('ascii-canvas');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let width = 0, height = 0, columns = 0, rows = 0;
    let rafId = 0, pageHidden = document.hidden;
    const chars = ' .:-=+*#%@'.split('');
    const trail = [];
    const mouse = { x: -1000, y: -1000 };
    const mobile = window.matchMedia('(max-width: 767px)');

    // ASCII CATS
    const CAT_VARIANTS = [
        {
            art: [
                '     \u256d\u2572       \u2571\u256e',
                '    \u2571  \u2572\u2500\u2500\u2500\u2500\u2500\u2571  \u2572',
                '  \u2500\u2595   \u25c8     \u25c8   \u258f\u2500',
                '  \u2500\u2595      \u25bc      \u258f\u2500',
                '    \u2572   \u2550\u2550\u256a\u2550\u2550   \u2571',
                '     \u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f',
            ],
            name: 'geometric'
        },
        {
            art: [
                '     \u2554\u2572       \u2571\u2557',
                '     \u2551 \u2572\u2550\u2550\u2550\u2550\u2550\u2571 \u2551',
                '   \u2550\u2550\u2562   \u25c8   \u25c8   \u255f\u2550\u2550',
                '   \u2550\u2550\u2562     \u25bc     \u255f\u2550\u2550',
                '     \u2551   \u2550\u2550\u256a\u2550\u2550   \u2551',
                '     \u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d',
            ],
            name: 'cyber'
        },
    ];

    let cats = [];

    function placeCats() {
        cats = [];
        if (columns < 30 || rows < 20) return;
        var count = Math.max(2, Math.floor((columns * rows) / 500));
        var marginX = 18, marginY = 10;
        for (var i = 0; i < count; i++) {
            var variant = CAT_VARIANTS[i % CAT_VARIANTS.length];
            var artW = 0;
            for (var r = 0; r < variant.art.length; r++) {
                if (variant.art[r].length > artW) artW = variant.art[r].length;
            }
            var artH = variant.art.length;
            cats.push({
                variant: variant,
                gx: marginX + Math.floor(Math.random() * (columns - artW - marginX * 2)),
                gy: marginY + Math.floor(Math.random() * (rows - artH - marginY * 2)),
                driftX: (Math.random() - 0.5) * 0.3,
                driftY: (Math.random() - 0.5) * 0.2,
                phase: Math.random() * Math.PI * 2,
                assemblyT: 0,
                assemblySpeed: 0.004 + Math.random() * 0.006,
                eyePulse: Math.random() * Math.PI * 2,
            });
        }
    }

    function getFontSize() { return mobile.matches ? 24 : 15; }

    function init() {
        var dpr = Math.min(window.devicePixelRatio || 1, 2);
        width = window.innerWidth;
        height = window.innerHeight;
        canvas.width = Math.floor(width * dpr);
        canvas.height = Math.floor(height * dpr);
        canvas.style.width = width + 'px';
        canvas.style.height = height + 'px';
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        var fontSize = getFontSize();
        columns = Math.ceil(width / fontSize);
        rows = Math.ceil(height / fontSize);
        placeCats();
    }

    function pushTrail(px, py) {
        var last = trail[trail.length - 1];
        if (!last || Math.hypot(px - last.x, py - last.y) > 12) {
            trail.push({ x: px, y: py, t: performance.now() });
        }
    }

    function catColor(time, phase) {
        var hue = ((time * 0.00015 + phase * 0.5) % 1);
        var t = 0.5 + 0.25 * Math.sin(hue * Math.PI * 2);
        var r = Math.round(140 + t * 40);
        var g = Math.round(255 - t * 135);
        var b = Math.round(220 + t * 35);
        return { r: r, g: g, b: b };
    }

    function draw(time) {
        if (pageHidden) { rafId = requestAnimationFrame(draw); return; }

        var fontSize = getFontSize();
        var now = performance.now();
        var maxAge = 1900, trailRadius = 120;

        while (trail.length && now - trail[0].t > maxAge) trail.shift();

        ctx.fillStyle = '#050505';
        ctx.fillRect(0, 0, width, height);
        ctx.font = fontSize + 'px "Geist Mono"';
        ctx.textAlign = 'center';

        var idleTime = now - lastActivityTime;
        for (var ci = 0; ci < cats.length; ci++) {
            var cat = cats[ci];
            if (idleTime > IDLE_THRESHOLD) {
                cat.assemblyT = Math.min(1, cat.assemblyT + cat.assemblySpeed);
            } else {
                cat.assemblyT = Math.max(0, cat.assemblyT - FADE_SPEED);
            }
            cat.gx += cat.driftX * 0.02;
            cat.gy += cat.driftY * 0.02;
            var artW = 0;
            for (var r2 = 0; r2 < cat.variant.art.length; r2++) {
                if (cat.variant.art[r2].length > artW) artW = cat.variant.art[r2].length;
            }
            var artH = cat.variant.art.length;
            if (cat.gx < -artW) cat.gx = columns;
            if (cat.gx > columns) cat.gx = -artW;
            if (cat.gy < -artH) cat.gy = rows;
            if (cat.gy > rows) cat.gy = -artH;
        }

        var catCellMap = {};
        for (var ci2 = 0; ci2 < cats.length; ci2++) {
            var cat2 = cats[ci2];
            if (cat2.assemblyT < 0.02) continue;
            var art = cat2.variant.art;
            var baseX = Math.round(cat2.gx), baseY = Math.round(cat2.gy);
            for (var rr = 0; rr < art.length; rr++) {
                for (var cc = 0; cc < art[rr].length; cc++) {
                    var ch = art[rr][cc];
                    if (ch === ' ') continue;
                    var cx = baseX + cc, cy = baseY + rr;
                    if (cx < 0 || cx >= columns || cy < 0 || cy >= rows) continue;
                    catCellMap[cx + ',' + cy] = {
                        cat: cat2,
                        char: ch,
                        isEye: ch === '\u25c8',
                    };
                }
            }
        }

        for (var y = 0; y < rows; y++) {
            for (var x = 0; x < columns; x++) {
                var charX = x * fontSize, charY = y * fontSize;
                var mouseDist = Math.hypot(charX - mouse.x, charY - mouse.y);
                var mouseEffect = Math.max(0, 1 - mouseDist / 390);

                var trailEffect = 0;
                for (var ti = trail.length - 1; ti >= 0; ti--) {
                    var p = trail[ti];
                    var dx = charX - p.x, dy = charY - p.y;
                    if (dx > trailRadius || dx < -trailRadius || dy > trailRadius || dy < -trailRadius) continue;
                    var d = Math.sqrt(dx * dx + dy * dy);
                    if (d < trailRadius) {
                        var spatial = 1 - d / trailRadius;
                        var temporal = 1 - (now - p.t) / maxAge;
                        trailEffect = Math.max(trailEffect, spatial * spatial * temporal);
                    }
                }

                var cellKey = x + ',' + y;
                var catCell = catCellMap[cellKey];

                if (catCell && catCell.cat.assemblyT > 0.02) {
                    var cat3 = catCell.cat;
                    var asm = cat3.assemblyT;
                    var col = catColor(time, cat3.phase);

                    var brightness = 1;
                    if (catCell.isEye) {
                        brightness = 0.7 + 0.3 * Math.sin(time * 0.004 + cat3.eyePulse);
                        var blink = Math.sin(time * 0.0013 + cat3.eyePulse * 3.7);
                        if (blink > 0.92) brightness = 0.15;
                    }

                    var asmEased = 1 - Math.pow(1 - asm, 3);
                    var alpha = 0.04 + asmEased * brightness * 0.22;

                    ctx.fillStyle = 'rgba(' + col.r + ',' + col.g + ',' + col.b + ',' + alpha.toFixed(3) + ')';

                    var displayChar = catCell.char;
                    if (asm < 0.5 && Math.random() < (1 - asm) * 0.5) {
                        var pool = '\u2591\u2592\u2593\u2588\u2580\u2584\u258c\u2590\u2502\u2524\u2561\u2562\u2556\u2555\u2563\u2551\u2557\u255d\u255c\u255b\u2510\u2514\u252c\u252c\u251c\u2500\u253c\u255e\u255f\u255a\u2569\u2566\u2560\u2550\u256c';
                        displayChar = pool[Math.floor(Math.random() * pool.length)];
                    }
                    ctx.fillText(displayChar, charX, charY);
                } else {
                    var noise = Math.sin(x * 0.3 + time * 0.0005) * Math.cos(y * 0.3 + time * 0.0005);
                    var combined = mouseEffect * 0.65 + trailEffect * 0.5;
                    var brightnessIdx = Math.min(chars.length - 1, Math.floor((noise * 0.5 + 0.5 + combined) * chars.length));
                    ctx.fillStyle = 'rgba(255, 255, 255, ' + (0.025 + mouseEffect * 0.1 + trailEffect * 0.08) + ')';
                    ctx.fillText(chars[brightnessIdx], charX, charY);
                }
            }
        }
        rafId = requestAnimationFrame(draw);
    }

    var lastActivityTime = performance.now();
    var IDLE_THRESHOLD = 120000;
    var FADE_SPEED = 0.015;

    function resetIdle() { lastActivityTime = performance.now(); }

    window.addEventListener('resize', function() { init(); resetIdle(); });
    window.addEventListener('mousemove', function(e) {
        mouse.x = e.clientX; mouse.y = e.clientY;
        pushTrail(e.clientX, e.clientY);
        resetIdle();
    });
    window.addEventListener('touchmove', function(e) {
        var touch = e.touches[0];
        if (!touch) return;
        mouse.x = touch.clientX; mouse.y = touch.clientY;
        pushTrail(touch.clientX, touch.clientY);
        resetIdle();
    }, { passive: true });
    window.addEventListener('touchend', function() { mouse.x = -1000; mouse.y = -1000; });
    window.addEventListener('scroll', resetIdle);
    window.addEventListener('click', resetIdle);
    window.addEventListener('keydown', resetIdle);
    document.addEventListener('visibilitychange', function() {
        pageHidden = document.hidden;
        if (!pageHidden) resetIdle();
    });

    init();
    rafId = requestAnimationFrame(draw);
    window.addEventListener('beforeunload', function() { cancelAnimationFrame(rafId); });
    window.addEventListener('pageshow', function(e) {
        if (e.persisted) {
            cancelAnimationFrame(rafId);
            rafId = requestAnimationFrame(draw);
        }
    });
})();
