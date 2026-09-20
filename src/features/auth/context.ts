import { createContext } from 'react'
import type { User, Session } from '@supabase/supabase-js'
import type { Database } from '../../types/database'

export type Profile = Database['public']['Tables']['profiles']['Row']

export interface AuthContextType {
  user: User | null
  session: Session | null
  profile: Profile | null
  loading: boolean
  signOut: () => Promise<void>
  refreshProfile: () => Promise<void>
}

export const AuthContext = createContext<AuthContextType | undefined>(undefined)
