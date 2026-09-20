import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import type { User, Session, SupabaseClient } from '@supabase/supabase-js'
import { LoginPage } from './LoginPage'
import { SignupPage } from './SignupPage'
import { ProtectedRoute } from './ProtectedRoute'
import * as AuthContextModule from './useAuth'
import * as supabaseModule from '../../lib/supabase'
import type { Database } from '../../types/database'

vi.mock('../../lib/supabase', () => ({
  getSupabase: vi.fn(),
}))

describe('LoginPage', () => {
  const mockSignInWithPassword = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: null,
      session: null,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })
    vi.mocked(supabaseModule.getSupabase).mockReturnValue({
      auth: {
        signInWithPassword: mockSignInWithPassword,
      },
    } as unknown as SupabaseClient<Database>)
  })

  it('renders login form with email and password inputs', () => {
    render(
      <MemoryRouter>
        <LoginPage />
      </MemoryRouter>,
    )

    expect(
      screen.getByRole('heading', { name: 'Welcome Back' }),
    ).toBeInTheDocument()
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Sign In' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Sign Up' })).toHaveAttribute(
      'href',
      '/signup',
    )
  })

  it('redirects to /workouts if user already has an active session', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: { id: 'user-1' } as User,
      session: { access_token: 'fake' } as Session,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/login']}>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/workouts" element={<div>Workouts Dashboard</div>} />
        </Routes>
      </MemoryRouter>,
    )

    expect(screen.getByText('Workouts Dashboard')).toBeInTheDocument()
  })

  it('handles successful login and navigates to /workouts', async () => {
    mockSignInWithPassword.mockResolvedValueOnce({
      data: {
        session: { access_token: 'token' } as Session,
        user: { id: 'user-1' } as User,
      },
      error: null,
    })

    render(
      <MemoryRouter initialEntries={['/login']}>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/workouts" element={<div>Workouts Dashboard</div>} />
        </Routes>
      </MemoryRouter>,
    )

    fireEvent.change(screen.getByLabelText('Email'), {
      target: { value: 'test@example.com' },
    })
    fireEvent.change(screen.getByLabelText('Password'), {
      target: { value: 'password123' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Sign In' }))

    expect(mockSignInWithPassword).toHaveBeenCalledWith({
      email: 'test@example.com',
      password: 'password123',
    })

    await waitFor(() => {
      expect(screen.getByText('Workouts Dashboard')).toBeInTheDocument()
    })
  })

  it('displays error message when login fails', async () => {
    mockSignInWithPassword.mockResolvedValueOnce({
      data: { session: null, user: null },
      error: new Error('Invalid login credentials'),
    })

    render(
      <MemoryRouter initialEntries={['/login']}>
        <LoginPage />
      </MemoryRouter>,
    )

    fireEvent.change(screen.getByLabelText('Email'), {
      target: { value: 'test@example.com' },
    })
    fireEvent.change(screen.getByLabelText('Password'), {
      target: { value: 'wrongpassword' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Sign In' }))

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent(
        'Invalid login credentials',
      )
    })
  })
})

describe('SignupPage', () => {
  const mockSignUp = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: null,
      session: null,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })
    vi.mocked(supabaseModule.getSupabase).mockReturnValue({
      auth: {
        signUp: mockSignUp,
      },
    } as unknown as SupabaseClient<Database>)
  })

  it('renders signup form with display name, email, and password inputs', () => {
    render(
      <MemoryRouter>
        <SignupPage />
      </MemoryRouter>,
    )

    expect(
      screen.getByRole('heading', { name: 'Create Account' }),
    ).toBeInTheDocument()
    expect(screen.getByLabelText('Display Name')).toBeInTheDocument()
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Sign Up' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Sign In' })).toHaveAttribute(
      'href',
      '/login',
    )
  })

  it('redirects to /workouts if user already has an active session', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: { id: 'user-1' } as User,
      session: { access_token: 'fake' } as Session,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/signup']}>
        <Routes>
          <Route path="/signup" element={<SignupPage />} />
          <Route path="/workouts" element={<div>Workouts Dashboard</div>} />
        </Routes>
      </MemoryRouter>,
    )

    expect(screen.getByText('Workouts Dashboard')).toBeInTheDocument()
  })

  it('submits signup with timezone metadata and navigates when instant session returned', async () => {
    mockSignUp.mockResolvedValueOnce({
      data: {
        session: { access_token: 'token' } as Session,
        user: { id: 'user-1' } as User,
      },
      error: null,
    })

    render(
      <MemoryRouter initialEntries={['/signup']}>
        <Routes>
          <Route path="/signup" element={<SignupPage />} />
          <Route path="/workouts" element={<div>Workouts Dashboard</div>} />
        </Routes>
      </MemoryRouter>,
    )

    fireEvent.change(screen.getByLabelText('Display Name'), {
      target: { value: 'John Doe' },
    })
    fireEvent.change(screen.getByLabelText('Email'), {
      target: { value: 'john@example.com' },
    })
    fireEvent.change(screen.getByLabelText('Password'), {
      target: { value: 'securepassword' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Sign Up' }))

    expect(mockSignUp).toHaveBeenCalledWith({
      email: 'john@example.com',
      password: 'securepassword',
      options: {
        data: {
          name: 'John Doe',
          timezone: expect.any(String),
        },
      },
    })

    await waitFor(() => {
      expect(screen.getByText('Workouts Dashboard')).toBeInTheDocument()
    })
  })

  it('shows confirmation notification when email confirmation is required', async () => {
    mockSignUp.mockResolvedValueOnce({
      data: {
        session: null,
        user: { id: 'user-1', email: 'john@example.com' } as User,
      },
      error: null,
    })

    render(
      <MemoryRouter initialEntries={['/signup']}>
        <SignupPage />
      </MemoryRouter>,
    )

    fireEvent.change(screen.getByLabelText('Email'), {
      target: { value: 'john@example.com' },
    })
    fireEvent.change(screen.getByLabelText('Password'), {
      target: { value: 'securepassword' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Sign Up' }))

    await waitFor(() => {
      expect(screen.getByRole('status')).toHaveTextContent(
        'Please check your email inbox to confirm your account',
      )
    })
  })

  it('displays error message when signup fails', async () => {
    mockSignUp.mockResolvedValueOnce({
      data: { session: null, user: null },
      error: new Error('User already registered'),
    })

    render(
      <MemoryRouter initialEntries={['/signup']}>
        <SignupPage />
      </MemoryRouter>,
    )

    fireEvent.change(screen.getByLabelText('Email'), {
      target: { value: 'john@example.com' },
    })
    fireEvent.change(screen.getByLabelText('Password'), {
      target: { value: 'securepassword' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Sign Up' }))

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent(
        'User already registered',
      )
    })
  })
})

describe('ProtectedRoute', () => {
  it('renders loading state when session is loading', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: null,
      session: null,
      profile: null,
      loading: true,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/protected']}>
        <Routes>
          <Route element={<ProtectedRoute />}>
            <Route path="/protected" element={<div>Protected Content</div>} />
          </Route>
        </Routes>
      </MemoryRouter>,
    )

    expect(screen.getByText('Loading session...')).toBeInTheDocument()
    expect(screen.queryByText('Protected Content')).not.toBeInTheDocument()
  })

  it('redirects unauthenticated user to /login', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: null,
      session: null,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/protected']}>
        <Routes>
          <Route path="/login" element={<div>Login Screen</div>} />
          <Route element={<ProtectedRoute />}>
            <Route path="/protected" element={<div>Protected Content</div>} />
          </Route>
        </Routes>
      </MemoryRouter>,
    )

    expect(screen.getByText('Login Screen')).toBeInTheDocument()
    expect(screen.queryByText('Protected Content')).not.toBeInTheDocument()
  })

  it('renders child outlet when session is authenticated', () => {
    vi.spyOn(AuthContextModule, 'useAuth').mockReturnValue({
      user: { id: 'user-1' } as User,
      session: { access_token: 'token' } as Session,
      profile: null,
      loading: false,
      signOut: vi.fn(),
      refreshProfile: vi.fn(),
    })

    render(
      <MemoryRouter initialEntries={['/protected']}>
        <Routes>
          <Route element={<ProtectedRoute />}>
            <Route path="/protected" element={<div>Protected Content</div>} />
          </Route>
        </Routes>
      </MemoryRouter>,
    )

    expect(screen.getByText('Protected Content')).toBeInTheDocument()
  })
})
