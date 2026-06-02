CREATE TABLE IF NOT EXISTS public.lists (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  owner_user_id   UUID NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  owner_team_id   UUID NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  created_by      UUID NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  name            TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT lists_owner_xor CHECK ((owner_user_id IS NOT NULL) <> (owner_team_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS lists_org_id_idx        ON public.lists(org_id);
CREATE INDEX IF NOT EXISTS lists_owner_user_id_idx ON public.lists(owner_user_id) WHERE owner_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS lists_owner_team_id_idx ON public.lists(owner_team_id) WHERE owner_team_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS lists_created_by_idx    ON public.lists(created_by);
