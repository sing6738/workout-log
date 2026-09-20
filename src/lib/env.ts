import { z } from 'zod'

const EnvSchema = z.object({
  VITE_SUPABASE_URL: z.string().url(),
  VITE_SUPABASE_ANON_KEY: z.string().min(1),
})

export function parseEnv(raw: Record<string, unknown>) {
  return EnvSchema.parse(raw)
}
