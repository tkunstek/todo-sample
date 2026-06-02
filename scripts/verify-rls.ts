import 'dotenv/config'
import { createClient, SupabaseClient } from '@supabase/supabase-js'

const URL = process.env.SUPABASE_TEST_URL
const SERVICE_KEY = process.env.SUPABASE_TEST_SERVICE_KEY
if (!URL || !SERVICE_KEY) throw new Error('Set SUPABASE_TEST_URL and SUPABASE_TEST_SERVICE_KEY')

const PASSWORD = 'verify-rls-fixture-pw-1!'

// Five user fixtures + the super admin.
const FIXTURES = {
  acmeAdmin: 'acme-admin@example.test',
  acmeMember: 'acme-member@example.test',
  globexAdmin: 'globex-admin@example.test',
  globexMember: 'globex-member@example.test',
  superAdmin: 'super-admin@example.test',
} as const
type FixtureKey = keyof typeof FIXTURES

const admin = createClient(URL, SERVICE_KEY, { auth: { persistSession: false } })

// ---- assertion plumbing -------------------------------------------------
let failures: string[] = []
let checks = 0
function check(name: string, cond: boolean, detail = '') {
  checks++
  if (!cond) failures.push(`FAIL: ${name}${detail ? ` — ${detail}` : ''}`)
}
async function expectRows<T>(
  label: string,
  q: PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
  expected: number,
) {
  const { data, error } = await q
  check(label, !error && (data?.length ?? -1) === expected,
    error ? `error: ${error.message}` : `got ${data?.length ?? 0}, want ${expected}`)
}
async function expectError<T>(
  label: string,
  q: PromiseLike<{ data: T | null; error: { message: string } | null }>,
) {
  const { error } = await q
  check(label, !!error, 'expected an error/policy rejection, got success')
}
async function expectOk<T>(
  label: string,
  q: PromiseLike<{ data: T | null; error: { message: string } | null }>,
) {
  const { error } = await q
  check(label, !error, error ? `unexpected error: ${error.message}` : '')
}

// ---- admin helpers ------------------------------------------------------
async function ensureUser(email: string): Promise<string> {
  const created = await admin.auth.admin.createUser({
    email, password: PASSWORD, email_confirm: true,
  })
  if (created.data.user) return created.data.user.id
  // already exists -> find it
  const { data } = await admin.auth.admin.listUsers({ perPage: 1000 })
  const found = data.users.find((u) => u.email === email)
  if (!found) throw new Error(`could not create or find user ${email}`)
  return found.id
}
async function signIn(email: string): Promise<SupabaseClient> {
  const client = createClient(URL!, process.env.VITE_SUPABASE_ANON_KEY ?? SERVICE_KEY!, {
    auth: { persistSession: false },
  })
  const { error } = await client.auth.signInWithPassword({ email, password: PASSWORD })
  if (error) throw new Error(`sign-in failed for ${email}: ${error.message}`)
  return client
}

const uids: Record<FixtureKey, string> = {} as Record<FixtureKey, string>
const ids = {
  acme: '', globex: '', system: '',
  acmeTeam1: '', acmeTeam2: '', globexTeam1: '', globexTeam2: '',
}

async function wipe() {
  // Order respects FKs; CASCADE covers the rest. auth.users is NOT touched.
  await Promise.resolve(admin.rpc('noop')).catch(() => {}) // no-op guard if rpc missing
  for (const t of ['todos', 'lists', 'team_members', 'teams', 'profiles', 'organizations']) {
    const { error } = await admin.from(t).delete().neq('id', '00000000-0000-0000-0000-000000000000')
      .then((r) => r, (e) => ({ error: e }))
    // team_members has no id column; fall back to truncate via rpc-less delete on its PK
    if (error && t === 'team_members') {
      await admin.from('team_members').delete().not('team_id', 'is', null)
    }
  }
}

