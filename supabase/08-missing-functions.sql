-- ============================================
-- BUNDLE 8: MISSING FUNCTIONS & BUG FIXES
-- Run AFTER all previous bundles
-- ============================================

-- ==========================================
-- FIX 1: get_public_profile_by_uid
-- Called by profile.js when opening /profile/<uid>
-- Was missing entirely — caused profile page to always fail
-- ==========================================

DROP FUNCTION IF EXISTS public.get_public_profile_by_uid(INTEGER);
CREATE OR REPLACE FUNCTION public.get_public_profile_by_uid(p_uid INTEGER)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    bio TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    role TEXT,
    created_at TIMESTAMPTZ,
    threads_count BIGINT,
    posts_count BIGINT,
    reactions_given_count BIGINT,
    achievement_points BIGINT,
    achievements_count BIGINT,
    showcased_achievements JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT profiles.user_id INTO v_user_id
    FROM profiles
    WHERE profiles.uid = p_uid;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY SELECT * FROM get_public_profile(v_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO service_role;

-- ==========================================
-- FIX 2: update_profile_bio — унифицировать лимит
-- В 01-core.sql было 44, в 03-forum.sql было 500, в profile.js textarea maxlength=400
-- Устанавливаем единый лимит 400 символов
-- ==========================================

DROP FUNCTION IF EXISTS public.update_profile_bio(TEXT);
CREATE OR REPLACE FUNCTION public.update_profile_bio(p_bio TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF length(p_bio) > 400 THEN
        RAISE EXCEPTION 'Bio must be at most 400 characters';
    END IF;
    UPDATE profiles SET bio = p_bio WHERE user_id = auth.uid();
    RETURN FOUND;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_profile_bio(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_profile_bio(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_profile_bio(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_profile_bio(TEXT) TO service_role;

-- ==========================================
-- FIX 3: check_and_grant_achievements — first_model_rate
-- Было: results.author = p_user_id::text (никогда не срабатывало)
-- Теперь: проверяем result_ratings — пользователь оценил хотя бы один результат
-- ==========================================

-- Обновляем только эту часть через отдельную функцию-обёртку
-- Полная функция check_and_grant_achievements уже переопределена в 06b,
-- поэтому добавляем отдельный RPC для проверки first_model_rate

DROP FUNCTION IF EXISTS public.check_first_model_rate_achievement(UUID);
CREATE OR REPLACE FUNCTION public.check_first_model_rate_achievement(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RETURN jsonb_build_object('granted', false, 'reason', 'forbidden');
    END IF;

    IF EXISTS(SELECT 1 FROM result_ratings WHERE user_id = p_user_id LIMIT 1) THEN
        RETURN grant_achievement(p_user_id, 'first_model_rate');
    END IF;

    RETURN jsonb_build_object('granted', false, 'reason', 'no_ratings');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) TO service_role;

-- ==========================================
-- FIX 4: admin_generate_invite_code — поднять TTL лимит
-- Было: LEAST(604800, ...) = макс 7 дней
-- Теперь: LEAST(35996400, ...) = совпадает с INVITE_INFINITE_TTL_SECONDS в JS
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.admin_generate_invite_code(
    p_max_uses INTEGER DEFAULT 10,
    p_ttl_seconds INTEGER DEFAULT 300
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_code TEXT;
    v_max_uses INTEGER;
    v_ttl_seconds INTEGER;
    v_attempt INTEGER := 0;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN NULL;
    END IF;

    v_max_uses := LEAST(10000, GREATEST(1, COALESCE(p_max_uses, 10)));
    -- Поднимаем лимит до INVITE_INFINITE_TTL_SECONDS (35996400 сек ≈ 416 дней)
    v_ttl_seconds := LEAST(35996400, GREATEST(1, COALESCE(p_ttl_seconds, 300)));

    LOOP
        v_attempt := v_attempt + 1;
        v_code := upper(encode(gen_random_bytes(6), 'hex'));

        BEGIN
            INSERT INTO public.invite_codes (code, created_by, is_admin_code, max_uses, use_count, expires_at)
            VALUES (v_code, auth.uid(), true, v_max_uses, 0, now() + make_interval(secs => v_ttl_seconds));
            EXIT;
        EXCEPTION
            WHEN unique_violation THEN
                IF v_attempt >= 8 THEN
                    RAISE EXCEPTION 'failed to generate a unique invite code after % attempts', v_attempt;
                END IF;
        END;
    END LOOP;

    RETURN v_code;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) TO service_role;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
