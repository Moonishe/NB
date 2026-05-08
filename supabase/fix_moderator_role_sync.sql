-- Fix admin_assign_moderator and admin_remove_moderator to sync profiles.role

CREATE OR REPLACE FUNCTION public.admin_assign_moderator(p_user_id UUID, p_telegram_id BIGINT DEFAULT NULL, p_telegram_username TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO moderators (user_id, telegram_id, telegram_username, assigned_by)
    VALUES (p_user_id, p_telegram_id, p_telegram_username, auth.uid())
    ON CONFLICT (user_id) DO UPDATE SET
        telegram_id = EXCLUDED.telegram_id,
        telegram_username = EXCLUDED.telegram_username,
        assigned_by = EXCLUDED.assigned_by;

    UPDATE profiles SET role = 'moderator' WHERE user_id = p_user_id AND role = 'member';
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_moderator(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM moderators WHERE user_id = p_user_id;
    IF FOUND THEN
        UPDATE profiles SET role = 'member' WHERE user_id = p_user_id AND role = 'moderator';
        RETURN true;
    END IF;
    RETURN false;
END;
$$;
