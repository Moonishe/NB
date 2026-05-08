-- Fix: allow moderators without telegram_id + fix RETURN FOUND issue
-- Run this in Supabase SQL Editor

ALTER TABLE moderators ALTER COLUMN telegram_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.admin_assign_moderator(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tg_id TEXT;
    v_tg_username TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = p_user_id) THEN
        RETURN false;
    END IF;
    SELECT telegram_id, telegram_username INTO v_tg_id, v_tg_username FROM profiles WHERE user_id = p_user_id;
    INSERT INTO moderators (user_id, telegram_id, telegram_username, assigned_by)
    VALUES (p_user_id, v_tg_id, v_tg_username, auth.uid())
    ON CONFLICT (user_id) DO NOTHING;
    RETURN EXISTS (SELECT 1 FROM moderators WHERE user_id = p_user_id);
END;
$$;

NOTIFY pgrst, 'reload schema';
