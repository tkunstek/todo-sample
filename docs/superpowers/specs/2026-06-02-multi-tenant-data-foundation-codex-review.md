# Codex adversarial review — Multi-tenant data foundation + RLS (Sub-project A)

**Reviewer:** OpenAI Codex (gpt-5.5, high reasoning effort)
**Date:** 2026-06-02
**Artifact reviewed:** docs/superpowers/specs/2026-05-19-multi-tenant-data-foundation-design.md

**Findings**

1. **Category:** ordering  
   **Severity:** critical  
   **Finding:** `20260519100016_bootstrap_first_super_admin.sql` is listed inside `supabase/migrations/`, but the bootstrap procedure says `npm run supabase:apply` pushes only migrations 1-15 and skips 16. Supabase CLI migrations are normally applied in timestamp order from the migrations folder; a psql-variable migration with `:super_admin_uid` will either fail during `supabase db push` or be accidentally skipped by undocumented process. Running it manually with `psql -f` also will not necessarily record it in Supabase migration history.  
   **Recommendation:** Do not keep the bootstrap script as a normal numbered migration unless the apply command explicitly excludes it and the migration-history implications are documented. Prefer `supabase/bootstrap/seed_first_super_admin.sql` or a script like `npm run bootstrap:first-admin` outside the migration chain.

2. **Category:** ordering  
   **Severity:** important  
   **Finding:** Triggers are created in `20260519100015_create_triggers.sql`, after RLS policies in migrations 9-14. The `lists` INSERT policies assume `lists_set_org_id_from_owner` and `lists_set_created_by` are already active, because clients must not supply trusted `org_id` or `created_by`. There is a deployment window where policies exist but the defensive triggers do not.  
   **Recommendation:** Move trigger creation before list/todo policies, ideally before enabling application writes. Build order should be: tables → functions → triggers → RLS enablement → grants/policies → bootstrap.

3. **Category:** completeness  
   **Severity:** important  
   **Finding:** The spec is “approved, ready for implementation planning” but has no formal work-unit decomposition. For a 16-migration security foundation, this is a real planning gap: the build order, verification dependencies, bootstrap mechanics, type generation, Netlify scaffold, README/CLAUDE updates, and recovery steps are all mixed together.  
   **Recommendation:** Add implementation work units before coding. At minimum: schema migrations, helper functions, triggers, RLS/grants, bootstrap script, verification fixtures/assertions, frontend skeleton, generated types/docs, and deployment validation.

4. **Category:** security  
   **Severity:** critical  
   **Finding:** `team_members.INSERT` only checks that `team_id` belongs to the current org. It does not check that `user_id` belongs to the current org. The trigger `team_members_enforce_same_org` catches this if present, but the policy itself allows an org admin to attempt cross-org membership. Because this is a tenant boundary, defense should not depend on only the trigger.  
   **Recommendation:** Add `WITH CHECK` logic requiring both the team and profile to be in `public.current_org_id()`, or replace with a SECURITY DEFINER helper such as `can_manage_team_member(p_team_id, p_user_id)` that checks both sides.

5. **Category:** testing  
   **Severity:** important  
   **Finding:** The assertion list tests cross-org `team_members` insert “as super admin,” but the more relevant attack is “as Acme org_admin inserting Globex user into Acme team.” That is exactly where the current policy is weakest.  
   **Recommendation:** Add negative tests for org admins inserting, deleting, and selecting `team_members` with cross-org `user_id` and `team_id` combinations.

6. **Category:** security  
   **Severity:** important  
   **Finding:** `profiles.UPDATE` relies on column-level grants: `GRANT UPDATE (display_name, updated_at)`. But the spec does not explicitly revoke table-level `UPDATE` from `anon`, `authenticated`, or inherited default grants before applying the column grant. It only says `REVOKE UPDATE ON profiles FROM authenticated`.  
   **Recommendation:** Add explicit grants migration covering every table: revoke all unintended privileges from `anon` and `public`, grant only required operation privileges to `authenticated`, then rely on RLS. Verify `anon` has no table privileges beyond what Supabase may default.

