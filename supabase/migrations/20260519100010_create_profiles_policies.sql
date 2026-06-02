-- SELECT: own org, or super admin sees all.
DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated
  USING (org_id = public.current_org_id() OR public.is_super_admin());

-- UPDATE: only your own row by identity...
DROP POLICY IF EXISTS profiles_update ON public.profiles;
CREATE POLICY profiles_update ON public.profiles FOR UPDATE TO authenticated
  USING (id = (select auth.uid()))
  WITH CHECK (id = (select auth.uid()));

-- DELETE: super admin only.
DROP POLICY IF EXISTS profiles_delete ON public.profiles;
CREATE POLICY profiles_delete ON public.profiles FOR DELETE TO authenticated
  USING (public.is_super_admin());

-- No INSERT policy: profiles are created by service role only.

-- Column-level enforcement (Codex #6): the actual guard on role/org_id/is_super_admin tampering.
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (display_name, updated_at) ON public.profiles TO authenticated;
