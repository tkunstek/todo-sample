# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

This repo currently contains **only `README.md`** — no `package.json`, no `src/`, no `supabase/` directory yet. The README is a detailed spec of the intended architecture (React + TypeScript + Vite + Supabase, mirroring the production "momentum" / SHA.TESSERA stack at small scale). Treat the README as the architectural contract: when scaffolding or adding code, conform to it rather than inventing a parallel design.

When asked to implement something, first check whether the surrounding infrastructure (Vite config, Supabase client, AuthContext, service layer, etc.) actually exists on disk. If not, scaffolding it is part of the task.

## Commands

These are the commands the README commits to. They don't work yet (no `package.json`), but new scripts must use these exact names so the documented workflow stays accurate:

```bash
npm run dev              # Vite dev server on localhost:5173
npm run build            # tsc + vite build
npm run preview          # serve dist/

npm run lint             # ESLint
npm run lint:styles      # Stylelint — must pass before commit
npm run lint:styles:fix

npm test                 # Jest + React Testing Library
npm run test:watch
npm run test:coverage

npm run supabase:apply   # supabase db push  (cloud-only, no local Postgres)
npm run gen:types        # supabase gen types typescript --linked > src/types/database.types.ts
npm run db:psql          # psql against $SUPABASE_DB_URL for ad-hoc reads
```

Run a single Jest test file: `npm test -- path/to/file.test.tsx`. Run a single test by name: `npm test -- -t "test name pattern"`.

## Architecture invariants

These are non-negotiable rules baked into the design. Violating any of them breaks a security boundary or the pattern this codebase exists to teach.

### Service layer is the only path to Supabase

- **Components and hooks never `import { supabase }` directly.** All DB I/O goes through `src/services/*.ts`.
- Services translate Supabase errors once, return plain typed values, and are the seam for tests (mock the service, not the Supabase client).
- React Query hooks (`src/hooks/use*.ts`) wrap services; components consume hooks. The chain is: component → hook → service → supabase client.

### Row Level Security is the authorization layer

- Authorization lives in Postgres policies, **not** in `if (todo.user_id === currentUser.id)` checks in TS. The anon key is public; the client is hostile.
- Use `(select auth.uid())` inside policies (subselect form) so Postgres caches it once per query instead of per row. Apply this everywhere, not just where it currently matters.
- Write **separate policies per operation** (SELECT / INSERT / UPDATE / DELETE) scoped `TO authenticated`. Don't collapse them.
- `user_id` is filled by a `BEFORE INSERT` trigger from `auth.uid()` — **the client never sets `user_id`**. RLS is the second line of defense; the trigger is the first.

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

## Mental model: this codebase mirrors momentum

The README's "momentum ↔ d2-todo-sample" mapping table is load-bearing — the file structure (`services/`, `hooks/`, `components/<Name>/<Name>.tsx + .scss + .test.tsx`, `styles/tokens.css`) intentionally matches the larger production codebase. When choosing where a new file goes, the answer is whatever momentum would do at the same shape. Don't reorganize toward a "cleaner" layout that breaks the parallel.
