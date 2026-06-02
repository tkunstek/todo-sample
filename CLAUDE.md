# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Sub-project A (multi-tenant data foundation + RLS) is complete.** The following now exist on disk:

- `package.json`, `tsconfig.json`, `vite.config.ts`, `index.html`, `netlify.toml` — the Vite + React project shell, Netlify deploy config.
- `src/lib/supabase.ts` — the single browser Supabase client (anon key).
- `src/services/rlsSmokeService.ts` — service seam for the placeholder anon-read smoke page.
- `src/App.tsx` — placeholder page that renders the anon-read result; replaced in sub-project B.
- `src/types/database.types.ts` — a committed **placeholder** with a loose `Database` type so the typed client compiles. Must be regenerated with `npm run gen:types` against a linked Supabase project before strong typing takes effect.
- `supabase/migrations/20260519100001–15_*.sql` — 15 idempotent migrations: tables → helpers → triggers → enable RLS → per-table policies (organizations, profiles, teams, team_members, lists, todos).
- `supabase/bootstrap/seed_first_super_admin.sql` — one-shot bootstrap SQL, run via `npm run bootstrap:first-admin`. **Not a migration** — it is never applied by `supabase db push`.
- `scripts/verify-rls.ts` — real-JWT RLS isolation test harness.
- `scripts/bootstrap-first-admin.ts` — thin `psql` wrapper for the bootstrap SQL.
- `.env.example` — documents all required env vars.

**Not yet on disk (added in later sub-projects):**

- `AuthContext`, route guards, `LoginPage` (sub-project B).
- List/todo UI components, hooks, Zod schemas, styles (sub-project C).
- Org admin and super admin consoles (sub-projects D/E).

When asked to implement something, first check whether the surrounding infrastructure actually exists on disk. The above list is the current reality.

## Commands

`package.json` exists. `dev`, `build`, `preview`, `supabase:apply`, `gen:types`, `db:psql`, `verify:rls`, and `bootstrap:first-admin` are fully wired. `lint`, `lint:styles`, and `test` scripts are reserved — their toolchains (ESLint, Stylelint, Jest) are scaffolded in sub-projects B/C when real UI/components exist.

```bash
npm run dev              # Vite dev server on localhost:5173
npm run build            # tsc + vite build
npm run preview          # serve dist/

npm run lint             # ESLint  (toolchain added in sub-project B)
npm run lint:styles      # Stylelint — must pass before commit  (sub-project B)
npm run lint:styles:fix

npm test                 # Jest + React Testing Library  (sub-project B/C)
npm run test:watch
npm run test:coverage

npm run supabase:apply   # supabase db push  (cloud-only, no local Postgres)
npm run gen:types        # supabase gen types typescript --linked > src/types/database.types.ts
npm run db:psql          # psql against $SUPABASE_DB_URL for ad-hoc reads

npm run verify:rls       # real-JWT RLS isolation test (needs SUPABASE_TEST_URL +
                         # SUPABASE_TEST_SERVICE_KEY + VITE_SUPABASE_ANON_KEY in .env)
npm run bootstrap:first-admin -- --uid <uid> --org <name>
                         # seed the first super admin post-deploy; runs
                         # supabase/bootstrap/seed_first_super_admin.sql via psql
```

Run a single Jest test file: `npm test -- path/to/file.test.tsx`. Run a single test by name: `npm test -- -t "test name pattern"`.

## Architecture invariants

These are non-negotiable rules baked into the design. Violating any of them breaks a security boundary or the pattern this codebase exists to teach.

### Service layer is the only path to Supabase

- **Components and hooks never `import { supabase }` directly.** All DB I/O goes through `src/services/*.ts`.
- Services translate Supabase errors once, return plain typed values, and are the seam for tests (mock the service, not the Supabase client).
- React Query hooks (`src/hooks/use*.ts`) wrap services; components consume hooks. The chain is: component → hook → service → supabase client.

### Row Level Security is the authorization layer

- Authorization lives in Postgres policies, **not** in `if (resource.user_id === currentUser.id)` checks in TS. The anon key is public; the client is hostile.
- Use `(select auth.uid())` inside policies (subselect form) so Postgres caches it once per query instead of per row. Apply this everywhere, not just where it currently matters.
- Write **separate policies per operation** (SELECT / INSERT / UPDATE / DELETE) scoped `TO authenticated`. Don't collapse them.
- `lists.org_id` and `lists.created_by` are filled by `BEFORE INSERT` triggers from the JWT — **the client never sets these columns reliably**. The triggers are the first line of defense; RLS is the second. The `lists_forbid_owner_change` trigger also blocks reparenting on UPDATE.
- The `profiles` UPDATE policy is backed by an explicit column grant (`GRANT UPDATE (display_name, updated_at)`). `role`, `org_id`, and `is_super_admin` cannot be changed by the authenticated role under any circumstances — not even by the row owner.

### Migrations are append-only and cloud-only

- Never edit a migration that has been applied. To change something, add a new migration.
- All SQL must be **idempotent** (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, etc.).
- Migration filenames: `YYYYMMDDHHmmss_description.sql` — use `supabase migration new <name>` to generate the timestamp.
- After any migration: run `npm run gen:types` and commit `supabase/migrations/` and `src/types/database.types.ts` in the **same commit**. Schema and types drift the moment you split them.

### Validation lives in Zod schemas (one source of truth)

- Define a Zod schema in `src/utils/schemas.ts`; export the inferred TS type.
- Forms use `zodResolver(SomeSchema)`; services accept the inferred input type; the DB enforces the same constraint via `CHECK`. Three layers, one definition.

### Styling discipline

- No Tailwind. Styles are SCSS using design tokens from `src/styles/tokens.css` (CSS custom properties) and mixins from `src/styles/_mixins.scss`.
- Stylelint **fails the build** on hardcoded hex values, `!important`, and pixel values outside the spacing scale. Don't disable rules — add a token instead.

### No client-state libraries

- No Redux / Zustand / MobX. Server state is React Query. UI state is `useState` / `useReducer`. Cross-cutting auth state is a single `AuthContext`. If you feel the pull toward another store, the answer is almost always "lift to React Query" or "this is a derived value, compute it."

### Todos query constraint (sub-project C and beyond)

- Sub-project C services **MUST** query `todos` scoped by `list_id` and paginate. **Never** issue an unbounded `select * from todos` (or `.from('todos').select()` without a `.eq('list_id', ...)` filter).
- The `todos` SELECT policy delegates to `can_read_list(list_id)` per row. That helper re-evaluates for each distinct `list_id` it encounters in the result set. An unbounded scan re-runs the helper across every todo in the caller's tenant — a query that is cheap with 10 todos becomes expensive at 10,000.
- Always include `.eq('list_id', listId)` and `.range(start, end)` (or `.limit(n)`) on every `todos` query. The `todos_list_id_idx` index makes the scoped query fast; the helper evaluation is then bounded to a single list.

## Mental model: this codebase mirrors momentum

The README's "momentum ↔ d2-todo-sample" mapping table is load-bearing — the file structure (`services/`, `hooks/`, `components/<Name>/<Name>.tsx + .scss + .test.tsx`, `styles/tokens.css`) intentionally matches the larger production codebase. When choosing where a new file goes, the answer is whatever momentum would do at the same shape. Don't reorganize toward a "cleaner" layout that breaks the parallel.
