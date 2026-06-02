-- Codex #14: ordinary roles must not be able to create objects (incl. replacing helpers).
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.is_super_admin() RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE((SELECT is_super_admin FROM public.profiles WHERE id = auth.uid()), false)
$$;

CREATE OR REPLACE FUNCTION public.is_org_admin() RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'org_admin')
$$;

CREATE OR REPLACE FUNCTION public.current_org_id() RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT org_id FROM public.profiles WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.is_team_member(p_team_id UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.team_members WHERE team_id = p_team_id AND user_id = auth.uid())
$$;

CREATE OR REPLACE FUNCTION public.can_read_list(p_list_id UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.lists l
    WHERE l.id = p_list_id AND (
      l.owner_user_id = auth.uid()
      OR (l.owner_team_id IS NOT NULL AND public.is_team_member(l.owner_team_id))
      OR (public.is_org_admin() AND l.org_id = public.current_org_id())
      OR public.is_super_admin()
    )
  )
$$;

-- Narrower than can_read_list: org admin does NOT get write access to personal lists.
CREATE OR REPLACE FUNCTION public.can_write_list(p_list_id UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.lists l
    WHERE l.id = p_list_id AND (
      l.owner_user_id = auth.uid()
      OR (l.owner_team_id IS NOT NULL AND public.is_team_member(l.owner_team_id))
      OR (l.owner_team_id IS NOT NULL AND public.is_org_admin() AND l.org_id = public.current_org_id())
      OR public.is_super_admin()
    )
  )
$$;

-- Codex #4: BOTH the team AND the target user must be in the actor's org.
CREATE OR REPLACE FUNCTION public.can_manage_team_member(p_team_id UUID, p_user_id UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_super_admin()
    OR (
      public.is_org_admin()
      AND EXISTS (SELECT 1 FROM public.teams t    WHERE t.id = p_team_id AND t.org_id = public.current_org_id())
      AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_user_id AND p.org_id = public.current_org_id())
    )
$$;

-- Helpers are callable only by authenticated; never by anon/PUBLIC.
REVOKE EXECUTE ON FUNCTION
  public.is_super_admin(), public.is_org_admin(), public.current_org_id(),
  public.is_team_member(UUID), public.can_read_list(UUID), public.can_write_list(UUID),
  public.can_manage_team_member(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  public.is_super_admin(), public.is_org_admin(), public.current_org_id(),
  public.is_team_member(UUID), public.can_read_list(UUID), public.can_write_list(UUID),
  public.can_manage_team_member(UUID, UUID)
TO authenticated;
