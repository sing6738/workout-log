import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { EnvErrorScreen } from '../EnvErrorScreen'

describe('EnvErrorScreen', () => {
  it('renders error message and configuration instructions', () => {
    render(<EnvErrorScreen error="Invalid url at VITE_SUPABASE_URL" />)

    expect(screen.getByText('Configuration Required')).toBeInTheDocument()
    expect(
      screen.getByText('Invalid url at VITE_SUPABASE_URL'),
    ).toBeInTheDocument()
    expect(screen.getByText('VITE_SUPABASE_URL')).toBeInTheDocument()
    expect(screen.getByText('VITE_SUPABASE_ANON_KEY')).toBeInTheDocument()
  })
})