7. **Category:** security  
   **Severity:** important  
   **Finding:** The Netlify placeholder violates the stated architecture invariant: `src/App.tsx` imports/uses `supabase` directly via `src/lib/supabase.ts`. The context says components/hooks never import the Supabase client directly and all DB I/O goes through services.  
   **Recommendation:** Even for the placeholder, create a tiny service such as `src/services/rlsSmokeService.ts` and call that from `App.tsx`. This keeps Sub-project A from teaching the wrong pattern.

8. **Category:** security  
   **Severity:** important  
   **Finding:** `lists_set_created_by` uses `auth.uid()` to fill a NOT NULL FK. That is good for authenticated clients, but service-role fixture/bootstrap inserts may not carry a user JWT. The verification spec says seed inserts “go through the Supabase Admin API so they bypass RLS and exercise the triggers,” but service-role inserts can produce `auth.uid() = null`, causing `created_by` to become null and violate NOT NULL.  
   **Recommendation:** Decide explicitly how service-role list creation supplies actor identity. Options: use user-scoped clients for fixture list creation, accept a trusted `created_by` only when `auth.uid()` is null and role is service, or provide a SECURITY DEFINER seed RPC.

9. **Category:** database  
   **Severity:** important  
   **Finding:** `lists.created_by UUID NOT NULL REFERENCES public.profiles(id)` has no `ON DELETE` behavior. Since `profiles` can be deleted by cascade from `organizations`, deleting a profile that created a team-owned list may be blocked because `created_by` references it. This conflicts with the claimed hard-delete cascade graph.  
   **Recommendation:** Choose and declare the intended behavior. Common fix: `created_by UUID REFERENCES profiles(id) ON DELETE SET NULL` and make it nullable, or `ON DELETE CASCADE` if creator deletion should delete lists they created. For audit-like metadata, nullable `SET NULL` is usually cleaner.

10. **Category:** database  
    **Severity:** important  
    **Finding:** `team_members` has no denormalized `org_id`, which is fine, but then every policy and trigger depends on joins through `teams` and `profiles`. The existing indexes cover `team_members.user_id` and PK `(team_id, user_id)`, but there is no explicit index supporting frequent “teams in org plus members” access beyond `teams_org_id_idx`.  
    **Recommendation:** Add or justify indexes for expected admin-console queries, likely `(user_id, team_id)` already covered partly by `team_members_user_id_idx`, and ensure `teams(id, org_id)` lookups use the PK plus filter efficiently. Include `EXPLAIN` checks in verification if this is meant to teach production patterns.

11. **Category:** testing  
    **Severity:** important  
    **Finding:** The verification list does not test `lists_forbid_owner_change` directly. This is a core protection against reparenting a list across users, teams, orgs, or creator identity.  
    **Recommendation:** Add negative UPDATE tests attempting to change `owner_user_id`, `owner_team_id`, `org_id`, and `created_by` as member, org admin, and super admin.

12. **Category:** testing  
    **Severity:** important  
    **Finding:** The verification list does not test trigger override behavior for `lists.org_id` and `lists.created_by`. A hostile client could submit mismatched `org_id` or forged `created_by`; the spec claims triggers override both, but the tests do not prove it.  
    **Recommendation:** Add assertions that inserting a personal list/team list with forged `org_id` and `created_by` stores the derived owner org and current JWT user.

13. **Category:** testing  
    **Severity:** important  
    **Finding:** The assertion list tests `profiles.role` escalation but not `profiles.org_id` or `profiles.is_super_admin` tampering. Those are equally sensitive columns protected only by column grants.  
    **Recommendation:** Add explicit negative updates for `profiles.org_id`, `profiles.is_super_admin`, `profiles.id`, `created_at`, and `role`.

