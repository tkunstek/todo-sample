# d2-todo-sample

A reference implementation of [TodoMVC](https://todomvc.com/) built as a **learning tool**. The goal is not the todo list — it's to demonstrate, end-to-end, the patterns we use on larger production apps (React + TypeScript + Vite + Supabase) in a codebase small enough to read in an afternoon.

This project is a scaled-down sibling of the SHA.TESSERA / momentum codebase. The architecture mirrors the production stack one-to-one (service layer, React Query, RLS, migration discipline, type generation, design tokens). The domain is intentionally trivial so the architecture stays in the foreground.

**Sub-project A (multi-tenant data foundation + RLS) is now implemented.** The Postgres schema, all 15 migrations, SECURITY DEFINER helpers, triggers, RLS policies, bootstrap script, and `verify:rls` harness are on disk and the Netlify deploy shell is wired up. See `docs/superpowers/specs/2026-05-19-multi-tenant-data-foundation-design.md` for the full design rationale. Sub-projects B (auth + role context), C (list/todo UX), D (org admin), and E (super admin) build on top of this foundation.

---

## What you'll learn by reading this codebase

1. **How a typed React + Supabase app is wired up** — from the database schema down to the generated `database.types.ts`, up through services, hooks, and components.
2. **How Row Level Security (RLS) replaces application-layer authorization** — every user only sees their own data, enforced by Postgres, not by `if (todo.user_id === currentUser.id)` checks scattered in the UI.
3. **How multi-tenant isolation works end-to-end** — organizations, teams, and per-table policies written once in SQL, tested with real signed-in JWTs.
4. **How React Query separates server state from UI state** — and why that distinction matters.
5. **How Zod + React Hook Form validate user input safely** without trusting the client.
6. **How the Supabase CLI manages cloud-only migrations** — idempotent SQL, generated types, no local Postgres required.
7. **How a small, consistent design system stays small and consistent** — design tokens, SCSS mixins, a Stylelint gate.

If you've read the momentum CLAUDE.md and want to see those rules applied in a project you can hold in your head, this is that project.

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Build tool | **Vite** | Fast dev server, ESM-native, no Webpack config to fight. |
| UI framework | **React 18** + **TypeScript (strict)** | Industry default. Strict mode catches errors at the type layer. |
| Routing | **React Router v6** | Two routes (`/` and `/login`) — enough to demonstrate auth-gated routing. |
| Server state | **@tanstack/react-query** | Cache invalidation, optimistic updates, retry, dedup — for free. |
| Form state | **React Hook Form** + **Zod** | Forms stay declarative; validation lives in one schema and types flow from it. |
| Styling | **SCSS + design tokens** (CSS custom properties) | No Tailwind in production styles — tokens enforce consistency. |
| Backend (BaaS) | **Supabase** (Postgres + Auth + RLS) | Authoritative database, hosted auth, security at the SQL layer. |
| Linting | **ESLint** + **Stylelint** | Stylelint catches hardcoded hex values, `!important`, off-token spacing. |
| Testing | **Jest** + **React Testing Library** | Component + service unit tests, no E2E in this sample. |

There is intentionally **no Redux, no Zustand, no MobX**. Server state lives in React Query; the small amount of UI state lives in `useState` / `useReducer` / a single `AuthContext`.

---

## Project structure

```
d2-todo-sample/
├── README.md                  # this file
├── package.json
├── tsconfig.json
├── vite.config.ts
├── netlify.toml               # Netlify build config (dist/, SPA redirect)
├── .env.example               # all env vars (VITE_ prefix for browser; bare for scripts)
├── supabase/
│   ├── config.toml
│   ├── bootstrap/
│   │   └── seed_first_super_admin.sql   # one-shot post-deploy bootstrap (NOT a migration)
│   └── migrations/            # 15 idempotent migrations, applied in order
│       ├── 20260519100001_create_organizations.sql
│       ├── 20260519100002_create_profiles.sql
│       ├── 20260519100003_create_teams.sql
│       ├── 20260519100004_create_team_members.sql
│       ├── 20260519100005_create_lists.sql
│       ├── 20260519100006_alter_todos_for_lists.sql
│       ├── 20260519100007_create_rls_helpers.sql
│       ├── 20260519100008_create_triggers.sql
│       ├── 20260519100009_enable_rls.sql
│       ├── 20260519100010_create_profiles_policies.sql
│       ├── 20260519100011_create_organizations_policies.sql
│       ├── 20260519100012_create_teams_policies.sql
│       ├── 20260519100013_create_team_members_policies.sql
│       ├── 20260519100014_create_lists_policies.sql
│       └── 20260519100015_create_todos_policies.sql
├── scripts/
│   ├── verify-rls.ts          # real-JWT RLS isolation test (npm run verify:rls)
│   └── bootstrap-first-admin.ts  # wrapper for seed_first_super_admin.sql
├── src/
│   ├── main.tsx               # React root (placeholder; AuthProvider added in sub-project B)
│   ├── App.tsx                # smoke page — renders anon-read result via service seam
│   ├── lib/
│   │   └── supabase.ts        # the single browser Supabase client (anon key)
│   ├── services/
│   │   └── rlsSmokeService.ts # service seam for the deploy smoke read
│   ├── types/
│   │   └── database.types.ts  # placeholder — regenerate with `npm run gen:types`
│   └── (hooks/, components/, pages/, contexts/, styles/, utils/ — added in sub-projects B/C)
└── docs/superpowers/
    ├── specs/2026-05-19-multi-tenant-data-foundation-design.md
    └── plans/2026-06-02-multi-tenant-data-foundation.md
```

The structure is deliberately the same shape as momentum, just smaller. The mapping is:

| momentum | d2-todo-sample |
|---|---|
| `src/services/contactService.ts` (and friends) | `src/services/rlsSmokeService.ts` (placeholder; list/todo services in sub-project C) |
| `src/hooks/useContacts.ts` | `src/hooks/use*.ts` (added in sub-projects B/C) |
| `src/features/*` | (collapsed — only one feature exists) |
| `src/styles/theme.css` | `src/styles/tokens.css` (added in sub-project B) |
| `src/styles/_momentum-tokens.scss` | `src/styles/_mixins.scss` (added in sub-project B) |
| `supabase/migrations/` | `supabase/migrations/` (same convention) |

---

## Data model

Six tables form the foundation of the multi-tenant design. The full schema with constraints, triggers, and indexes is in `supabase/migrations/`. The design spec at `docs/superpowers/specs/2026-05-19-multi-tenant-data-foundation-design.md` documents every architectural decision.

### Tables and relationships

```
organizations          (id, name, slug, created_at, updated_at)
  └── profiles         (id → auth.users, org_id, role, is_super_admin, display_name, ...)
        └── team_members  (team_id, user_id)  ──┐
  └── teams            (id, org_id, name, ...)   │
        └── team_members ─────────────────────────┘
  └── lists            (id, org_id, owner_user_id XOR owner_team_id, created_by, name, ...)
        └── todos       (id, list_id, title, is_complete, ...)
```

Key invariants:

- **One org per user.** `profiles.org_id` is `NOT NULL`. Users are assigned to exactly one organization.
- **Lists have a polymorphic owner.** `owner_user_id` and `owner_team_id` are both nullable, but exactly one must be set (`CONSTRAINT lists_owner_xor`). A list belongs to either a user (personal) or a team.
- **`lists.org_id` is denormalized** — filled by a `BEFORE INSERT` trigger from the owner's org so the org-admin policy is a single indexed comparison (`org_id = current_org_id()`).
- **`lists.created_by`** is `nullable` with `ON DELETE SET NULL`. It records who created the list (audit metadata) without blocking team-list survival when the creator's profile is deleted.
- **`todos` hang off `lists`** via a `NOT NULL` FK. There is no `user_id` on `todos`.

### Row Level Security

RLS is the most important pattern in this sample. The anon key is public and the client is hostile. Authorization lives entirely in Postgres policies — there are no `if (resource.user_id === currentUser.id)` checks in TypeScript.

All six tables have RLS enabled. The policies are split per operation (`SELECT / INSERT / UPDATE / DELETE`), scoped `TO authenticated`, and backed by seven `SECURITY DEFINER` helper functions:

| Helper | Purpose |
|---|---|
| `is_super_admin()` | `true` if the caller's profile has `is_super_admin = true` |
| `is_org_admin()` | `true` if the caller's profile has `role = 'org_admin'` |
| `current_org_id()` | the caller's `profiles.org_id` |
| `is_team_member(team_id)` | `true` if the caller is in `team_members` for that team |
| `can_read_list(list_id)` | owner, team member, org admin (read-only on personal lists), or super admin |
| `can_write_list(list_id)` | owner, team member with write, org admin on team lists, or super admin |
| `can_manage_team_member(team_id, user_id)` | both team AND user must be in the actor's own org |

The `todos` SELECT policy delegates entirely to `can_read_list(list_id)`. This is intentional and has a performance consequence — see the **Todos query constraint** invariant in CLAUDE.md.

Notes:

- `(select auth.uid())` is used inside every policy (subselect form) so Postgres caches it once per query rather than calling it per row.
- Policies are scoped `TO authenticated` so the `anon` role gets nothing (RLS default-deny).
- The `profiles` UPDATE policy is backed by an explicit column grant: only `display_name` and `updated_at` are writable by the authenticated role. `role`, `org_id`, and `is_super_admin` cannot be set from the client under any circumstances.

---

## Architecture patterns

### 1. Service layer

All Supabase calls go through `src/services/`. Components and hooks never `import { supabase }` directly. This means:

- The Supabase client is easy to mock in tests.
- Error shapes are translated once, in one place.
- Swapping the backend later (or splitting one service into many) is a localized change.

The existing service in sub-project A is `src/services/rlsSmokeService.ts` — a minimal proof-of-concept. Sub-project C will add the real list and todo services. When it does, every `todos` query **must** be scoped by `list_id` and paginated (see the todos query constraint in CLAUDE.md). An illustrative skeleton:

```ts
// src/services/todoService.ts  (sub-project C)
import { supabase } from '../lib/supabase'
import type { Database } from '../types/database.types'

type Todo = Database['public']['Tables']['todos']['Row']
type TodoInsert = Database['public']['Tables']['todos']['Insert']

export const todoService = {
  async listForList(listId: string, page = 0, pageSize = 50): Promise<Todo[]> {
    const { data, error } = await supabase
      .from('todos')
      .select('*')
      .eq('list_id', listId)          // REQUIRED — never omit list_id
      .order('created_at', { ascending: false })
      .range(page * pageSize, (page + 1) * pageSize - 1)
    if (error) throw error
    return data
  },

  async create(input: Pick<TodoInsert, 'list_id' | 'title'>): Promise<Todo> {
    const { data, error } = await supabase
      .from('todos').insert(input).select().single()
    if (error) throw error
    return data
  },
}
```

Note `list_id` is required on every insert and every `SELECT`. The `todos` SELECT policy delegates to `can_read_list(list_id)` — an unbounded `select * from todos` re-evaluates that helper for each distinct `list_id` across the caller's entire tenant, which is expensive.

### 2. React Query for server state

React Query hooks (`src/hooks/use*.ts`) will be added in sub-projects B and C. The pattern, when implemented: every read goes through a hook that wraps a service function, every write goes through a mutation that invalidates the relevant query keys, and components only see `isLoading`, `data`, `error`.

```ts
// src/hooks/useTodos.ts  (sub-project C — illustrative)
import { useQuery } from '@tanstack/react-query'
import { todoService } from '../services/todoService'

export function useTodos(listId: string) {
  return useQuery({
    queryKey: ['todos', listId],
    queryFn: () => todoService.listForList(listId),
    staleTime: 30_000,
  })
}
```

The query key always includes `listId` so React Query caches per-list, not per-tenant.

### 3. Zod for validation, inferred for types

`src/utils/schemas.ts` (added in sub-project C) will hold all Zod schemas. The pattern:

```ts
// src/utils/schemas.ts  (sub-project C — illustrative)
import { z } from 'zod'

export const TodoCreateSchema = z.object({
  list_id: z.string().uuid(),
  title: z.string().trim().min(1, 'Title is required').max(280),
})

export type TodoCreateInput = z.infer<typeof TodoCreateSchema>
```

The form uses `zodResolver(TodoCreateSchema)`. The service accepts `TodoCreateInput`. The DB enforces the same length constraint via `CHECK (length(title) BETWEEN 1 AND 280)`. Three layers of validation, one source of truth.

### 4. Auth context

`AuthContext` (added in sub-project B) will expose `{ user, session, profile, signIn, signOut }`. `profile` carries the tenant-aware fields (`org_id`, `role`, `is_super_admin`) so components can derive what the current user is permitted to see without making additional DB calls. Until sub-project B lands, there is no in-app auth — use the Supabase dashboard to manage users.

### 5. Design tokens

`src/styles/tokens.css` defines every color, spacing step, and radius as a CSS custom property. Components reference tokens via SCSS mixins or directly. Stylelint fails the build on hardcoded hex values, `!important`, or any pixel value not in the spacing scale. This is the same discipline as momentum's "Momentum" design system, just with a smaller palette.

---

## Development workflow

### Prerequisites

- Node 20+
- A Supabase account (free tier is fine)
- The Supabase CLI: `brew install supabase/tap/supabase`

### Initial setup

```bash
git clone <this-repo>
cd d2-todo-sample
npm install

# 1. Create a Supabase project at https://supabase.com/dashboard.
#    Note the project URL, anon key, service_role key, and DB connection string.
cp .env.example .env
# Fill in VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY,
#          SUPABASE_TEST_URL, SUPABASE_TEST_SERVICE_KEY, SUPABASE_DB_URL

# 2. Link the CLI to your project
supabase login
supabase link --project-ref <your-project-ref>

# 3. Push all 15 migrations
npm run supabase:apply

# 4. Seed the first super admin (run once after first deploy)
#    Create a user in the Supabase dashboard (Auth → Users), copy its UID.
npm run bootstrap:first-admin -- --uid '<uid-from-dashboard>' --org 'System'

# 5. Generate TypeScript types from the cloud schema
npm run gen:types

# 6. Start the dev server
npm run dev
```

There is no in-app sign-up flow yet (sub-project B). Users are provisioned by service role during the invite flow (sub-projects D/E); the bootstrap script is the only mechanism in sub-project A for seeding a user into an org.

### Adding a database change

```bash
# 1. Create a new migration file (CLI generates the timestamp)
supabase migration new add_priority_to_todos

# 2. Edit supabase/migrations/<timestamp>_add_priority_to_todos.sql
#    Always write idempotent SQL:
#    ALTER TABLE public.todos ADD COLUMN IF NOT EXISTS priority int NOT NULL DEFAULT 0;

# 3. Apply to cloud
npm run supabase:apply

# 4. Regenerate types — the new column appears in database.types.ts
npm run gen:types

# 5. Commit migration + regenerated types together
git add supabase/migrations/ src/types/database.types.ts
git commit -m "feat(todos): add priority column"
```

**Never edit an already-applied migration.** If a migration was wrong, create a new one to fix it. Migrations are append-only; the file list is the history.

### Commands

```bash
npm run dev              # Vite dev server on localhost:5173
npm run build            # tsc + vite build
npm run preview          # serve dist/

npm run lint             # ESLint
npm run lint:styles      # Stylelint — must pass before commit
npm run lint:styles:fix  # auto-fix where possible

npm test                 # Jest unit + component tests
npm run test:watch
npm run test:coverage

npm run supabase:apply   # supabase db push
npm run gen:types        # supabase gen types typescript --linked > src/types/database.types.ts
npm run db:psql          # psql against $SUPABASE_DB_URL for ad-hoc reads

npm run verify:rls       # real-JWT RLS isolation test (needs .env with test project creds)
npm run bootstrap:first-admin -- --uid <uid> --org <name>  # seed first super admin
```

### `verify:rls` workflow

`verify:rls` (`scripts/verify-rls.ts`) proves tenant isolation end-to-end against a real Supabase project using real signed-in JWTs. It cannot be mocked — `auth.uid()` inside Postgres is only populated for a genuine session.

**Required env vars** (all in `.env`, never committed):

```dotenv
SUPABASE_TEST_URL=https://<ref>.supabase.co
SUPABASE_TEST_SERVICE_KEY=<service_role key>
VITE_SUPABASE_ANON_KEY=<anon key>
```

The harness creates five fixture users (or reuses them), wipes all tenant data, seeds two orgs and four teams, creates lists and todos via each owner's authenticated session (so triggers fire with a real `auth.uid()`), and runs ~30 assertions covering personal/team list visibility, cross-org isolation, org-admin read-only-on-personal, cross-org `team_members` rejection, profile column tamper-proofing, and trigger-driven `org_id`/`created_by` derivation.

> Use a **dedicated test project** — the harness truncates all six tables on every run.

### Bootstrap procedure

The bootstrap script (`scripts/bootstrap-first-admin.ts`) wraps `supabase/bootstrap/seed_first_super_admin.sql` via `psql`. It is run **once** after first deploy:

```bash
# 1. Create the user in the Supabase dashboard (Auth → Users). Copy the UID.
# 2. Run:
npm run bootstrap:first-admin -- --uid '<uid>' --org 'System'
# Expected output: psql prints INSERT 0 1 (or INSERT 0 0 on a repeat idempotent run).
```

The SQL is idempotent: if the org or profile already exists it does nothing. The bootstrap file is **not** in the numbered migration chain — it is a one-shot seed and must never be applied by `supabase db push`.

---

## What is intentionally NOT yet in this sample

Sub-project A delivers the data foundation. The following are out of scope until later sub-projects:

| Omitted | Planned in | Notes |
|---|---|---|
| `AuthContext` and route guards | Sub-project B | No in-app login/logout yet. Auth happens in the Supabase dashboard during development. |
| List/todo UI | Sub-project C | The placeholder `App.tsx` only proves RLS returns 0 rows for anon. |
| User invitation and org management UI | Sub-project D | Users are provisioned by service role only (or the bootstrap script for the first admin). |
| Super admin console | Sub-project E | Cross-org actions are service-role only today. |
| Edge Functions | — | No server-side logic is needed for the current scope. |
| Realtime subscriptions | — | Polling via React Query's `staleTime` is enough. Supabase Realtime is a one-hook change. |
| E2E tests (Playwright) | — | Unit + component tests are enough at this scale. |
| A formal design system page | Sub-project B | Design tokens and Stylelint will be wired up when the real UI arrives. |

Each of these is a one-sub-project extension. The data foundation (RLS, triggers, policies) is already tested and in place.

---

## Suggested exercises

If you're using this as a learning project, here is a rough difficulty curve:

1. **Easy** — Run `npm run verify:rls` against your own Supabase test project and read through `scripts/verify-rls.ts`. Trace each assertion back to the policy that enforces it.
2. **Easy** — Add a `priority` column to `todos` via a new migration (migration 16+). Update the generated types and the smoke service. Practice the append-only, idempotent migration discipline.
3. **Medium** — Implement sub-project B: wire up `AuthContext`, sign-in/sign-out, and route guards. The data foundation is already in place — you only need the React layer.
4. **Medium** — Implement the list/todo UI (sub-project C). Use the existing service-layer seam. Pay attention to the todos query constraint — scope every `todos` query by `list_id`.
5. **Medium** — Add optimistic updates to the todo toggle mutation. Compare UX before and after.
6. **Hard** — Implement the org admin console (sub-project D): user invitation flow, team creation, membership management. The RLS policies already enforce the boundaries; your job is the UI and service layer.
7. **Hard** — Add a "collaborator" role to `lists` (read-only access for invited users who are not team members). This requires a new table, new RLS helper, and updated policies — without touching any already-applied migration.

---

## License

MIT. This is a teaching sample — copy it, fork it, rewrite it.
