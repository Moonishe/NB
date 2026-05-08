-- ============================================
-- BUNDLE 1: CORE - Auth, Users, Roles, Invites
-- Run this FIRST
-- ============================================


-- --- PREREQUISITE: page_views table ---
CREATE TABLE IF NOT EXISTS page_views (
    id BIGSERIAL PRIMARY KEY,
    visitor_hash TEXT NOT NULL,
    page TEXT,
    referrer TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE page_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_insert_page_views" ON page_views;
CREATE POLICY "public_insert_page_views" ON page_views FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "public_read_page_views" ON page_views;
CREATE POLICY "public_read_page_views" ON page_views FOR SELECT USING (true);
CREATE INDEX IF NOT EXISTS idx_page_views_created_at ON page_views(created_at);
CREATE INDEX IF NOT EXISTS idx_page_views_visitor_hash ON page_views(visitor_hash);

-- --- PREREQUISITE: admin_users + moderators tables ---

-- Admin users table (must exist before RLS policies reference it)
CREATE TABLE IF NOT EXISTS admin_users (
    id SERIAL PRIMARY KEY,
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Moderators table (must exist before RLS policies reference it)
CREATE TABLE IF NOT EXISTS moderators (
    id SERIAL PRIMARY KEY,
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    telegram_id TEXT,
    telegram_username TEXT,
    assigned_by UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE moderators ENABLE ROW LEVEL SECURITY;

-- --- migration_invite_system.sql ---

-- ============================================
-- NeuroBench: Invite-Only Registration System
-- ============================================
-- Run this entire script in Supabase SQL Editor
-- (Dashboard ГІГ†Г’ SQL Editor ГІГ†Г’ New Query ГІГ†Г’ Paste ГІГ†Г’ Run)

-- 1. Invite codes table
CREATE TABLE IF NOT EXISTS invite_codes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    created_by UUID,
    is_admin_code BOOLEAN DEFAULT false,
    used_by UUID,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Profiles table (auto-created on signup via trigger)
CREATE TABLE IF NOT EXISTS profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    is_verified BOOLEAN DEFAULT false,
    pending_invite_code TEXT,
    used_invite_code_id UUID REFERENCES invite_codes(id),
    has_generated_invite BOOLEAN DEFAULT false,
    generated_invite_code_id UUID REFERENCES invite_codes(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Enable RLS
ALTER TABLE invite_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 4. RLS: invite_codes
-- Registration page needs to check if a code is valid (unused)
DROP POLICY IF EXISTS "read_unused_codes" ON invite_codes;
CREATE POLICY "read_unused_codes" ON invite_codes
    FOR SELECT USING (used_by IS NULL);

-- Users can read codes they created or used
DROP POLICY IF EXISTS "read_own_codes" ON invite_codes;
CREATE POLICY "read_own_codes" ON invite_codes
    FOR SELECT USING (created_by = auth.uid() OR used_by = auth.uid());

-- Admins can read all codes
DROP POLICY IF EXISTS "admin_read_codes" ON invite_codes;
CREATE POLICY "admin_read_codes" ON invite_codes
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- Admins can insert codes
DROP POLICY IF EXISTS "admin_insert_codes" ON invite_codes;
CREATE POLICY "admin_insert_codes" ON invite_codes
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- Verified users can insert one invite code for themselves (RLS double-check)
DROP POLICY IF EXISTS "user_insert_own_invite" ON invite_codes;
CREATE POLICY "user_insert_own_invite" ON invite_codes
    FOR INSERT WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE user_id = auth.uid()
            AND is_verified = true
            AND has_generated_invite = false
        )
    );

-- Admins can update/delete codes
DROP POLICY IF EXISTS "admin_update_codes" ON invite_codes;
CREATE POLICY "admin_update_codes" ON invite_codes
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
DROP POLICY IF EXISTS "admin_delete_codes" ON invite_codes;
CREATE POLICY "admin_delete_codes" ON invite_codes
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- 5. RLS: profiles
-- Users can read their own profile
DROP POLICY IF EXISTS "read_own_profile" ON profiles;
CREATE POLICY "read_own_profile" ON profiles
    FOR SELECT USING (user_id = auth.uid());

-- Admins can read all profiles
DROP POLICY IF EXISTS "admin_read_profiles" ON profiles;
CREATE POLICY "admin_read_profiles" ON profiles
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- Only SECURITY DEFINER functions (service-level) can insert/update profiles
DROP POLICY IF EXISTS "fn_manage_profiles" ON profiles;
CREATE POLICY "fn_manage_profiles" ON profiles
    FOR ALL USING (auth.role() = 'service_role' OR auth.uid() = user_id);

-- 6. Trigger: auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO profiles (user_id, email, is_verified, pending_invite_code)
    VALUES (
        NEW.id,
        NEW.email,
        false,
        NEW.raw_user_meta_data->>'invite_code'
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 7. RPC: Claim invite code after OTP verification
-- Uses auth.uid() for security ГІГЂГ” only the logged-in user can claim for themselves
DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT);
CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code TEXT;
    v_invite_id UUID;
BEGIN
    IF p_code IS NOT NULL THEN
        v_code := p_code;
    ELSE
        SELECT pending_invite_code INTO v_code
        FROM profiles WHERE user_id = auth.uid();
    END IF;

    IF v_code IS NULL THEN
        RETURN false;
    END IF;

    SELECT id INTO v_invite_id
    FROM invite_codes
    WHERE code = v_code AND used_by IS NULL;

    IF v_invite_id IS NULL THEN
        RETURN false;
    END IF;

    UPDATE invite_codes
    SET used_by = auth.uid(), used_at = now()
    WHERE id = v_invite_id AND used_by IS NULL;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE profiles
    SET is_verified = true,
        used_invite_code_id = v_invite_id,
        pending_invite_code = NULL
    WHERE user_id = auth.uid();

    RETURN true;
END;
$$;

-- 8. RPC: User generates their one-time invite code
DROP FUNCTION IF EXISTS public.generate_user_invite_code();
CREATE OR REPLACE FUNCTION public.generate_user_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_code TEXT;
    v_invite_id UUID;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE user_id = auth.uid()
        AND is_verified = true
        AND has_generated_invite = false
    ) THEN
        RETURN NULL;
    END IF;

    v_new_code := upper(substr(md5(random()::text), 1, 8));

    INSERT INTO invite_codes (code, created_by, is_admin_code)
    VALUES (v_new_code, auth.uid(), false)
    RETURNING id INTO v_invite_id;

    UPDATE profiles
    SET has_generated_invite = true, generated_invite_code_id = v_invite_id
    WHERE user_id = auth.uid();

    RETURN v_new_code;
END;
$$;

-- 9. RPC: Admin generates invite code (unlimited)
DROP FUNCTION IF EXISTS public.admin_generate_invite_code();
CREATE OR REPLACE FUNCTION public.admin_generate_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_code TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN NULL;
    END IF;

    v_new_code := upper(substr(md5(random()::text), 1, 8));

    INSERT INTO invite_codes (code, created_by, is_admin_code)
    VALUES (v_new_code, auth.uid(), true);

    RETURN v_new_code;
END;
$$;

-- 10. RPC: Get current user's invite status
DROP FUNCTION IF EXISTS public.get_user_invite_status();
CREATE OR REPLACE FUNCTION public.get_user_invite_status()
RETURNS TABLE (
    is_verified BOOLEAN,
    has_generated_invite BOOLEAN,
    generated_code TEXT,
    used_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.is_verified,
        p.has_generated_invite,
        gen_ic.code,
        used_ic.code
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    LEFT JOIN invite_codes used_ic ON used_ic.id = p.used_invite_code_id
    WHERE p.user_id = auth.uid();
END;
$$;

-- 11. RPC: Admin list all invite codes
DROP FUNCTION IF EXISTS public.admin_get_invite_codes();
CREATE OR REPLACE FUNCTION public.admin_get_invite_codes()
RETURNS SETOF invite_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT * FROM invite_codes ORDER BY created_at DESC;
END;
$$;

-- 12. RPC: Admin delete unused invite code
DROP FUNCTION IF EXISTS public.admin_delete_invite_code(UUID);
CREATE OR REPLACE FUNCTION public.admin_delete_invite_code(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    DELETE FROM invite_codes WHERE id = p_id AND used_by IS NULL;
    RETURN FOUND;
END;
$$;

-- 13. RPC: Admin list all profiles
DROP FUNCTION IF EXISTS public.admin_get_profiles();
CREATE OR REPLACE FUNCTION public.admin_get_profiles()
RETURNS SETOF profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT * FROM profiles ORDER BY created_at DESC;
END;
$$;

-- 14. Enable pg_net extension for Turnstile verification
CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;

-- 15. RPC: Verify Cloudflare Turnstile token server-side
-- IMPORTANT: Replace 'YOUR_TURNSTILE_SECRET_KEY' with your actual secret key
-- The function source is NOT readable by anon users ГІГЂГ” only database admins can see it
DROP FUNCTION IF EXISTS public.verify_turnstile(TEXT);
CREATE OR REPLACE FUNCTION public.verify_turnstile(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    req_id bigint;
    response_body text;
    success_val boolean;
    attempts integer := 0;
BEGIN
    IF p_token IS NULL OR p_token = '' THEN
        RETURN false;
    END IF;

    SELECT INTO req_id extensions.net.http_post(
        url := 'https://challenges.cloudflare.com/turnstile/v0/siteverify',
        body := json_build_object(
            'secret', 'YOUR_TURNSTILE_SECRET_KEY',
            'response', p_token
        )::text,
        content_type := 'application/json'
    );

    LOOP
        attempts := attempts + 1;
        IF attempts > 30 THEN
            RETURN false;
        END IF;

        SELECT t.body INTO response_body
        FROM extensions.net._http_response t
        WHERE t.id = req_id;

        IF response_body IS NOT NULL THEN
            EXIT;
        END IF;

        PERFORM pg_sleep(0.15);
    END LOOP;

    IF response_body IS NULL THEN
        RETURN false;
    END IF;

    SELECT INTO success_val (response_body::json->>'success')::boolean;
    RETURN COALESCE(success_val, false);
END;
$$;


-- --- migration_telegram_auth.sql ---

-- ============================================
-- NeuroBench: Telegram Auth Migration
-- ============================================
-- Run this in Supabase SQL Editor AFTER the original migration_invite_system.sql
--
-- SETUP INSTRUCTIONS:
--
-- 1. CREATE TELEGRAM BOT:
--    a. Open Telegram, find @BotFather
--    b. Send /newbot, choose name (e.g. "NeuroBench Auth")
--    c. Choose username (e.g. "neurobench_auth_bot")
--    d. Copy the BOT TOKEN you receive
--
-- 2. SET BOT DOMAIN:
--    a. Send /setdomain to @BotFather
--    b. Select your bot
--    c. Set domain to: moonishe.github.io
--       (or your actual GitHub Pages domain)
--
-- 3. SET EDGE FUNCTION SECRETS:
--    In Supabase Dashboard ГІГ†Г’ Edge Functions ГІГ†Г’ Secrets:
--    - TELEGRAM_BOT_TOKEN = <your bot token from step 1>
--    - SESSION_SECRET = <random 32+ char string, e.g. openssl rand -hex 32>
--    The SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
--    are auto-provided by Supabase.
--
-- 4. DEPLOY EDGE FUNCTION:
--    Option A (CLI): supabase functions deploy telegram-auth
--    Option B (Dashboard): Supabase ГІГ†Г’ Edge Functions ГІГ†Г’ New Function
--      ГІГ†Г’ Name: telegram-auth ГІГ†Г’ Paste code from supabase/functions/telegram-auth/index.ts
--
-- 5. UPDATE js/config.js:
--    Set window.TELEGRAM_BOT_USERNAME = 'your_bot_username'  (without @)
--
-- 6. KEEP EMAIL AUTH ENABLED:
--    Do NOT disable email auth in Supabase Dashboard ГІГЂГ” the admin panel
--    still uses email+password login. The public UI just won't offer it.
-- ============================================

-- 1. Add Telegram columns to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telegram_id TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telegram_username TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telegram_first_name TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telegram_last_name TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telegram_photo_url TEXT;

-- 2. Unique constraint on telegram_id to prevent duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_telegram_id ON profiles (telegram_id) WHERE telegram_id IS NOT NULL;

-- 3. Update handle_new_user trigger to support telegram data
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_telegram_id TEXT;
    v_invite_code TEXT;
BEGIN
    v_telegram_id := NEW.raw_user_meta_data->>'telegram_id';
    v_invite_code := NEW.raw_user_meta_data->>'invite_code';

    INSERT INTO profiles (user_id, email, is_verified, pending_invite_code, telegram_id)
    VALUES (
        NEW.id,
        NEW.email,
        (v_telegram_id IS NOT NULL),
        CASE WHEN v_telegram_id IS NULL THEN v_invite_code ELSE NULL END,
        v_telegram_id
    );
    RETURN NEW;
END;
$$;

-- 4. RPC: Get user display info (for nav menu)
-- Returns telegram username or email for display
DROP FUNCTION IF EXISTS public.get_user_display_name();
DROP FUNCTION IF EXISTS public.get_user_display_name(UUID);
CREATE OR REPLACE FUNCTION public.get_user_display_name()
RETURNS TABLE (
    display_name TEXT,
    telegram_username TEXT,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_photo_url TEXT,
    is_verified BOOLEAN,
    has_generated_invite BOOLEAN,
    generated_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(NULLIF(p.telegram_username, ''), NULLIF(p.telegram_first_name, ''), p.email) AS display_name,
        p.telegram_username,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_photo_url,
        p.is_verified,
        p.has_generated_invite,
        gen_ic.code AS generated_code
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    WHERE p.user_id = auth.uid();
END;
$$;

-- 5. RPC: Admin reset invite limit for a single user
DROP FUNCTION IF EXISTS public.admin_reset_user_invite_limit(UUID);
CREATE OR REPLACE FUNCTION public.admin_reset_user_invite_limit(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    UPDATE profiles
    SET has_generated_invite = false,
        generated_invite_code_id = NULL
    WHERE user_id = p_user_id
      AND has_generated_invite = true;
    RETURN FOUND;
END;
$$;

-- 6. RPC: Admin reset invite limits for all users
DROP FUNCTION IF EXISTS public.admin_reset_all_invite_limits();
CREATE OR REPLACE FUNCTION public.admin_reset_all_invite_limits()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN -1;
    END IF;
    UPDATE profiles
    SET has_generated_invite = false,
        generated_invite_code_id = NULL
    WHERE has_generated_invite = true;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;


-- --- migration_roles.sql ---

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
DROP FUNCTION IF EXISTS public.admin_set_user_role(UUID, TEXT);
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
DROP FUNCTION IF EXISTS public.get_public_profile(UUID);
-- (Drop and recreate if it exists В¦-В¦Г‚ГІГЂГќ the function may vary, so this is additive)
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

DROP FUNCTION IF EXISTS public.get_user_display_name();
DROP FUNCTION IF EXISTS public.get_user_display_name(UUID);
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
        (SELECT COALESCE(vp.telegram_username, vp.telegram_first_name, 'В¦ГђВ¦+В¦-В¦В¬В¦-')
         FROM profiles vp
         WHERE vp.user_id = p.verified_by) AS verified_by_name
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    WHERE p.user_id = auth.uid();
END;
$$;


-- --- migration_uid_system.sql ---

-- UID system: sequential user IDs (1, 2, 3, ...)
-- Run this migration to add uid column to profiles and auto-assign on registration

-- 1. Create sequence
CREATE SEQUENCE IF NOT EXISTS user_uid_seq START 1;

-- 2. Add uid column
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS uid INTEGER UNIQUE;

-- 3. Backfill existing users (ordered by created_at)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT user_id FROM profiles ORDER BY created_at ASC
    LOOP
        UPDATE profiles SET uid = nextval('user_uid_seq') WHERE user_id = r.user_id AND uid IS NULL;
    END LOOP;
END;
$$;

-- 4. Set default for new users
ALTER TABLE profiles ALTER COLUMN uid SET DEFAULT nextval('user_uid_seq');

-- 5. Update trigger to include uid in INSERT (it will use the default)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_telegram_id TEXT;
    v_invite_code TEXT;
BEGIN
    v_telegram_id := NEW.raw_user_meta_data->>'telegram_id';
    v_invite_code := NEW.raw_user_meta_data->>'invite_code';

    INSERT INTO profiles (user_id, email, is_verified, pending_invite_code, telegram_id)
    VALUES (
        NEW.id,
        NEW.email,
        (v_telegram_id IS NOT NULL),
        CASE WHEN v_telegram_id IS NULL THEN v_invite_code ELSE NULL END,
        v_telegram_id
    );
    RETURN NEW;
END;
$$;

-- 6. Update get_public_profile to return uid
DROP FUNCTION IF EXISTS public.get_public_profile(UUID);
CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
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
        p.uid,
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

-- 7. Update get_user_display_name to return uid
DROP FUNCTION IF EXISTS public.get_user_display_name();
DROP FUNCTION IF EXISTS public.get_user_display_name(UUID);
CREATE OR REPLACE FUNCTION public.get_user_display_name(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
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
    role TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.user_id,
        p.uid,
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
        p.role
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    WHERE p.user_id = p_user_id;
END;
$$;

-- 8. Update get_forum_threads to return author_uid
DROP FUNCTION IF EXISTS public.get_forum_threads(INTEGER, INTEGER, TEXT);
CREATE OR REPLACE FUNCTION public.get_forum_threads(
    p_category_id INTEGER DEFAULT NULL,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    id INTEGER,
    category_id INTEGER,
    author_id UUID,
    title TEXT,
    content TEXT,
    is_pinned BOOLEAN,
    is_locked BOOLEAN,
    posts_count INTEGER,
    last_post_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    author_username TEXT,
    author_first_name TEXT,
    author_last_name TEXT,
    author_photo_url TEXT,
    is_author_moderator BOOLEAN,
    category_name TEXT,
    category_slug TEXT,
    author_uid INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ft.id, ft.category_id, ft.author_id, ft.title, ft.content,
        ft.is_pinned, ft.is_locked, ft.posts_count,
        ft.last_post_at, ft.created_at, ft.updated_at,
        p.telegram_username,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_photo_url,
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = ft.author_id),
        fc.name,
        fc.slug,
        p.uid
    FROM forum_threads ft
    LEFT JOIN profiles p ON p.user_id = ft.author_id
    LEFT JOIN forum_categories fc ON fc.id = ft.category_id
    WHERE ft.is_deleted = false
      AND (p_category_id IS NULL OR ft.category_id = p_category_id)
    ORDER BY ft.is_pinned DESC, ft.last_post_at DESC NULLS LAST, ft.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 9. Update get_forum_thread_posts to return author_uid
DROP FUNCTION IF EXISTS public.get_forum_thread_posts(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.get_forum_thread_posts(
    p_thread_id INTEGER,
    p_limit INTEGER DEFAULT 25,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    id INTEGER,
    thread_id INTEGER,
    author_id UUID,
    content TEXT,
    is_deleted BOOLEAN,
    edited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    author_username TEXT,
    author_first_name TEXT,
    author_last_name TEXT,
    author_photo_url TEXT,
    is_author_moderator BOOLEAN,
    author_uid INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        fp.id, fp.thread_id, fp.author_id, fp.content,
        fp.is_deleted, fp.edited_at, fp.created_at,
        p.telegram_username,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_photo_url,
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = fp.author_id),
        p.uid
    FROM forum_posts fp
    LEFT JOIN profiles p ON p.user_id = fp.author_id
    WHERE fp.thread_id = p_thread_id
      AND fp.is_deleted = false
    ORDER BY fp.created_at ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 10. Index for fast UID lookups
CREATE INDEX IF NOT EXISTS idx_profiles_uid ON profiles(uid);

-- 11. Update bio limit to 120 chars
DROP FUNCTION IF EXISTS public.update_profile_bio(TEXT);
CREATE OR REPLACE FUNCTION public.update_profile_bio(p_bio TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF length(p_bio) > 44 THEN
        RAISE EXCEPTION 'Bio must be at most 44 characters';
    END IF;
    UPDATE profiles SET bio = p_bio WHERE user_id = auth.uid();
    RETURN FOUND;
END;
$$;

-- 12. Invite quota per role: member=1, beta=3, alpha=10, moderator+=unlimited
DROP FUNCTION IF EXISTS public.get_invite_max(TEXT);
CREATE OR REPLACE FUNCTION public.get_invite_max(p_role TEXT)
RETURNS INTEGER
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN CASE p_role
        WHEN 'admin' THEN 999999
        WHEN 'stmoderator' THEN 999999
        WHEN 'moderator' THEN 999999
        WHEN 'alpha' THEN 10
        WHEN 'beta' THEN 3
        ELSE 1
    END;
END;
$$;

-- 13. Rewrite generate_user_invite_code: multiple invites, delete oldest unused if at limit
DROP FUNCTION IF EXISTS public.generate_user_invite_code();
CREATE OR REPLACE FUNCTION public.generate_user_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_role TEXT;
    v_max INTEGER;
    v_active_count INTEGER;
    v_oldest_id UUID;
    v_new_code TEXT;
    v_invite_id UUID;
BEGIN
    SELECT role INTO v_role FROM profiles WHERE user_id = v_user_id AND is_verified = true;
    IF v_role IS NULL THEN RETURN NULL; END IF;

    v_max := get_invite_max(v_role);

    SELECT COUNT(*) INTO v_active_count
    FROM invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND (used_by IS NULL);

    IF v_active_count >= v_max THEN
        SELECT id INTO v_oldest_id
        FROM invite_codes
        WHERE created_by = v_user_id
          AND is_admin_code = false
          AND used_by IS NULL
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_oldest_id IS NOT NULL THEN
            DELETE FROM invite_codes WHERE id = v_oldest_id;
        END IF;
    END IF;

    v_new_code := upper(substr(md5(random()::text), 1, 8));

    INSERT INTO invite_codes (code, created_by, is_admin_code)
    VALUES (v_new_code, v_user_id, false)
    RETURNING id INTO v_invite_id;

    UPDATE profiles
    SET has_generated_invite = true, generated_invite_code_id = v_invite_id
    WHERE user_id = v_user_id;

    RETURN v_new_code;
END;
$$;

-- 14. Update get_user_display_name to return invite quota info
DROP FUNCTION IF EXISTS public.get_user_display_name();
DROP FUNCTION IF EXISTS public.get_user_display_name(UUID);
CREATE OR REPLACE FUNCTION public.get_user_display_name(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
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
        p.uid,
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
        get_invite_max(p.role) AS invite_max,
        (SELECT COUNT(*)::int FROM invite_codes WHERE created_by = p.user_id AND is_admin_code = false AND used_by IS NULL AND (expires_at IS NULL OR expires_at > now())) AS invite_active_count,
        (SELECT COALESCE(vp.telegram_username, vp.telegram_first_name, 'В¦ГђВ¦+В¦-В¦В¬В¦-')
         FROM profiles vp WHERE vp.user_id = p.verified_by) AS verified_by_name
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    WHERE p.user_id = p_user_id;
END;
$$;

-- 15. Add verified_by column to profiles (tracks which admin verified)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- 16. Add expires_at column to invite_codes (5 minute TTL)
ALTER TABLE invite_codes ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- 17. Update generate_user_invite_code to set 5-minute TTL
DROP FUNCTION IF EXISTS public.generate_user_invite_code();
CREATE OR REPLACE FUNCTION public.generate_user_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_role TEXT;
    v_max INTEGER;
    v_active_count INTEGER;
    v_oldest_id UUID;
    v_new_code TEXT;
    v_invite_id UUID;
BEGIN
    SELECT role INTO v_role FROM profiles WHERE user_id = v_user_id AND is_verified = true;
    IF v_role IS NULL THEN RETURN NULL; END IF;

    v_max := get_invite_max(v_role);

    SELECT COUNT(*) INTO v_active_count
    FROM invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND used_by IS NULL
      AND (expires_at IS NULL OR expires_at > now());

    IF v_active_count >= v_max THEN
        SELECT id INTO v_oldest_id
        FROM invite_codes
        WHERE created_by = v_user_id
          AND is_admin_code = false
          AND used_by IS NULL
          AND (expires_at IS NULL OR expires_at > now())
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_oldest_id IS NOT NULL THEN
            DELETE FROM invite_codes WHERE id = v_oldest_id;
        END IF;
    END IF;

    -- Cleanup expired invites for this user
    DELETE FROM invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND used_by IS NULL
      AND expires_at IS NOT NULL
      AND expires_at <= now();

    v_new_code := upper(substr(md5(random()::text), 1, 8));

    INSERT INTO invite_codes (code, created_by, is_admin_code, expires_at)
    VALUES (v_new_code, v_user_id, false, now() + interval '5 minutes')
    RETURNING id INTO v_invite_id;

    UPDATE profiles
    SET has_generated_invite = true, generated_invite_code_id = v_invite_id
    WHERE user_id = v_user_id;

    RETURN v_new_code;
END;
$$;

-- 18. Update claim_invite_code to check expiry
DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT);
DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite invite_codes%ROWTYPE;
    v_user_id UUID := auth.uid();
BEGIN
    SELECT * INTO v_invite FROM invite_codes
    WHERE code = p_code AND used_by IS NULL AND is_admin_code = false;

    IF v_invite IS NULL THEN RETURN false; END IF;

    IF v_invite.expires_at IS NOT NULL AND v_invite.expires_at <= now() THEN
        DELETE FROM invite_codes WHERE id = v_invite.id;
        RETURN false;
    END IF;

    IF v_invite.max_uses IS NOT NULL AND v_invite.use_count >= v_invite.max_uses THEN
        RETURN false;
    END IF;

    UPDATE invite_codes
    SET use_count = use_count + 1,
        used_by = CASE WHEN max_uses IS NULL OR max_uses = 1 THEN v_user_id ELSE used_by END,
        used_at = CASE WHEN max_uses IS NULL OR max_uses = 1 THEN now() ELSE used_at END
    WHERE id = v_invite.id;

    UPDATE profiles SET used_invite_code_id = v_invite.id WHERE user_id = v_user_id;

    INSERT INTO invite_code_uses (invite_code_id, user_id)
    VALUES (v_invite.id, v_user_id);

    RETURN true;
END;
$$;

-- --- migration_member_invite_regeneration.sql ---

DROP FUNCTION IF EXISTS public.generate_user_invite_code();
CREATE OR REPLACE FUNCTION public.generate_user_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_old_invite_id UUID;
    v_old_invite_used BOOLEAN;
    v_new_code TEXT;
    v_invite_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE user_id = v_user_id
          AND is_verified = true
    ) THEN
        RETURN NULL;
    END IF;

    SELECT p.generated_invite_code_id,
           COALESCE(ic.use_count, 0) > 0 OR ic.used_by IS NOT NULL
    INTO v_old_invite_id, v_old_invite_used
    FROM profiles p
    LEFT JOIN invite_codes ic ON ic.id = p.generated_invite_code_id
    WHERE p.user_id = v_user_id
    FOR UPDATE;

    IF v_old_invite_id IS NOT NULL THEN
        IF v_old_invite_used THEN
            RAISE EXCEPTION 'В¦ГЎTГ‚В¦-TГЂTГ‹В¦В¦ В¦В¬В¦-В¦-В¦-В¦В¦TГ‚ TГѓВ¦В¦В¦В¦ В¦В¬TГЃВ¦В¬В¦-В¦В¬TГЊВ¦В¬В¦-В¦-В¦-В¦- ГІГЂГ” В¦В¬В¦В¦TГЂВ¦В¦В¦В¦В¦В¦В¦-В¦В¦TГЂВ¦-TГ†В¦В¬TГЏ В¦В¬В¦-В¦В¬TГЂВ¦В¦TГ‰В¦В¦В¦-В¦-';
        END IF;

        DELETE FROM invite_codes
        WHERE id = v_old_invite_id
          AND created_by = v_user_id
          AND is_admin_code = false
          AND COALESCE(use_count, 0) = 0
          AND used_by IS NULL;
    END IF;

    DELETE FROM invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND COALESCE(use_count, 0) = 0
      AND used_by IS NULL;

    LOOP
        v_new_code := upper(substr(md5(random()::text), 1, 8));

        BEGIN
            INSERT INTO invite_codes (code, created_by, is_admin_code, max_uses, use_count, expires_at)
            VALUES (v_new_code, v_user_id, false, 1, 0, now() + interval '5 minutes')
            RETURNING id INTO v_invite_id;
            EXIT;
        EXCEPTION
            WHEN unique_violation THEN
        END;
    END LOOP;

    UPDATE profiles
    SET has_generated_invite = true,
        generated_invite_code_id = v_invite_id
    WHERE user_id = v_user_id;

    RETURN v_new_code;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_user_invite_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.generate_user_invite_code() FROM anon;
GRANT EXECUTE ON FUNCTION public.generate_user_invite_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_user_invite_code() TO service_role;


-- --- migration_multiuse_and_fixes.sql ---

-- ============================================
-- NeuroBench: Fix FK + Multi-use invites + User deletion
-- ============================================
-- Run this in Supabase SQL Editor

-- 1. Fix FK constraints: SET NULL instead of RESTRICT on delete
--    This prevents "violates foreign key constraint" when deleting users
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_used_invite_code_id_fkey;
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_generated_invite_code_id_fkey;
ALTER TABLE profiles ADD CONSTRAINT profiles_used_invite_code_id_fkey
    FOREIGN KEY (used_invite_code_id) REFERENCES invite_codes(id) ON DELETE SET NULL;
ALTER TABLE profiles ADD CONSTRAINT profiles_generated_invite_code_id_fkey
    FOREIGN KEY (generated_invite_code_id) REFERENCES invite_codes(id) ON DELETE SET NULL;

-- 2. Add multi-use columns to invite_codes
ALTER TABLE invite_codes ADD COLUMN IF NOT EXISTS max_uses INTEGER DEFAULT 1;
ALTER TABLE invite_codes ADD COLUMN IF NOT EXISTS use_count INTEGER DEFAULT 0;

-- 3. Create invite_code_uses table (tracks each use of a code)
CREATE TABLE IF NOT EXISTS invite_code_uses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    invite_code_id UUID REFERENCES invite_codes(id) ON DELETE CASCADE,
    user_id UUID,
    used_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE invite_code_uses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_read_code_uses" ON invite_code_uses;
CREATE POLICY "admin_read_code_uses" ON invite_code_uses
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- 4. Backfill: set use_count based on existing used_by
UPDATE invite_codes SET use_count = 1 WHERE used_by IS NOT NULL AND use_count = 0;
-- Set max_uses = 1 for existing regular codes, NULL (unlimited) for admin codes without limit
UPDATE invite_codes SET max_uses = 1 WHERE is_admin_code = false AND max_uses IS NULL;
UPDATE invite_codes SET max_uses = 10 WHERE is_admin_code = true AND max_uses = 1;

-- 5. Migrate existing used_by into invite_code_uses
INSERT INTO invite_code_uses (invite_code_id, user_id, used_at)
SELECT id, used_by, COALESCE(used_at, created_at)
FROM invite_codes
WHERE used_by IS NOT NULL
ON CONFLICT DO NOTHING;

-- 6. Update claim_invite_code RPC for multi-use codes
DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT);
DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code TEXT;
    v_invite_id UUID;
    v_max_uses INTEGER;
    v_current_uses INTEGER;
BEGIN
    IF p_code IS NOT NULL THEN
        v_code := p_code;
    ELSE
        SELECT pending_invite_code INTO v_code
        FROM profiles WHERE user_id = auth.uid();
    END IF;

    IF v_code IS NULL THEN
        RETURN false;
    END IF;

    SELECT id, max_uses, use_count INTO v_invite_id, v_max_uses, v_current_uses
    FROM invite_codes
    WHERE code = v_code AND (max_uses IS NULL OR use_count < max_uses);

    IF v_invite_id IS NULL THEN
        RETURN false;
    END IF;

    IF EXISTS (SELECT 1 FROM invite_code_uses WHERE invite_code_id = v_invite_id AND user_id = auth.uid()) THEN
        RETURN false;
    END IF;

    UPDATE invite_codes
    SET use_count = use_count + 1,
        used_by = auth.uid(),
        used_at = now()
    WHERE id = v_invite_id;

    INSERT INTO invite_code_uses (invite_code_id, user_id)
    VALUES (v_invite_id, auth.uid());

    UPDATE profiles
    SET is_verified = true,
        used_invite_code_id = v_invite_id,
        pending_invite_code = NULL
    WHERE user_id = auth.uid();

    RETURN true;
END;
$$;

-- 7. Update admin_delete_invite_code: allow deleting, reset owner's has_generated_invite
DROP FUNCTION IF EXISTS public.admin_delete_invite_code(UUID);
CREATE OR REPLACE FUNCTION public.admin_delete_invite_code(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    UPDATE profiles
    SET has_generated_invite = false,
        generated_invite_code_id = NULL
    WHERE generated_invite_code_id = p_id;
    DELETE FROM invite_code_uses WHERE invite_code_id = p_id;
    DELETE FROM invite_codes WHERE id = p_id;
    RETURN FOUND;
END;
$$;

-- 8. Update admin_generate_invite_code: accept max_uses parameter
DROP FUNCTION IF EXISTS public.admin_generate_invite_code();
DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER);
DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.admin_generate_invite_code(p_max_uses INTEGER DEFAULT 10)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_code TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN NULL;
    END IF;

    v_new_code := upper(substr(md5(random()::text), 1, 8));

    INSERT INTO invite_codes (code, created_by, is_admin_code, max_uses)
    VALUES (v_new_code, auth.uid(), true, p_max_uses);

    RETURN v_new_code;
END;
$$;

-- 9. Update RLS: read codes with remaining uses
DROP POLICY IF EXISTS "read_unused_codes" ON invite_codes;
CREATE POLICY "read_unused_codes" ON invite_codes
    FOR SELECT USING (max_uses IS NULL OR use_count < max_uses);

-- 10. Update read_own_codes to also show codes the user used
DROP POLICY IF EXISTS "read_own_codes" ON invite_codes;
CREATE POLICY "read_own_codes" ON invite_codes
    FOR SELECT USING (
        created_by = auth.uid()
        OR EXISTS (SELECT 1 FROM invite_code_uses WHERE invite_code_id = invite_codes.id AND user_id = auth.uid())
    );

-- 11. RPC: Admin get invite code uses (for detailed view)
DROP FUNCTION IF EXISTS public.admin_get_invite_code_uses(UUID);
CREATE OR REPLACE FUNCTION public.admin_get_invite_code_uses(p_code_id UUID)
RETURNS SETOF invite_code_uses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT * FROM invite_code_uses WHERE invite_code_id = p_code_id ORDER BY used_at DESC;
END;
$$;

-- 12. Fix existing telegram profiles that are missing telegram_id
UPDATE profiles p
SET telegram_id = replace(p.email, 'telegram_', ''),
    is_verified = true
WHERE p.email LIKE 'telegram_%@neurobench.local'
  AND p.telegram_id IS NULL;

-- 13. Fix profiles where invite code was deleted but has_generated_invite still true
UPDATE profiles
SET has_generated_invite = false,
    generated_invite_code_id = NULL
WHERE has_generated_invite = true
  AND generated_invite_code_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM invite_codes WHERE id = profiles.generated_invite_code_id);

UPDATE profiles
SET has_generated_invite = false,
    generated_invite_code_id = NULL
WHERE has_generated_invite = true
  AND generated_invite_code_id IS NULL;

-- 14. Update getUserDisplayName to include invite_use_count
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
    invite_use_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT p.telegram_first_name,
           p.telegram_last_name,
           p.telegram_username,
           p.telegram_photo_url,
           COALESCE(p.telegram_first_name, split_part(p.email, '@', 1)) AS display_name,
           p.is_verified,
           p.has_generated_invite,
           ic.code AS generated_code,
           ic.use_count AS invite_use_count
    FROM profiles p
    LEFT JOIN invite_codes ic ON p.generated_invite_code_id = ic.id
    WHERE p.user_id = auth.uid();
END;
$$;

