-- todos may not exist (greenfield) or may exist from the README's single-user design.
CREATE TABLE IF NOT EXISTS public.todos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id      UUID REFERENCES public.lists(id) ON DELETE CASCADE,
  title        TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 280),
  is_complete  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Drop the README's single-user column if a prior environment created it.
ALTER TABLE public.todos DROP COLUMN IF EXISTS user_id;

-- Ensure list_id exists (covers a pre-existing todos table without it), then enforce NOT NULL.
ALTER TABLE public.todos ADD COLUMN IF NOT EXISTS list_id UUID REFERENCES public.lists(id) ON DELETE CASCADE;
ALTER TABLE public.todos ALTER COLUMN list_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS todos_list_id_idx ON public.todos(list_id);
