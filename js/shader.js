const ShaderModule = (() => {
    const vertexShaderSource = `
        attribute vec2 position;
        void main() {
            gl_Position = vec4(position, 0.0, 1.0);
        }
    `;

    const fragmentShaderSource = `
        precision highp float;
        uniform vec2 u_resolution;
        uniform vec2 u_mouse;
        uniform float u_time;

        void main() {
            vec2 uv = gl_FragCoord.xy / u_resolution.xy;
            vec2 st = uv;
            st.x *= u_resolution.x / u_resolution.y;

            vec2 mouse = u_mouse.xy / u_resolution.xy;
            mouse.x *= u_resolution.x / u_resolution.y;

            vec2 center = vec2(0.5 * (u_resolution.x / u_resolution.y), 0.5);
            float distToMouse = distance(st, mouse);

            vec2 warpedSt = st;
            float warpRadius = 0.6;
            if(distToMouse < warpRadius) {
                float influence = pow(1.0 - distToMouse / warpRadius, 2.5);
                vec2 dir = normalize(st - mouse);
                warpedSt -= dir * influence * 0.15 * sin(distToMouse * 40.0 - u_time * 3.0);
            }

            float r = distance(warpedSt, center);
            float angle = atan(warpedSt.y - center.y, warpedSt.x - center.x);

            float rosette = sin(r * 250.0 - u_time * 2.0 + sin(angle * 12.0) * 4.0);
            float wavyLines = cos(warpedSt.x * 200.0 + sin(warpedSt.y * 15.0 + u_time * 1.5) * 4.0);
            float moire = rosette * wavyLines;
            float lines = smoothstep(0.01, 0.05, moire) - smoothstep(0.05, 0.09, moire);
            float vignette = 1.0 - smoothstep(0.2, 1.5, distance(uv, vec2(0.5)));
            vec3 color = vec3(lines * vignette * 0.85);

            gl_FragColor = vec4(color, 1.0);
        }
    `;

    function createShader(gl, type, source) {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        return shader;
    }

    function init() {
        const canvas = document.getElementById('glcanvas');
        if (!canvas) return null;
        const gl = canvas.getContext('webgl');
        if (!gl) return null;

        const program = gl.createProgram();
        gl.attachShader(program, createShader(gl, gl.VERTEX_SHADER, vertexShaderSource));
        gl.attachShader(program, createShader(gl, gl.FRAGMENT_SHADER, fragmentShaderSource));
        gl.linkProgram(program);
        gl.useProgram(program);

        const positionBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);

        const posAttr = gl.getAttribLocation(program, 'position');
        gl.enableVertexAttribArray(posAttr);
        gl.vertexAttribPointer(posAttr, 2, gl.FLOAT, false, 0, 0);

        const resLoc = gl.getUniformLocation(program, 'u_resolution');
        const mouseLoc = gl.getUniformLocation(program, 'u_mouse');
        const timeLoc = gl.getUniformLocation(program, 'u_time');

        let mouseX = 0, mouseY = 0;
        let targetX = 0, targetY = 0;

        window.addEventListener('mousemove', (e) => {
            targetX = e.clientX * window.devicePixelRatio;
            targetY = (window.innerHeight - e.clientY) * window.devicePixelRatio;
        });

        function resizeCanvas() {
            canvas.width = window.innerWidth * window.devicePixelRatio;
            canvas.height = window.innerHeight * window.devicePixelRatio;
            canvas.style.width = window.innerWidth + 'px';
            canvas.style.height = window.innerHeight + 'px';
            gl.viewport(0, 0, canvas.width, canvas.height);
            if (targetX === 0) {
                targetX = canvas.width / 2;
                targetY = canvas.height / 2;
                mouseX = targetX;
                mouseY = targetY;
            }
        }
        window.addEventListener('resize', resizeCanvas);
        resizeCanvas();

        function render(time) {
            mouseX += (targetX - mouseX) * 0.08;
            mouseY += (targetY - mouseY) * 0.08;
            gl.uniform2f(resLoc, canvas.width, canvas.height);
            gl.uniform2f(mouseLoc, mouseX, mouseY);
            gl.uniform1f(timeLoc, time * 0.001);
            gl.drawArrays(gl.TRIANGLES, 0, 6);
            requestAnimationFrame(render);
        }
        requestAnimationFrame(render);

        return { gl, canvas };
    }

    return { init };
})();
