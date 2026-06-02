DROP POLICY IF EXISTS teams_select ON public.teams;
CREATE POLICY teams_select ON public.teams FOR SELECT TO authenticated
  USING (org_id = public.current_org_id() OR public.is_super_admin());

DROP POLICY IF EXISTS teams_insert ON public.teams;
CREATE POLICY teams_insert ON public.teams FOR INSERT TO authenticated
  WITH CHECK (public.is_super_admin() OR (public.is_org_admin() AND org_id = public.current_org_id()));

DROP POLICY IF EXISTS teams_update ON public.teams;
CREATE POLICY teams_update ON public.teams FOR UPDATE TO authenticated
  USING (public.is_super_admin() OR (public.is_org_admin() AND org_id = public.current_org_id()))
  WITH CHECK (public.is_super_admin() OR (public.is_org_admin() AND org_id = public.current_org_id()));

DROP POLICY IF EXISTS teams_delete ON public.teams;
CREATE POLICY teams_delete ON public.teams FOR DELETE TO authenticated
  USING (public.is_super_admin() OR (public.is_org_admin() AND org_id = public.current_org_id()));
