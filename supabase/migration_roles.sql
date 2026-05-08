-- ============================================
-- NeuroBench: Role System
-- ============================================
-- Run this in Supabase SQL Editor
--
-- Adds a `role` column to profiles with 6 levels:
--   admin > stmoderator > moderator > beta > alpha > member
--
-- Also adds RPC for admins to change roles,
-- and updates get_public_profile to return role.
-- ============================================

-- 1. Add role column to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('admin', 'stmoderator', 'moderator', 'beta', 'alpha', 'member'));

-- 2. Backfill: set role based on existing tables
-- Admins from admin_users table
UPDATE profiles SET role = 'admin'
WHERE user_id IN (SELECT user_id FROM admin_users);

-- Moderators from moderators table (not already admin)
UPDATE profiles SET role = 'moderator'
WHERE user_id IN (SELECT user_id FROM moderators)
AND role = 'member';

-- 3. Create st_moderators table (senior moderators)
CREATE TABLE IF NOT EXISTS st_moderators (
    id SERIAL PRIMARY KEY,
    user_id UUID UNIQUE NOT NULL REFERENCES profiles(user_id) ON DELETE CASCADE,
    telegram_id TEXT,
    telegram_username TEXT,
    assigned_by UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE st_moderators ENABLE ROW LEVEL SECURITY;

-- st_moderators: public read, admin manage
DROP POLICY IF EXISTS "public_read_st_moderators" ON st_moderators;
CREATE POLICY "public_read_st_moderators" ON st_moderators
    FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_manage_st_moderators" ON st_moderators;
CREATE POLICY "admin_manage_st_moderators" ON st_moderators
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- 4. RPC: Admin sets user role
CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id UUID, p_role TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only admins can set roles
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;

    -- Validate role
    IF p_role NOT IN ('admin', 'stmoderator', 'moderator', 'beta', 'alpha', 'member') THEN
        RETURN false;
    END IF;

    -- Update profile role
    UPDATE profiles SET role = p_role WHERE user_id = p_user_id;

    -- Sync role tables
    -- st_moderators
    DELETE FROM st_moderators WHERE user_id = p_user_id;
    IF p_role = 'stmoderator' THEN
        INSERT INTO st_moderators (user_id, telegram_id, telegram_username, assigned_by)
        SELECT p_user_id, telegram_id, telegram_username, auth.uid()
        FROM profiles WHERE user_id = p_user_id;
    END IF;

    -- moderators (keep in sync for RLS policies that check moderators table)
    DELETE FROM moderators WHERE user_id = p_user_id;
    IF p_role IN ('moderator', 'stmoderator') THEN
        INSERT INTO moderators (user_id, telegram_id, telegram_username, assigned_by)
        SELECT p_user_id, telegram_id, telegram_username, auth.uid()
        FROM profiles WHERE user_id = p_user_id;
    END IF;

    -- admin_users (keep in sync for RLS policies that check admin_users table)
    DELETE FROM admin_users WHERE user_id = p_user_id;
    IF p_role = 'admin' THEN
        INSERT INTO admin_users (user_id) VALUES (p_user_id);
    END IF;

    RETURN true;
END;
$$;

-- 5. Update get_public_profile to return role
-- (Drop and recreate if it exists вЂ” the function may vary, so this is additive)
CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
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
    posts_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.user_id,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_username,
        p.telegram_photo_url,
        p.bio,
        (p.role IN ('moderator', 'stmoderator', 'admin')) AS is_moderator,
        p.is_verified,
        p.role,
        p.created_at,
        (SELECT COUNT(*) FROM forum_threads WHERE author_id = p.user_id AND is_deleted = false),
        (SELECT COUNT(*) FROM forum_posts WHERE author_id = p.user_id AND is_deleted = false)
    FROM profiles p
    WHERE p.user_id = p_user_id;
END;
$$;

-- 6. Update get_user_display_name to return role
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE invite_codes ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

DROP FUNCTION IF EXISTS public.get_user_display_name();

CREATE OR REPLACE FUNCTION public.get_user_display_name()
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    is_banned BOOLEAN,
    is_muted BOOLEAN,
    has_generated_invite BOOLEAN,
    generated_code TEXT,
    invite_use_count INTEGER,
    role TEXT,
    invite_max INTEGER,
    invite_active_count INTEGER,
    verified_by_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.user_id,
        COALESCE(NULLIF(p.telegram_username, ''), NULLIF(p.telegram_first_name, ''), p.email) AS display_name,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_username,
        p.telegram_photo_url,
        (p.role IN ('moderator', 'stmoderator', 'admin')) AS is_moderator,
        p.is_verified,
        EXISTS (SELECT 1 FROM user_mod_actions WHERE user_id = p.user_id AND action_type = 'ban' AND is_active = true AND (expires_at IS NULL OR expires_at > now())) AS is_banned,
        EXISTS (SELECT 1 FROM user_mod_actions WHERE user_id = p.user_id AND action_type = 'mute' AND is_active = true AND (expires_at IS NULL OR expires_at > now())) AS is_muted,
        p.has_generated_invite,
        gen_ic.code AS generated_code,
        (SELECT COUNT(*)::int FROM invite_code_uses WHERE invite_code_id = p.generated_invite_code_id) AS invite_use_count,
        p.role,
        CASE
            WHEN p.role = 'admin' THEN 999999
            WHEN p.role = 'stmoderator' THEN 10
            WHEN p.role = 'moderator' THEN 5
            WHEN p.role = 'beta' THEN 3
            WHEN p.role = 'alpha' THEN 2
            ELSE 1
        END AS invite_max,
        (SELECT COUNT(*)::int
         FROM invite_codes
         WHERE created_by = p.user_id
           AND is_admin_code = false
           AND used_by IS NULL
           AND (expires_at IS NULL OR expires_at > now())) AS invite_active_count,
        (SELECT COALESCE(vp.telegram_username, vp.telegram_first_name, 'Админ')
         FROM profiles vp
         WHERE vp.user_id = p.verified_by) AS verified_by_name
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    WHERE p.user_id = auth.uid();
END;
$$;