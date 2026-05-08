(() => {
    const canvas = document.getElementById('ascii-canvas');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let width = 0;
    let height = 0;
    let columns = 0;
    let rows = 0;
    let rafId = 0;
    let pageHidden = document.hidden;
    const chars = ' .:-=+*#%@'.split('');
    const trail = [];
    const mouse = { x: -1000, y: -1000 };
    const mobile = window.matchMedia('(max-width: 767px)');

    // --- Easter egg: flowers bloom after idle ---
    const FLOWER_ARTS = [
        [' , ', '\\|/', '-@-', '/|\\', " ' "],
        ['.**.', '*%%*', '*%%*', "'**'", " '' "],
        [' , ', '@|@', '*|*', '@|@', " ' "],
        [' { ', '{@}', '_|_', "   ", "   "],
    ];
    let flowerPositions = [];
    let lastActivityTime = performance.now();
    let flowerAlpha = 0; // 0 = hidden, 1 = full bloom
    const IDLE_THRESHOLD = 15000;  // 15s idle to start blooming
    const BLOOM_SPEED = 0.003;     // fade in speed per frame
    const FADE_SPEED = 0.015;      // fade out speed per frame

    function placeFlowers() {
        flowerPositions = [];
        if (columns < 20 || rows < 20) return;
        const count = Math.max(3, Math.floor((columns * rows) / 600));
        const margin = 6;
        for (let i = 0; i < count; i++) {
            const art = FLOWER_ARTS[Math.floor(Math.random() * FLOWER_ARTS.length)];
            const artCols = Math.max(...art.map(r => r.length));
            const gx = margin + Math.floor(Math.random() * (columns - artCols - margin * 2));
            const gy = margin + Math.floor(Math.random() * (rows - art.length - margin * 2));
            flowerPositions.push({ art, gx, gy, phase: Math.random() * Math.PI * 2 });
        }
    }

    function resetIdle() {
        lastActivityTime = performance.now();
    }

    function getFontSize() {
        return mobile.matches ? 24 : 15;
    }

    function init() {
        const dpr = Math.min(window.devicePixelRatio || 1, 2);
        width = window.innerWidth;
        height = window.innerHeight;
        canvas.width = Math.floor(width * dpr);
        canvas.height = Math.floor(height * dpr);
        canvas.style.width = width + 'px';
        canvas.style.height = height + 'px';
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        const fontSize = getFontSize();
        columns = Math.ceil(width / fontSize);
        rows = Math.ceil(height / fontSize);
        placeFlowers();
    }

    function pushTrail(px, py) {
        const last = trail[trail.length - 1];
        if (!last || Math.hypot(px - last.x, py - last.y) > 12) {
            trail.push({ x: px, y: py, t: performance.now() });
        }
    }

    function draw(time) {
        if (pageHidden) {
            rafId = requestAnimationFrame(draw);
            return;
        }

        const fontSize = getFontSize();
        const now = performance.now();
        const maxAge = 1900;
        const trailRadius = 120;

        while (trail.length && now - trail[0].t > maxAge) trail.shift();

        // Update flower alpha based on idle time
        const idleTime = now - lastActivityTime;
        if (idleTime > IDLE_THRESHOLD) {
            flowerAlpha = Math.min(1, flowerAlpha + BLOOM_SPEED);
        } else {
            flowerAlpha = Math.max(0, flowerAlpha - FADE_SPEED);
        }

        ctx.fillStyle = '#050505';
        ctx.fillRect(0, 0, width, height);
        ctx.font = fontSize + 'px "Geist Mono"';
        ctx.textAlign = 'center';

        // Build a set of flower cells for quick lookup
        const flowerCells = new Map(); // "x,y" -> { char, phase }
        if (flowerAlpha > 0.01) {
            for (const f of flowerPositions) {
                for (let r = 0; r < f.art.length; r++) {
                    for (let c = 0; c < f.art[r].length; c++) {
                        if (f.art[r][c] !== ' ') {
                            flowerCells.set((f.gx + c) + ',' + (f.gy + r), { char: f.art[r][c], phase: f.phase });
                        }
                    }
                }
            }
        }

        for (let y = 0; y < rows; y++) {
            for (let x = 0; x < columns; x++) {
                const charX = x * fontSize;
                const charY = y * fontSize;
                const mouseEffect = Math.max(0, 1 - Math.hypot(charX - mouse.x, charY - mouse.y) / 390);
                let trailEffect = 0;

                for (let i = trail.length - 1; i >= 0; i--) {
                    const p = trail[i];
                    const dx = charX - p.x;
                    const dy = charY - p.y;
                    if (dx > trailRadius || dx < -trailRadius || dy > trailRadius || dy < -trailRadius) continue;
                    const d = Math.sqrt(dx * dx + dy * dy);
                    if (d < trailRadius) {
                        const spatial = 1 - d / trailRadius;
                        const temporal = 1 - (now - p.t) / maxAge;
                        trailEffect = Math.max(trailEffect, spatial * spatial * temporal);
                    }
                }

                const noise = Math.sin(x * 0.3 + time * 0.0005) * Math.cos(y * 0.3 + time * 0.0005);
                const combined = mouseEffect * 0.65 + trailEffect * 0.5;
                const brightness = Math.min(chars.length - 1, Math.floor((noise * 0.5 + 0.5 + combined) * chars.length));

                // Check if this cell is a flower
                const key = x + ',' + y;
                const flowerCell = flowerCells.get(key);

                if (flowerCell && flowerAlpha > 0.01) {
                    // Flower char with bloom animation — gentle pulse
                    const pulse = 0.7 + 0.3 * Math.sin(time * 0.001 + flowerCell.phase);
                    const alpha = flowerAlpha * pulse;
                    // Soft greenish tint for flowers
                    ctx.fillStyle = `rgba(140, 255, 180, ${0.06 + alpha * 0.18})`;
                    ctx.fillText(flowerCell.char, charX, charY);
                } else {
                    ctx.fillStyle = `rgba(255, 255, 255, ${0.025 + mouseEffect * 0.1 + trailEffect * 0.08})`;
                    ctx.fillText(chars[brightness], charX, charY);
                }
            }
        }

        rafId = requestAnimationFrame(draw);
    }

    window.addEventListener('resize', init);
    window.addEventListener('mousemove', e => {
        mouse.x = e.clientX;
        mouse.y = e.clientY;
        pushTrail(e.clientX, e.clientY);
        resetIdle();
    });
    window.addEventListener('touchmove', e => {
        const touch = e.touches[0];
        if (!touch) return;
        mouse.x = touch.clientX;
        mouse.y = touch.clientY;
        pushTrail(touch.clientX, touch.clientY);
        resetIdle();
    }, { passive: true });
    window.addEventListener('touchend', () => {
        mouse.x = -1000;
        mouse.y = -1000;
    });
    window.addEventListener('scroll', resetIdle);
    window.addEventListener('click', resetIdle);
    window.addEventListener('keydown', resetIdle);
    document.addEventListener('visibilitychange', () => {
        pageHidden = document.hidden;
        if (!pageHidden) resetIdle();
    });

    init();
    rafId = requestAnimationFrame(draw);
    window.addEventListener('beforeunload', () => cancelAnimationFrame(rafId));
})();