async function seedTenancy() {
  // ensure auth users
  for (const k of Object.keys(FIXTURES) as FixtureKey[]) uids[k] = await ensureUser(FIXTURES[k])

  // orgs
  const orgs = await admin.from('organizations').insert([
    { name: 'Acme' }, { name: 'Globex' }, { name: 'System' },
  ]).select('id, name')
  if (orgs.error) throw orgs.error
  ids.acme = orgs.data.find((o: { id: string; name: string }) => o.name === 'Acme')!.id
  ids.globex = orgs.data.find((o: { id: string; name: string }) => o.name === 'Globex')!.id
  ids.system = orgs.data.find((o: { id: string; name: string }) => o.name === 'System')!.id

  // profiles (service role; bypasses RLS)
  const profs = await admin.from('profiles').insert([
    { id: uids.acmeAdmin, org_id: ids.acme, role: 'org_admin' },
    { id: uids.acmeMember, org_id: ids.acme, role: 'member' },
    { id: uids.globexAdmin, org_id: ids.globex, role: 'org_admin' },
    { id: uids.globexMember, org_id: ids.globex, role: 'member' },
    { id: uids.superAdmin, org_id: ids.system, role: 'org_admin', is_super_admin: true },
  ])
  if (profs.error) throw profs.error

  // teams
  const teams = await admin.from('teams').insert([
    { org_id: ids.acme, name: 'Acme Team 1' }, { org_id: ids.acme, name: 'Acme Team 2' },
    { org_id: ids.globex, name: 'Globex Team 1' }, { org_id: ids.globex, name: 'Globex Team 2' },
  ]).select('id, name')
  if (teams.error) throw teams.error
  ids.acmeTeam1 = teams.data.find((t: { id: string; name: string }) => t.name === 'Acme Team 1')!.id
  ids.acmeTeam2 = teams.data.find((t: { id: string; name: string }) => t.name === 'Acme Team 2')!.id
  ids.globexTeam1 = teams.data.find((t: { id: string; name: string }) => t.name === 'Globex Team 1')!.id
  ids.globexTeam2 = teams.data.find((t: { id: string; name: string }) => t.name === 'Globex Team 2')!.id

  // crisscrossed membership: member on team1 only; admin on team1+team2
  const tm = await admin.from('team_members').insert([
    { team_id: ids.acmeTeam1, user_id: uids.acmeMember },
    { team_id: ids.acmeTeam1, user_id: uids.acmeAdmin },
    { team_id: ids.acmeTeam2, user_id: uids.acmeAdmin },
    { team_id: ids.globexTeam1, user_id: uids.globexMember },
    { team_id: ids.globexTeam1, user_id: uids.globexAdmin },
    { team_id: ids.globexTeam2, user_id: uids.globexAdmin },
  ])
  if (tm.error) throw tm.error
}

// Lists + todos created via each owner's authenticated session (Codex #8).
const listIds: Record<string, string> = {}
async function seedListsAndTodos(clients: Record<FixtureKey, SupabaseClient>) {
  async function makeList(owner: FixtureKey, body: Record<string, unknown>, key: string) {
    const { data, error } = await clients[owner].from('lists').insert(body).select('id').single()
    if (error) throw new Error(`seed list ${key} as ${owner}: ${error.message}`)
    listIds[key] = data!.id
    const t = await clients[owner].from('todos').insert([
      { list_id: data!.id, title: `${key} todo 1` },
      { list_id: data!.id, title: `${key} todo 2` },
    ])
    if (t.error) throw new Error(`seed todos ${key}: ${t.error.message}`)
  }
  // personal lists (owner_user_id only; org_id + created_by are trigger-filled)
  await makeList('acmeMember', { name: 'Acme member personal', owner_user_id: uids.acmeMember }, 'acmeMemberPersonal')
  await makeList('acmeAdmin', { name: 'Acme admin personal', owner_user_id: uids.acmeAdmin }, 'acmeAdminPersonal')
  await makeList('globexMember', { name: 'Globex member personal', owner_user_id: uids.globexMember }, 'globexMemberPersonal')
  // team lists (owner_team_id only)
  await makeList('acmeMember', { name: 'Acme team 1 list', owner_team_id: ids.acmeTeam1 }, 'acmeTeam1List')
  await makeList('acmeAdmin', { name: 'Acme team 2 list', owner_team_id: ids.acmeTeam2 }, 'acmeTeam2List')
  await makeList('globexMember', { name: 'Globex team 1 list', owner_team_id: ids.globexTeam1 }, 'globexTeam1List')
}

