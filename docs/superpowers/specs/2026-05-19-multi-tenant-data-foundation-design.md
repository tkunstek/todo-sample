# Multi-tenant data foundation + RLS — Design

**Date:** 2026-05-19
**Sub-project:** A (of a six-sub-project program — see "Program context" below)
**Status:** Approved, ready for implementation planning

## Program context

The user is extending `d2-todo-sample` from its README-described single-user todo app into a multi-tenant system with three roles (super admin, org admin, member), organizations, teams, and lists that todos hang off of. The full program decomposes into six sub-projects, each with its own spec → plan → implementation cycle:

| | Sub-project | Depends on |
|---|---|---|
| A | **Multi-tenant data foundation + RLS** *(this spec)* + Netlify deploy bundle | — |
| B | Auth + role context (frontend) | A |
| C | List + todo UX, tenant-scoped | A, B |
| D | Org admin console (user invitation, team/membership management) | A, B |
| E | Super admin console (org creation, cross-org browse) | A, B |
| F | (folded into A) Netlify deployment | — |

Sub-project A is the bedrock. Nothing else can be built, let alone validated, without it.

## What this sub-project delivers

1. The complete database schema (six tables) with constraints, triggers, and indexes.
2. SECURITY DEFINER helper functions used by RLS policies.
3. RLS policies on all six tables, per-operation, scoped `TO authenticated`.
4. A one-time bootstrap migration that seeds the first organization + super admin from an env-supplied UID.
5. A verification script (`npm run verify:rls`) that proves tenant isolation against a real Supabase project using real JWTs.
6. A minimal Vite + React skeleton (`index.html`, `src/main.tsx`, placeholder `App.tsx`) and `netlify.toml` so the deploy pipeline is wired end-to-end before sub-project B replaces the app shell.
7. Regenerated `src/types/database.types.ts` committed alongside the migrations.

## Explicitly out of scope

- Any React UI beyond the single Netlify-validation placeholder page.
- `AuthContext` and route guards (sub-project B).
- The list/todo UX (sub-project C).
- User invitation, team management, role promotion flows (sub-projects D / E). The bootstrap migration is the *only* mechanism in this sub-project for putting a user into an org or promoting a super admin; everything else stays service-role / dashboard-only until D / E.

## Architecture decisions

These are the load-bearing calls; the rationale is preserved here so future Claude sessions don't relitigate them.

### One org per user → `profiles.org_id` (not a memberships table)

Each user belongs to exactly one organization. Modeled as a non-null FK on `profiles`, not as a `memberships` join table. If the program ever needs multi-org users, this becomes the join. Until then, the simpler shape is correct.

### Polymorphic list owner → two nullable FKs + XOR check

`lists.owner_user_id` and `lists.owner_team_id` are both nullable, with `CHECK ((owner_user_id IS NOT NULL) <> (owner_team_id IS NOT NULL))`. Rejected the `owner_type TEXT + owner_id UUID` alternative because it loses FK enforcement, breaks cascade-delete, and forces RLS to branch on a string. Two columns for one concept is the price; the wins are worth it.

### `lists.org_id` denormalized, `todos.org_id` not

`lists.org_id` is denormalized from the owner (filled by trigger) so the org-admin policy can be `org_id = current_org_id()` — a single indexed comparison instead of a two-hop subquery on every read. `todos` always scope through `list_id`, the join via the `(list_id)` index is cheap, and skipping denorm there keeps the hottest table minimal.

### `role` lives on `profiles` directly

`profiles.role TEXT CHECK (role IN ('member','org_admin'))`. Only safe because of "one org per user". Becomes a join-table column if that ever changes.

### Hard-delete (cascade) everywhere

Cascade graph: org delete → teams, profiles, lists cascade; team delete → team_members and team-owned lists cascade; profile delete → personal lists, team_members cascade; list delete → todos cascade. Soft-delete was rejected — this sample doesn't need audit/restore, and the cascade graph is clean enough that re-deriving it after the fact would be more work than living with hard-delete from the start.

### `profiles.org_id` is NOT NULL — no "limbo profile"

