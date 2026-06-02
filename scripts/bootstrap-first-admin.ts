import 'dotenv/config'
import { spawnSync } from 'node:child_process'

function arg(flag: string): string | undefined {
  const i = process.argv.indexOf(flag)
  return i >= 0 ? process.argv[i + 1] : undefined
}

const uid = arg('--uid') ?? process.env.SUPER_ADMIN_UID
const org = arg('--org') ?? process.env.FIRST_ORG_NAME ?? 'System'
const dbUrl = process.env.SUPABASE_DB_URL
if (!uid) throw new Error('Provide --uid <auth.users UID> (or SUPER_ADMIN_UID)')
if (!dbUrl) throw new Error('Set SUPABASE_DB_URL')

const res = spawnSync('psql', [
  dbUrl,
  '-v', `super_admin_uid=${uid}`,
  '-v', `first_org_name=${org}`,
  '-f', 'supabase/bootstrap/seed_first_super_admin.sql',
], { stdio: 'inherit' })

process.exit(res.status ?? 1)
