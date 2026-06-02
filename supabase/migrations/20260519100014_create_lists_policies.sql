-- SELECT
DROP POLICY IF EXISTS lists_select ON public.lists;
CREATE POLICY lists_select ON public.lists FOR SELECT TO authenticated
  USING (
    owner_user_id = (select auth.uid())
    OR (owner_team_id IS NOT NULL AND public.is_team_member(owner_team_id))
    OR (public.is_org_admin() AND org_id = public.current_org_id())
    OR public.is_super_admin()
  );

-- INSERT (org-admin clause intentionally restricted to TEAM lists)
DROP POLICY IF EXISTS lists_insert ON public.lists;
CREATE POLICY lists_insert ON public.lists FOR INSERT TO authenticated
  WITH CHECK (
    (owner_user_id = (select auth.uid()) AND owner_team_id IS NULL)
    OR (owner_team_id IS NOT NULL AND owner_user_id IS NULL AND public.is_team_member(owner_team_id))
    OR (owner_team_id IS NOT NULL AND owner_user_id IS NULL
        AND public.is_org_admin() AND org_id = public.current_org_id())
    OR public.is_super_admin()
  );

-- UPDATE (no org-admin-on-personal clause: read-only rule)
DROP POLICY IF EXISTS lists_update ON public.lists;
CREATE POLICY lists_update ON public.lists FOR UPDATE TO authenticated
  USING (
    owner_user_id = (select auth.uid())
    OR (owner_team_id IS NOT NULL AND public.is_team_member(owner_team_id))
    OR (owner_team_id IS NOT NULL AND public.is_org_admin() AND org_id = public.current_org_id())
    OR public.is_super_admin()
  )
  WITH CHECK (
    owner_user_id = (select auth.uid())
    OR (owner_team_id IS NOT NULL AND public.is_team_member(owner_team_id))
    OR (owner_team_id IS NOT NULL AND public.is_org_admin() AND org_id = public.current_org_id())
    OR public.is_super_admin()
  );

-- DELETE (team lists: creator OR org admin; personal: owner only)
DROP POLICY IF EXISTS lists_delete ON public.lists;
CREATE POLICY lists_delete ON public.lists FOR DELETE TO authenticated
  USING (
    owner_user_id = (select auth.uid())
    OR (owner_team_id IS NOT NULL AND created_by = (select auth.uid()))
    OR (owner_team_id IS NOT NULL AND public.is_org_admin() AND org_id = public.current_org_id())
    OR public.is_super_admin()
  );
