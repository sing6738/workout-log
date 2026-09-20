export function PlaceholderPage({ title }: { title: string }) {
  return (
    <div className="p-8 text-center bg-white rounded-xl shadow-sm border border-gray-100">
      <h1 className="text-2xl font-bold text-gray-900 mb-2">{title}</h1>
      <p className="text-gray-500 text-sm">
        Feature module under construction.
      </p>
    </div>
  )
}
