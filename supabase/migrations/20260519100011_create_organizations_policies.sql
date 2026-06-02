DROP POLICY IF EXISTS organizations_select ON public.organizations;
CREATE POLICY organizations_select ON public.organizations FOR SELECT TO authenticated
  USING (id = public.current_org_id() OR public.is_super_admin());

DROP POLICY IF EXISTS organizations_insert ON public.organizations;
CREATE POLICY organizations_insert ON public.organizations FOR INSERT TO authenticated
  WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS organizations_update ON public.organizations;
CREATE POLICY organizations_update ON public.organizations FOR UPDATE TO authenticated
  USING (public.is_super_admin() OR (public.is_org_admin() AND id = public.current_org_id()))
  WITH CHECK (public.is_super_admin() OR (public.is_org_admin() AND id = public.current_org_id()));

DROP POLICY IF EXISTS organizations_delete ON public.organizations;
CREATE POLICY organizations_delete ON public.organizations FOR DELETE TO authenticated
  USING (public.is_super_admin());