14. **Category:** security  
    **Severity:** important  
    **Finding:** `can_read_list()` and `can_write_list()` are SECURITY DEFINER functions that call other SECURITY DEFINER helpers per row: `is_team_member()`, `is_org_admin()`, `current_org_id()`, `is_super_admin()`. The predicates are logically reasonable, but the spec does not discuss function owner, ownership hardening, or preventing ordinary roles from replacing helper functions.  
    **Recommendation:** State that helpers are owned by a migration/admin role, not `authenticated`, and add explicit `REVOKE CREATE ON SCHEMA public FROM PUBLIC` if not already guaranteed. Keep `SET search_path = ''`.

15. **Category:** performance  
    **Severity:** important  
    **Finding:** `todos.SELECT` delegates every row to `public.can_read_list(list_id)`, which queries `lists`, may query `team_members`, and calls several helpers. This can become expensive on unbounded todo queries. The spec calls `todos` the hottest table but does not include pagination or query-shape constraints.  
    **Recommendation:** Require list-scoped todo queries in services, add pagination defaults, and include performance verification for representative `todos` reads. Consider denormalizing `todos.list_id` only is fine, but then service queries must avoid `select * from todos` across the tenant.

16. **Category:** testing  
    **Severity:** suggestion  
    **Finding:** The `auth.uid()` caching assertion via `EXPLAIN ANALYZE` is underspecified and may not prove what it claims, especially because helper functions use plain `auth.uid()` internally rather than `(select auth.uid())`.  
    **Recommendation:** Either remove this as a hard assertion or replace it with concrete plan checks that are stable enough for CI. More importantly, use `(select auth.uid())` inside helper SQL where possible by assigning through subqueries/CTEs.

17. **Category:** database  
    **Severity:** important  
    **Finding:** The spec says all migrations are idempotent, but the schema examples use plain `CREATE INDEX`, `CREATE FUNCTION`, and likely `CREATE POLICY`. PostgreSQL does not support `CREATE POLICY IF NOT EXISTS`, and `CREATE FUNCTION` without `OR REPLACE` is not idempotent.  
    **Recommendation:** Define exact idempotent patterns: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `DROP POLICY IF EXISTS ...; CREATE POLICY ...`, and guarded `ALTER TABLE`.

18. **Category:** rollback  
    **Severity:** critical  
    **Finding:** Rollback is essentially unaddressed. This matters because the plan is cloud-only, append-only, includes destructive `alter_todos_for_lists`, manual bootstrap, RLS enablement, grants, and hard-delete cascades.  
    **Recommendation:** Add a recovery section. At minimum: require pre-migration database backup, define how to disable/recreate bad policies with service role, document how to recover from failed bootstrap, and state that rollback is forward-fix migration plus restore-from-backup for destructive failures.

19. **Category:** integration  
    **Severity:** important  
    **Finding:** Sub-project B depends on loading the signed-in user's `profiles` row, but there is no profile creation path in A except bootstrap. The spec says future D/E will create profiles server-side, but B may be unable to test normal non-bootstrap auth flows without manual SQL or verification fixtures.  
    **Recommendation:** Add a documented dev/test profile creation path using service role SQL or a seed script, clearly marked non-production UI. Otherwise B will block on missing users.

20. **Category:** completeness  
    **Severity:** suggestion  
    **Finding:** Validation is declared as Zod one source of truth, but Sub-project A does not deliver `src/utils/schemas.ts` for `organizations.name`, `organizations.slug`, `teams.name`, `lists.name`, or `todos.title`. Only DB CHECK constraints are specified for `lists.name` and `todos.title`.  
    **Recommendation:** Either include Zod schemas in A or explicitly defer them to B/C/D. If deferred, remove “one source of truth” from A’s implied deliverables.

**Summary**

Overall spec quality: **6/10**. The schema and policy intent are thoughtful, but several operational and security details are not ready for implementation as written.

Top 3 risks:

1. Bootstrap as migration 16 is likely to break migration application or migration history.
2. `team_members.INSERT` does not policy-check `user_id` org membership.
3. Rollback/recovery is missing for a cloud-only, security-sensitive migration set.

This needs revision before implementation planning. The core design is salvageable, but the migration strategy, trigger/policy ordering, bootstrap mechanics, and verification gaps should be fixed before decomposing into work units.