A user never exists in the system without an org. Profile rows are created server-side by service role during the invite flow (sub-project D) with the org already set. The very first super admin + first org are seeded by a one-shot bootstrap migration that takes a UID from an env var. There is no in-app sign-up.

## Schema

```sql
-- ============================================================
-- organizations
-- ============================================================
CREATE TABLE public.organizations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- profiles  (1:1 with auth.users; one org per user)
-- ============================================================
CREATE TABLE public.profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  org_id          UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  role            TEXT NOT NULL DEFAULT 'member'
                    CHECK (role IN ('member','org_admin')),
  is_super_admin  BOOLEAN NOT NULL DEFAULT FALSE,
  display_name    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX profiles_org_id_idx ON public.profiles(org_id);
CREATE INDEX profiles_is_super_admin_idx ON public.profiles(is_super_admin)
  WHERE is_super_admin;

-- ============================================================
-- teams
-- ============================================================
CREATE TABLE public.teams (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (org_id, name)
);

CREATE INDEX teams_org_id_idx ON public.teams(org_id);

-- ============================================================
-- team_members  (user ↔ team within an org; many teams per user)
-- ============================================================
CREATE TABLE public.team_members (
  team_id    UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (team_id, user_id)
);

CREATE INDEX team_members_user_id_idx ON public.team_members(user_id);

-- ============================================================
-- lists  (polymorphic owner: user XOR team)
-- ============================================================
CREATE TABLE public.lists (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  owner_user_id   UUID NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  owner_team_id   UUID NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  created_by      UUID NOT NULL REFERENCES public.profiles(id),
  name            TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((owner_user_id IS NOT NULL) <> (owner_team_id IS NOT NULL))
);

CREATE INDEX lists_org_id_idx        ON public.lists(org_id);
CREATE INDEX lists_owner_user_id_idx ON public.lists(owner_user_id) WHERE owner_user_id IS NOT NULL;
CREATE INDEX lists_owner_team_id_idx ON public.lists(owner_team_id) WHERE owner_team_id IS NOT NULL;
CREATE INDEX lists_created_by_idx    ON public.lists(created_by);

-- ============================================================
-- todos  (now hangs off list_id; no direct user_id or org_id)
-- ============================================================
CREATE TABLE public.todos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id      UUID NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  title        TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 280),
  is_complete  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX todos_list_id_idx ON public.todos(list_id);
```

Note that the README's earlier `todos.user_id` is gone entirely. All scope for todos flows through `list_id → lists.org_id` and `list_id → lists.owner_{user,team}_id`. This is the central simplification the "lists" abstraction buys us.

## SECURITY DEFINER helpers

RLS policies on `profiles`, `team_members`, and `lists` need to *read* those same tables to compute the predicate. Doing this directly causes recursion / permission-denied. The fix is small, audited, `SECURITY DEFINER STABLE` helper functions that run with the owner's privileges (bypassing RLS internally), exposed only as boolean / UUID return values.

All helpers:
- `LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = ''`
- Reference `auth.uid()` internally — never accept a user-id parameter, so callers cannot impersonate.
- `GRANT EXECUTE ... TO authenticated`; `REVOKE EXECUTE ... FROM PUBLIC`.

```sql
CREATE FUNCTION public.is_super_admin() RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(
    (SELECT is_super_admin FROM public.profiles WHERE id = auth.uid()),
    false
  )
$$;

CREATE FUNCTION public.is_org_admin() RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'org_admin'
  )
$$;

CREATE FUNCTION public.current_org_id() RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT org_id FROM public.profiles WHERE id = auth.uid()
$$;

CREATE FUNCTION public.is_team_member(p_team_id UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.team_members
    WHERE team_id = p_team_id AND user_id = auth.uid()
  )
$$;

-- Encapsulates the lists SELECT predicate so todos policies can delegate cleanly.
CREATE FUNCTION public.can_read_list(p_list_id UUID) RETURNS BOOLEAN
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
CREATE FUNCTION public.can_write_list(p_list_id UUID) RETURNS BOOLEAN
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
```

The asymmetry between `can_read_list` and `can_write_list` is the SQL realization of the policy decision "org admin sees personal lists, but read-only."

