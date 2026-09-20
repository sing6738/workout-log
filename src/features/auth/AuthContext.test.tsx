import { describe, it, expect, vi, beforeEach, type Mock } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import type { ReactNode } from 'react'
import type { Session, User, SupabaseClient } from '@supabase/supabase-js'
import { AuthProvider } from './AuthContext'
import { useAuth } from './useAuth'
import * as supabaseModule from '../../lib/supabase'
import type { Database } from '../../types/database'

vi.mock('../../lib/supabase', () => ({
  getSupabase: vi.fn(),
}))

describe('AuthContext & useAuth', () => {
  let mockGetSession: Mock
  let mockOnAuthStateChange: Mock
  let mockSignOut: Mock
  let mockFrom: Mock
  let authListener: (event: string, session: Session | null) => void

  beforeEach(() => {
    vi.clearAllMocks()

    mockGetSession = vi.fn().mockResolvedValue({
      data: { session: null },
    })

    mockOnAuthStateChange = vi.fn().mockImplementation((callback) => {
      authListener = callback
      return {
        data: {
          subscription: {
            unsubscribe: vi.fn(),
          },
        },
      }
    })

    mockSignOut = vi.fn().mockResolvedValue({ error: null })

    mockFrom = vi.fn().mockReturnValue({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({
            data: {
              id: 'user-1',
              display_name: 'Test Athlete',
              weight_unit: 'kg',
              timezone: 'Asia/Bangkok',
              created_at: new Date().toISOString(),
            },
            error: null,
          }),
        }),
      }),
    })

    vi.mocked(supabaseModule.getSupabase).mockReturnValue({
      auth: {
        getSession: mockGetSession,
        onAuthStateChange: mockOnAuthStateChange,
        signOut: mockSignOut,
      },
      from: mockFrom,
    } as unknown as SupabaseClient<Database>)
  })

  const wrapper = ({ children }: { children: ReactNode }) => (
    <AuthProvider>{children}</AuthProvider>
  )

  it('throws error when useAuth is used outside AuthProvider', () => {
    expect(() => renderHook(() => useAuth())).toThrow(
      'useAuth must be used within an AuthProvider',
    )
  })

  it('initializes with null session when user is not logged in', async () => {
    const { result } = renderHook(() => useAuth(), { wrapper })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    expect(result.current.user).toBeNull()
    expect(result.current.session).toBeNull()
    expect(result.current.profile).toBeNull()
  })

  it('fetches profile when session exists on initialization', async () => {
    mockGetSession.mockResolvedValueOnce({
      data: {
        session: {
          user: { id: 'user-1', email: 'test@example.com' } as User,
          access_token: 'fake-jwt',
        } as Session,
      },
    })

    const { result } = renderHook(() => useAuth(), { wrapper })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    expect(result.current.user?.id).toBe('user-1')
    expect(result.current.session?.access_token).toBe('fake-jwt')

    await waitFor(() => {
      expect(result.current.profile?.display_name).toBe('Test Athlete')
    })
  })

  it('updates state when onAuthStateChange fires and allows signing out', async () => {
    const { result } = renderHook(() => useAuth(), { wrapper })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    act(() => {
      authListener('SIGNED_IN', {
        user: { id: 'user-1', email: 'test@example.com' } as User,
        access_token: 'fake-jwt',
      } as Session)
    })

    await waitFor(() => {
      expect(result.current.user?.id).toBe('user-1')
    })

    await act(async () => {
      await result.current.signOut()
    })

    expect(mockSignOut).toHaveBeenCalled()
    expect(result.current.user).toBeNull()
    expect(result.current.session).toBeNull()
    expect(result.current.profile).toBeNull()
  })
})
