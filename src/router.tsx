import { Routes, Route, Navigate } from 'react-router-dom'
import { AppLayout } from './components/layout/AppLayout'
import { PlaceholderPage } from './pages/PlaceholderPage'

export function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<PlaceholderPage title="Login" />} />
      <Route path="/signup" element={<PlaceholderPage title="Sign Up" />} />
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
      <Route path="*" element={<Navigate to="/workouts" replace />} />
    </Routes>
  )
}
