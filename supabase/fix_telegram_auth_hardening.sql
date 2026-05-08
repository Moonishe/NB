-- Telegram auth hardening: DB-backed rate limit for the Edge Function.
-- Run this before deploying supabase/functions/telegram-auth/index.ts.

CREATE TABLE IF NOT EXISTS public.telegram_auth_rate_limits (
    identifier TEXT PRIMARY KEY,
    attempts INTEGER NOT NULL DEFAULT 0,
    window_started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.telegram_auth_rate_limits ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.telegram_auth_rate_limits FROM PUBLIC;
REVOKE ALL ON TABLE public.telegram_auth_rate_limits FROM anon;
REVOKE ALL ON TABLE public.telegram_auth_rate_limits FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.telegram_auth_rate_limits TO service_role;

CREATE INDEX IF NOT EXISTS idx_telegram_auth_rate_limits_updated_at
    ON public.telegram_auth_rate_limits (updated_at);

CREATE OR REPLACE FUNCTION public.check_telegram_auth_rate_limit(
    p_identifier TEXT,
    p_max_attempts INTEGER DEFAULT 20,
    p_window_seconds INTEGER DEFAULT 300
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := now();
    v_window INTERVAL := make_interval(secs => GREATEST(1, COALESCE(p_window_seconds, 300)));
    v_attempts INTEGER;
BEGIN
    IF COALESCE(btrim(p_identifier), '') = '' THEN
        RETURN false;
    END IF;

    IF COALESCE(p_max_attempts, 0) <= 0 THEN
        RETURN false;
    END IF;

    INSERT INTO public.telegram_auth_rate_limits AS rl (
        identifier,
        attempts,
        window_started_at,
        updated_at
    )
    VALUES (
        p_identifier,
        1,
        v_now,
        v_now
    )
    ON CONFLICT (identifier) DO UPDATE
    SET attempts = CASE
            WHEN rl.window_started_at <= v_now - v_window THEN 1
            ELSE rl.attempts + 1
        END,
        window_started_at = CASE
            WHEN rl.window_started_at <= v_now - v_window THEN v_now
            ELSE rl.window_started_at
        END,
        updated_at = v_now
    RETURNING attempts INTO v_attempts;

    DELETE FROM public.telegram_auth_rate_limits
    WHERE updated_at < v_now - interval '1 day';

    RETURN v_attempts <= p_max_attempts;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION public.get_auth_user_id_by_email(p_email TEXT)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.id
    FROM auth.users AS u
    WHERE lower(u.email) = lower(btrim(p_email))
    LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) TO service_role;

NOTIFY pgrst, 'reload schema';