## RLS policies

Every policy below is `TO authenticated`. Anonymous role has no access to anything.

### Conventions

- All references to `auth.uid()` inside a policy expression use the subselect form: `(select auth.uid())`. Postgres caches it once per query instead of evaluating per row. This is convention across the project.
- One policy per operation per table. No combined / ALL policies. This makes each access decision separately auditable.
- Policies on profiles / team_members / lists that need to read those tables themselves go through the SECURITY DEFINER helpers above, not direct subqueries.

### `profiles`

| Op | USING / WITH CHECK |
|---|---|
| SELECT | `org_id = public.current_org_id() OR public.is_super_admin()` |
| INSERT | *no policy* — service role only |
| UPDATE | USING: `id = (select auth.uid())`<br>WITH CHECK: `id = (select auth.uid())`<br>+ column-level: `REVOKE UPDATE ON profiles FROM authenticated; GRANT UPDATE (display_name, updated_at) ON profiles TO authenticated;` |
| DELETE | `public.is_super_admin()` |

The column-level grant is the actual enforcement on role/org_id/is_super_admin tampering. The RLS UPDATE policy permits self-update by row identity; the grant restricts which columns can be sent. Either alone would be insufficient.

### `organizations`

| Op | USING / WITH CHECK |
|---|---|
| SELECT | `id = public.current_org_id() OR public.is_super_admin()` |
| INSERT | WITH CHECK: `public.is_super_admin()` |
| UPDATE | USING: `public.is_super_admin() OR (public.is_org_admin() AND id = public.current_org_id())`<br>WITH CHECK: same |
| DELETE | USING: `public.is_super_admin()` |

### `teams`

| Op | USING / WITH CHECK |
|---|---|
| SELECT | `org_id = public.current_org_id() OR public.is_super_admin()` |
| INSERT | WITH CHECK: `public.is_super_admin() OR (public.is_org_admin() AND org_id = public.current_org_id())` |
| UPDATE | USING / WITH CHECK: same as INSERT |
| DELETE | USING: same as INSERT |

### `team_members`

| Op | USING / WITH CHECK |
|---|---|
| SELECT | `public.is_super_admin() OR EXISTS (SELECT 1 FROM public.teams t WHERE t.id = team_id AND t.org_id = public.current_org_id())` |
| INSERT | WITH CHECK: `public.is_super_admin() OR (public.is_org_admin() AND EXISTS (SELECT 1 FROM public.teams t WHERE t.id = team_id AND t.org_id = public.current_org_id()))` |
| DELETE | USING: same predicate as INSERT |
| UPDATE | *no policy* — no mutable columns besides joined_at, no use case |

The `EXISTS` join into `teams` does not need a SECURITY DEFINER helper because the inner select runs subject to its own table's RLS (teams.SELECT), which is already permissive for own-org. The join still works for org admins because they can see their org's teams.

### `lists`

```
-- SELECT
USING:
  owner_user_id = (select auth.uid())
  OR (owner_team_id IS NOT NULL AND public.is_team_member(owner_team_id))
  OR (public.is_org_admin() AND org_id = public.current_org_id())
  OR public.is_super_admin()

-- INSERT
WITH CHECK:
  (owner_user_id = (select auth.uid()) AND owner_team_id IS NULL)
  OR (owner_team_id IS NOT NULL AND owner_user_id IS NULL AND public.is_team_member(owner_team_id))
  OR (owner_team_id IS NOT NULL AND owner_user_id IS NULL
      AND public.is_org_admin() AND org_id = public.current_org_id())
  OR public.is_super_admin()

-- Note: the org-admin INSERT clause is intentionally restricted to TEAM lists.
-- A broader "org_admin AND org_id = current_org_id()" would let an org admin
-- create a *personal* list owned by another user (org_id is trigger-filled
-- from owner_user_id.org_id, so the check would pass). Per Q7, org admins
-- have read-only access to others' personal lists; creating one for someone
-- else lands in that read-only zone immediately, which is more confusing than
-- useful. Personal lists are created only by their owner (or super admin).

-- UPDATE
USING:
  owner_user_id = (select auth.uid())
  OR (owner_team_id IS NOT NULL AND public.is_team_member(owner_team_id))
  OR (owner_team_id IS NOT NULL AND public.is_org_admin() AND org_id = public.current_org_id())
  OR public.is_super_admin()
WITH CHECK: same as USING

-- DELETE
USING:
  owner_user_id = (select auth.uid())
  OR (owner_team_id IS NOT NULL AND created_by = (select auth.uid()))
  OR (owner_team_id IS NOT NULL AND public.is_org_admin() AND org_id = public.current_org_id())
  OR public.is_super_admin()
```

