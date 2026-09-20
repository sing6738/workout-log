export function EnvErrorScreen({ error }: { error: string }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="max-w-md w-full bg-white rounded-xl shadow-md p-8 border border-red-200">
        <h2 className="text-xl font-bold text-red-600 mb-2">
          Configuration Required
        </h2>
        <p className="text-sm text-gray-600 mb-4">
          Supabase environment variables are missing or invalid:
        </p>
        <div className="bg-red-50 text-red-700 p-3 rounded text-xs font-mono mb-4 break-all whitespace-pre-wrap">
          {error}
        </div>
        <p className="text-xs text-gray-500">
          Please configure{' '}
          <code className="font-semibold">VITE_SUPABASE_URL</code> and{' '}
          <code className="font-semibold">VITE_SUPABASE_ANON_KEY</code> in your
          environment variables.
        </p>
      </div>
    </div>
  )
}
