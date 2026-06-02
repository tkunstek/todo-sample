DROP POLICY IF EXISTS todos_select ON public.todos;
CREATE POLICY todos_select ON public.todos FOR SELECT TO authenticated
  USING (public.can_read_list(list_id));

DROP POLICY IF EXISTS todos_insert ON public.todos;
CREATE POLICY todos_insert ON public.todos FOR INSERT TO authenticated
  WITH CHECK (public.can_write_list(list_id));

DROP POLICY IF EXISTS todos_update ON public.todos;
CREATE POLICY todos_update ON public.todos FOR UPDATE TO authenticated
  USING (public.can_write_list(list_id))
  WITH CHECK (public.can_write_list(list_id));

DROP POLICY IF EXISTS todos_delete ON public.todos;
CREATE POLICY todos_delete ON public.todos FOR DELETE TO authenticated
  USING (public.can_write_list(list_id));
