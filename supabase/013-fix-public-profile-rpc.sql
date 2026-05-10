-- Fix public profile RPC functions after invited users fields were added

DROP FUNCTION IF EXISTS public.get_public_profile_by_uid(INTEGER);
DROP FUNCTION IF EXISTS public.get_public_profile(UUID);

CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    username TEXT,
    pending_username TEXT,
    bio TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    role TEXT,
    created_at TIMESTAMPTZ,
    threads_count BIGINT,
    posts_count BIGINT,
    reactions_received_count BIGINT,
    achievement_points BIGINT,
    achievements_count BIGINT,
    showcased_achievements JSONB,
    invited_users_count BIGINT,
    invited_users JSONB
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT
        p.user_id::UUID,
        p.uid::INTEGER,
        p.telegram_first_name::TEXT,
        p.telegram_last_name::TEXT,
        p.telegram_username::TEXT,
        p.telegram_photo_url::TEXT,
        p.username::TEXT,
        p.pending_username::TEXT,
        p.bio::TEXT,
        (COALESCE(p.role, 'member') IN ('moderator', 'stmoderator', 'admin'))::BOOLEAN,
        COALESCE(p.is_verified, false)::BOOLEAN,
        COALESCE(p.role, 'member')::TEXT,
        p.created_at::TIMESTAMPTZ,
        COALESCE(ft.threads_count, 0)::BIGINT,
        COALESCE(fp.posts_count, 0)::BIGINT,
        COALESCE(pr.reactions_received_count, 0)::BIGINT,
        COALESCE(ua.achievement_points, 0)::BIGINT,
        COALESCE(uc.achievements_count, 0)::BIGINT,
        COALESCE(sa.showcased_achievements, '[]'::JSONB)::JSONB,
        COALESCE(iuc.invited_users_count, 0)::BIGINT,
        COALESCE(iu.invited_users, '[]'::JSONB)::JSONB
    FROM public.profiles p
    LEFT JOIN LATERAL (
        SELECT COUNT(*)::BIGINT AS threads_count
        FROM public.forum_threads ft
        WHERE ft.author_id = p.user_id AND ft.is_deleted = false
    ) ft ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(*)::BIGINT AS posts_count
        FROM public.forum_posts fp
        WHERE fp.author_id = p.user_id AND fp.is_deleted = false
    ) fp ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(*)::BIGINT AS reactions_received_count
        FROM public.post_reactions pr
        JOIN public.forum_posts fp ON fp.id = pr.post_id AND fp.is_deleted = false
        WHERE fp.author_id = p.user_id
    ) pr ON true
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(a.points), 0)::BIGINT AS achievement_points
        FROM public.user_achievements uap
        JOIN public.achievements a ON a.id = uap.achievement_id
        WHERE uap.user_id = p.user_id
    ) ua ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(*)::BIGINT AS achievements_count
        FROM public.user_achievements uac
        WHERE uac.user_id = p.user_id
    ) uc ON true
    LEFT JOIN LATERAL (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', a.id,
            'title', a.title,
            'icon_emoji', a.icon_emoji,
            'rarity', a.rarity,
            'points', a.points
        ) ORDER BY a.sort_order), '[]'::JSONB) AS showcased_achievements
        FROM public.user_achievements uas
        JOIN public.achievements a ON a.id = uas.achievement_id
        WHERE uas.user_id = p.user_id AND uas.is_showcased = true
    ) sa ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(DISTINCT icu.user_id)::BIGINT AS invited_users_count
        FROM public.invite_codes ic
        JOIN public.invite_code_uses icu ON icu.invite_code_id = ic.id
        WHERE ic.created_by = p.user_id
    ) iuc ON true
    LEFT JOIN LATERAL (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'user_id', invited.user_id,
            'uid', invited.uid,
            'telegram_first_name', invited.telegram_first_name,
            'telegram_last_name', invited.telegram_last_name,
            'telegram_username', invited.telegram_username,
            'username', invited.username,
            'telegram_photo_url', invited.telegram_photo_url
        ) ORDER BY invited.uid), '[]'::JSONB) AS invited_users
        FROM (
            SELECT DISTINCT
                ip.user_id,
                ip.uid,
                ip.telegram_first_name,
                ip.telegram_last_name,
                ip.telegram_username,
                ip.username,
                ip.telegram_photo_url
            FROM public.invite_codes ic
            JOIN public.invite_code_uses icu ON icu.invite_code_id = ic.id
            JOIN public.profiles ip ON ip.user_id = icu.user_id
            WHERE ic.created_by = p.user_id
            ORDER BY ip.uid
            LIMIT 12
        ) invited
    ) iu ON true
    WHERE p.user_id = p_user_id
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_public_profile_by_uid(p_uid INTEGER)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    username TEXT,
    pending_username TEXT,
    bio TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    role TEXT,
    created_at TIMESTAMPTZ,
    threads_count BIGINT,
    posts_count BIGINT,
    reactions_received_count BIGINT,
    achievement_points BIGINT,
    achievements_count BIGINT,
    showcased_achievements JSONB,
    invited_users_count BIGINT,
    invited_users JSONB
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT gp.*
    FROM public.profiles p
    CROSS JOIN LATERAL public.get_public_profile(p.user_id) gp
    WHERE p.uid = p_uid
    LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO service_role;
