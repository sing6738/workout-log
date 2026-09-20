import { Link, useLocation } from 'react-router-dom'
import { Dumbbell, List, Settings } from 'lucide-react'

export function Navbar() {
  const location = useLocation()

  const navItems = [
    { label: 'Workouts', path: '/workouts', icon: Dumbbell },
    { label: 'Exercises', path: '/exercises', icon: List },
    { label: 'Settings', path: '/settings', icon: Settings },
  ]

  return (
    <nav className="bg-white border-b border-gray-200 sticky top-0 z-10">
      <div className="max-w-4xl mx-auto px-4 flex items-center justify-between h-14">
        <Link
          to="/workouts"
          className="font-bold text-indigo-600 text-lg flex items-center gap-2"
        >
          <Dumbbell className="w-5 h-5" />
          <span>WorkoutLog</span>
        </Link>
        <div className="flex items-center gap-4">
          {navItems.map(({ label, path, icon: Icon }) => (
            <Link
              key={path}
              to={path}
              className={`flex items-center gap-1 text-sm font-medium px-2 py-1 rounded-md transition-colors ${
                location.pathname.startsWith(path)
                  ? 'text-indigo-600 bg-indigo-50'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              <Icon className="w-4 h-4" />
              <span>{label}</span>
            </Link>
          ))}
        </div>
      </div>
    </nav>
  )
}