The UPDATE predicate omits the "org admin on personal list" clause that SELECT has — that's the read-only-for-org-admins rule from Q7. The DELETE predicate further narrows to "creator OR org admin" for team lists — that's the policy from Q5. Personal lists: only the owner (or super admin) can delete.

### `todos`

```
-- SELECT
USING: public.can_read_list(list_id)

-- INSERT
WITH CHECK: public.can_write_list(list_id)

-- UPDATE
USING / WITH CHECK: public.can_write_list(list_id)

-- DELETE
USING: public.can_write_list(list_id)
```

All access decisions delegate to the helpers, so future policy changes on lists automatically propagate to todos.

## Triggers

1. **`set_updated_at_trigger`** — generic. Applied to profiles, organizations, teams, lists, todos. Updates `updated_at = NOW()` on row-level updates.

2. **`lists_set_org_id_from_owner` BEFORE INSERT**
   ```sql
   IF NEW.owner_user_id IS NOT NULL THEN
     NEW.org_id := (SELECT org_id FROM public.profiles WHERE id = NEW.owner_user_id);
   ELSIF NEW.owner_team_id IS NOT NULL THEN
     NEW.org_id := (SELECT org_id FROM public.teams WHERE id = NEW.owner_team_id);
   END IF;
   ```
   Clients cannot set `org_id` directly; it's derived. The XOR check on `lists` guarantees exactly one of the owners is set.

3. **`lists_set_created_by` BEFORE INSERT** — `NEW.created_by := auth.uid()`. Always overrides whatever the client sent.

4. **`lists_forbid_owner_change` BEFORE UPDATE** — rejects with an exception if any of `owner_user_id`, `owner_team_id`, `org_id`, `created_by` changed between OLD and NEW. Renames are fine; reparenting is not.

5. **`team_members_enforce_same_org` BEFORE INSERT**
   ```sql
   IF (SELECT org_id FROM public.profiles WHERE id = NEW.user_id)
      <> (SELECT org_id FROM public.teams WHERE id = NEW.team_id) THEN
     RAISE EXCEPTION 'team_members: user and team must belong to the same org';
   END IF;
   ```
   Defense against bugs in service-role code; RLS alone doesn't catch this case because service role bypasses RLS.

## Migration file layout

Cloud-only (no local Postgres). Each migration is its own file, append-only, idempotent. Order matters because later migrations reference earlier objects.

```
supabase/migrations/
  20260519100001_create_organizations.sql
  20260519100002_create_profiles.sql
  20260519100003_create_teams.sql
  20260519100004_create_team_members.sql
  20260519100005_create_lists.sql
  20260519100006_alter_todos_for_lists.sql
  20260519100007_create_rls_helpers.sql
  20260519100008_enable_rls.sql
  20260519100009_create_profiles_policies.sql
  20260519100010_create_organizations_policies.sql
  20260519100011_create_teams_policies.sql
  20260519100012_create_team_members_policies.sql
  20260519100013_create_lists_policies.sql
  20260519100014_create_todos_policies.sql
  20260519100015_create_triggers.sql
  20260519100016_bootstrap_first_super_admin.sql
```

The `alter_todos_for_lists` migration drops the README's planned `user_id` column from todos (if it existed) and adds the `list_id` FK. Since no todos exist yet in any deployed environment, the migration can `ALTER TABLE ... DROP COLUMN IF EXISTS user_id` without a data backfill.

