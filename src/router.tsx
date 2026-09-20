import { Routes, Route, Navigate } from 'react-router-dom'
import { AppLayout } from './components/layout/AppLayout'
import { LoginPage } from './features/auth/LoginPage'
import { SignupPage } from './features/auth/SignupPage'
import { ProtectedRoute } from './features/auth/ProtectedRoute'
import { PlaceholderPage } from './pages/PlaceholderPage'

export function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/signup" element={<SignupPage />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AppLayout />}>
          <Route path="/" element={<Navigate to="/workouts" replace />} />
          <Route
            path="/workouts"
            element={<PlaceholderPage title="Workouts" />}
          />
          <Route
            path="/workouts/new"
            element={<PlaceholderPage title="New Workout" />}
          />
          <Route
            path="/workouts/:id"
            element={<PlaceholderPage title="Edit Workout" />}
          />
          <Route
            path="/exercises"
            element={<PlaceholderPage title="Exercises" />}
          />
          <Route
            path="/settings"
            element={<PlaceholderPage title="Settings" />}
          />
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/workouts" replace />} />
    </Routes>
  )
}
