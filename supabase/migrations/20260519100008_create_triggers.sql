-- Generic updated_at bump.
CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END $$;

-- Derive lists.org_id from the owner (client cannot set it).
CREATE OR REPLACE FUNCTION public.lists_set_org_id_from_owner() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.owner_user_id IS NOT NULL THEN
    NEW.org_id := (SELECT org_id FROM public.profiles WHERE id = NEW.owner_user_id);
  ELSIF NEW.owner_team_id IS NOT NULL THEN
    NEW.org_id := (SELECT org_id FROM public.teams WHERE id = NEW.owner_team_id);
  END IF;
  RETURN NEW;
END $$;

-- Capture creator from the JWT; always override the client.
CREATE OR REPLACE FUNCTION public.lists_set_created_by() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.created_by := auth.uid();
  RETURN NEW;
END $$;

-- Codex #9: forbid reparenting; allow the ON DELETE SET NULL cascade on created_by.
CREATE OR REPLACE FUNCTION public.lists_forbid_owner_change() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id
     OR NEW.owner_team_id IS DISTINCT FROM OLD.owner_team_id
     OR NEW.org_id        IS DISTINCT FROM OLD.org_id THEN
    RAISE EXCEPTION 'lists: owner/org are immutable';
  END IF;
  IF NEW.created_by IS DISTINCT FROM OLD.created_by AND NEW.created_by IS NOT NULL THEN
    RAISE EXCEPTION 'lists: created_by cannot be reassigned';
  END IF;
  RETURN NEW;
END $$;

-- team_members: user and team must share an org (defense vs service-role bugs).
CREATE OR REPLACE FUNCTION public.team_members_enforce_same_org() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT org_id FROM public.profiles WHERE id = NEW.user_id)
     <> (SELECT org_id FROM public.teams WHERE id = NEW.team_id) THEN
    RAISE EXCEPTION 'team_members: user and team must belong to the same org';
  END IF;
  RETURN NEW;
END $$;

-- updated_at triggers on all five mutable tables.
DROP TRIGGER IF EXISTS set_updated_at ON public.organizations;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON public.profiles;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON public.teams;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.teams
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON public.lists;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.lists
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON public.todos;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.todos
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- lists insert derivations.
DROP TRIGGER IF EXISTS lists_set_org_id ON public.lists;
CREATE TRIGGER lists_set_org_id BEFORE INSERT ON public.lists
  FOR EACH ROW EXECUTE FUNCTION public.lists_set_org_id_from_owner();
DROP TRIGGER IF EXISTS lists_set_created_by ON public.lists;
CREATE TRIGGER lists_set_created_by BEFORE INSERT ON public.lists
  FOR EACH ROW EXECUTE FUNCTION public.lists_set_created_by();

-- lists update guard.
DROP TRIGGER IF EXISTS lists_forbid_owner_change ON public.lists;
CREATE TRIGGER lists_forbid_owner_change BEFORE UPDATE ON public.lists
  FOR EACH ROW EXECUTE FUNCTION public.lists_forbid_owner_change();

-- team_members guard.
DROP TRIGGER IF EXISTS team_members_enforce_same_org ON public.team_members;
CREATE TRIGGER team_members_enforce_same_org BEFORE INSERT ON public.team_members
  FOR EACH ROW EXECUTE FUNCTION public.team_members_enforce_same_org();
