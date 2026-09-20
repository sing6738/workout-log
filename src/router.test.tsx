import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { AppRoutes } from './router'

describe('Router Scaffolding', () => {
  it('renders workouts placeholder on /workouts', () => {
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

  it('renders exercises placeholder on /exercises', () => {
    render(
      <MemoryRouter initialEntries={['/exercises']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Exercises' }),
    ).toBeInTheDocument()
  })

  it('renders settings placeholder on /settings', () => {
    render(
      <MemoryRouter initialEntries={['/settings']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(
      screen.getByRole('heading', { name: 'Settings' }),
    ).toBeInTheDocument()
  })

  it('renders login placeholder on /login', () => {
    render(
      <MemoryRouter initialEntries={['/login']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(screen.getByRole('heading', { name: 'Login' })).toBeInTheDocument()
  })

  it('renders signup placeholder on /signup', () => {
    render(
      <MemoryRouter initialEntries={['/signup']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(screen.getByRole('heading', { name: 'Sign Up' })).toBeInTheDocument()
  })
})
