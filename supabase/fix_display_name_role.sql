-- Fix: get_user_display_name missing 'role' field
-- Without this, forum.js can't determine admin_like visibility

DROP FUNCTION IF EXISTS public.get_user_display_name();

CREATE OR REPLACE FUNCTION public.get_user_display_name()
RETURNS TABLE(
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    display_name TEXT,
    is_verified BOOLEAN,
    has_generated_invite BOOLEAN,
    generated_code TEXT,
    invite_use_count INTEGER,
    bio TEXT,
    role TEXT,
    is_moderator BOOLEAN,
    is_banned BOOLEAN,
    is_muted BOOLEAN,
    ban_reason TEXT,
    mute_reason TEXT,
    ban_expires TIMESTAMPTZ,
    mute_expires TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_username,
        p.telegram_photo_url,
        COALESCE(p.telegram_first_name, split_part(p.email, '@', 1)) AS display_name,
        p.is_verified,
        p.has_generated_invite,
        ic.code AS generated_code,
        ic.use_count AS invite_use_count,
        p.bio,
        COALESCE(p.role, 'member') AS role,
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = p.user_id) AS is_moderator,
        EXISTS (
            SELECT 1 FROM user_mod_actions uma
            WHERE uma.user_id = p.user_id AND uma.action_type = 'ban'
            AND uma.is_active = true AND (uma.expires_at IS NULL OR uma.expires_at > now())
        ) AS is_banned,
        EXISTS (
            SELECT 1 FROM user_mod_actions uma
            WHERE uma.user_id = p.user_id AND uma.action_type = 'mute'
            AND uma.is_active = true AND (uma.expires_at IS NULL OR uma.expires_at > now())
        ) AS is_muted,
        (SELECT uma_b.reason FROM user_mod_actions uma_b
         WHERE uma_b.user_id = p.user_id AND uma_b.action_type = 'ban'
         AND uma_b.is_active = true AND (uma_b.expires_at IS NULL OR uma_b.expires_at > now())
         ORDER BY uma_b.created_at DESC LIMIT 1) AS ban_reason,
        (SELECT uma_m.reason FROM user_mod_actions uma_m
         WHERE uma_m.user_id = p.user_id AND uma_m.action_type = 'mute'
         AND uma_m.is_active = true AND (uma_m.expires_at IS NULL OR uma_m.expires_at > now())
         ORDER BY uma_m.created_at DESC LIMIT 1) AS mute_reason,
        (SELECT uma_b2.expires_at FROM user_mod_actions uma_b2
         WHERE uma_b2.user_id = p.user_id AND uma_b2.action_type = 'ban'
         AND uma_b2.is_active = true AND (uma_b2.expires_at IS NULL OR uma_b2.expires_at > now())
         ORDER BY uma_b2.created_at DESC LIMIT 1) AS ban_expires,
        (SELECT uma_m2.expires_at FROM user_mod_actions uma_m2
         WHERE uma_m2.user_id = p.user_id AND uma_m2.action_type = 'mute'
         AND uma_m2.is_active = true AND (uma_m2.expires_at IS NULL OR uma_m2.expires_at > now())
         ORDER BY uma_m2.created_at DESC LIMIT 1) AS mute_expires
    FROM profiles p
    LEFT JOIN invite_codes ic ON p.generated_invite_code_id = ic.id
    WHERE p.user_id = auth.uid();
END;
$$;
