-- ==========================================
-- Admin audit log table
-- ==========================================
CREATE TABLE IF NOT EXISTS public.admin_actions (
    id          BIGSERIAL PRIMARY KEY,
    actor_id    UUID NOT NULL,
    action      TEXT NOT NULL,
    target_id   UUID,
    payload     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_read_actions" ON public.admin_actions
    FOR SELECT USING (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()));

CREATE POLICY "service_insert_actions" ON public.admin_actions
    FOR INSERT WITH CHECK (true);
