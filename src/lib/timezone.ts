export const DEFAULT_TIMEZONE = 'Asia/Bangkok'

export function getClientTimezone(): string {
  try {
    const detected = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (detected && typeof Intl.supportedValuesOf === 'function') {
      const supported = Intl.supportedValuesOf('timeZone')
      if (supported.includes(detected)) {
        return detected
      }
    }
    return DEFAULT_TIMEZONE
  } catch {
    return DEFAULT_TIMEZONE
  }
}
