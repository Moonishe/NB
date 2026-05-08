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
            RAISE EXCEPTION 'Старый инвайт уже использован — перегенерация запрещена';
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
