import { createClient, SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database'
import { parseEnv } from './env'

let _client: SupabaseClient<Database> | null = null

export function getSupabase(): SupabaseClient<Database> {
  if (!_client) {
    const env = parseEnv(import.meta.env)
    _client = createClient<Database>(
      env.VITE_SUPABASE_URL,
      env.VITE_SUPABASE_ANON_KEY,
    )
  }
  return _client
}

export type { Database } from '../types/database'
