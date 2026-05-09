const Api = (() => {
    let sb = null;

    function getClient() {
        if (sb) return sb;
        const url = window.SUPABASE_URL || '';
        const key = window.SUPABASE_ANON_KEY || '';
        if (typeof supabase === 'undefined' || !url || !key) return null;
        sb = supabase.createClient(url, key, {
            auth: {
                storageKey: 'neurobench-auth',
                storage: window.sessionStorage,
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: false
            }
        });
        return sb;
    }

    function reinit() {
        sb = null;
        getClient();
    }

    function reinitAdmin() {
        sb = null;
        const url = window.SUPABASE_URL || '';
        const key = window.SUPABASE_ANON_KEY || '';
        if (typeof supabase === 'undefined' || !url || !key) return;
        sb = supabase.createClient(url, key, {
            auth: {
                storageKey: 'neurobench-admin-auth',
                storage: window.sessionStorage,
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: false
            }
        });
    }

    function isLocalhost() {
        return ['localhost', '127.0.0.1', '::1'].includes(window.location.hostname);
    }

    function getSupabaseProjectRef() {
        const url = window.SUPABASE_URL || '';
        if (!url) return null;
        try {
            return new URL(url).hostname.split('.')[0] || null;
        } catch (_) {
            return null;
        }
    }

    function getSupabaseAuthStorageKey() {
        const projectRef = getSupabaseProjectRef();
        return projectRef ? `sb-${projectRef}-auth-token` : null;
    }

    function hasStoredSupabaseSession() {
        if (sessionStorage.getItem('neurobench-auth')) return true;
        if (sessionStorage.getItem('neurobench-admin-auth')) return true;
        return false;
    }

    function clearStoredAuthSessions() {
        const storageKey = getSupabaseAuthStorageKey();
        sessionStorage.removeItem('neurobench-auth');
        sessionStorage.removeItem('neurobench-admin-auth');
        localStorage.removeItem('neurobench-admin-auth');
        if (storageKey) localStorage.removeItem(storageKey);
    }

    function normalizeAdminWriteRows(data) {
        if (Array.isArray(data)) return data;
        if (data == null) return [];
        return [data];
    }

    async function callAdminWriteRpc(rpcName, params) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc(rpcName, params);
        if (error) throw error;
        return data;
    }

    async function callAdminWriteRpcExpectRows(rpcName, params) {
        const data = await callAdminWriteRpc(rpcName, params);
        return normalizeAdminWriteRows(data);
    }

    function normalizeModelSpaceUrl(url) {
        if (url === undefined) return undefined;
        if (url === null) return null;
        if (typeof url !== 'string') throw new Error('Model space URL must start with https:// or be empty');
        const trimmedUrl = url.trim();
        if (!trimmedUrl) return null;
        let parsedUrl;
        try {
            parsedUrl = new URL(trimmedUrl);
        } catch (_) {
            throw new Error('Model space URL must start with https:// or be empty');
        }
        if (parsedUrl.protocol !== 'https:') {
            throw new Error('Model space URL must start with https:// or be empty');
        }
        return parsedUrl.toString();
    }

    function normalizeModelSpacePayload(space) {
        if (!space || typeof space !== 'object') return space;
        const normalizedSpace = { ...space };
        if (Object.prototype.hasOwnProperty.call(normalizedSpace, 'url')) {
            normalizedSpace.url = normalizeModelSpaceUrl(normalizedSpace.url);
        }
        return normalizedSpace;
    }

    // ========== PROMPTS ==========

    async function getPromptsByDifficulty(difficulty) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('prompts').select('*').eq('difficulty', difficulty).order('id');
        if (error) throw error;
        return data;
    }

    async function getAllPrompts() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('prompts').select('*').order('id');
        if (error) throw error;
        return data;
    }

    async function addPrompt(prompt) {
        return callAdminWriteRpcExpectRows('admin_add_prompt', { p_prompt: prompt });
    }

    async function updatePrompt(id, prompt) {
        return callAdminWriteRpcExpectRows('admin_update_prompt', { p_id: id, p_prompt: prompt });
    }

    async function deletePrompt(id) {
        await callAdminWriteRpc('admin_delete_prompt', { p_id: id });
    }

    // ========== MODELS (global catalog) ==========

    async function getAllModels() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('models').select('*').order('name');
        if (error) throw error;
        return data;
    }

    async function addModel(model) {
        return callAdminWriteRpcExpectRows('admin_add_model', { p_model: model });
    }

    async function updateModel(id, model) {
        return callAdminWriteRpcExpectRows('admin_update_model', { p_id: id, p_model: model });
    }

    async function deleteModel(id) {
        await callAdminWriteRpc('admin_delete_model', { p_id: id });
    }

    // ========== MODEL SPACES (per model, macro) ==========

    async function getModelSpaces(modelId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('model_spaces').select('*').eq('model_id', modelId).order('id');
        if (error) throw error;
        return data;
    }

    async function getAllModelSpaces() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('model_spaces').select('*, models(id, name)').order('model_id').order('id');
        if (error) throw error;
        return data;
    }

    async function addModelSpace(space) {
        const normalizedSpace = normalizeModelSpacePayload(space);
        return callAdminWriteRpcExpectRows('admin_add_model_space', { p_space: normalizedSpace });
    }

    async function updateModelSpace(id, space) {
        const normalizedSpace = normalizeModelSpacePayload(space);
        return callAdminWriteRpcExpectRows('admin_update_model_space', { p_id: id, p_space: normalizedSpace });
    }

    async function deleteModelSpace(id) {
        await callAdminWriteRpc('admin_delete_model_space', { p_id: id });
    }

    // ========== MODEL PARAMS (per model, micro definitions) ==========

    async function getModelParams(modelId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('model_params').select('*, model_param_values(id, value)').eq('model_id', modelId).order('id');
        if (error) throw error;
        return data;
    }

    async function getAllModelParams() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('model_params').select('*, models(id, name), model_param_values(id, value)').order('model_id').order('id');
        if (error) throw error;
        return data;
    }

    async function addModelParam(param) {
        return callAdminWriteRpcExpectRows('admin_add_model_param', { p_param: param });
    }

    async function updateModelParam(id, param) {
        return callAdminWriteRpcExpectRows('admin_update_model_param', { p_id: id, p_param: param });
    }

    async function deleteModelParam(id) {
        await callAdminWriteRpc('admin_delete_model_param', { p_id: id });
    }

    // ========== MODEL PARAM VALUES ==========

    async function addModelParamValue(paramValue) {
        return callAdminWriteRpcExpectRows('admin_add_model_param_value', { p_param_value: paramValue });
    }

    async function updateModelParamValue(id, paramValue) {
        return callAdminWriteRpcExpectRows('admin_update_model_param_value', { p_id: id, p_param_value: paramValue });
    }

    async function deleteModelParamValue(id) {
        await callAdminWriteRpc('admin_delete_model_param_value', { p_id: id });
    }

    // ========== RESULTS ==========

    async function getResultsByPrompt(promptId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('results')
            .select('*, models(id, name), model_spaces(id, name, url), prompts(id, difficulty, text, name), result_param_values(id, param_value_id, model_param_values(id, value, param_id, model_params(id, name, model_id)))')
            .eq('prompt_id', promptId)
            .order('overall', { ascending: false });
        if (error) throw error;
        return data;
    }

    async function getAllResults() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('results')
            .select('*, models(id, name), model_spaces(id, name, url), prompts(id, difficulty, text, name), result_param_values(id, param_value_id, model_param_values(id, value, param_id, model_params(id, name, model_id)))')
            .order('prompt_id')
            .order('overall', { ascending: false });
        if (error) throw error;
        return data;
    }

    async function addResult(result) {
        return callAdminWriteRpcExpectRows('admin_add_result', { p_result: result });
    }

    async function updateResult(id, result) {
        return callAdminWriteRpcExpectRows('admin_update_result', { p_id: id, p_result: result });
    }

    async function deleteResult(id) {
        await callAdminWriteRpc('admin_delete_result', { p_id: id });
    }

    // ========== RESULT PARAM VALUES (junction) ==========

    async function setResultParamValues(resultId, paramValueIds) {
        await callAdminWriteRpc('admin_set_result_param_values', {
            p_result_id: resultId,
            p_param_value_ids: Array.isArray(paramValueIds) ? paramValueIds : []
        });
    }

    async function getResultParamValues(resultId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.from('result_param_values')
            .select('*, model_param_values(id, value, param_id, model_params(id, name))')
            .eq('result_id', resultId);
        if (error) throw error;
        return data;
    }

    async function getResultRatingStats(resultIds) {
        const client = getClient();
        if (!client || !Array.isArray(resultIds) || resultIds.length === 0) return [];
        const ids = [...new Set(resultIds.map(id => parseInt(id)).filter(Boolean))];
        if (ids.length === 0) return [];
        const { data, error } = await client.rpc('get_result_rating_stats', { p_result_ids: ids });
        if (error) return [];
        return data || [];
    }

    async function getResultRatingEntries(resultIds, limitPerResult) {
        const client = getClient();
        if (!client || !Array.isArray(resultIds) || resultIds.length === 0) return [];
        const ids = [...new Set(resultIds.map(id => parseInt(id)).filter(Boolean))];
        if (ids.length === 0) return [];
        const { data, error } = await client.rpc('get_result_rating_entries', {
            p_result_ids: ids,
            p_limit_per_result: limitPerResult || 8
        });
        if (error) return [];
        return data || [];
    }

    function getUserId() {
        if (!isLocalhost()) return null;
        const devRaw = localStorage.getItem('nb_dev_session');
        if (devRaw) {
            try {
                const dev = JSON.parse(devRaw);
                if (dev && dev.user_id) return dev.user_id;
            } catch (_) {}
        }
        return null;
    }

    function isDevSession() {
        return !!getUserId() && !hasStoredSupabaseSession();
    }
    async function rateResult(resultId, scores) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');

        if (isDevSession()) {
            const devKey = 'nb_dev_ratings';
            const stored = JSON.parse(localStorage.getItem(devKey) || '{}');
            const prev = stored[resultId];
            const updateCount = prev ? Number(prev.update_count || 0) : 0;
            if (prev && updateCount >= 2) {
                throw new Error('Rating update limit reached');
            }
            const nextUpdateCount = prev ? updateCount + 1 : 0;
            const numericScores = {
                s_visual: parseFloat(scores.s_visual),
                s_animation: parseFloat(scores.s_animation),
                s_creative: parseFloat(scores.s_creative),
                s_code: parseFloat(scores.s_code),
                s_detail: parseFloat(scores.s_detail)
            };
            const myScore = Math.round((numericScores.s_visual + numericScores.s_animation + numericScores.s_creative + numericScores.s_code + numericScores.s_detail) * 18) / 10;
            stored[resultId] = {
                result_id: parseInt(resultId),
                ...numericScores,
                update_count: nextUpdateCount,
                created_at: prev?.created_at || Date.now(),
                ts: Date.now()
            };
            localStorage.setItem(devKey, JSON.stringify(stored));
            return [{
                result_id: parseInt(resultId),
                avg_score: null,
                rating_count: 0,
                my_score: myScore,
                my_s_visual: numericScores.s_visual,
                my_s_animation: numericScores.s_animation,
                my_s_creative: numericScores.s_creative,
                my_s_code: numericScores.s_code,
                my_s_detail: numericScores.s_detail,
                my_update_count: nextUpdateCount
            }];
        }

        const { data, error } = await client.rpc('rate_result', {
            p_result_id: parseInt(resultId),
            p_s_visual: parseFloat(scores.s_visual),
            p_s_animation: parseFloat(scores.s_animation),
            p_s_creative: parseFloat(scores.s_creative),
            p_s_code: parseFloat(scores.s_code),
            p_s_detail: parseFloat(scores.s_detail)
        });
        if (error) throw error;
        return data;
    }

    // ========== AUTH ==========

    async function login(email, password) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.auth.signInWithPassword({ email, password });
        if (error) throw error;
        return data;
    }

    async function logout() {
        const client = getClient();
        if (client) await client.auth.signOut();
        clearStoredAuthSessions();
    }

    async function getSession() {
        const client = getClient();
        if (!client) return null;
        const { data } = await client.auth.getSession();
        return data.session;
    }

    async function isAdmin() {
        const session = await getSession();
        if (!session) return false;
        const client = getClient();
        if (!client) return false;
        const { data } = await client.from('admin_users').select('id').eq('user_id', session.user.id).single();
        return !!data;
    }

    async function telegramAuth(authData, inviteCode) {
        const supabaseUrl = window.SUPABASE_URL;
        const anonKey = window.SUPABASE_ANON_KEY;
        if (!supabaseUrl || !anonKey) throw new Error('Supabase not configured');

        const body = { auth_data: authData };
        if (inviteCode) body.invite_code = inviteCode;

        let response;
        try {
            response = await fetch(`${supabaseUrl}/functions/v1/telegram-auth`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'apikey': anonKey,
                    'Authorization': `Bearer ${anonKey}`,
                },
                body: JSON.stringify(body)
            });
        } catch (e) {
            throw new Error('Не удалось подключиться к серверу аутентификации. Проверьте что Edge Function telegram-auth задеплоена в Supabase Dashboard.');
        }

        let result;
        try {
            result = await response.json();
        } catch (e) {
            throw new Error(`Сервер вернул некорректный ответ (HTTP ${response.status})`);
        }

        if (!response.ok) {
            const err = new Error(result.error || 'Authentication failed');
            err.needsInvite = result.needs_invite || false;
            throw err;
        }

        return result;
    }

    async function setSession(accessToken, refreshToken) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.auth.setSession({ access_token: accessToken, refresh_token: refreshToken });
        if (error) throw error;
        return data;
    }

    // ========== STATS ==========

    async function trackPageView(visitorHash, page, referrer) {
        const client = getClient();
        if (!client) return;
        await client.rpc('log_page_view', { p_visitor_hash: visitorHash, p_page: page, p_referrer: referrer });
    }

    async function getStats() {
        const client = getClient();
        if (!client) return null;
        const now = new Date();
        const fiveMinAgo = new Date(now.getTime() - 5 * 60 * 1000).toISOString();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
        const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

        const [online, today, total, daily, monthlyUnique] = await Promise.all([
            client.from('page_views').select('visitor_hash', { count: 'exact', head: false }).gte('created_at', fiveMinAgo),
            client.from('page_views').select('id', { count: 'exact', head: true }).gte('created_at', todayStart),
            client.from('page_views').select('id', { count: 'exact', head: true }),
            client.from('page_views').select('created_at').gte('created_at', thirtyDaysAgo).order('created_at'),
            client.from('page_views').select('visitor_hash').gte('created_at', thirtyDaysAgo)
        ]);

        const onlineUnique = new Set((online.data || []).map(r => r.visitor_hash)).size;

        const dailyMap = {};
        (daily.data || []).forEach(r => {
            const day = r.created_at.slice(0, 10);
            dailyMap[day] = (dailyMap[day] || 0) + 1;
        });
        const dailyList = Object.entries(dailyMap).map(([date, count]) => ({ date, count })).sort((a, b) => a.date.localeCompare(b.date));

        const monthlyUniqueCount = new Set((monthlyUnique.data || []).map(r => r.visitor_hash)).size;

        return {
            onlineNow: onlineUnique,
            viewsToday: today.count || 0,
            totalViews: total.count || 0,
            monthlyUnique: monthlyUniqueCount,
            daily: dailyList
        };
    }

    // ========== INVITES (RPC) ==========

    async function claimInviteCode(code) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('claim_invite_code', { p_code: code || null });
        if (error) throw error;
        return data;
    }

    async function generateInviteCode() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('generate_user_invite_code');
        if (error) throw error;
        return data;
    }

    async function getUserInviteStatus() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('get_user_invite_status');
        if (error) throw error;
        return data && data[0] ? data[0] : null;
    }

    async function getUserDisplayName() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('get_user_display_name');
        if (error) throw error;
        return data && data[0] ? data[0] : null;
    }

    async function adminGetInviteCodes() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_get_invite_codes');
        if (error) throw error;
        return data || [];
    }

    async function adminGenerateInviteCode(maxUses, ttlSeconds) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const params = { p_max_uses: maxUses || null };
        if (ttlSeconds) params.p_ttl_seconds = ttlSeconds;
        let { data, error } = await client.rpc('admin_generate_invite_code', params);
        if (error && ttlSeconds && /p_ttl_seconds|schema cache|function/i.test(error.message || '')) {
            const fallbackParams = { p_max_uses: maxUses || null, p_ttl_minutes: Math.ceil(ttlSeconds / 60) };
            ({ data, error } = await client.rpc('admin_generate_invite_code', fallbackParams));
        }
        if (error) throw error;
        return data;
    }

    async function adminDeleteInviteCode(id) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_delete_invite_code', { p_id: id });
        if (error) throw error;
        return data;
    }

    async function adminGetProfiles() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_get_profiles');
        if (error) throw error;
        return data || [];
    }

    async function adminResetUserInviteLimit(userId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_reset_user_invite_limit', { p_user_id: userId });
        if (error) throw error;
        return data;
    }

    async function adminResetAllInviteLimits() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_reset_all_invite_limits');
        if (error) throw error;
        return data;
    }

    async function adminSetUserRole(userId, role) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_set_user_role', { p_user_id: userId, p_role: role });
        if (error) throw error;
        return data;
    }

    async function adminGrantAchievement(userId, achievementId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_grant_achievement', { p_user_id: userId, p_achievement_id: achievementId });
        if (error) throw error;
        return data;
    }

    async function adminRevokeAchievement(userId, achievementId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_revoke_achievement', { p_user_id: userId, p_achievement_id: achievementId });
        if (error) throw error;
        return data;
    }

    async function adminUpdateUserProfile(userId, fields) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const params = { p_user_id: userId };
        if (fields.is_verified !== undefined) params.p_is_verified = fields.is_verified;
        if (fields.created_at !== undefined) params.p_created_at = fields.created_at;
        if (fields.bio !== undefined) params.p_bio = fields.bio;
        if (fields.telegram_first_name !== undefined) params.p_telegram_first_name = fields.telegram_first_name;
        if (fields.telegram_last_name !== undefined) params.p_telegram_last_name = fields.telegram_last_name;
        if (fields.telegram_username !== undefined) params.p_telegram_username = fields.telegram_username;
        if (fields.telegram_photo_url !== undefined) params.p_telegram_photo_url = fields.telegram_photo_url;
        const { data, error } = await client.rpc('admin_update_user_profile', params);
        if (error) throw error;
        return data;
    }

    async function adminGenerateInviteForUser(userId, maxUses) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_generate_invite_for_user', { p_user_id: userId, p_max_uses: maxUses || 1 });
        if (error) throw error;
        return data;
    }

    async function adminGetUserDetail(userId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_get_user_detail', { p_user_id: userId });
        if (error) throw error;
        return data;
    }

    async function adminDeleteUser(userId) {
        const supabaseUrl = window.SUPABASE_URL;
        const anonKey = window.SUPABASE_ANON_KEY;
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data: { session } } = await client.auth.getSession();
        if (!session) throw new Error('Not authenticated');

        let result;
        try {
            const response = await fetch(`${supabaseUrl}/functions/v1/admin-action`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'apikey': anonKey,
                    'Authorization': `Bearer ${session.access_token}`,
                },
                body: JSON.stringify({ action: 'delete_user', user_id: userId })
            });
            result = await response.json();
            if (!response.ok) throw new Error(result.error || 'Delete failed');
        } catch (e) {
            if (e.message && !e.message.includes('подключиться')) throw e;
            throw new Error('Не удалось подключиться к серверу. Проверьте что Edge Function admin-action задеплоена в Supabase Dashboard.');
        }
        return result;
    }

    // ========== FORUM ==========

    async function getForumCategories() {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.from('forum_categories').select('*').order('sort_order');
        if (error) throw error;
        return data || [];
    }

    async function getForumThreads(categoryId, limit, offset) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('get_forum_threads', {
            p_category_id: categoryId || null,
            p_limit: limit || 20,
            p_offset: offset || 0
        });
        if (error) throw error;
        return data || [];
    }

    async function getForumThreadsCount(categoryId) {
        const client = getClient();
        if (!client) return 0;
        const { data, error } = await client.rpc('get_forum_threads_count', {
            p_category_id: categoryId || null
        });
        if (error) throw error;
        return data || 0;
    }

    async function getForumThreadPosts(threadId, limit, offset) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('get_forum_thread_posts', {
            p_thread_id: threadId,
            p_limit: limit || 25,
            p_offset: offset || 0
        });
        if (error) throw error;
        return data || [];
    }

    async function getForumThreadPostsCount(threadId) {
        const client = getClient();
        if (!client) return 0;
        const { data, error } = await client.rpc('get_forum_thread_posts_count', {
            p_thread_id: threadId
        });
        if (error) throw error;
        return data || 0;
    }

    async function getForumThread(threadId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client
            .from('forum_threads')
            .select('*')
            .eq('id', threadId)
            .single();
        if (error) throw error;
        return data;
    }

    async function createForumThread(categoryId, title, content) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('create_forum_thread', {
            p_category_id: categoryId,
            p_title: title,
            p_content: content
        });
        if (error) throw error;
        return data;
    }

    async function createForumPost(threadId, content) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('create_forum_post', {
            p_thread_id: threadId,
            p_content: content
        });
        if (error) throw error;
        return data;
    }

    async function updateForumPost(postId, content) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('update_forum_post', {
            p_post_id: postId,
            p_content: content
        });
        if (error) throw error;
        return data;
    }

    async function updateForumThread(threadId, title, content) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('update_forum_thread', {
            p_thread_id: threadId,
            p_title: title,
            p_content: content
        });
        if (error) throw error;
        return data;
    }

    // ========== MODERATION ==========

    async function isModeratorCheck() {
        const client = getClient();
        if (!client) return false;
        const { data, error } = await client.rpc('is_moderator');
        if (error) return false;
        return !!data;
    }

    async function modPinThread(threadId, pin) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_pin_thread', {
            p_thread_id: threadId, p_pin: pin
        });
        if (error) throw error;
        return data;
    }

    async function modLockThread(threadId, lock) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_lock_thread', {
            p_thread_id: threadId, p_lock: lock
        });
        if (error) throw error;
        return data;
    }

    async function modDeleteThread(threadId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_delete_thread', {
            p_thread_id: threadId
        });
        if (error) throw error;
        return data;
    }

    async function modDeletePost(postId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_delete_post', {
            p_post_id: postId
        });
        if (error) throw error;
        return data;
    }

    async function modBanUser(userId, reason, expiresAt) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_ban_user', {
            p_user_id: userId, p_reason: reason || null, p_expires_at: expiresAt || null
        });
        if (error) throw error;
        return data;
    }

    async function modMuteUser(userId, reason, expiresAt) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_mute_user', {
            p_user_id: userId, p_reason: reason || null, p_expires_at: expiresAt || null
        });
        if (error) throw error;
        return data;
    }

    async function modUnbanUser(userId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_unban_user', { p_user_id: userId });
        if (error) throw error;
        return data;
    }

    async function modUnmuteUser(userId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('mod_unmute_user', { p_user_id: userId });
        if (error) throw error;
        return data;
    }

    async function getUserModActions(userId) {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('get_user_mod_actions', { p_user_id: userId });
        if (error) throw error;
        return data || [];
    }

    // ========== PROFILE ==========

    async function getPublicProfile(userId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('get_public_profile', { p_user_id: userId });
        if (error) throw error;
        return data && data[0] ? data[0] : null;
    }

    async function updateProfileBio(bio) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('update_profile_bio', { p_bio: bio || '' });
        if (error) throw error;
        return data;
    }

    // ========== ADMIN MODERATOR ==========

    async function adminAssignModerator(userId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_assign_moderator', { p_user_id: userId });
        if (error) throw error;
        return data;
    }

    async function adminRemoveModerator(userId) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_remove_moderator', { p_user_id: userId });
        if (error) throw error;
        return data;
    }

    async function adminGetModerators() {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_get_moderators');
        if (error) throw error;
        return data || [];
    }

    // ========== REACTIONS ==========

    async function togglePostReaction(postId, emoji) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('toggle_post_reaction', {
            p_post_id: postId, p_emoji: emoji
        });
        if (error) throw error;
        return data;
    }

    // ========== NOTIFICATIONS ==========

    async function getMyNotifications(limit) {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('get_my_notifications', {
            p_limit: limit || 20
        });
        if (error) throw error;
        return data || [];
    }

    async function getUnreadCount() {
        const client = getClient();
        if (!client) return 0;
        const { data, error } = await client.rpc('get_unread_count');
        if (error) return 0;
        return data || 0;
    }

    async function markNotificationsRead() {
        const client = getClient();
        if (!client) return 0;
        const { data, error } = await client.rpc('mark_notifications_read');
        if (error) throw error;
        return data || 0;
    }

    // ========== @MENTIONS ==========

    async function resolveUsernames(usernames) {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('resolve_usernames', {
            p_usernames: usernames
        });
        if (error) return [];
        return data || [];
    }

    async function createMentionNotifications(postId, threadId, mentionedUserIds) {
        const client = getClient();
        if (!client) return 0;
        const { data, error } = await client.rpc('create_mention_notifications', {
            p_post_id: postId,
            p_thread_id: threadId,
            p_mentioned_user_ids: mentionedUserIds
        });
        if (error) return 0;
        return data || 0;
    }

    // ========== PROFILE ACTIVITY ==========

    async function getUserRecentActivity(userId, limit, offset) {
        const client = getClient();
        if (!client) return [];
        const params = {
            p_user_id: userId,
            p_limit: limit || 10
        };
        if (offset && offset > 0) params.p_offset = offset;
        const { data, error } = await client.rpc('get_user_recent_activity', params);
        if (error) return [];
        return data || [];
    }

    async function getUserThreads(userId, limit, offset) {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('get_user_threads', {
            p_user_id: userId,
            p_limit: limit || 20,
            p_offset: offset || 0
        });
        if (error) return [];
        return data || [];
    }

    // ========== ACHIEVEMENTS ==========

    async function getAchievementsCatalog() {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('get_achievements_catalog');
        if (error) return [];
        return data || [];
    }

    async function getUserAchievements(userId) {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('get_user_achievements', { p_user_id: userId });
        if (error) return [];
        return data || [];
    }

    async function setShowcasedAchievements(achievementIds) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('set_showcased_achievements', {
            p_achievement_ids: achievementIds
        });
        if (error) throw error;
        return data;
    }

    async function checkAndGrantAchievements() {
        const client = getClient();
        if (!client) return null;
        const session = await getSession();
        if (!session) return null;
        const { data, error } = await client.rpc('check_and_grant_achievements', {
            p_user_id: session.user.id
        });
        if (error) return null;
        return data;
    }

    async function recordLogin() {
        const client = getClient();
        if (!client) return null;
        const { data, error } = await client.rpc('record_login');
        if (error) return null;
        return data;
    }

    // ========== ADMIN EXTENSIONS ==========

    async function adminGetAllThreads() {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('admin_get_all_threads').catch(() => client.from('forum_threads').select('id,title,author_id,is_pinned,is_locked,posts_count,created_at').order('created_at', { ascending: false }).limit(50));
        if (error) return [];
        return data || [];
    }

    async function adminGetBans() {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('admin_get_bans').catch(() => client.from('user_mod_actions').select('user_id,action_type,reason,created_at,expires_at,is_active').eq('action_type', 'ban').eq('is_active', true).order('created_at', { ascending: false }));
        if (error) return [];
        return data || [];
    }

    async function adminGetAnnouncements() {
        const client = getClient();
        if (!client) return [];
        const { data, error } = await client.rpc('admin_get_announcements').catch(() => client.from('announcements').select('*').order('created_at', { ascending: false }));
        if (error) return [];
        return data || [];
    }

    async function adminCreateAnnouncement(title, body) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_create_announcement', { p_title: title, p_body: body }).catch(async () => {
            const { data: d2, error: e2 } = await client.from('announcements').insert({ title, body }).select().single();
            if (e2) throw e2;
            return d2;
        });
        if (error) throw error;
        return data;
    }

    async function adminDeleteAnnouncement(id) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { error } = await client.rpc('admin_delete_announcement', { p_id: id }).catch(async () => {
            const { error: e2 } = await client.from('announcements').delete().eq('id', id);
            if (e2) throw e2;
        });
        if (error) throw error;
    }

    async function adminCreateAchievement(ach) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        const { data, error } = await client.rpc('admin_create_achievement', { p_data: ach }).catch(async () => {
            const { data: d2, error: e2 } = await client.from('achievements').insert(ach).select().single();
            if (e2) throw e2;
            return d2;
        });
        if (error) throw error;
        return data;
    }

    async function adminBanUser(uid, reason, duration) {
        const client = getClient();
        if (!client) throw new Error('Supabase not configured');
        let expiresAt = null;
        if (duration !== 'forever') {
            const ms = { '1h': 3600000, '1d': 86400000, '7d': 604800000, '30d': 2592000000 }[duration] || 604800000;
            expiresAt = new Date(Date.now() + ms).toISOString();
        }
        return modBanUser(uid, reason, expiresAt);
    }

    return {
        getPromptsByDifficulty, getAllPrompts, addPrompt, updatePrompt, deletePrompt,
        getAllModels, addModel, updateModel, deleteModel,
        getModelSpaces, getAllModelSpaces, addModelSpace, updateModelSpace, deleteModelSpace,
        getModelParams, getAllModelParams, addModelParam, updateModelParam, deleteModelParam,
        addModelParamValue, updateModelParamValue, deleteModelParamValue,
        getResultsByPrompt, getAllResults, addResult, updateResult, deleteResult,
        setResultParamValues, getResultParamValues, getResultRatingStats, getResultRatingEntries, rateResult, getUserId, isDevSession, hasStoredSupabaseSession,
        login, logout, getSession, isAdmin, isModeratorCheck, reinit, reinitAdmin, getClient,
        telegramAuth, setSession,
        trackPageView, getStats,
        claimInviteCode, generateInviteCode, getUserInviteStatus, getUserDisplayName,
        adminGetInviteCodes, adminGenerateInviteCode, adminDeleteInviteCode, adminGetProfiles,
        adminResetUserInviteLimit, adminResetAllInviteLimits, adminDeleteUser,
        adminSetUserRole, adminGrantAchievement, adminRevokeAchievement,
        adminUpdateUserProfile, adminGenerateInviteForUser, adminGetUserDetail,
        getForumCategories, getForumThreads, getForumThreadsCount,
        getForumThreadPosts, getForumThreadPostsCount, getForumThread,
        createForumThread, createForumPost, updateForumPost, updateForumThread,
        modPinThread, modLockThread, modDeleteThread, modDeletePost,
        modBanUser, modMuteUser, modUnbanUser, modUnmuteUser,
        getUserModActions, getPublicProfile, updateProfileBio,
        adminAssignModerator, adminRemoveModerator, adminGetModerators,
        togglePostReaction,
        getMyNotifications, getUnreadCount, markNotificationsRead,
        resolveUsernames, createMentionNotifications,
        getUserRecentActivity, getUserThreads,
        getAchievementsCatalog, getUserAchievements,
        setShowcasedAchievements, checkAndGrantAchievements,
        recordLogin,
        adminGetAllThreads, adminGetBans, adminGetAnnouncements,
        adminCreateAnnouncement, adminDeleteAnnouncement,
        adminCreateAchievement, adminBanUser
    };
})();
