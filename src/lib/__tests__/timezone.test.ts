import { describe, it, expect, vi, afterEach } from 'vitest'
import { getClientTimezone, DEFAULT_TIMEZONE } from '../timezone'

describe('getClientTimezone', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('returns valid detected timezone if supported', () => {
    vi.spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions').mockReturnValue({
      timeZone: 'America/New_York',
      locale: 'en-US',
      calendar: 'gregory',
      numberingSystem: 'latn',
    })

    const tz = getClientTimezone()
    expect(tz).toBe('America/New_York')
  })

  it('falls back to DEFAULT_TIMEZONE if detected timezone is unsupported/invalid', () => {
    vi.spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions').mockReturnValue({
      timeZone: 'Fake/Unsupported_Timezone',
      locale: 'en-US',
      calendar: 'gregory',
      numberingSystem: 'latn',
    })

    const tz = getClientTimezone()
    expect(tz).toBe(DEFAULT_TIMEZONE)
  })

  it('falls back to DEFAULT_TIMEZONE if resolvedOptions throws', () => {
    vi.spyOn(
      Intl.DateTimeFormat.prototype,
      'resolvedOptions',
    ).mockImplementation(() => {
      throw new Error('Intl error')
    })

    const tz = getClientTimezone()
    expect(tz).toBe(DEFAULT_TIMEZONE)
  })
})
