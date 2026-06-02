DROP POLICY IF EXISTS team_members_select ON public.team_members;
CREATE POLICY team_members_select ON public.team_members FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR EXISTS (SELECT 1 FROM public.teams t WHERE t.id = team_id AND t.org_id = public.current_org_id())
  );

-- Codex #4: both team AND user must be in the actor's org.
DROP POLICY IF EXISTS team_members_insert ON public.team_members;
CREATE POLICY team_members_insert ON public.team_members FOR INSERT TO authenticated
  WITH CHECK (public.can_manage_team_member(team_id, user_id));

DROP POLICY IF EXISTS team_members_delete ON public.team_members;
CREATE POLICY team_members_delete ON public.team_members FOR DELETE TO authenticated
  USING (public.can_manage_team_member(team_id, user_id));

-- No UPDATE policy: no mutable columns beyond joined_at.
