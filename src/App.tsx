import { BrowserRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider } from './features/auth/AuthContext'
import { EnvErrorScreen } from './components/EnvErrorScreen'
import { getEnvError } from './lib/supabase'
import { AppRoutes } from './router'

const queryClient = new QueryClient()

export default function App() {
  const envError = getEnvError()
  if (envError) {
    return <EnvErrorScreen error={envError} />
  }

  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <BrowserRouter>
          <AppRoutes />
        </BrowserRouter>
      </AuthProvider>
    </QueryClientProvider>
  )
}
