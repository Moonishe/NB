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
--    In Supabase Dashboard → Edge Functions → Secrets:
--    - TELEGRAM_BOT_TOKEN = <your bot token from step 1>
--    - SESSION_SECRET = <random 32+ char string, e.g. openssl rand -hex 32>
--    The SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
--    are auto-provided by Supabase.
--
-- 4. DEPLOY EDGE FUNCTION:
--    Option A (CLI): supabase functions deploy telegram-auth
--    Option B (Dashboard): Supabase → Edge Functions → New Function
--      → Name: telegram-auth → Paste code from supabase/functions/telegram-auth/index.ts
--
-- 5. UPDATE js/config.js:
--    Set window.TELEGRAM_BOT_USERNAME = 'your_bot_username'  (without @)
--
-- 6. KEEP EMAIL AUTH ENABLED:
--    Do NOT disable email auth in Supabase Dashboard — the admin panel
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