`bootstrap_first_super_admin.sql` reads two psql variables (`:super_admin_uid`, `:first_org_name`), creates the seed org, and inserts a profile pointing at the auth.users UID with `is_super_admin = true` and `role = 'org_admin'`. Run via `psql -v super_admin_uid='...' -v first_org_name='...' -f ...` after first deploy. The migration must be idempotent (`ON CONFLICT DO NOTHING`).

## Bootstrap procedure

The full deploy-to-running-system sequence, executed once per environment:

1. Create a new Supabase project in the dashboard.
2. `supabase link --project-ref <ref>`.
3. `npm run supabase:apply` — pushes migrations 1–15. Migration 16 is skipped here because it requires a UID.
4. In the Supabase dashboard, sign up the first super admin via Auth → Users (email + password).
5. Copy that user's UID from the dashboard.
6. Run migration 16 manually: `psql $SUPABASE_DB_URL -v super_admin_uid='<uid>' -v first_org_name='System' -f supabase/migrations/20260519100016_bootstrap_first_super_admin.sql`.
7. `npm run gen:types` — regenerate `src/types/database.types.ts`. Commit alongside the migrations.
8. Create a Netlify site from the repo. Set env vars: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`. Trigger a deploy.
9. Visit the deployed URL. The placeholder page should render "anonymous read of lists returned: 0 rows" — proving the deploy works and RLS rejects unauthenticated access from a real browser.

Sub-projects D and E will eventually replace step 6 with proper UI flows. Until then, all org / user / role changes flow through the dashboard + service-role SQL.

## Verification: `npm run verify:rls`

The single most important deliverable in this sub-project. RLS that "looks right" but isn't exercised by real JWTs against the real Postgres engine is a security claim without evidence.

### Shape

A Node script at `scripts/verify-rls.ts`, run via `npm run verify:rls`. Uses `@supabase/supabase-js`. Two env vars: `SUPABASE_TEST_URL`, `SUPABASE_TEST_SERVICE_KEY`.

### Steps

1. **Wipe**: using service role, `TRUNCATE` the six `public.*` tables (CASCADE). Do **not** truncate `auth.users` — that's invasive and the script doesn't own it.
2. **Ensure fixture users exist** (idempotent): for each of the five known fixture emails, call the Supabase Admin API to create the user with a known password (`createUser`) or fetch the existing UID if creation returns "already exists". Cache the resulting UIDs for the seed step. This step is a no-op on subsequent runs.
3. **Seed**: create two organizations ("Acme", "Globex"); two users per org (one `org_admin`, one `member`); two teams per org with crisscrossed membership (member A on team 1 only, org_admin A on teams 1+2, etc.); a personal list for each user; a team list for each team; 2 todos per list. Plus one super-admin user not assigned to any org other than the seed "System" org. All inserts go through the Supabase Admin API so they bypass RLS and exercise the triggers correctly (`org_id` auto-fill, `created_by` capture).
4. **Sign in**: for each of the five user fixtures, sign in via `supabase.auth.signInWithPassword` and produce a user-scoped client (using the returned JWT). The seed sets each user's password to a known value.
5. **Assert**: run the assertion list below. Each assertion is "as user X, query Y, expect Z." Failures collect into an error report; the script exits nonzero on any failure with a per-assertion diff.

### Assertion list (representative — full list lives in the script)

Each assertion explicitly names the role being tested.

- **Anonymous** (no JWT): `SELECT * FROM lists` returns 0 rows (RLS hides, doesn't error).
- **Member A in Acme**: sees own personal list ✓; sees Acme team 1's list (on team) ✓; does NOT see Acme team 2's list (not on team) ✓; does NOT see member B's personal list ✓; does NOT see anything in Globex ✓.
- **Member A in Acme**: can INSERT a todo into a list they can write to; INSERT into a list they cannot write to returns RLS error.
- **Member A in Acme**: can DELETE their own personal list ✓; cannot DELETE a team list they did not create ✓ (unless they're the creator).
- **Org admin in Acme**: sees all Acme lists including members' personal ones ✓; cannot UPDATE a personal list (read-only) ✓; cannot DELETE a personal list ✓; can UPDATE/DELETE team lists ✓; cannot see any Globex data ✓.
- **Org admin in Acme**: can INSERT a team into Acme; INSERT a team into Globex returns RLS error.
- **Super admin**: sees all rows in all tables across orgs ✓.
- **Profile column grants**: a member attempting to `UPDATE profiles SET role = 'org_admin'` returns permission denied even though the row-level USING clause matches.
- **Cross-org team membership**: as super admin, attempting to insert `team_members(team_id=acme_team, user_id=globex_user)` raises the trigger exception.
- **Lists XOR**: INSERT a list with both `owner_user_id` and `owner_team_id` set raises the check-constraint violation. INSERT with neither set raises it as well.
- **`auth.uid()` caching**: an `EXPLAIN ANALYZE` of a "list todos in my list" query shows the auth.uid call evaluated once per query, not per row (sanity check on the subselect convention).

The script is the contract. The schema's correctness is whatever this script says.

### Why not Jest

`auth.uid()` only returns a value when the request carries a valid JWT. Jest with a mocked Supabase client never hits the policy at all; the engine sees `auth.uid() = NULL`. Real RLS validation requires a real signed-in session, which means a real Supabase project. The script is the right shape.

## Netlify bundle

Minimal scaffolding so the deploy pipeline is wired end-to-end before sub-project B replaces the app shell.

### `netlify.toml`

```toml
[build]
  command = "npm run build"
  publish = "dist"

