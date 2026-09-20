import { describe, it, expect } from 'vitest'
import { parseEnv } from '../env'

describe('parseEnv', () => {
  it('parses valid env', () => {
    const result = parseEnv({
      VITE_SUPABASE_URL: 'http://localhost:54321',
      VITE_SUPABASE_ANON_KEY: 'test-key',
    })
    expect(result.VITE_SUPABASE_URL).toBe('http://localhost:54321')
    expect(result.VITE_SUPABASE_ANON_KEY).toBe('test-key')
  })

  it('throws on missing URL', () => {
    expect(() => parseEnv({ VITE_SUPABASE_ANON_KEY: 'test-key' })).toThrow()
  })

  it('throws on invalid URL', () => {
    expect(() =>
      parseEnv({
        VITE_SUPABASE_URL: 'not-a-url',
        VITE_SUPABASE_ANON_KEY: 'test-key',
      }),
    ).toThrow()
  })

  it('throws on empty anon key', () => {
    expect(() =>
      parseEnv({
        VITE_SUPABASE_URL: 'http://localhost:54321',
        VITE_SUPABASE_ANON_KEY: '',
      }),
    ).toThrow()
  })
})
