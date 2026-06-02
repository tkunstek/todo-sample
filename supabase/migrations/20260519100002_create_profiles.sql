CREATE TABLE IF NOT EXISTS public.profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  org_id          UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member','org_admin')),
  is_super_admin  BOOLEAN NOT NULL DEFAULT FALSE,
  display_name    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS profiles_org_id_idx ON public.profiles(org_id);
CREATE INDEX IF NOT EXISTS profiles_is_super_admin_idx ON public.profiles(is_super_admin) WHERE is_super_admin;