[build.environment]
  NODE_VERSION = "20"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
```

### Env vars (set in Netlify dashboard, not committed)

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

The `VITE_` prefix is required for Vite to expose them to client bundles.

### Placeholder app

Minimal Vite + React skeleton — `index.html`, `src/main.tsx`, `src/App.tsx`, `src/lib/supabase.ts`. The placeholder `App.tsx`:

```tsx
export default function App() {
  const [result, setResult] = useState<string>('loading...');
  useEffect(() => {
    supabase.from('lists').select('*').then(({ data, error }) => {
      setResult(error ? `error: ${error.message}` : `rows: ${data?.length ?? 0}`);
    });
  }, []);
  return <pre>anonymous read of lists → {result}</pre>;
}
```

Expected output in a deployed environment: `anonymous read of lists → rows: 0`. This proves the deploy pipeline works, the Supabase client is correctly configured, and anonymous role gets nothing (because no policies grant SELECT to anon).

Sub-project B replaces this entire `App.tsx` with the routed, auth-gated application.

### `package.json` script additions

```
"verify:rls": "tsx scripts/verify-rls.ts",
"build": "tsc && vite build"
```

Per the README convention, `gen:types`, `supabase:apply`, `db:psql`, and the lint/test scripts are already documented and will be wired up alongside the initial Vite scaffold.

## Definition of done

Sub-project A is complete when *every* item below is true. No partial completion.

1. All 16 migrations applied to a target Supabase project; `supabase db diff` shows no drift.
2. `src/types/database.types.ts` regenerated and committed in the same commit as the migrations.
3. `npm run verify:rls` exits 0 against a clean Supabase test project. The script's assertion list is fully implemented (not stubbed).
4. The bootstrap procedure has been executed end-to-end on a real Supabase project at least once, producing a working super admin login.
5. The Netlify deploy renders the placeholder page and shows `rows: 0` for the anonymous lists read.
6. README and CLAUDE.md updated to reflect the new schema, the new bootstrap procedure, and the `verify:rls` workflow. The README's "lists" exercise is removed (it's now built); the multi-tenancy "intentionally NOT in this sample" note is replaced with a pointer to this spec.

## Sub-projects this unblocks

| Sub-project | What it can now do |
|---|---|
| B (Auth + role context) | Load `profiles` for the signed-in user; derive `is_super_admin`, `role`, `org_id`; route-gate on role. |
| C (List + todo UX) | Read/write lists and todos under real RLS; the service layer in `src/services/` can call straight through. |
| D (Org admin console) | Service-role flows for invite + team management; UI binds to the existing tables. |
| E (Super admin console) | Service-role flows for org creation + super-admin bootstrap; replaces the manual psql migration step. |