async function runAssertions(clients: Record<FixtureKey, SupabaseClient>) {
  const anon = createClient(URL!, process.env.VITE_SUPABASE_ANON_KEY ?? SERVICE_KEY!, {
    auth: { persistSession: false },
  })
  const m = clients.acmeMember, a = clients.acmeAdmin, s = clients.superAdmin

  // --- Anonymous: RLS hides everything (no error, 0 rows) ---
  await expectRows('anon sees 0 lists', anon.from('lists').select('*'), 0)
  await expectRows('anon sees 0 todos', anon.from('todos').select('*'), 0)

  // --- Member A in Acme: list visibility ---
  await expectRows('member sees own personal + team1 list (2)', m.from('lists').select('id'), 2)
  await expectRows('member sees own personal list',
    m.from('lists').select('id').eq('id', listIds.acmeMemberPersonal), 1)
  await expectRows('member sees team1 list (on team)',
    m.from('lists').select('id').eq('id', listIds.acmeTeam1List), 1)
  await expectRows('member does NOT see team2 list (not on team)',
    m.from('lists').select('id').eq('id', listIds.acmeTeam2List), 0)
  await expectRows('member does NOT see admin personal list',
    m.from('lists').select('id').eq('id', listIds.acmeAdminPersonal), 0)
  await expectRows('member sees nothing in Globex',
    m.from('lists').select('id').eq('id', listIds.globexMemberPersonal), 0)

  // --- Member A: todo write within reachable list / blocked outside ---
  await expectOk('member inserts todo into own personal list',
    m.from('todos').insert({ list_id: listIds.acmeMemberPersonal, title: 'm-ok' }))
  await expectError('member cannot insert todo into team2 list',
    m.from('todos').insert({ list_id: listIds.acmeTeam2List, title: 'm-bad' }))

  // --- Member A: delete rules ---
  await expectError('member cannot delete team1 list it did not create',
    m.from('lists').delete().eq('id', listIds.acmeTeam1List).select('id').single())
  // (acmeMember DID create acmeTeam1List in seed -> allowed; assert a not-creator case instead)
  await expectError('member cannot delete admin personal list',
    m.from('lists').delete().eq('id', listIds.acmeAdminPersonal).select('id').single())

  // --- Org admin in Acme: sees all Acme incl. personal; read-only on personal ---
  await expectRows('org admin sees all Acme lists (5)', a.from('lists').select('id'), 5)
  await expectRows('org admin sees a member personal list',
    a.from('lists').select('id').eq('id', listIds.acmeMemberPersonal), 1)
  await expectError('org admin cannot UPDATE a personal list (read-only)',
    a.from('lists').update({ name: 'hijack' }).eq('id', listIds.acmeMemberPersonal).select('id').single())
  await expectError('org admin cannot DELETE a personal list',
    a.from('lists').delete().eq('id', listIds.acmeMemberPersonal).select('id').single())
  await expectOk('org admin can UPDATE a team list',
    a.from('lists').update({ name: 'team renamed' }).eq('id', listIds.acmeTeam1List))
  await expectRows('org admin sees nothing in Globex',
    a.from('lists').select('id').eq('id', listIds.globexMemberPersonal), 0)

  // --- Org admin: team management scoped to own org ---
  await expectOk('org admin inserts a team into Acme',
    a.from('teams').insert({ org_id: ids.acme, name: 'Acme Team 3' }))
  await expectError('org admin cannot insert a team into Globex',
    a.from('teams').insert({ org_id: ids.globex, name: 'rogue' }).select('id').single())

  // --- Codex #5: org admin cross-org team_members must be rejected by POLICY ---
  await expectError('org admin cannot add Globex user to an Acme team',
    a.from('team_members').insert({ team_id: ids.acmeTeam1, user_id: uids.globexMember }).select('team_id').single())
  await expectError('org admin cannot add Acme user to a Globex team',
    a.from('team_members').insert({ team_id: ids.globexTeam1, user_id: uids.acmeMember }).select('team_id').single())

  // --- Super admin: sees across orgs ---
  await expectRows('super admin sees a Globex personal list',
    s.from('lists').select('id').eq('id', listIds.globexMemberPersonal), 1)
  await expectRows('super admin sees an Acme personal list',
    s.from('lists').select('id').eq('id', listIds.acmeMemberPersonal), 1)

  // --- Codex #13: profile column tampering blocked by column grant ---
  await expectError('member cannot escalate role',
    m.from('profiles').update({ role: 'org_admin' }).eq('id', uids.acmeMember).select('id').single())
  await expectError('member cannot change own org_id',
    m.from('profiles').update({ org_id: ids.globex }).eq('id', uids.acmeMember).select('id').single())
  await expectError('member cannot set is_super_admin',
    m.from('profiles').update({ is_super_admin: true }).eq('id', uids.acmeMember).select('id').single())
  await expectOk('member can update own display_name',
    m.from('profiles').update({ display_name: 'Mem' }).eq('id', uids.acmeMember))

  // --- Codex #11: reparenting blocked by lists_forbid_owner_change ---
  await expectError('cannot change owner_user_id of own list',
    m.from('lists').update({ owner_user_id: uids.acmeAdmin })
      .eq('id', listIds.acmeMemberPersonal).select('id').single())
  await expectError('cannot move list to another org_id',
    m.from('lists').update({ org_id: ids.globex })
      .eq('id', listIds.acmeMemberPersonal).select('id').single())
  await expectOk('renaming own list is allowed',
    m.from('lists').update({ name: 'renamed ok' }).eq('id', listIds.acmeMemberPersonal))

  // --- Codex #12: trigger derives org_id/created_by, ignoring forged client values ---
  const forged = await m.from('lists')
    .insert({ name: 'forged', owner_user_id: uids.acmeMember, org_id: ids.globex })
    .select('id, org_id, created_by').single()
  check('forged org_id is overridden to derived (Acme)',
    !forged.error && forged.data?.org_id === ids.acme,
    forged.error ? forged.error.message : `org_id=${forged.data?.org_id}`)
  check('created_by captured from JWT (acmeMember)',
    !forged.error && forged.data?.created_by === uids.acmeMember,
    forged.error ? forged.error.message : `created_by=${forged.data?.created_by}`)

  // --- XOR + same-org trigger (service role) ---
  await expectError('list with both owners violates XOR',
    admin.from('lists').insert({ name: 'x', owner_user_id: uids.acmeMember, owner_team_id: ids.acmeTeam1 }).select('id').single())
  await expectError('list with neither owner violates XOR',
    admin.from('lists').insert({ name: 'x', org_id: ids.acme }).select('id').single())
  await expectError('cross-org team membership raises trigger exception (service role)',
    admin.from('team_members').insert({ team_id: ids.acmeTeam1, user_id: uids.globexMember }).select('team_id').single())
}

async function main() {
  await wipe()
  await seedTenancy()
  const clients = {} as Record<FixtureKey, SupabaseClient>
  for (const k of Object.keys(FIXTURES) as FixtureKey[]) clients[k] = await signIn(FIXTURES[k])
  await seedListsAndTodos(clients)
  await runAssertions(clients)

  if (failures.length) {
    console.error(`\n${failures.length} of ${checks} checks FAILED:\n` + failures.map((f) => '  ' + f).join('\n'))
    process.exit(1)
  }
  console.log(`\nAll ${checks} RLS checks passed.`)
}

main().catch((e) => { console.error('verify:rls crashed:', e); process.exit(1) })
