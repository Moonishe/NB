CREATE OR REPLACE FUNCTION public.admin_delete_invite_code(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite public.invite_codes%ROWTYPE;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN false;
    END IF;

    IF p_id IS NULL THEN
        RETURN false;
    END IF;

    SELECT * INTO v_invite
    FROM public.invite_codes
    WHERE id = p_id
    FOR UPDATE;

    IF v_invite.id IS NULL THEN
        RETURN false;
    END IF;

    IF COALESCE(v_invite.use_count, 0) > 0 OR v_invite.used_by IS NOT NULL THEN
        RAISE EXCEPTION 'Нельзя удалить использованный инвайт';
    END IF;

    UPDATE public.profiles
    SET has_generated_invite = false,
        generated_invite_code_id = NULL
    WHERE generated_invite_code_id = p_id;

    DELETE FROM public.invite_codes
    WHERE id = p_id;

    RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) TO service_role;
