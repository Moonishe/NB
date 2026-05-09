const AdminApp = (() => {
    let currentSection = 'dashboard';
    let currentDifficulty = 'easy';
    let allModelsData = [];
    let allModelSpacesData = [];
    let allModelParamsData = [];
    let allPromptsData = [];
    let allResultsData = [];
    let invitesData = [];
    let profilesData = [];
    let currentInviteFilter = 'all';
    let currentResultPromptFilter = 'all';
    let currentResultModelFilter = 'all';
    let modelSearchQuery = '';

    function showModal(html) {
        document.getElementById('modal-content').innerHTML = html;
        document.getElementById('modal-overlay').classList.remove('hidden');
    }

    function hideModal() {
        document.getElementById('modal-overlay').classList.add('hidden');
        document.getElementById('modal-content').innerHTML = '';
    }

    async function checkAuth() {
        if (!window.SUPABASE_URL || !window.SUPABASE_ANON_KEY) { showAuth(); return; }
        Api.reinitAdmin();
        const session = await Api.getSession();
        if (session) {
            const admin = await Api.isAdmin();
            if (admin) { showAdmin(session.user.email); }
            else { await Api.logout(); showAuth('Нет прав администратора'); }
        } else { showAuth(); }
    }

    function showAuth(errMsg) {
        document.getElementById('auth-screen').classList.remove('hidden');
        document.getElementById('admin-screen').classList.add('hidden');
        if (errMsg) {
            const errEl = document.getElementById('login-error');
            errEl.textContent = errMsg;
            errEl.classList.remove('hidden');
        }
    }

    let currentLogFilter = 'all';
    let currentModFilter = 'threads';
    let liveLogsInterval = null;
    let achievementsCatalogData = [];

    function toast(msg, type) {
        const el = document.createElement('div');
        el.className = 'admin-toast ' + (type || '');
        el.textContent = msg;
        document.body.appendChild(el);
        setTimeout(() => el.remove(), 3000);
    }

    function switchSection(name) {
        document.querySelectorAll('.admin-nav-btn').forEach(b => b.classList.remove('active'));
        const btn = document.querySelector(`.admin-nav-btn[data-section="${name}"]`);
        if (btn) btn.classList.add('active');
        currentSection = name;
        document.querySelectorAll('.admin-section').forEach(s => s.classList.add('hidden'));
        const sec = document.getElementById('section-' + name);
        if (sec) sec.classList.remove('hidden');
    }

    function showAdmin(email) {
        document.getElementById('auth-screen').classList.add('hidden');
        document.getElementById('admin-screen').classList.remove('hidden');
        document.getElementById('admin-email').textContent = email || '';
        loadDashboard();
        loadPrompts();
        loadModels();
        loadResults();
        loadStats();
        loadInvites();
        loadBans();
        loadAnnouncements();
        loadAchievementsAdmin();
        const profilesReady = loadProfiles().then(() => loadModerators());
        Promise.all([profilesReady, loadAchievementsCatalog()]).then(() => renderProfilesGrid());
    }

    function escapeHtml(str) {
        const d = document.createElement('div');
        d.textContent = str;
        return d.innerHTML.replace(/"/g, '&quot;');
    }

    function escapeJs(str) {
        return String(str).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '');
    }

    function formatDateForDisplay(dateVal) {
        if (!dateVal) return '';
        if (typeof dateVal === 'string') {
            const parts = dateVal.split('-');
            if (parts.length === 3) return `${parts[2]}.${parts[1]}.${parts[0]}`;
        }
        return String(dateVal);
    }

    function formatDateForInput(dateVal) {
        if (!dateVal) return '';
        if (typeof dateVal === 'string') return dateVal;
        const d = new Date(dateVal);
        return d.toISOString().split('T')[0];
    }

    // ========== PROMPTS ==========

    async function loadPrompts() {
        try { allPromptsData = await Api.getAllPrompts(); } catch { allPromptsData = []; }
        renderPromptsList();
        renderResultsFilters();
    }

    function getPromptsByDiff(diff) { return allPromptsData.filter(p => p.difficulty === diff); }

    const PROMPT_MAX_LINES = 4;

    function renderPromptsList() {
        const container = document.getElementById('prompts-list');
        const prompts = getPromptsByDiff(currentDifficulty);
        if (prompts.length === 0) {
            container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет промптов</p>';
            return;
        }
        container.innerHTML = prompts.map((p, i) => `
            <div class="admin-prompt-card flex justify-between items-start gap-4">
                <div class="flex-1 min-w-0">
                    <span class="text-[10px] text-gray-500 uppercase tracking-widest block mb-2">${p.name ? escapeHtml(p.name) : 'Промпт #' + (i + 1)} (id: ${p.id})</span>
                    <div class="admin-prompt-text-wrap relative overflow-hidden" style="max-height:none;">
                        <span class="admin-prompt-text text-sm leading-relaxed" style="color: rgba(200,200,210,0.9); white-space: pre-wrap; display: block;">${escapeHtml(p.text)}</span>
                        <div class="admin-prompt-fade hidden absolute bottom-0 left-0 right-0 h-10 bg-gradient-to-t from-surface to-transparent pointer-events-none"></div>
                    </div>
                    <button class="admin-prompt-toggle-btn hidden text-[9px] uppercase tracking-widest text-gray-400 hover:text-white transition-colors mt-1 border border-white/15 px-2 py-1 bg-white/5 hover:bg-white/10 cursor-pointer">Открыть полностью</button>
                </div>
                <div class="flex-shrink-0 flex gap-2">
                    <button class="text-gray-400 hover:text-white transition-colors text-xs" onclick="AdminApp.editPrompt(${p.id})">Ред.</button>
                    <button class="text-red-400/60 hover:text-red-400 transition-colors text-xs" onclick="AdminApp.deletePrompt(${p.id})">Удал.</button>
                </div>
            </div>
        `).join('');
        requestAnimationFrame(() => {
            container.querySelectorAll('.admin-prompt-text-wrap').forEach(wrap => {
                const el = wrap.querySelector('.admin-prompt-text');
                const cs = getComputedStyle(el);
                const lh = parseFloat(cs.lineHeight);
                const fontSize = parseFloat(cs.fontSize);
                const effectiveLH = isNaN(lh) ? fontSize * 1.5 : lh;
                const maxH = effectiveLH * PROMPT_MAX_LINES;
                if (el.scrollHeight > maxH + 4) {
                    const fade = wrap.querySelector('.admin-prompt-fade');
                    const btn = wrap.parentElement.querySelector('.admin-prompt-toggle-btn');
                    wrap.style.maxHeight = maxH + 'px';
                    fade.classList.remove('hidden');
                    btn.classList.remove('hidden');
                    btn.addEventListener('click', () => {
                        if (wrap.style.maxHeight !== 'none') {
                            wrap.style.maxHeight = 'none'; fade.classList.add('hidden'); btn.textContent = 'Свернуть';
                        } else {
                            wrap.style.maxHeight = maxH + 'px'; fade.classList.remove('hidden'); btn.textContent = 'Открыть полностью';
                        }
                    });
                }
            });
        });
    }

    function showAddPromptForm() {
        showModal(`
            <h3 class="font-title text-lg uppercase tracking-widest mb-6">Добавить промпт</h3>
            <form id="prompt-form" class="flex flex-col gap-4">
                <input name="name" placeholder="Название (необязательно)" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                <select name="difficulty" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50">
                    <option value="easy" ${currentDifficulty === 'easy' ? 'selected' : ''}>Лёгкий</option>
                    <option value="medium" ${currentDifficulty === 'medium' ? 'selected' : ''}>Средний</option>
                    <option value="hard" ${currentDifficulty === 'hard' ? 'selected' : ''}>Сложный</option>
                </select>
                <textarea name="text" rows="8" placeholder="Текст промпта..." required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50 resize-y"></textarea>
                <div class="flex gap-3 mt-2">
                    <button type="submit" class="flex-1 bg-white text-black py-3 text-xs uppercase tracking-widest font-bold hover:bg-gray-200 transition-colors">Сохранить</button>
                    <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Отмена</button>
                </div>
            </form>
        `);
        document.getElementById('prompt-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(e.target);
            try { await Api.addPrompt({ difficulty: fd.get('difficulty'), text: fd.get('text'), name: fd.get('name') || null }); await loadPrompts(); hideModal(); }
            catch (err) { alert('Ошибка: ' + err.message); }
        });
    }

    function editPrompt(id) {
        const prompt = allPromptsData.find(p => p.id === id);
        if (!prompt) return;
        showModal(`
            <h3 class="font-title text-lg uppercase tracking-widest mb-6">Редактировать промпт</h3>
            <form id="prompt-edit-form" class="flex flex-col gap-4">
                <input name="name" value="${escapeHtml(prompt.name || '')}" placeholder="Название" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                <select name="difficulty" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50">
                    <option value="easy" ${prompt.difficulty === 'easy' ? 'selected' : ''}>Лёгкий</option>
                    <option value="medium" ${prompt.difficulty === 'medium' ? 'selected' : ''}>Средний</option>
                    <option value="hard" ${prompt.difficulty === 'hard' ? 'selected' : ''}>Сложный</option>
                </select>
                <textarea name="text" rows="8" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50 resize-y">${escapeHtml(prompt.text)}</textarea>
                <div class="flex gap-3 mt-2">
                    <button type="submit" class="flex-1 bg-white text-black py-3 text-xs uppercase tracking-widest font-bold hover:bg-gray-200 transition-colors">Обновить</button>
                    <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Отмена</button>
                </div>
            </form>
        `);
        document.getElementById('prompt-edit-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(e.target);
            try { await Api.updatePrompt(id, { text: fd.get('text'), difficulty: fd.get('difficulty'), name: fd.get('name') || null }); await loadPrompts(); hideModal(); }
            catch (err) { alert('Ошибка: ' + err.message); }
        });
    }

    async function deletePrompt(id) {
        if (!confirm('Удалить промпт? Связанные результаты тоже удалятся.')) return;
        try { await Api.deletePrompt(id); await loadPrompts(); await loadResults(); } catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== MODELS (settings hub) ==========

    async function loadModels() {
        try { allModelsData = await Api.getAllModels(); } catch { allModelsData = []; }
        try { allModelSpacesData = await Api.getAllModelSpaces(); } catch { allModelSpacesData = []; }
        try { allModelParamsData = await Api.getAllModelParams(); } catch { allModelParamsData = []; }
        renderModelsList();
        renderResultsFilters();
    }

    function renderModelsList() {
        const container = document.getElementById('models-list');
        let filteredModels = allModelsData;
        if (modelSearchQuery) {
            const q = modelSearchQuery.toLowerCase();
            filteredModels = allModelsData.filter(m => m.name.toLowerCase().includes(q));
        }
        if (filteredModels.length === 0) {
            container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет моделей</p>';
            return;
        }
        container.innerHTML = filteredModels.map(m => {
            const spaces = allModelSpacesData.filter(s => s.model_id === m.id);
            const params = allModelParamsData.filter(p => p.model_id === m.id);
            const testCount = allResultsData.filter(r => r.model_id === m.id).length;
            const spacesStr = spaces.length > 0 ? spaces.map(s => escapeHtml(s.name)).join(', ') : '—';
            const paramsStr = params.length > 0 ? params.map(p => {
                const vals = (p.model_param_values || []).map(v => escapeHtml(v.value)).join(', ');
                return `<span class="text-blue-400/80">${escapeHtml(p.name)}</span>: ${vals || '—'}`;
            }).join(' &nbsp;|&nbsp; ') : '—';
            return `
                <div class="admin-prompt-card">
                    <div class="flex justify-between items-start gap-4">
                        <div class="flex-1">
                            <span class="text-gray-200 font-bold text-sm">${escapeHtml(m.name)}</span>
                            <span class="text-xs text-gray-500 block mt-1">id: ${m.id} | Тестов: ${testCount}</span>
                        </div>
                        <div class="flex-shrink-0 flex gap-2">
                            <button class="text-gray-400 hover:text-white transition-colors text-xs" onclick="AdminApp.editModel(${m.id})">Ред.</button>
                            <button class="text-red-400/60 hover:text-red-400 transition-colors text-xs" onclick="AdminApp.deleteModel(${m.id})">Удал.</button>
                        </div>
                    </div>
                    <div class="mt-3 pt-3 border-t border-white/5">
                        <div class="mb-2">
                            <span class="text-[9px] uppercase tracking-widest text-gray-500">Пространства (макро):</span>
                            <span class="text-xs text-gray-300 ml-2">${spacesStr}</span>
                            <button class="text-[10px] uppercase tracking-widest text-blue-400/60 hover:text-blue-400 ml-2" onclick="AdminApp.manageModelSpaces(${m.id})">управлять</button>
                        </div>
                        <div>
                            <span class="text-[9px] uppercase tracking-widest text-gray-500">Параметры (микро):</span>
                            <span class="text-xs ml-2">${paramsStr}</span>
                            <button class="text-[10px] uppercase tracking-widest text-blue-400/60 hover:text-blue-400 ml-2" onclick="AdminApp.manageModelParams(${m.id})">управлять</button>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    }

    function showAddModelForm() {
        showModal(`
            <h3 class="font-title text-lg uppercase tracking-widest mb-6">Новая модель</h3>
            <form id="model-form" class="flex flex-col gap-4">
                <input name="name" placeholder="Gemini 2.5 Pro" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                <div class="flex gap-3 mt-2">
                    <button type="submit" class="flex-1 bg-white text-black py-3 text-xs uppercase tracking-widest font-bold hover:bg-gray-200 transition-colors">Сохранить</button>
                    <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Отмена</button>
                </div>
            </form>
        `);
        document.getElementById('model-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(e.target);
            try { await Api.addModel({ name: fd.get('name') }); await loadModels(); hideModal(); }
            catch (err) { alert('Ошибка: ' + err.message); }
        });
    }

    function editModel(id) {
        const model = allModelsData.find(m => m.id === id);
        if (!model) return;
        showModal(`
            <h3 class="font-title text-lg uppercase tracking-widest mb-6">Редактировать модель</h3>
            <form id="model-edit-form" class="flex flex-col gap-4">
                <input name="name" value="${escapeHtml(model.name || '')}" placeholder="Название" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                <div class="flex gap-3 mt-2">
                    <button type="submit" class="flex-1 bg-white text-black py-3 text-xs uppercase tracking-widest font-bold hover:bg-gray-200 transition-colors">Обновить</button>
                    <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Отмена</button>
                </div>
            </form>
        `);
        document.getElementById('model-edit-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(e.target);
            try { await Api.updateModel(id, { name: fd.get('name') }); await loadModels(); hideModal(); }
            catch (err) { alert('Ошибка: ' + err.message); }
        });
    }

    async function deleteModel(id) {
        if (!confirm('Удалить модель? Пространства, параметры и результаты тоже удалятся.')) return;
        try { await Api.deleteModel(id); await loadModels(); await loadResults(); } catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== MODEL SPACES (manage modal) ==========

    async function manageModelSpaces(modelId) {
        const model = allModelsData.find(m => m.id === modelId);
        if (!model) return;
        let spaces;
        try { spaces = await Api.getModelSpaces(modelId); } catch { spaces = []; }
        showModal(`
            <h3 class="font-title text-lg uppercase tracking-widest mb-6">Пространства: ${escapeHtml(model.name)}</h3>
            <div id="spaces-list" class="flex flex-col gap-2 mb-4">
                ${spaces.length > 0 ? spaces.map(s => `
                    <div class="flex items-center gap-2 border border-border p-3 rounded-xl">
                        <input name="space_name_${s.id}" value="${escapeHtml(s.name)}" placeholder="Название" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <input name="space_url_${s.id}" value="${escapeHtml(s.url || '')}" placeholder="URL (опц.)" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <button type="button" class="text-red-400/60 hover:text-red-400 text-xs" onclick="AdminApp.deleteModelSpaceItem(${s.id}, ${model.id})">Удал.</button>
                    </div>
                `).join('') : '<p class="text-gray-500 text-xs">Нет пространств. Добавьте ниже.</p>'}
            </div>
            <div class="border border-border p-3 rounded-xl mb-4">
                <p class="text-xs uppercase tracking-widest text-gray-400 mb-2">+ Новое пространство</p>
                <div class="flex gap-2">
                    <input id="new-space-name" placeholder="AI Studio, Official site..." class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                    <input id="new-space-url" placeholder="URL (опц.)" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                    <button type="button" id="add-space-btn" class="text-[10px] uppercase tracking-widest border border-white/15 px-4 py-2 bg-white/5 hover:bg-white/10 transition-colors">Добавить</button>
                </div>
            </div>
            <div class="flex gap-3 mt-2">
                <button type="button" id="save-spaces-btn" class="flex-1 bg-white text-black py-3 text-xs uppercase tracking-widest font-bold hover:bg-gray-200 transition-colors">Сохранить</button>
                <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Закрыть</button>
            </div>
        `);
        document.getElementById('add-space-btn').addEventListener('click', async () => {
            const name = document.getElementById('new-space-name').value.trim();
            const url = document.getElementById('new-space-url').value.trim();
            if (!name) { alert('Введите название'); return; }
            try { await Api.addModelSpace({ model_id: model.id, name, url: url || null }); await loadModels(); AdminApp.manageModelSpaces(model.id); }
            catch (err) { alert('Ошибка: ' + err.message); }
        });
        document.getElementById('save-spaces-btn').addEventListener('click', async () => {
            try {
                for (const s of spaces) {
                    const n = document.querySelector(`[name="space_name_${s.id}"]`);
                    const u = document.querySelector(`[name="space_url_${s.id}"]`);
                    if (n) await Api.updateModelSpace(s.id, { name: n.value.trim(), url: u ? (u.value.trim() || null) : s.url });
                }
                await loadModels(); hideModal();
            } catch (err) { alert('Ошибка: ' + err.message); }
        });
    }

    async function deleteModelSpaceItem(spaceId, modelId) {
        if (!confirm('Удалить пространство?')) return;
        try { await Api.deleteModelSpace(spaceId); await loadModels(); await loadResults(); AdminApp.manageModelSpaces(modelId); }
        catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== MODEL PARAMS (manage modal) ==========

    async function manageModelParams(modelId) {
        const model = allModelsData.find(m => m.id === modelId);
        if (!model) return;
        let params;
        try { params = await Api.getModelParams(modelId); } catch { params = []; }
        renderModelParamsModal(model, params);
    }

    function renderModelParamsModal(model, params) {
        const paramsHtml = params.length > 0 ? params.map(p => {
            const values = p.model_param_values || [];
            const valuesStr = values.length > 0 ? values.map(v => `
                <div class="flex items-center gap-1 bg-surface border border-border px-2 py-1 rounded-lg">
                    <span class="text-xs text-gray-300">${escapeHtml(v.value)}</span>
                    <button type="button" class="text-red-400/60 hover:text-red-400 text-[9px] ml-1" onclick="AdminApp.deleteParamValue(${v.id}, ${model.id}, ${p.id})">×</button>
                </div>
            `).join('') : '<span class="text-gray-500 text-xs">Нет значений</span>';
            return `
                <div class="border border-border p-3 rounded-xl">
                    <div class="flex items-center gap-2 mb-2">
                        <input name="param_name_${p.id}" value="${escapeHtml(p.name)}" placeholder="Название параметра" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <button type="button" class="text-red-400/60 hover:text-red-400 text-xs" onclick="AdminApp.deleteParam(${p.id}, ${model.id})">Удал. параметр</button>
                    </div>
                    <div class="flex flex-wrap gap-1 mb-2">${valuesStr}</div>
                    <div class="flex gap-2">
                        <input id="new-val-input-${p.id}" placeholder="Новое значение" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <button type="button" class="text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1 bg-white/5 hover:bg-white/10 transition-colors" onclick="AdminApp.addParamValue(${p.id}, ${model.id})">+</button>
                    </div>
                </div>
            `;
        }).join('') : '<p class="text-gray-500 text-xs">Нет параметров. Добавьте ниже.</p>';

        showModal(`
            <h3 class="font-title text-lg uppercase tracking-widest mb-6">Параметры: ${escapeHtml(model.name)}</h3>
            <div id="params-list" class="flex flex-col gap-3 mb-4">${paramsHtml}</div>
            <div class="border border-border p-3 rounded-xl mb-4">
                <p class="text-xs uppercase tracking-widest text-gray-400 mb-2">+ Новый параметр</p>
                <div class="flex gap-2">
                    <input id="new-param-name" placeholder="Thinking mode, Tools..." class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                    <input id="new-param-default-val" placeholder="Значение по умолчанию (опц.)" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                    <button type="button" id="add-param-btn" class="text-[10px] uppercase tracking-widest border border-white/15 px-4 py-2 bg-white/5 hover:bg-white/10 transition-colors">Добавить</button>
                </div>
            </div>
            <div class="flex gap-3 mt-2">
                <button type="button" id="save-params-btn" class="flex-1 bg-white text-black py-3 text-xs uppercase tracking-widest font-bold hover:bg-gray-200 transition-colors">Сохранить</button>
                <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Закрыть</button>
            </div>
        `);

        document.getElementById('add-param-btn').addEventListener('click', async () => {
            const name = document.getElementById('new-param-name').value.trim();
            if (!name) { alert('Введите название параметра'); return; }
            try {
                const created = await Api.addModelParam({ model_id: model.id, name });
                const defaultVal = document.getElementById('new-param-default-val').value.trim();
                if (defaultVal && created[0]) {
                    await Api.addModelParamValue({ param_id: created[0].id, value: defaultVal });
                }
                await loadModels();
                AdminApp.manageModelParams(model.id);
            } catch (err) { alert('Ошибка: ' + err.message); }
        });

        document.getElementById('save-params-btn').addEventListener('click', async () => {
            try {
                for (const p of params) {
                    const n = document.querySelector(`[name="param_name_${p.id}"]`);
                    if (n) await Api.updateModelParam(p.id, { name: n.value.trim() });
                }
                await loadModels(); renderResultsFilters(); hideModal();
            } catch (err) { alert('Ошибка: ' + err.message); }
        });
    }

    async function addParamValue(paramId, modelId) {
        const input = document.getElementById(`new-val-input-${paramId}`);
        const val = input.value.trim();
        if (!val) { alert('Введите значение'); return; }
        try { await Api.addModelParamValue({ param_id: paramId, value: val }); await loadModels(); AdminApp.manageModelParams(modelId); }
        catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function deleteParamValue(valueId, modelId) {
        if (!confirm('Удалить значение параметра?')) return;
        try { await Api.deleteModelParamValue(valueId); await loadModels(); await loadResults(); AdminApp.manageModelParams(modelId); }
        catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function deleteParam(paramId, modelId) {
        if (!confirm('Удалить параметр и все его значения?')) return;
        try { await Api.deleteModelParam(paramId); await loadModels(); await loadResults(); AdminApp.manageModelParams(modelId); }
        catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== RESULTS ==========

    async function loadResults() {
        try { allResultsData = await Api.getAllResults(); } catch { allResultsData = []; }
        renderResultsList();
    }

    function renderResultsFilters() {
        const promptSelect = document.getElementById('results-prompt-filter');
        const modelSelect = document.getElementById('results-model-filter');
        if (!promptSelect || !modelSelect) return;

        const prevPrompt = promptSelect.value;
        const prevModel = modelSelect.value;

        promptSelect.innerHTML = '<option value="all">Все</option>';
        allPromptsData.forEach(p => {
            const diffLabel = p.difficulty === 'easy' ? 'Лёгкий' : p.difficulty === 'medium' ? 'Средний' : 'Сложный';
            const option = document.createElement('option');
            option.value = String(p.id);
            option.textContent = `[${diffLabel}] ${p.name || '#' + p.id}`;
            promptSelect.appendChild(option);
        });
        promptSelect.value = prevPrompt || 'all';

        modelSelect.innerHTML = '<option value="all">Все</option>';
        allModelsData.forEach(m => {
            const option = document.createElement('option');
            option.value = String(m.id);
            option.textContent = m.name || '';
            modelSelect.appendChild(option);
        });
        modelSelect.value = prevModel || 'all';
    }

    function getResultParamLabel(result) {
        const rpvs = result.result_param_values || [];
        if (rpvs.length === 0) return '';
        return rpvs.map(rpv => {
            const mpv = rpv.model_param_values;
            if (!mpv) return '';
            const mp = mpv.model_params;
            return mp ? `${mp.name}: ${mpv.value}` : mpv.value;
        }).filter(Boolean).join(' + ');
    }

    function renderResultsList() {
        const container = document.getElementById('results-list');
        let filtered = allResultsData;
        if (currentResultPromptFilter !== 'all') filtered = filtered.filter(r => r.prompt_id === parseInt(currentResultPromptFilter));
        if (currentResultModelFilter !== 'all') filtered = filtered.filter(r => r.model_id === parseInt(currentResultModelFilter));

        if (filtered.length === 0) {
            container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет результатов</p>';
            return;
        }

        container.innerHTML = filtered.map(r => {
            const modelName = r.models ? r.models.name : '—';
            const spaceName = r.model_spaces ? r.model_spaces.name : '—';
            const promptName = r.prompts ? (r.prompts.name || '#' + r.prompt_id) : '#' + r.prompt_id;
            const dateStr = r.test_date ? formatDateForDisplay(r.test_date) : '—';
            const paramLabel = getResultParamLabel(r);
            return `
                <div class="admin-prompt-card flex justify-between items-start gap-4">
                    <div class="flex-1">
                        <span class="text-gray-200 font-bold">${escapeHtml(modelName)}</span>
                        <span class="text-blue-400/70 ml-2 text-xs">${escapeHtml(spaceName)}</span>
                        ${paramLabel ? `<span class="text-purple-400/70 ml-2 text-xs">${escapeHtml(paramLabel)}</span>` : ''}
                        ${r.author ? `<span class="text-gray-500 ml-2 text-xs">by ${escapeHtml(r.author)}</span>` : ''}
                        <span class="text-gray-500 ml-2 text-xs">${escapeHtml(promptName)}</span>
                        <span class="text-xs text-gray-500 block mt-1">
                            id: ${escapeHtml(r.id)} | Дата: ${escapeHtml(dateStr)} | Балл: ${escapeHtml(r.overall)}${r.svg_content ? ' | SVG ✓' : ''}
                            | ${escapeHtml(r.s_visual)}/${escapeHtml(r.s_animation)}/${escapeHtml(r.s_creative)}/${escapeHtml(r.s_code)}/${escapeHtml(r.s_detail)}
                        </span>
                    </div>
                    <div class="flex-shrink-0 flex gap-2">
                        <button class="text-gray-400 hover:text-white transition-colors text-xs" onclick="AdminApp.editResult(${r.id})">Ред.</button>
                        <button class="text-red-400/60 hover:text-red-400 transition-colors text-xs" onclick="AdminApp.deleteResult(${r.id})">Удал.</button>
                    </div>
                </div>
            `;
        }).join('');
    }

    function buildResultFormHTML(opts = {}) {
        const { result, isEdit } = opts;
        const promptId = result ? result.prompt_id : '';
        const modelId = result ? result.model_id : '';
        const spaceId = result ? (result.model_space_id || '') : '';
        const testDate = result ? formatDateForInput(result.test_date) : '';
        const sVisual = result ? result.s_visual : '';
        const sAnimation = result ? result.s_animation : '';
        const sCreative = result ? result.s_creative : '';
        const sCode = result ? result.s_code : '';
        const sDetail = result ? result.s_detail : '';
        const svgContent = result ? (result.svg_content || '') : '';
        const author = result ? (result.author || '') : '';
        const existingParamValueIds = result ? (result.result_param_values || []).map(rpv => rpv.param_value_id) : [];

        const promptsOptions = allPromptsData.map(p => {
            const diffLabel = p.difficulty === 'easy' ? 'Лёгкий' : p.difficulty === 'medium' ? 'Средний' : 'Сложный';
            const selected = p.id === promptId ? 'selected' : '';
            return `<option value="${p.id}" ${selected}>[${diffLabel}] ${escapeHtml(p.name || '#' + p.id)}</option>`;
        }).join('');

        const modelsOptions = allModelsData.map(m => {
            const selected = m.id === modelId ? 'selected' : '';
            return `<option value="${m.id}" ${selected}>${escapeHtml(m.name)}</option>`;
        }).join('');

        const spacesForModel = modelId ? allModelSpacesData.filter(s => s.model_id === modelId) : [];
        const spacesOptions = spacesForModel.map(s => {
            const selected = s.id === spaceId ? 'selected' : '';
            return `<option value="${s.id}" ${selected}>${escapeHtml(s.name)}</option>`;
        }).join('');

        const paramsForModel = modelId ? allModelParamsData.filter(p => p.model_id === modelId) : [];
        const paramsSectionHtml = paramsForModel.length > 0 ? paramsForModel.map(p => {
            const values = p.model_param_values || [];
            const valueOptions = values.map(v => {
                const selected = existingParamValueIds.includes(v.id) ? 'selected' : '';
                return `<option value="${v.id}" ${selected}>${escapeHtml(v.value)}</option>`;
            }).join('');
            return `
                <label class="flex flex-col gap-1">
                    <span class="text-[9px] uppercase tracking-widest text-purple-400/60">${escapeHtml(p.name)}</span>
                    <select name="param_${p.id}" class="w-full bg-surface border border-border px-3 py-2 text-xs text-white outline-none focus:border-white/50">
                        <option value="">— не выбрано —</option>
                        ${valueOptions}
                    </select>
                </label>
            `;
        }).join('') : '';

        return `
            <h3 class="font-title text-lg uppercase tracking-widest mb-6">${isEdit ? 'Редактировать результат' : 'Добавить результат'}</h3>
            <form id="result-form" class="flex flex-col gap-4">
                <label class="flex flex-col gap-1">
                    <span class="text-xs uppercase tracking-widest text-gray-400">Промпт *</span>
                    <select name="prompt_id" id="result-prompt-select" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50">
                        <option value="">Выберите промпт</option>
                        ${promptsOptions}
                    </select>
                </label>
                <label class="flex flex-col gap-1">
                    <span class="text-xs uppercase tracking-widest text-gray-400">Модель *</span>
                    <select name="model_id" id="result-model-select" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50">
                        <option value="">Выберите модель</option>
                        ${modelsOptions}
                        <option value="__new__">+ Создать новую модель...</option>
                    </select>
                    <div id="new-model-fields" class="hidden mt-2 flex gap-2">
                        <input id="new-model-name" placeholder="Название новой модели" class="flex-1 bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                    </div>
                </label>
                <label class="flex flex-col gap-1">
                    <span class="text-xs uppercase tracking-widest text-gray-400">Пространство (макро) *</span>
                    <select name="model_space_id" id="result-space-select" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50">
                        <option value="">Сначала выберите модель</option>
                        ${spacesOptions}
                        <option value="__new__">+ Добавить пространство...</option>
                    </select>
                    <div id="new-space-fields" class="hidden mt-2 flex gap-2">
                        <input id="new-space-name" placeholder="Название пространства" class="flex-1 bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <input id="new-space-url" placeholder="URL (опц.)" class="flex-1 bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                    </div>
                </label>
                <div id="params-section" class="${paramsForModel.length > 0 ? '' : 'hidden'} border border-purple-400/10 p-4">
                    <p class="text-xs uppercase tracking-widest text-purple-400/40 mb-3">Параметры (микро)</p>
                    <div class="grid grid-cols-2 gap-3" id="params-selects">${paramsSectionHtml}</div>
                    <div id="new-param-inline" class="hidden mt-3 border-t border-white/5 pt-3">
                        <p class="text-[9px] uppercase tracking-widest text-gray-400 mb-2">+ Новый параметр к модели</p>
                        <div class="flex gap-2">
                            <input id="inline-param-name" placeholder="Название (Thinking mode)" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                            <input id="inline-param-value" placeholder="Значение (High)" class="flex-1 bg-surface border border-border px-3 py-2 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                            <button type="button" id="inline-param-add-btn" class="text-[10px] uppercase tracking-widest border border-white/15 px-3 py-2 bg-white/5 hover:bg-white/10 transition-colors">+</button>
                        </div>
                    </div>
                    <button type="button" id="toggle-new-param" class="text-[9px] uppercase tracking-widest text-purple-400/60 hover:text-purple-400 mt-2">+ Добавить параметр</button>
                </div>
                <label class="flex flex-col gap-1">
                    <span class="text-xs uppercase tracking-widest text-gray-400">Дата теста *</span>
                    <input name="test_date" type="date" value="${testDate}" required class="w-full bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50">
                </label>
                <input name="author" value="${escapeHtml(author)}" placeholder="Автор теста (опционально)" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50">
                <div class="border border-border p-4">
                    <p class="text-xs uppercase tracking-widest text-gray-400 mb-3">Оценки</p>
                    <div class="grid grid-cols-5 gap-2">
                        <input name="s_visual" type="number" step="0.1" min="0" max="10" value="${sVisual}" placeholder="Визуал" required class="w-full bg-surface border border-border px-2 py-2 text-xs text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <input name="s_animation" type="number" step="0.1" min="0" max="10" value="${sAnimation}" placeholder="Анимация" required class="w-full bg-surface border border-border px-2 py-2 text-xs text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <input name="s_creative" type="number" step="0.1" min="0" max="10" value="${sCreative}" placeholder="Креатив" required class="w-full bg-surface border border-border px-2 py-2 text-xs text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <input name="s_code" type="number" step="0.1" min="0" max="10" value="${sCode}" placeholder="Код" required class="w-full bg-surface border border-border px-2 py-2 text-xs text-white placeholder-gray-500 outline-none focus:border-white/50">
                        <input name="s_detail" type="number" step="0.1" min="0" max="10" value="${sDetail}" placeholder="Детали" required class="w-full bg-surface border border-border px-2 py-2 text-xs text-white placeholder-gray-500 outline-none focus:border-white/50">
                    </div>
                    <p class="text-xs text-gray-500 mt-2">Общий балл: <span id="computed-overall">—</span> (сумма × 1.8)</p>
                </div>
                <label class="flex flex-col gap-1">
                    <span class="text-xs uppercase tracking-widest text-gray-400">SVG результат</span>
                    <div class="flex gap-2">
                        <input type="file" id="svg-file-input" accept=".svg" class="text-xs text-gray-400 file:mr-2 file:py-2 file:px-3 file:border file:border-border file:bg-white/5 file:text-white file:text-xs file:uppercase file:tracking-widest file:cursor-pointer">
                        <button type="button" id="svg-paste-btn" class="text-[10px] uppercase tracking-widest border border-border px-3 py-2 bg-white/5 hover:bg-white/10 transition-colors">Вставить код</button>
                    </div>
                    <textarea name="svg_content" id="svg-content-area" rows="4" placeholder="SVG-код или загрузите файл..." style="display:none" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-gray-500 outline-none focus:border-white/50 resize-y font-mono text-xs">${escapeHtml(svgContent)}</textarea>
                </label>
                <div class="flex gap-3 mt-2">
                    <button type="submit" class="flex-1 bg-white text-black py-3 text-xs uppercase tracking-widest font-bold hover:bg-gray-200 transition-colors">${isEdit ? 'Обновить' : 'Сохранить'}</button>
                    <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Отмена</button>
                </div>
            </form>
        `;
    }

    function attachResultFormHandlers(resultId) {
        const modelSelect = document.getElementById('result-model-select');
        const spaceSelect = document.getElementById('result-space-select');
        const newModelFields = document.getElementById('new-model-fields');
        const newSpaceFields = document.getElementById('new-space-fields');
        const paramsSection = document.getElementById('params-section');
        const paramsSelects = document.getElementById('params-selects');
        const toggleNewParam = document.getElementById('toggle-new-param');
        const newParamInline = document.getElementById('new-param-inline');

        function updateSpaceDropdown(modelIdVal) {
            const spaces = allModelSpacesData.filter(s => s.model_id === parseInt(modelIdVal));
            const currentVal = spaceSelect.value;
            spaceSelect.innerHTML = '<option value="">Выберите пространство</option>';
            spaces.forEach(s => {
                const option = document.createElement('option');
                option.value = String(s.id);
                option.textContent = s.name || '';
                spaceSelect.appendChild(option);
            });
            spaceSelect.appendChild(new Option('+ Добавить пространство...', '__new__'));
            if (spaces.find(s => String(s.id) === currentVal)) spaceSelect.value = currentVal;
        }

        function updateParamsSection(modelIdVal) {
            const params = allModelParamsData.filter(p => p.model_id === parseInt(modelIdVal));
            if (params.length === 0) {
                paramsSection.classList.add('hidden');
                return;
            }
            paramsSection.classList.remove('hidden');
            paramsSelects.innerHTML = params.map(p => {
                const values = p.model_param_values || [];
                const valueOptions = values.map(v => `<option value="${v.id}">${escapeHtml(v.value)}</option>`).join('');
                return `
                    <label class="flex flex-col gap-1">
                        <span class="text-[9px] uppercase tracking-widest text-purple-400/60">${escapeHtml(p.name)}</span>
                        <select name="param_${p.id}" class="w-full bg-surface border border-border px-3 py-2 text-xs text-white outline-none focus:border-white/50">
                            <option value="">— не выбрано —</option>
                            ${valueOptions}
                        </select>
                    </label>
                `;
            }).join('');
        }

        if (modelSelect.value && modelSelect.value !== '__new__') {
            updateSpaceDropdown(modelSelect.value);
            updateParamsSection(modelSelect.value);
        }

        modelSelect.addEventListener('change', () => {
            if (modelSelect.value === '__new__') {
                newModelFields.classList.remove('hidden');
                spaceSelect.innerHTML = '<option value="">Сначала сохраните модель</option><option value="__new__">+ Добавить пространство...</option>';
                paramsSection.classList.add('hidden');
            } else {
                newModelFields.classList.add('hidden');
                if (modelSelect.value) { updateSpaceDropdown(modelSelect.value); updateParamsSection(modelSelect.value); }
                else { spaceSelect.innerHTML = '<option value="">Сначала выберите модель</option>'; paramsSection.classList.add('hidden'); }
            }
        });

        spaceSelect.addEventListener('change', () => {
            if (spaceSelect.value === '__new__') newSpaceFields.classList.remove('hidden');
            else newSpaceFields.classList.add('hidden');
        });

        toggleNewParam.addEventListener('click', () => { newParamInline.classList.toggle('hidden'); });

        document.getElementById('inline-param-add-btn').addEventListener('click', async () => {
            const currentModelId = modelSelect.value;
            if (!currentModelId || currentModelId === '__new__') { alert('Сначала выберите/создайте модель'); return; }
            const pName = document.getElementById('inline-param-name').value.trim();
            const pValue = document.getElementById('inline-param-value').value.trim();
            if (!pName) { alert('Введите название параметра'); return; }
            try {
                const created = await Api.addModelParam({ model_id: parseInt(currentModelId), name: pName });
                if (pValue && created[0]) await Api.addModelParamValue({ param_id: created[0].id, value: pValue });
                await loadModels();
                updateParamsSection(currentModelId);
                document.getElementById('inline-param-name').value = '';
                document.getElementById('inline-param-value').value = '';
                newParamInline.classList.add('hidden');
            } catch (err) { alert('Ошибка: ' + err.message); }
        });

        const scoreInputs = ['s_visual', 's_animation', 's_creative', 's_code', 's_detail'];
        function computeOverall() {
            const sum = scoreInputs.reduce((acc, name) => acc + (parseFloat(document.querySelector(`[name="${name}"]`).value) || 0), 0);
            document.getElementById('computed-overall').textContent = (sum * 1.8).toFixed(1);
        }
        scoreInputs.forEach(name => { document.querySelector(`[name="${name}"]`).addEventListener('input', computeOverall); });
        computeOverall();

        const svgContentArea = document.getElementById('svg-content-area');
        document.getElementById('svg-paste-btn').addEventListener('click', () => { svgContentArea.style.display = svgContentArea.style.display === 'none' ? '' : 'none'; });
        document.getElementById('svg-file-input').addEventListener('change', (e) => {
            const file = e.target.files[0]; if (!file) return;
            const reader = new FileReader();
            reader.onload = (ev) => { svgContentArea.value = ev.target.result; svgContentArea.style.display = ''; };
            reader.readAsText(file);
        });

        document.getElementById('result-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(e.target);
            const scores = {
                s_visual: parseFloat(fd.get('s_visual')),
                s_animation: parseFloat(fd.get('s_animation')),
                s_creative: parseFloat(fd.get('s_creative')),
                s_code: parseFloat(fd.get('s_code')),
                s_detail: parseFloat(fd.get('s_detail'))
            };
            const overall = parseFloat(((scores.s_visual + scores.s_animation + scores.s_creative + scores.s_code + scores.s_detail) * 1.8).toFixed(1));

            let modelIdVal = fd.get('model_id');
            let spaceIdVal = fd.get('model_space_id');

            if (modelIdVal === '__new__') {
                const newName = document.getElementById('new-model-name').value.trim();
                if (!newName) { alert('Введите название модели'); return; }
                try { const created = await Api.addModel({ name: newName }); modelIdVal = created[0].id; await loadModels(); }
                catch (err) { alert('Ошибка создания модели: ' + err.message); return; }
            }

            if (spaceIdVal === '__new__') {
                const newSpaceName = document.getElementById('new-space-name').value.trim();
                const newSpaceUrl = document.getElementById('new-space-url').value.trim();
                if (!newSpaceName) { alert('Введите название пространства'); return; }
                try { const created = await Api.addModelSpace({ model_id: parseInt(modelIdVal), name: newSpaceName, url: newSpaceUrl || null }); spaceIdVal = created[0].id; await loadModels(); }
                catch (err) { alert('Ошибка создания пространства: ' + err.message); return; }
            }

            const currentParams = allModelParamsData.filter(p => p.model_id === parseInt(modelIdVal));
            const paramValueIds = [];
            for (const p of currentParams) {
                const val = fd.get(`param_${p.id}`);
                if (val) paramValueIds.push(parseInt(val));
            }

            const resultData = {
                model_id: parseInt(modelIdVal),
                prompt_id: parseInt(fd.get('prompt_id')),
                model_space_id: parseInt(spaceIdVal),
                test_date: fd.get('test_date') || null,
                author: fd.get('author') || null,
                ...scores,
                overall,
                svg_content: document.getElementById('svg-content-area').value || null
            };

            try {
                let savedResult;
                if (resultId) {
                    await Api.updateResult(resultId, resultData);
                    savedResult = [{ id: resultId }];
                } else {
                    savedResult = await Api.addResult(resultData);
                }
                if (savedResult && savedResult[0]) {
                    await Api.setResultParamValues(savedResult[0].id, paramValueIds);
                }
                await loadResults();
                hideModal();
            } catch (err) { alert('Ошибка сохранения: ' + err.message); }
        });
    }

    function showAddResultForm() {
        if (allPromptsData.length === 0) { alert('Сначала добавьте хотя бы один промпт'); return; }
        showModal(buildResultFormHTML({ isEdit: false }));
        attachResultFormHandlers(null);
    }

    function editResult(id) {
        const result = allResultsData.find(r => r.id === id);
        if (!result) return;
        showModal(buildResultFormHTML({ result, isEdit: true }));
        attachResultFormHandlers(id);
    }

    async function deleteResult(id) {
        if (!confirm('Удалить результат?')) return;
        try { await Api.deleteResult(id); await loadResults(); } catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== INVITES & USERS ==========

    async function loadInvites() {
        try { invitesData = await Api.adminGetInviteCodes(); } catch { invitesData = []; }
        renderInvitesList();
    }

    async function loadProfiles() {
        try { profilesData = await Api.adminGetProfiles(); } catch { profilesData = []; }
        renderProfilesList();
    }

    function renderProfilesList() {
        const container = document.getElementById('users-list');
        if (!container) return;
        if (profilesData.length === 0) { container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет пользователей</p>'; return; }
        const modUserIds = new Set(moderatorsData.map(m => m.user_id));
        container.innerHTML = profilesData.map(p => {
            const name = p.telegram_first_name || p.telegram_last_name ? [p.telegram_first_name, p.telegram_last_name].filter(Boolean).join(' ') : (p.telegram_username || '');
            const username = p.telegram_username ? '@' + p.telegram_username : '';
            const verified = p.is_verified ? '<span class="ml-2 text-xs text-green-400/60">Верифицирован</span>' : '<span class="ml-2 text-xs text-red-400/60">Не верифицирован</span>';
            const modLabel = modUserIds.has(p.user_id) ? '<span class="admin-mod-badge ml-2">MOD</span>' : '';
            const inviteColor = p.has_generated_invite ? 'text-yellow-400/60' : 'text-green-400/60';
            return `
            <div class="admin-prompt-card flex justify-between items-start gap-4">
                <div class="flex-1">
                    <span class="text-gray-200 font-bold">${escapeHtml(name)}</span>${username ? `<span class="text-gray-400 ml-2 text-xs">${escapeHtml(username)}</span>` : ''}${verified}${modLabel}
                    <span class="text-xs text-gray-500 block mt-1">Email: ${escapeHtml(p.email || '—')} | ID: ${p.user_id ? p.user_id.slice(0, 8) + '...' : '—'}</span>
                </div>
                <div class="flex-shrink-0 flex gap-2">
                    <button class="text-gray-400 hover:text-white transition-colors text-xs" onclick="AdminApp.resetInviteLimit('${p.user_id}')">Сбросить лимит</button>
                    <button class="text-red-400/60 hover:text-red-400 transition-colors text-xs" onclick="AdminApp.deleteUser('${p.user_id}')">Удал.</button>
                </div>
            </div>`;
        }).join('');
    }

    function renderInvitesList() {
        const container = document.getElementById('invites-list');
        if (!container) return;
        let filtered = invitesData;
        if (currentInviteFilter === 'unused') filtered = invitesData.filter(i => (i.max_uses === null || i.use_count < i.max_uses));
        else if (currentInviteFilter === 'used') filtered = invitesData.filter(i => i.max_uses !== null && i.use_count >= i.max_uses);
        else if (currentInviteFilter === 'admin') filtered = invitesData.filter(i => i.is_admin_code);
        if (filtered.length === 0) { container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет инвайт-кодов</p>'; return; }
        container.innerHTML = filtered.map(i => {
            const maxLabel = i.max_uses === null ? '∞' : i.max_uses;
            const statusText = i.max_uses === null ? (i.use_count > 0 ? 'Используется' : 'Свободен') : (i.use_count >= i.max_uses ? 'Исчерпан' : `${i.use_count}/${i.max_uses}`);
            const statusColor = (i.max_uses !== null && i.use_count >= i.max_uses) ? 'text-red-400/60' : (i.use_count > 0 ? 'text-yellow-400/60' : 'text-green-400/60');
            const createdBy = !i.is_admin_code && i.created_by ? profilesData.find(p => p.user_id === i.created_by) : null;
            const createdByLabel = i.is_admin_code ? 'Админ' : (createdBy ? (createdBy.telegram_username ? '@' + createdBy.telegram_username : (createdBy.email || '—')) : '—');
            return `
            <div class="admin-prompt-card flex justify-between items-start gap-4">
                <div class="flex-1">
                    <span class="text-gray-200 font-bold font-mono tracking-widest">${escapeHtml(i.code)}</span>
                    <span class="ml-3 text-xs ${statusColor}">${statusText}</span>
                    ${i.is_admin_code ? '<span class="ml-2 text-xs text-yellow-400/60">Админский</span>' : ''}
                    <span class="text-xs text-gray-500 block mt-1">Лимит: ${maxLabel} | Создал: ${escapeHtml(createdByLabel)}</span>
                </div>
                <div class="flex-shrink-0 flex gap-2">
                    ${(i.max_uses === null || i.use_count < i.max_uses) ? `<button class="text-red-400/60 hover:text-red-400 transition-colors text-xs" onclick="AdminApp.deleteInvite('${i.id}')">Удал.</button>` : ''}
                </div>
            </div>`;
        }).join('');
    }

    async function deleteInvite(id) {
        if (!confirm('Удалить?')) return;
        try { await Api.adminDeleteInviteCode(id); await loadInvites(); } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function resetInviteLimit(userId) {
        if (!confirm('Сбросить лимит?')) return;
        try { const r = await Api.adminResetUserInviteLimit(userId); if (!r) { alert('Не удалось'); return; } await loadProfiles(); } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function resetAllLimits() {
        const count = profilesData.filter(p => p.has_generated_invite).length;
        if (count === 0) { alert('Нет пользователей'); return; }
        if (!confirm(`Сбросить лимит для ${count} пользователей?`)) return;
        try { const r = await Api.adminResetAllInviteLimits(); if (r < 0) { alert('Нет прав'); return; } await loadProfiles(); } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function deleteUser(userId) {
        const profile = profilesData.find(p => p.user_id === userId);
        const label = profile ? (profile.telegram_username ? '@' + profile.telegram_username : (profile.email || userId.slice(0, 8))) : userId.slice(0, 8);
        if (!confirm(`Удалить ${label}?`)) return;
        try { await Api.adminDeleteUser(userId); await loadProfiles(); } catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== MODERATORS ==========

    let moderatorsData = [];

    async function loadModerators() {
        try { moderatorsData = await Api.adminGetModerators(); } catch { moderatorsData = []; }
        renderModeratorsList();
        renderModeratorCandidates();
    }

    function renderModeratorsList() {
        const container = document.getElementById('moderators-list');
        if (!container) return;
        if (moderatorsData.length === 0) {
            container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет модераторов</p>';
            return;
        }
        container.innerHTML = moderatorsData.map(m => {
            const name = profilesData.find(p => p.user_id === m.user_id);
            const displayName = name
                ? [name.telegram_first_name, name.telegram_last_name].filter(Boolean).join(' ') || name.telegram_username || '—'
                : '—';
            const tgLabel = m.telegram_username ? `@${escapeHtml(m.telegram_username)}` : `ID: ${escapeHtml(m.telegram_id || '').slice(0, 10)}...`;
            const assignedAt = m.created_at ? new Date(m.created_at).toLocaleDateString('ru') : '—';
            return `
                <div class="admin-prompt-card flex justify-between items-start gap-4">
                    <div class="flex-1">
                        <span class="text-gray-200 font-bold">${escapeHtml(displayName)}</span>
                        <span class="text-yellow-400/60 ml-2 text-xs">${tgLabel}</span>
                        <span class="text-xs text-gray-500 block mt-1">ID: ${m.user_id ? m.user_id.slice(0, 8) + '...' : '—'} | Назначен: ${assignedAt}</span>
                    </div>
                    <button class="text-red-400/60 hover:text-red-400 transition-colors text-xs" onclick="AdminApp.removeModerator('${m.user_id}')">Снять</button>
                </div>
            `;
        }).join('');
    }

    function renderModeratorCandidates() {
        const container = document.getElementById('moderator-candidates');
        if (!container) return;
        const modUserIds = new Set(moderatorsData.map(m => m.user_id));
        const candidates = profilesData.filter(p =>
            p.is_verified && !modUserIds.has(p.user_id)
        );
        if (candidates.length === 0) {
            container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет подходящих пользователей (нужен верифицированный аккаунт)</p>';
            return;
        }
        container.innerHTML = candidates.map(p => {
            const name = [p.telegram_first_name, p.telegram_last_name].filter(Boolean).join(' ') || p.telegram_username || 'Без имени';
            const tgLabel = p.telegram_username ? `@${escapeHtml(p.telegram_username)}` : '';
            return `
                <div class="admin-prompt-card flex justify-between items-center gap-4">
                    <div>
                        <span class="text-gray-200 font-bold">${escapeHtml(name)}</span>
                        ${tgLabel ? `<span class="text-gray-400 ml-2 text-xs">${tgLabel}</span>` : ''}
                    </div>
                    <button class="text-yellow-400/60 hover:text-yellow-400 transition-colors text-xs" onclick="AdminApp.assignModerator('${p.user_id}')">Назначить</button>
                </div>
            `;
        }).join('');
    }

    async function assignModerator(userId) {
        try {
            const r = await Api.adminAssignModerator(userId);
            if (!r) { alert('Не удалось назначить модератором'); return; }
            await loadModerators();
            renderProfilesList();
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function removeModerator(userId) {
        if (!confirm('Снять права модератора?')) return;
        try {
            const r = await Api.adminRemoveModerator(userId);
            if (!r) { alert('Не удалось снять'); return; }
            await loadModerators();
            renderProfilesList();
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== PROFILES MANAGEMENT ==========

    let achievementsCatalog = [];
    let profilesSearchQuery = '';

    async function loadAchievementsCatalog() {
        try { achievementsCatalog = await Api.getAchievementsCatalog(); } catch { achievementsCatalog = []; }
    }

    const ROLE_COLORS = {
        admin: 'bg-red-500/20 text-red-300 border-red-500/40',
        stmoderator: 'bg-orange-500/20 text-orange-300 border-orange-500/40',
        moderator: 'bg-yellow-500/20 text-yellow-300 border-yellow-500/40',
        beta: 'bg-blue-500/20 text-blue-300 border-blue-500/40',
        alpha: 'bg-purple-500/20 text-purple-300 border-purple-500/40',
        member: 'bg-gray-500/20 text-gray-400 border-gray-500/40'
    };

    function renderProfilesGrid() {
        const container = document.getElementById('profiles-grid');
        if (!container) return;
        let filtered = profilesData;
        if (profilesSearchQuery) {
            const q = profilesSearchQuery.toLowerCase();
            filtered = profilesData.filter(p => {
                const name = [p.telegram_first_name, p.telegram_last_name].filter(Boolean).join(' ').toLowerCase();
                const uname = (p.telegram_username || '').toLowerCase();
                const email = (p.email || '').toLowerCase();
                return name.includes(q) || uname.includes(q) || email.includes(q) || (p.user_id || '').includes(q);
            });
        }
        if (filtered.length === 0) {
            container.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest">Нет пользователей</p>';
            return;
        }
        container.innerHTML = filtered.map(p => {
            const name = [p.telegram_first_name, p.telegram_last_name].filter(Boolean).join(' ') || p.telegram_username || 'Без имени';
            const role = p.role || 'member';
            const rc = ROLE_COLORS[role] || ROLE_COLORS.member;
            const verified = p.is_verified ? '<span class="text-green-400/60 text-[9px] ml-1">✓</span>' : '<span class="text-red-400/40 text-[9px] ml-1">✗</span>';
            return `
            <div class="admin-prompt-card flex justify-between items-start gap-4 cursor-pointer hover:border-white/40" onclick="AdminApp.openProfileDetail('${p.user_id}')">
                <div class="flex-1">
                    <span class="text-gray-200 font-bold">${escapeHtml(name)}</span>${verified}
                    <span class="ml-2 text-xs ${rc} border px-1.5 py-0.5 rounded text-[9px] uppercase tracking-wider">${escapeHtml(role)}</span>
                    ${p.telegram_username ? `<span class="text-gray-400 ml-2 text-xs">@${escapeHtml(p.telegram_username)}</span>` : ''}
                    <span class="text-xs text-gray-500 block mt-1">ID: ${p.user_id ? p.user_id.slice(0, 8) + '...' : '—'} | Рег: ${p.created_at ? new Date(p.created_at).toLocaleDateString('ru') : '—'}</span>
                </div>
                <span class="text-gray-500 text-[9px] uppercase tracking-widest">открыть →</span>
            </div>`;
        }).join('');
    }

    async function openProfileDetail(userId) {
        showModal('<div class="text-center py-8 text-gray-500 text-xs uppercase tracking-widest">Загрузка...</div>');
        let detail;
        try { detail = await Api.adminGetUserDetail(userId); } catch (err) { showModal('<p class="text-red-400 text-xs">Ошибка: ' + escapeHtml(err.message) + '</p>'); return; }
        if (!detail || !detail.ok) { showModal('<p class="text-red-400 text-xs">Профиль не найден</p>'); return; }

        const p = detail.profile;
        const stats = detail.stats;
        const achs = detail.achievements || [];
        const role = p.role || 'member';
        const allRoles = ['admin', 'stmoderator', 'moderator', 'beta', 'alpha', 'member'];
        const roleOptions = allRoles.map(r => `<option value="${r}" ${r === role ? 'selected' : ''}>${r}</option>`).join('');
        const name = [p.telegram_first_name, p.telegram_last_name].filter(Boolean).join(' ') || p.telegram_username || 'Без имени';
        const regDate = p.created_at ? new Date(p.created_at).toISOString().slice(0, 16) : '';

        const achChips = achs.length > 0 ? achs.map(a => `
            <span class="admin-ach-chip">
                ${escapeHtml(a.icon_emoji || '')} ${escapeHtml(a.title)} <span class="text-gray-500 text-[8px]">${a.points}pt</span>
                <button type="button" class="admin-ach-remove" onclick="AdminApp.revokeAch(${escapeHtml(JSON.stringify(userId || ''))}, ${escapeHtml(JSON.stringify(a.achievement_id || ''))})">×</button>
            </span>
        `).join('') : '<span class="text-gray-500 text-xs">Нет достижений</span>';

        const grantOptions = achievementsCatalog
            .filter(ac => !achs.some(ua => ua.achievement_id === ac.id))
            .map(ac => `<option value="${escapeHtml(ac.id || '')}">${escapeHtml(ac.icon_emoji || '')} ${escapeHtml(ac.title)} (${escapeHtml(ac.rarity)})</option>`)
            .join('');

        showModal(`
            <h3 class="font-title text-lg uppercase tracking-widest mb-4">${escapeHtml(name)}</h3>
            <p class="text-xs text-gray-500 mb-6">ID: ${p.user_id ? p.user_id.slice(0, 12) + '...' : '—'}</p>

            <div class="grid grid-cols-2 gap-4 mb-6">
                <div class="border border-border p-4 rounded-xl">
                    <p class="text-[9px] uppercase tracking-widest text-gray-500 mb-2">Роль</p>
                    <select id="pd-role" class="w-full bg-surface border border-border px-3 py-2 text-xs text-white outline-none focus:border-white/50 rounded-xl">${roleOptions}</select>
                    <button type="button" class="mt-2 w-full text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1.5 bg-white/5 hover:bg-white/10 transition-colors rounded-lg" onclick="AdminApp.setRole('${userId}')">Сменить роль</button>
                </div>
                <div class="border border-border p-4 rounded-xl">
                    <p class="text-[9px] uppercase tracking-widest text-gray-500 mb-2">Верификация</p>
                    <p class="text-sm mb-2 ${p.is_verified ? 'text-green-400' : 'text-red-400'}">${p.is_verified ? 'Верифицирован' : 'Не верифицирован'}</p>
                    <button type="button" class="w-full text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1.5 bg-white/5 hover:bg-white/10 transition-colors rounded-lg" onclick="AdminApp.toggleVerified('${userId}', ${!p.is_verified})">${p.is_verified ? 'Снять верификацию' : 'Верифицировать'}</button>
                </div>
            </div>

            <div class="border border-border p-4 rounded-xl mb-4">
                <p class="text-[9px] uppercase tracking-widest text-gray-500 mb-2">Дата регистрации</p>
                <div class="flex gap-2">
                    <input id="pd-created-at" type="datetime-local" value="${regDate}" class="flex-1 bg-surface border border-border px-3 py-2 text-xs text-white outline-none focus:border-white/50 rounded-xl">
                    <button type="button" class="text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1.5 bg-white/5 hover:bg-white/10 transition-colors rounded-lg" onclick="AdminApp.updateCreatedAt('${userId}')">Сохранить</button>
                </div>
            </div>

            <div class="border border-border p-4 rounded-xl mb-4">
                <p class="text-[9px] uppercase tracking-widest text-gray-500 mb-2">Статистика</p>
                <div class="grid grid-cols-3 gap-2 text-center text-xs">
                    <div><span class="text-white font-bold">${stats.threads_count || 0}</span><br><span class="text-gray-500">Тредов</span></div>
                    <div><span class="text-white font-bold">${stats.posts_count || 0}</span><br><span class="text-gray-500">Постов</span></div>
                    <div><span class="text-white font-bold">${stats.reactions_given || 0}</span><br><span class="text-gray-500">Реакций дано</span></div>
                    <div><span class="text-white font-bold">${stats.reactions_received || 0}</span><br><span class="text-gray-500">Реакций получено</span></div>
                    <div><span class="text-white font-bold">${stats.achievement_points || 0}</span><br><span class="text-gray-500">Очки ачивок</span></div>
                    <div><span class="text-white font-bold">${stats.login_streak || 0}/${stats.max_streak || 0}</span><br><span class="text-gray-500">Стрик</span></div>
                </div>
                ${stats.is_banned ? '<p class="text-red-400 text-xs mt-2 font-bold">ЗАБЛОКИРОВАН</p>' : ''}
                ${stats.is_muted ? '<p class="text-yellow-400 text-xs mt-2 font-bold">ЗАГЛУШЁН</p>' : ''}
            </div>

            <div class="border border-border p-4 rounded-xl mb-4">
                <p class="text-[9px] uppercase tracking-widest text-gray-500 mb-2">Достижения (${achs.length})</p>
                <div class="flex flex-wrap gap-1.5 mb-3">${achChips}</div>
                ${grantOptions ? `
                <div class="flex gap-2 mt-2">
                    <select id="pd-grant-ach" class="flex-1 bg-surface border border-border px-3 py-2 text-xs text-white outline-none focus:border-white/50 rounded-xl">
                        <option value="">— Выдать достижение —</option>
                        ${grantOptions}
                    </select>
                    <button type="button" class="text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1.5 bg-white/5 hover:bg-white/10 transition-colors rounded-lg" onclick="AdminApp.grantAch('${userId}')">Выдать</button>
                </div>` : '<p class="text-xs text-gray-500 mt-2">Все достижения уже выданы</p>'}
            </div>

            <div class="border border-border p-4 rounded-xl mb-4">
                <p class="text-[9px] uppercase tracking-widest text-gray-500 mb-2">Инвайты</p>
                <p class="text-xs text-gray-400 mb-2">Код: ${escapeHtml(p.generated_code || '—')} | Использований: ${p.invite_use_count || 0} | Лимит: ${p.invite_max || 1}</p>
                <div class="flex gap-2">
                    <button type="button" class="text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1.5 bg-white/5 hover:bg-white/10 transition-colors rounded-lg" onclick="AdminApp.grantInvite('${userId}', 1)">Выдать инвайт (1)</button>
                    <button type="button" class="text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1.5 bg-white/5 hover:bg-white/10 transition-colors rounded-lg" onclick="AdminApp.grantInvite('${userId}', 5)">Выдать инвайт (5)</button>
                    <button type="button" class="text-[10px] uppercase tracking-widest border border-white/15 px-3 py-1.5 bg-white/5 hover:bg-white/10 transition-colors rounded-lg" onclick="AdminApp.resetInviteLimit('${userId}')">Сбросить лимит</button>
                </div>
            </div>

            <div class="flex gap-3 mt-2">
                <button type="button" onclick="AdminApp.openProfileDetail('${userId}')" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Обновить</button>
                <button type="button" onclick="AdminApp.closeModal()" class="flex-1 border border-border py-3 text-xs uppercase tracking-widest hover:bg-white/10 transition-colors">Закрыть</button>
            </div>
        `);
    }

    async function setRole(userId) {
        const role = document.getElementById('pd-role').value;
        if (!role) return;
        try {
            const r = await Api.adminSetUserRole(userId, role);
            if (!r) { alert('Не удалось сменить роль'); return; }
            await loadProfiles();
            await loadModerators();
            await openProfileDetail(userId);
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function toggleVerified(userId, newVal) {
        try {
            const r = await Api.adminUpdateUserProfile(userId, { is_verified: newVal });
            if (!r || !r.ok) { alert('Не удалось'); return; }
            await loadProfiles();
            await openProfileDetail(userId);
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function updateCreatedAt(userId) {
        const val = document.getElementById('pd-created-at').value;
        if (!val) { alert('Укажите дату'); return; }
        try {
            const r = await Api.adminUpdateUserProfile(userId, { created_at: new Date(val).toISOString() });
            if (!r || !r.ok) { alert('Не удалось'); return; }
            await loadProfiles();
            await openProfileDetail(userId);
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function grantAch(userId) {
        const sel = document.getElementById('pd-grant-ach');
        if (!sel || !sel.value) { alert('Выберите достижение'); return; }
        try {
            const r = await Api.adminGrantAchievement(userId, sel.value);
            if (!r || !r.ok) { alert('Не удалось: ' + (r.reason || '')); return; }
            await openProfileDetail(userId);
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function revokeAch(userId, achId) {
        if (!confirm('Забрать достижение?')) return;
        try {
            const r = await Api.adminRevokeAchievement(userId, achId);
            if (!r || !r.ok) { alert('Не удалось'); return; }
            await openProfileDetail(userId);
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    async function grantInvite(userId, maxUses) {
        try {
            const r = await Api.adminGenerateInviteForUser(userId, maxUses);
            if (!r || !r.ok) { alert('Не удалось'); return; }
            alert('Инвайт выдан: ' + (r.code || ''));
            await loadProfiles();
            await loadInvites();
            await openProfileDetail(userId);
        } catch (err) { alert('Ошибка: ' + err.message); }
    }

    // ========== STATS ==========

    async function loadStats() {
        let stats; try { stats = await Api.getStats(); } catch { stats = null; }
        let commitSha = '';
        try { const resp = await fetch('https://api.github.com/repos/Moonishe/NB/commits?per_page=1'); const data = await resp.json(); if (data && data[0] && data[0].sha) commitSha = data[0].sha.slice(0, 7); } catch {}

        renderStats(stats, commitSha);
    }

    function renderStats(stats, commitSha) {
        const grid = document.getElementById('stats-grid');
        if (!stats) { grid.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest col-span-4">Не удалось загрузить</p>'; return; }
        const cards = [
            { label: 'Онлайн сейчас', value: stats.onlineNow, color: 'text-green-400' },
            { label: 'Просмотры сегодня', value: stats.viewsToday, color: 'text-blue-400' },
            { label: 'Всего просмотров', value: stats.totalViews, color: 'text-white' },
            { label: 'Уникальных за 30д', value: stats.monthlyUnique, color: 'text-purple-400' },
            { label: 'Коммит', value: commitSha || '—', color: 'text-yellow-400' }
        ];
        grid.innerHTML = cards.map(c => `<div class="admin-prompt-card text-center py-6"><p class="text-[10px] text-gray-500 uppercase tracking-widest mb-2">${c.label}</p><p class="font-title text-3xl font-bold ${c.color}">${c.value}</p></div>`).join('');

        const chart = document.getElementById('stats-chart');
        const daily = stats.daily || [];
        if (daily.length === 0) { chart.innerHTML = '<p class="text-gray-500 text-xs uppercase tracking-widest w-full text-center self-center">Нет данных</p>'; return; }
        const maxCount = Math.max(...daily.map(d => d.count), 1);
        chart.innerHTML = daily.map(d => {
            const pct = (d.count / maxCount) * 100; const label = d.date.slice(5);
            return `<div class="flex flex-col items-center flex-1 min-w-0" title="${d.date}: ${d.count}"><div class="w-full bg-white/10 relative" style="height:${Math.max(pct, 2)}%"><span class="absolute -top-5 left-1/2 -translate-x-1/2 text-[8px] text-gray-500 whitespace-nowrap">${d.count}</span></div><span class="text-[7px] text-gray-600 mt-1 truncate w-full text-center">${label}</span></div>`;
        }).join('');
    }

    // ========== DASHBOARD ==========

    async function loadDashboard() {
        const grid = document.getElementById('dashboard-metrics');
        const events = document.getElementById('dashboard-events');
        if (!grid || !events) return;

        grid.innerHTML = '<div class="admin-metric-card"><div class="skeleton"></div></div>'.repeat(5);
        events.innerHTML = '<div class="skeleton" style="margin:4px 0"></div>'.repeat(5);

        try {
            const [profiles, threads, models, prompts, results] = await Promise.all([
                Api.adminGetProfiles().catch(() => []),
                Api.adminGetAllThreads ? Api.adminGetAllThreads().catch(() => []) : Promise.resolve([]),
                Api.getAllModels().catch(() => []),
                Api.getAllPrompts().catch(() => []),
                Api.getAllResults().catch(() => [])
            ]);

            const metrics = [
                { value: profiles.length, label: 'Пользователей' },
                { value: Array.isArray(threads) ? threads.length : 0, label: 'Тредов' },
                { value: models.length, label: 'Моделей' },
                { value: prompts.length, label: 'Промптов' },
                { value: results.length, label: 'Результатов' }
            ];

            grid.innerHTML = metrics.map(m => `
                <div class="admin-metric-card">
                    <div class="admin-metric-value">${m.value}</div>
                    <div class="admin-metric-label">${m.label}</div>
                </div>
            `).join('');

            // Recent events from profiles (latest signups)
            const recent = [...(profiles || [])].sort((a, b) => new Date(b.created_at) - new Date(a.created_at)).slice(0, 8);
            events.innerHTML = recent.map(p => {
                const name = [p.telegram_first_name, p.telegram_last_name].filter(Boolean).join(' ') || p.telegram_username || 'User';
                const date = p.created_at ? formatDateForDisplay(p.created_at.split('T')[0]) : '';
                return `<div class="flex justify-between items-center py-1 border-b border-white/5">
                    <span class="text-xs opacity-60">${escapeHtml(name)}</span>
                    <span class="text-[10px] opacity-30">зарегистрирован ${date}</span>
                </div>`;
            }).join('') || '<p class="text-xs opacity-30">Нет событий</p>';
        } catch (e) {
            grid.innerHTML = '<p class="text-xs opacity-30 col-span-5">Ошибка загрузки метрик</p>';
            events.innerHTML = '<p class="text-xs opacity-30">Ошибка</p>';
        }
    }

    // ========== LIVE LOGS ==========

    function startLiveLogs() {
        if (liveLogsInterval) return;
        const console = document.getElementById('live-logs-console');
        if (!console) return;
        console.innerHTML = '';
        addLogEntry('system', 'Подключение к логам...');

        // Poll for recent activity every 5s
        liveLogsInterval = setInterval(async () => {
            try {
                const profiles = await Api.adminGetProfiles().catch(() => []);
                if (profiles.length > 0) {
                    const latest = profiles.sort((a, b) => new Date(b.created_at) - new Date(a.created_at))[0];
                    const name = [latest.telegram_first_name, latest.telegram_last_name].filter(Boolean).join(' ') || latest.telegram_username;
                    if (name) addLogEntry('auth', `${escapeHtml(name)} — новый пользователь`);
                }
            } catch {}
        }, 5000);
    }

    function stopLiveLogs() {
        if (liveLogsInterval) { clearInterval(liveLogsInterval); liveLogsInterval = null; }
    }

    function addLogEntry(type, text) {
        const console = document.getElementById('live-logs-console');
        if (!console) return;
        if (currentLogFilter !== 'all' && type !== currentLogFilter) return;
        const now = new Date();
        const time = [now.getHours(), now.getMinutes(), now.getSeconds()].map(n => String(n).padStart(2, '0')).join(':');
        const entry = document.createElement('div');
        entry.className = 'log-entry';
        entry.innerHTML = `<span class="log-time">[${time}]</span> <span class="log-type-${type}">${text}</span>`;
        console.appendChild(entry);
        console.scrollTop = console.scrollHeight;
    }

    // ========== MODERATION ==========

    async function loadModeration() {
        const list = document.getElementById('moderation-list');
        if (!list) return;
        list.innerHTML = '<div class="skeleton" style="margin:8px 0"></div>'.repeat(3);

        try {
            if (currentModFilter === 'threads') {
                const threads = Api.adminGetAllThreads ? await Api.adminGetAllThreads().catch(() => []) : [];
                if (threads.length === 0) { list.innerHTML = '<p class="text-xs opacity-30">Нет тредов</p>'; return; }
                list.innerHTML = threads.slice(0, 30).map(t => {
                    const author = t.author_nickname || t.author_username || (t.author_id ? t.author_id.substring(0,8) + '...' : 'anon');
                    return `<div class="mod-thread-card">
                        <div class="flex justify-between items-start mb-2">
                            <div>
                                <span class="opacity-70">${escapeHtml(t.title || 'Без названия')}</span>
                                <span class="text-[10px] opacity-30 ml-2">by ${escapeHtml(author)}</span>
                            </div>
                            <div class="flex gap-1">
                                ${t.is_pinned ? '<span class="text-[9px] opacity-30">📌</span>' : `<button class="mod-action-btn success" onclick="AdminApp.pinThread('${t.id}')">Pin</button>`}
                                <button class="mod-action-btn danger" onclick="AdminApp.deleteThread('${t.id}')">Del</button>
                            </div>
                        </div>
                        <p class="text-[10px] opacity-30">${t.posts_count || 0} постов · ${formatDateForDisplay((t.created_at || '').split('T')[0])}</p>
                    </div>`;
                }).join('');
            } else if (currentModFilter === 'posts') {
                list.innerHTML = '<p class="text-xs opacity-30">Загрузка постов...</p>';
            } else {
                list.innerHTML = '<p class="text-xs opacity-30">Жалобы пока не реализованы в API</p>';
            }
        } catch (e) {
            list.innerHTML = '<p class="text-xs opacity-30">Ошибка загрузки</p>';
        }
    }

    async function pinThread(id) {
        try {
            if (Api.modPinThread) await Api.modPinThread(id);
            toast('Тред закреплён', 'success');
            loadModeration();
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    async function deleteThread(id) {
        if (!confirm('Удалить тред?')) return;
        try {
            if (Api.modDeleteThread) await Api.modDeleteThread(id);
            toast('Тред удалён', 'success');
            loadModeration();
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    // ========== BAN HAMMER ==========

    async function loadBans() {
        const list = document.getElementById('bans-list');
        if (!list) return;
        try {
            const bans = Api.adminGetBans ? await Api.adminGetBans().catch(() => []) : [];
            if (bans.length === 0) {
                list.innerHTML = '<p class="text-xs opacity-30 uppercase tracking-widest">Нет забаненных 🔨</p>';
                return;
            }
            list.innerHTML = bans.map(b => {
                const name = b.telegram_username || (b.user_id ? b.user_id.substring(0,8) + '...' : 'Unknown');
                const reason = b.reason || 'Не указана';
                const expires = b.expires_at ? formatDateForDisplay(b.expires_at.split('T')[0]) : 'Навсегда';
                return `<div class="ban-card">
                    <div class="flex justify-between items-center">
                        <div>
                            <span class="opacity-70">🔨 ${escapeHtml(name)}</span>
                            <span class="text-[10px] opacity-30 ml-2">Причина: ${escapeHtml(reason)}</span>
                        </div>
                        <div class="flex items-center gap-2">
                            <span class="text-[10px] opacity-30">${expires}</span>
                            <button class="mod-action-btn success" onclick="AdminApp.unban('${b.user_id}')">Разбан</button>
                        </div>
                    </div>
                </div>`;
            }).join('');
        } catch {
            list.innerHTML = '<p class="text-xs opacity-30">Ошибка загрузки</p>';
        }
    }

    function showBanForm() {
        showModal(`
            <h2 class="font-title text-lg uppercase tracking-widest text-shiny mb-6">🔨 Забанить пользователя</h2>
            <div class="flex flex-col gap-4">
                <input id="ban-uid" placeholder="User ID" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                <input id="ban-reason" placeholder="Причина" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                <select id="ban-duration" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50 rounded-xl">
                    <option value="1h">1 час</option>
                    <option value="1d">1 день</option>
                    <option value="7d" selected>7 дней</option>
                    <option value="30d">30 дней</option>
                    <option value="forever">Навсегда</option>
                </select>
                <button onclick="AdminApp.doBan()" class="w-full bg-red-900/50 text-red-300 border border-red-800/50 py-3 text-[10px] uppercase tracking-widest font-bold rounded-full hover:bg-red-900/80 transition-colors">🔨 Забанить</button>
            </div>
        `);
    }

    async function doBan() {
        const uid = document.getElementById('ban-uid').value.trim();
        const reason = document.getElementById('ban-reason').value.trim();
        const duration = document.getElementById('ban-duration').value;
        if (!uid) { toast('Укажите User ID', 'error'); return; }
        try {
            if (Api.adminBanUser) await Api.adminBanUser(uid, reason, duration);
            toast('Пользователь забанен 🔨', 'success');
            hideModal();
            loadBans();
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    async function unban(uid) {
        if (!confirm('Разбанить пользователя?')) return;
        try {
            if (Api.modUnbanUser) await Api.modUnbanUser(uid);
            toast('Пользователь разбанен', 'success');
            loadBans();
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    // ========== ANNOUNCEMENTS ==========

    async function loadAnnouncements() {
        const list = document.getElementById('announcements-list');
        if (!list) return;
        try {
            const anns = Api.adminGetAnnouncements ? await Api.adminGetAnnouncements().catch(() => []) : [];
            if (anns.length === 0) {
                list.innerHTML = '<p class="text-xs opacity-30 uppercase tracking-widest">Нет анонсов</p>';
                return;
            }
            list.innerHTML = anns.map(a => {
                return `<div class="announcement-card">
                    <div class="flex justify-between items-center">
                        <div>
                            <span class="opacity-70">${escapeHtml(a.title || 'Без названия')}</span>
                            <span class="text-[10px] opacity-30 ml-2">${formatDateForDisplay((a.created_at || '').split('T')[0])}</span>
                        </div>
                        <div class="flex gap-1">
                            <button class="mod-action-btn" onclick="AdminApp.editAnnouncement('${a.id}')">Edit</button>
                            <button class="mod-action-btn danger" onclick="AdminApp.deleteAnnouncement('${a.id}')">Del</button>
                        </div>
                    </div>
                    <p class="text-[10px] opacity-40 mt-2">${escapeHtml((a.body || '').substring(0, 120))}</p>
                </div>`;
            }).join('');
        } catch {
            list.innerHTML = '<p class="text-xs opacity-30">Ошибка загрузки</p>';
        }
    }

    function showAnnouncementForm() {
        showModal(`
            <h2 class="font-title text-lg uppercase tracking-widest text-shiny mb-6">📢 Новый анонс</h2>
            <div class="flex flex-col gap-4">
                <input id="ann-title" placeholder="Заголовок" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                <textarea id="ann-body" placeholder="Текст анонса" rows="5" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl"></textarea>
                <button onclick="AdminApp.doAnnouncement()" class="w-full bg-white text-black py-3 text-[10px] uppercase tracking-widest font-bold rounded-full hover:scale-105 transition-transform">📢 Отправить</button>
            </div>
        `);
    }

    async function doAnnouncement() {
        const title = document.getElementById('ann-title').value.trim();
        const body = document.getElementById('ann-body').value.trim();
        if (!title) { toast('Укажите заголовок', 'error'); return; }
        try {
            if (Api.adminCreateAnnouncement) await Api.adminCreateAnnouncement(title, body);
            toast('Анонс отправлен 📢', 'success');
            hideModal();
            loadAnnouncements();
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    async function deleteAnnouncement(id) {
        if (!confirm('Удалить анонс?')) return;
        try {
            if (Api.adminDeleteAnnouncement) await Api.adminDeleteAnnouncement(id);
            toast('Анонс удалён', 'success');
            loadAnnouncements();
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    // ========== ACHIEVEMENTS ADMIN ==========

    async function loadAchievementsAdmin() {
        const list = document.getElementById('achievements-list');
        if (!list) return;
        try {
            const achs = await Api.getAchievementsCatalog ? Api.getAchievementsCatalog().catch(() => []) : (achievementsCatalogData || []);
            if (achs.length === 0) {
                list.innerHTML = '<p class="text-xs opacity-30 uppercase tracking-widest">Нет ачивок</p>';
                return;
            }
            list.innerHTML = achs.map(a => {
                const rarityClass = 'ach-rarity-' + (a.rarity || 'common');
                return `<div class="ach-admin-card">
                    <div class="flex justify-between items-center">
                        <div class="flex items-center gap-3">
                            <span class="text-lg">${a.icon_emoji || '🏆'}</span>
                            <div>
                                <span class="opacity-70">${escapeHtml(a.title || a.id)}</span>
                                <span class="${rarityClass} text-[9px] ml-2">${a.rarity || 'common'}</span>
                            </div>
                        </div>
                        <div class="flex items-center gap-2">
                            <span class="text-[10px] opacity-30">${a.points || 0} pts</span>
                            <button class="mod-action-btn" onclick="AdminApp.grantAchById('${escapeJs(a.id)}')">Выдать</button>
                        </div>
                    </div>
                    <p class="text-[10px] opacity-40 mt-1">${escapeHtml(a.description || '')}</p>
                </div>`;
            }).join('');
        } catch {
            list.innerHTML = '<p class="text-xs opacity-30">Ошибка загрузки</p>';
        }
    }

    function showAchievementForm() {
        showModal(`
            <h2 class="font-title text-lg uppercase tracking-widest text-shiny mb-6">🏆 Новая ачивка</h2>
            <div class="flex flex-col gap-4">
                <input id="ach-id" placeholder="ID (например: first_step)" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                <input id="ach-title" placeholder="Название" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                <input id="ach-description" placeholder="Описание" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                <input id="ach-emoji" placeholder="Эмодзи" value="🏆" class="w-full bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                <div class="grid grid-cols-2 gap-3">
                    <select id="ach-rarity" class="bg-surface border border-border px-4 py-3 text-sm text-white outline-none focus:border-white/50 rounded-xl">
                        <option value="common">Common</option>
                        <option value="rare">Rare</option>
                        <option value="unique">Unique</option>
                        <option value="limited">Limited</option>
                    </select>
                    <input id="ach-points" type="number" placeholder="Очки" value="10" class="bg-surface border border-border px-4 py-3 text-sm text-white placeholder-white/30 outline-none focus:border-white/50 rounded-xl">
                </div>
                <button onclick="AdminApp.doCreateAchievement()" class="w-full bg-white text-black py-3 text-[10px] uppercase tracking-widest font-bold rounded-full hover:scale-105 transition-transform">Создать</button>
            </div>
        `);
    }

    async function doCreateAchievement() {
        const id = document.getElementById('ach-id').value.trim();
        const title = document.getElementById('ach-title').value.trim();
        const description = document.getElementById('ach-description').value.trim();
        const icon_emoji = document.getElementById('ach-emoji').value.trim();
        const rarity = document.getElementById('ach-rarity').value;
        const points = parseInt(document.getElementById('ach-points').value) || 10;
        if (!id || !title) { toast('Заполните ID и название', 'error'); return; }
        try {
            if (Api.adminCreateAchievement) await Api.adminCreateAchievement({ id, title, description, icon_emoji, rarity, points });
            toast('Ачивка создана 🏆', 'success');
            hideModal();
            loadAchievementsAdmin();
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    async function grantAchById(achId) {
        const uid = prompt('Введите User ID для выдачи ачивки:');
        if (!uid) return;
        try {
            if (Api.adminGrantAchievement) await Api.adminGrantAchievement(uid, achId);
            toast('Ачивка выдана', 'success');
        } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
    }

    // ========== INIT ==========

    function init() {
        window.SUPABASE_URL = window.SUPABASE_URL || '';
        window.SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || '';

        Api.reinitAdmin();

        document.getElementById('login-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const email = document.getElementById('login-email').value;
            const password = document.getElementById('login-password').value;
            const errEl = document.getElementById('login-error');
            try {
                const result = await Api.login(email, password);
                errEl.classList.add('hidden');
                const admin = await Api.isAdmin();
                if (admin) showAdmin(result.user.email);
                else { await Api.logout(); errEl.textContent = 'Нет прав администратора'; errEl.classList.remove('hidden'); }
            } catch (err) { errEl.textContent = 'Ошибка входа: ' + err.message; errEl.classList.remove('hidden'); }
        });

        document.getElementById('logout-btn').addEventListener('click', async () => { await Api.logout(); showAuth(); });

        document.querySelectorAll('.admin-nav-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.admin-nav-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentSection = btn.getAttribute('data-section');
                document.querySelectorAll('.admin-section').forEach(s => s.classList.add('hidden'));
                document.getElementById('section-' + currentSection).classList.remove('hidden');
            });
        });

        document.querySelectorAll('.admin-difficulty-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.admin-difficulty-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentDifficulty = btn.getAttribute('data-diff');
                renderPromptsList();
            });
        });

        document.getElementById('add-model-btn').addEventListener('click', showAddModelForm);
        document.getElementById('add-prompt-btn').addEventListener('click', showAddPromptForm);
        document.getElementById('add-result-btn').addEventListener('click', showAddResultForm);

        document.getElementById('model-settings-search').addEventListener('input', (e) => {
            modelSearchQuery = e.target.value.trim();
            renderModelsList();
        });

        document.getElementById('add-invite-btn').addEventListener('click', async () => {
            const maxUses = prompt('Максимальное количество активаций (пусто = безлимит):', '10');
            if (maxUses === null) return;
            try { const code = await Api.adminGenerateInviteCode(maxUses.trim() === '' ? null : parseInt(maxUses)); if (!code) throw new Error('Нет прав'); await loadInvites(); }
            catch (err) { alert('Ошибка: ' + err.message); }
        });

        document.querySelectorAll('.invite-filter-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.invite-filter-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentInviteFilter = btn.dataset.invFilter;
                renderInvitesList();
            });
        });

        document.getElementById('modal-overlay').addEventListener('click', (e) => { if (e.target.id === 'modal-overlay') hideModal(); });

        const profilesSearch = document.getElementById('profiles-search');
        if (profilesSearch) profilesSearch.addEventListener('input', (e) => { profilesSearchQuery = e.target.value.trim(); renderProfilesGrid(); });

        document.getElementById('results-prompt-filter').addEventListener('change', (e) => { currentResultPromptFilter = e.target.value; renderResultsList(); });
        document.getElementById('results-model-filter').addEventListener('change', (e) => { currentResultModelFilter = e.target.value; renderResultsList(); });

        document.getElementById('reset-all-limits-btn').addEventListener('click', async () => { await AdminApp.resetAllLimits(); });

        // New section: Ban hammer
        const addBanBtn = document.getElementById('add-ban-btn');
        if (addBanBtn) addBanBtn.addEventListener('click', showBanForm);

        // New section: Announcements
        const addAnnBtn = document.getElementById('add-announcement-btn');
        if (addAnnBtn) addAnnBtn.addEventListener('click', showAnnouncementForm);

        // New section: Achievements
        const addAchBtn = document.getElementById('add-achievement-btn');
        if (addAchBtn) addAchBtn.addEventListener('click', showAchievementForm);

        // Live logs filters
        document.querySelectorAll('.admin-log-filter').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.admin-log-filter').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentLogFilter = btn.dataset.logFilter;
            });
        });

        // Moderation filters
        document.querySelectorAll('.admin-mod-filter').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.admin-mod-filter').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentModFilter = btn.dataset.modFilter;
                loadModeration();
            });
        });

        // Start/stop live logs when switching sections
        document.querySelectorAll('.admin-nav-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const sec = btn.getAttribute('data-section');
                if (sec === 'live-logs') startLiveLogs();
                else stopLiveLogs();
                if (sec === 'moderation') loadModeration();
            });
        });

        checkAuth();
    }

    return {
        init, editModel, deleteModel, editPrompt, deletePrompt,
        closeModal: hideModal, deleteInvite, resetInviteLimit, resetAllLimits, deleteUser,
        manageModelSpaces, deleteModelSpaceItem,
        manageModelParams, addParamValue, deleteParamValue, deleteParam,
        showAddResultForm, editResult, deleteResult,
        assignModerator, removeModerator,
        openProfileDetail, setRole, toggleVerified, updateCreatedAt,
        grantAch, revokeAch, grantInvite,
        switchSection, openAddPrompt: showAddPromptForm, openAddInvite: () => document.getElementById('add-invite-btn')?.click(),
        pinThread, deleteThread, unban, doBan,
        doAnnouncement, deleteAnnouncement, editAnnouncement: () => toast('Редактирование в разработке'),
        doCreateAchievement, grantAchById
    };
})();

document.addEventListener('DOMContentLoaded', AdminApp.init);
