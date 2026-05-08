-- Fix is_moderator() to check profiles.role in addition to moderators table
CREATE OR REPLACE FUNCTION public.is_moderator()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role FROM profiles WHERE user_id = auth.uid();
    IF v_role IN ('admin', 'stmoderator', 'moderator') THEN
        RETURN true;
    END IF;
    RETURN EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid());
END;
$$;
