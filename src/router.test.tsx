import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import type { User, Session } from '@supabase/supabase-js'
import { AppRoutes } from './router'
import App from './App'
import * as AuthContextModule from './features/auth/useAuth'
import * as supabaseModule from './lib/supabase'

vi.mock('./lib/supabase', () => ({
  getSupabase: vi.fn(),
  getEnvError: vi.fn(),
}))

describe('Router & App Integration', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(supabaseModule.getEnvError).mockReturnValue(null)
  })

  it('renders login page on /login when unauthenticated', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: null,
      session: null,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/login']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Welcome Back' }),
    ).toBeInTheDocument()
  })

  it('renders signup page on /signup when unauthenticated', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: null,
      session: null,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/signup']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Create Account' }),
    ).toBeInTheDocument()
  })

  it('redirects unauthenticated users from /workouts to /login', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: null,
      session: null,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/workouts']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Welcome Back' }),
    ).toBeInTheDocument()
  })

  it('renders workouts placeholder on /workouts for authenticated users', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: { id: 'user-1' } as User,
      session: { access_token: 'valid-jwt' } as Session,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/workouts']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Workouts' }),
    ).toBeInTheDocument()
    expect(screen.getByText('WorkoutLog')).toBeInTheDocument()
  })

  it('renders exercises placeholder on /exercises for authenticated users', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: { id: 'user-1' } as User,
      session: { access_token: 'valid-jwt' } as Session,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/exercises']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Exercises' }),
    ).toBeInTheDocument()
  })

  it('renders settings placeholder on /settings for authenticated users', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: { id: 'user-1' } as User,
      session: { access_token: 'valid-jwt' } as Session,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/settings']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Settings' }),
    ).toBeInTheDocument()
  })

  it('renders EnvErrorScreen when getEnvError returns an error', () => {
    vi.mocked(supabaseModule.getEnvError).mockReturnValueOnce(
      'Missing VITE_SUPABASE_URL',
    )

    render(<App />)
    expect(screen.getByText('Configuration Required')).toBeInTheDocument()
    expect(screen.getByText('Missing VITE_SUPABASE_URL')).toBeInTheDocument()
  })
})
