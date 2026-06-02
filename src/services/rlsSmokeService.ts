import { supabase } from '../lib/supabase'

export interface AnonReadResult {
  rows: number | null
  error: string | null
}

/** Anonymous read of lists — used by the deploy smoke page. RLS should return 0 rows. */
export async function readListsCount(): Promise<AnonReadResult> {
  const { data, error } = await supabase.from('lists').select('id')
  if (error) return { rows: null, error: error.message }
  return { rows: data?.length ?? 0, error: null }
}
